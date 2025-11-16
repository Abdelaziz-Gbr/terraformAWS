# ECR Access Configuration with IAM Roles for Service Accounts (IRSA)

This document explains the updated ECR access configuration for your Terraform AWS infrastructure.

## Overview

The project has been updated to use **IAM Roles for Service Accounts (IRSA)** instead of hardcoded credentials to access ECR "my-repo". This allows both ArgoCD Image Updater and Kubernetes pods to securely access the ECR repository.

## Architecture

```
OIDC Provider (EKS)
    ↓
    ├─→ ArgoCD Image Updater Service Account (IRSA)
    │   └─→ IAM Role: my-cluster-argocd-image-updater-role
    │       └─→ ECR Access Policy
    │
    └─→ EKS Pods Service Account (IRSA)
        └─→ IAM Role: my-cluster-eks-pods-ecr-access-role
            └─→ ECR Access Policy
```

## Changes Made

### 1. **New Terraform Files**

#### `modules/eks/ecr.tf`
- Creates ECR repository `my-repo`
- Configures repository policy to allow pull/push operations
- Outputs repository URL and ARN

#### `modules/eks/irsa-ecr-roles.tf`
- Creates IAM role for ArgoCD Image Updater with IRSA
- Creates IAM role for EKS pods with IRSA
- Both roles assume identity via OIDC provider
- Attaches policies for ECR access

#### `modules/eks/variables.tf` (Updated)
- Added `oidc_provider_arn` variable

### 2. **Updated Files**

#### `main.tf`
- Passes `oidc_provider_arn` to the EKS module

#### `values/image-updater.yaml`
- Removed hardcoded ECR credentials secret reference
- Updated to use pre-existing service account with IRSA annotations
- Set `serviceAccount.create = false` to use the annotated service account

### 3. **New Kubernetes Manifests**

#### `manifists/argo-application/argocd-image-updater-sa.yaml`
- Service account for ArgoCD Image Updater
- Annotated with IAM role ARN for IRSA

#### `manifists/argo-application/ecr-access-sa.yaml`
- Reusable service account for pods needing ECR access
- Created in both `default` and `test` namespaces
- Can be referenced by any deployment

#### `manifists/base-app/my-app-deployment-irsa.yaml`
- Example deployment using IRSA for ECR access
- References the `ecr-access-sa` service account

## Prerequisites

Before applying this configuration:

1. **Update AWS Account ID**
   Replace `ACCOUNT_ID` with your actual AWS account ID in:
   - `manifists/argo-application/argocd-image-updater-sa.yaml`
   - `manifists/argo-application/ecr-access-sa.yaml`
   - `manifists/base-app/my-app-deployment-irsa.yaml`

2. **Update ECR Registry URL**
   Replace `579385932895.dkr.ecr.us-east-1.amazonaws.com` with your actual ECR registry URL in:
   - `values/image-updater.yaml`
   - `manifists/base-app/my-app-deployment-irsa.yaml`

## Deployment Steps

### Step 1: Apply Terraform Configuration

```bash
cd /home/abdelaziz/terraformAWS
terraform plan
terraform apply
```

This will:
- Create the ECR repository
- Create the necessary IAM roles with IRSA
- Output the role ARNs

### Step 2: Update Kubernetes Manifests

Replace placeholder values in:

```bash
# For ArgoCD Image Updater
ACCOUNT_ID=<your-account-id>
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/argo-application/argocd-image-updater-sa.yaml

# For EKS Pods
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/argo-application/ecr-access-sa.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/base-app/my-app-deployment-irsa.yaml
```

### Step 3: Deploy Service Accounts

```bash
# Apply the service accounts
kubectl apply -f manifists/argo-application/argocd-image-updater-sa.yaml
kubectl apply -f manifists/argo-application/ecr-access-sa.yaml
```

### Step 4: Verify IRSA Setup

```bash
# Check the service account annotations
kubectl get sa argocd-image-updater -n argocd -o yaml | grep role-arn

# Check the service account in other namespaces
kubectl get sa ecr-access-sa -n default -o yaml | grep role-arn
kubectl get sa ecr-access-sa -n test -o yaml | grep role-arn
```

## How It Works

### For ArgoCD Image Updater

1. ArgoCD Image Updater pod mounts the service account token
2. Pod calls AWS STS with the service account token
3. STS validates token against the OIDC provider
4. STS returns temporary AWS credentials
5. Pod uses these credentials to access ECR

### For Kubernetes Pods

1. Pod mounts the service account token and assumes the ECR access role
2. Kubelet automatically injects AWS credentials via environment variables:
   - `AWS_ROLE_ARN`: The ARN of the IAM role
   - `AWS_WEB_IDENTITY_TOKEN_FILE`: Path to the token file
3. AWS SDK automatically uses these credentials

## Security Benefits

1. **No Secret Storage**: Eliminates the need to store and manage AWS credentials in Kubernetes secrets
2. **Least Privilege**: Each service gets only the permissions it needs
3. **Temporary Credentials**: AWS STS provides short-lived credentials
4. **Audit Trail**: All operations are logged in CloudTrail with the IAM role
5. **Pod-level Control**: Different pods can have different permissions

## Removing Old ECR Secrets

The following files contain hardcoded base64-encoded ECR credentials and should be removed:

```bash
# Remove old ECR secrets (optional - only if using IRSA exclusively)
rm -f manifists/argo-application/ecr-secret.yaml
rm -f manifists/argo-application/ecr-secret-for-aiu.yaml
rm -f manifists/argo-application/github-secret.yaml
```

## IAM Policies Explanation

### ArgoCD Image Updater Policy
- `ecr:GetAuthorizationToken`: Required to authenticate with ECR
- `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`: To pull images
- `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`: To push images
- `ecr:BatchCheckLayerAvailability`, `ecr:GetLifecyclePolicy`, `ecr:DescribeRepositories`, `ecr:DescribeImages`, `ecr:ListImages`: For image metadata operations

### EKS Pods Policy
- `ecr:GetAuthorizationToken`: Required to authenticate with ECR
- `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`: To pull images
- `ecr:DescribeImages`, `ecr:DescribeRepositories`: For image metadata

## Troubleshooting

### Pod cannot pull images from ECR

1. **Check service account annotation**:
   ```bash
   kubectl describe sa ecr-access-sa -n test
   ```

2. **Verify IAM role exists**:
   ```bash
   aws iam get-role --role-name my-cluster-eks-pods-ecr-access-role
   ```

3. **Check pod logs**:
   ```bash
   kubectl logs -n test deployment/my-app
   ```

4. **Check EKS pod identity webhook**:
   ```bash
   kubectl get pods -n kube-system | grep pod-identity-webhook
   ```

### ArgoCD Image Updater cannot access ECR

1. **Check service account token**:
   ```bash
   kubectl get secrets -n argocd | grep argocd-image-updater-token
   ```

2. **Verify the role annotation**:
   ```bash
   kubectl describe sa argocd-image-updater -n argocd
   ```

3. **Check image-updater pod logs**:
   ```bash
   kubectl logs -n argocd deployment/argocd-image-updater
   ```

## References

- [AWS IAM Roles for Service Accounts Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [ECR Authentication Documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/Registries.html)
- [ArgoCD Image Updater Documentation](https://argocd-image-updater.readthedocs.io/en/stable/)
