# Architecture Diagram

## IRSA Flow for ArgoCD Image Updater

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EKS Cluster                                  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ IRSA WebHook (kube-system namespace)                          │ │
│  │ - Intercepts pod creation                                    │ │
│  │ - Injects AWS credentials as env vars                        │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ ArgoCD Namespace                                              │ │
│  │ ┌─────────────────────────────────────────────────────────┐   │ │
│  │ │ ArgoCD Image Updater Pod                                │   │ │
│  │ │ - Mounted Token: /var/run/secrets/eks.../token         │   │ │
│  │ │ - Mounts ServiceAccount: argocd-image-updater          │   │ │
│  │ │ - Env: AWS_ROLE_ARN=arn:aws:iam::*:role/...           │   │ │
│  │ │ - Env: AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/...       │   │ │
│  │ └─────────────────────────────────────────────────────────┘   │ │
│  │                                                                 │ │
│  │ ┌─────────────────────────────────────────────────────────┐   │ │
│  │ │ ServiceAccount: argocd-image-updater                    │   │ │
│  │ │ Annotation:                                             │   │ │
│  │ │   eks.amazonaws.com/role-arn:                          │   │ │
│  │ │   arn:aws:iam::ACCOUNT_ID:role/...argocd-image-updater│   │ │
│  │ └─────────────────────────────────────────────────────────┘   │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ Test Namespace                                                │ │
│  │ ┌──────────────────────────────────────────────────────────┐  │ │
│  │ │ My-App Pod                                               │  │ │
│  │ │ - Container: my-repo:latest                              │  │ │
│  │ │ - ServiceAccount: ecr-access-sa                          │  │ │
│  │ │ - Env: AWS_ROLE_ARN=arn:aws:iam::*:role/...            │  │ │
│  │ │ - Env: AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/...        │  │ │
│  │ └──────────────────────────────────────────────────────────┘  │ │
│  │                                                                │ │
│  │ ┌──────────────────────────────────────────────────────────┐  │ │
│  │ │ ServiceAccount: ecr-access-sa                            │  │ │
│  │ │ Annotation:                                              │  │ │
│  │ │   eks.amazonaws.com/role-arn:                           │  │ │
│  │ │   arn:aws:iam::ACCOUNT_ID:role/...eks-pods-ecr-access  │  │ │
│  │ └──────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ OIDC Provider (in cluster)                                    │ │
│  │ - Issues and validates tokens                                │ │
│  │ - URL: https://oidc.eks.us-east-1.amazonaws.com/id/...      │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │
                     Validates Token
                              │
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Account                                │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ AWS STS (Security Token Service)                              │ │
│  │ - Receives token + role ARN                                  │ │
│  │ - Validates against OIDC provider                            │ │
│  │ - Returns temporary credentials                              │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                              ▲                                      │
│                              │                                      │
│                    Returns Credentials                              │
│                              │                                      │
│  ┌──────────────┬────────────┴──────────┬──────────────────────┐   │
│  │              │                       │                      │   │
│  ▼              ▼                       ▼                      ▼   │
│ ┌────────────────────────┐  ┌────────────────────────┐  ┌────────────┐
│ │ ECR Repository: my-repo│  │ IAM Role:              │  │ IAM Role:  │
│ │                        │  │ argocd-image-updater   │  │ eks-pods   │
│ │ ┌──────────────────┐   │  │ - Can pull/push        │  │ -ecr-access│
│ │ │ my-repo images   │   │  │ - Trust OIDC provider  │  │ - Can pull │
│ │ │ └─────────────────   │  │ - Permissions:         │  │ - Trust OID│
│ │ └────────────────────┘   │  │   ecr:* (except push) │  │   Perms:   │
│ │                        │  │                        │  │ ecr:pull   │
│ │ Policy:                │  │                        │  │            │
│ │ Allow roles to access  │  │                        │  │            │
│ └────────────────────────┘  └────────────────────────┘  └────────────┘
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Request Flow: Pod Pulling Image from ECR

```
1. Pod Startup (Kubelet)
   ├─ Create pod with serviceAccount: ecr-access-sa
   └─ IRSA Webhook intercepts pod
      └─ Injects AWS credential env vars

2. Credential Injection by Webhook
   ├─ AWS_ROLE_ARN = arn:aws:iam::ACCOUNT:role/eks-pods-ecr-access-role
   ├─ AWS_WEB_IDENTITY_TOKEN_FILE = /var/run/secrets/eks.../token
   └─ Token file contains OIDC token

3. Container Runtime - Pull Image
   ├─ Needs to authenticate with ECR
   └─ AWS SDK (in container) uses injected credentials
      ├─ Reads AWS_ROLE_ARN
      ├─ Reads AWS_WEB_IDENTITY_TOKEN_FILE (OIDC token)
      └─ Calls AWS STS AssumeRoleWithWebIdentity

4. AWS STS Validation
   ├─ Receives: Token, Role ARN, and Session Name
   ├─ Validates token against OIDC Provider
   │  └─ Checks token issuer, audience, subject claims
   ├─ If valid, returns temporary credentials:
   │  ├─ AccessKeyId (expires in 15 min)
   │  ├─ SecretAccessKey
   │  └─ SessionToken
   └─ If invalid, denies request

5. ECR Authentication
   ├─ Container runtime uses temp credentials
   ├─ AWS CLI/SDK calls: ecr:GetAuthorizationToken
   ├─ ECR verifies credentials and role permissions
   └─ Returns ECR login token (valid for 12 hours)

6. Image Pull
   ├─ Container runtime logs into ECR registry
   ├─ Pulls image layers from ECR
   └─ Image available for container to use

7. Credential Refresh (Automatic)
   ├─ After ~12 min, credentials expire
   ├─ AWS SDK automatically re-assumes role
   └─ New credentials obtained without user action
```

## Comparison: Secrets vs IRSA

```
┌──────────────────────────────────────────────────────────────────┐
│                    Using ECR Secrets                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Deployment                                                      │
│  ├─ imagePullSecrets: [ecr-secret]                              │
│  └─ ServiceAccount: default                                     │
│                                                                  │
│  Secret (etcd - plaintext when decrypted)                        │
│  └─ .dockerconfigjson: eyJhdXRo... (base64 AWS creds)          │
│                                                                  │
│  Kubelet Image Pull                                              │
│  ├─ Reads secret from etcd                                      │
│  ├─ Decodes base64                                              │
│  ├─ Uses credentials to auth with ECR                           │
│  └─ Credentials stored in memory on node                        │
│                                                                  │
│  Risks:                                                          │
│  ├─ Credentials in etcd (at rest unencrypted by default)       │
│  ├─ Credentials in memory on all nodes                          │
│  ├─ Manual credential rotation required                         │
│  ├─ Secrets visible to cluster admins                           │
│  ├─ No fine-grained audit trail                                │
│  └─ Single set of creds for all pods                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    Using IRSA (Current)                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Deployment                                                      │
│  ├─ serviceAccountName: ecr-access-sa                           │
│  └─ No imagePullSecrets                                         │
│                                                                  │
│  ServiceAccount Annotation                                       │
│  └─ eks.amazonaws.com/role-arn: arn:aws:iam::...role/...       │
│                                                                  │
│  IRSA Webhook (on pod creation)                                  │
│  ├─ Injects: AWS_ROLE_ARN                                       │
│  ├─ Injects: AWS_WEB_IDENTITY_TOKEN_FILE                        │
│  └─ Token is short-lived OIDC token (signed by cluster)         │
│                                                                  │
│  Container Runtime Image Pull                                    │
│  ├─ AWS SDK detects injected credentials                        │
│  ├─ Calls AWS STS with token                                    │
│  ├─ STS validates against OIDC provider                         │
│  ├─ STS returns temporary credentials (15 min TTL)              │
│  └─ Credentials auto-rotate every 15 minutes                    │
│                                                                  │
│  Benefits:                                                       │
│  ├─ No secrets stored anywhere                                  │
│  ├─ Temporary credentials (15 min TTL)                          │
│  ├─ Automatic credential rotation                               │
│  ├─ Fine-grained per-pod access control                         │
│  ├─ Full CloudTrail audit trail                                 │
│  ├─ Credentials never stored in memory long-term                │
│  ├─ OIDC token validated by AWS                                 │
│  └─ Different pods can have different permissions               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## File Organization

```
terraformAWS/
├── modules/
│   └── eks/
│       ├── cluster.tf
│       ├── node-group.tf
│       ├── oidc.tf (existing - used by IRSA)
│       ├── ecr.tf (NEW - ECR repository)
│       ├── irsa-ecr-roles.tf (NEW - IAM roles with IRSA)
│       ├── variables.tf (UPDATED - added oidc_provider_arn)
│       └── output.tf
├── manifists/
│   ├── argo-application/
│   │   ├── argocd-image-updater-sa.yaml (NEW)
│   │   ├── ecr-access-sa.yaml (NEW)
│   │   ├── ecr-secret.yaml (OLD - can be deleted)
│   │   └── ...
│   └── base-app/
│       ├── my-app-deployment-irsa.yaml (NEW - example)
│       └── myapp-deployment.yaml (existing)
├── values/
│   ├── image-updater.yaml (UPDATED)
│   └── argocd.yaml
├── main.tf (UPDATED - passes oidc_provider_arn)
├── setup-irsa-ecr.sh (NEW - automated setup)
├── SETUP_SUMMARY.md (NEW - this overview)
├── QUICK_REFERENCE.md (NEW - quick commands)
├── IRSA_ECR_SETUP.md (NEW - detailed guide)
└── MIGRATION_GUIDE.md (NEW - migration steps)
```
