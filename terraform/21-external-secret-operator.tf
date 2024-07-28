data "aws_caller_identity" "account_info" {}

data "aws_eks_cluster" "cluster" {
  name = "${var.env}-${var.eks_name}"
}

data "aws_eks_cluster_auth" "cluster" {
  name = "${var.env}-${var.eks_name}"
}

data "aws_iam_openid_connect_provider" "oidc_provider" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name   = "external-secrets"
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.20"

  create_namespace = false

  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    name  = "webhook.port"
    value = "9443"
  }
}

###########################################################################################
# Permission
###########################################################################################

# Associate OIDC with EKS Service Account
data "aws_iam_policy_document" "secrets_manager_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub" 
      values   = ["system:serviceaccount:external-secrets:eso-cluster-css-sa"]
    }

    principals {
      identifiers = [data.aws_iam_openid_connect_provider.oidc_provider.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "secrets_manager_role" {
  name               = "secretsManagerRole"
  assume_role_policy = data.aws_iam_policy_document.secrets_manager_assume_role_policy.json
}


resource "aws_iam_policy" "secrets_manager_policy" {
  name = "secrets_manager_policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Action" : [
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ],
      "Resource" : [
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.account_info.account_id}:secret:*",
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_manager_policy_attachment" {
  role       = aws_iam_role.secrets_manager_role.name
  policy_arn = aws_iam_policy.secrets_manager_policy.arn
}


###########################################################################################
# Create a Service Account
###########################################################################################
resource "kubernetes_service_account" "cluster_secret_store" {
  metadata {
    name      = "eso-cluster-css-sa"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_manager_role.arn
    }
  }
}


###########################################################################################
#  Create a ClusterSecretStore
###########################################################################################
resource "kubernetes_manifest" "secrets_manager_secret_store" {
  depends_on = [helm_release.external_secrets]

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "acm-css"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = kubernetes_service_account.cluster_secret_store.metadata[0].name,
                namespace = kubernetes_namespace.external_secrets.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}


