# Stateful application - Elastic File System (EFS)

- Applications that are "backed-up" by mounting a stateful volume to them are known as stateful
- stateful applications can be backed up by EBS volumes, EFS volumes or databases.
- EBS CSI Drivers are used to connect EKS with EBS
- EFS is elastic file storage
-   scales automatically when add/remove files
-   You don't need to specify storage request when creating PVC (but K8S needs it just to make their code work)
-   You can mount the EFS to multiple pods, unlike EBS.
- It's much more expensive than EBS!
- Since it's a network file system, you must add routes for the EFS to connect with EKS workers.
- For now, EFS drivers only work with OpenID Connect (OIDC) Identity Provider in IAM.