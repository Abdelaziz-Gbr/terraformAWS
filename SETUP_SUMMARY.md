# Project Update Summary: ECR IRSA Configuration

## Overview

Your Terraform AWS project has been updated to use **IAM Roles for Service Accounts (IRSA)** for ECR access. This replaces hardcoded credentials with secure, temporary AWS credentials managed by AWS STS.

## What Changed

### New Terraform Modules

1. **`modules/eks/ecr.tf`** - Creates and manages the ECR repository
   - ECR repository: `my-repo`
   - Repository policy allowing pull/push operations
   - Outputs repository URL and ARN

2. **`modules/eks/irsa-ecr-roles.tf`** - Sets up IRSA for both use cases
   - `my-cluster-argocd-image-updater-role`: For ArgoCD Image Updater with push permissions
   - `my-cluster-eks-pods-ecr-access-role`: For Kubernetes pods with pull permissions
   - Both roles use OIDC provider for secure authentication

### Updated Terraform Files

- **`main.tf`**: Now passes `oidc_provider_arn` from EKS module to enable IRSA
- **`modules/eks/variables.tf`**: Added `oidc_provider_arn` variable

### New Kubernetes Manifests

1. **`manifists/argo-application/argocd-image-updater-sa.yaml`**
   - Service account for ArgoCD Image Updater with IRSA annotation

2. **`manifists/argo-application/ecr-access-sa.yaml`**
   - Reusable service accounts in `default` and `test` namespaces
   - Can be used by any pod needing ECR access

3. **`manifists/base-app/my-app-deployment-irsa.yaml`**
   - Example deployment showing how to use IRSA

### Updated Configuration Files

- **`values/image-updater.yaml`**
  - Removed hardcoded ECR credentials reference
  - Now uses pre-existing service account with IRSA
  - Set `serviceAccount.create = false`

### Documentation

- **`IRSA_ECR_SETUP.md`**: Comprehensive setup and troubleshooting guide
- **`QUICK_REFERENCE.md`**: Quick setup and verification commands
- **`MIGRATION_GUIDE.md`**: Step-by-step migration from secrets to IRSA
- **`SETUP_SUMMARY.md`**: This file

### Helper Script

- **`setup-irsa-ecr.sh`**: Automated setup script that:
  - Gets your AWS account ID and region
  - Updates all manifest files automatically
  - Runs Terraform plan and apply
  - Deploys service accounts
  - Verifies IRSA setup

## Key Benefits

| Feature | Benefit |
|---------|---------|
| No Stored Secrets | Eliminates plaintext credentials in Kubernetes |
| Temporary Credentials | AWS STS provides short-lived tokens (auto-rotating) |
| Least Privilege | Each role has only necessary permissions |
| Audit Trail | All operations logged to CloudTrail |
| Pod-level Control | Different pods/namespaces can have different permissions |
| Zero Configuration | AWS SDK automatically uses OIDC tokens |

## Quick Start

### Automated Setup (Recommended)
```bash
./setup-irsa-ecr.sh
```

### Manual Setup
```bash
# 1. Apply Terraform
terraform plan
terraform apply

# 2. Update manifests (replace with your account ID)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/argo-application/*.yaml manifists/base-app/*.yaml

# 3. Deploy service accounts
kubectl apply -f manifists/argo-application/argocd-image-updater-sa.yaml
kubectl apply -f manifists/argo-application/ecr-access-sa.yaml

# 4. Restart ArgoCD Image Updater
kubectl rollout restart deployment/argocd-image-updater -n argocd
```

## Using IRSA in Your Deployments

### Before (with ECR Secrets)
```yaml
spec:
  imagePullSecrets:
  - name: ecr-secret
  containers:
  - image: 579385932895.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
```

### After (with IRSA)
```yaml
spec:
  serviceAccountName: ecr-access-sa
  containers:
  - image: 579385932895.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
```

## Verification

```bash
# Verify service accounts have IRSA annotation
kubectl get sa argocd-image-updater -n argocd -o yaml | grep role-arn
kubectl get sa ecr-access-sa -n test -o yaml | grep role-arn

# Check ECR repository exists
aws ecr describe-repositories --repository-names my-repo --region us-east-1

# Check IAM roles exist
aws iam get-role --role-name my-cluster-argocd-image-updater-role
aws iam get-role --role-name my-cluster-eks-pods-ecr-access-role
```

## Files to Delete (Optional)

Old hardcoded ECR secret files (now obsolete):
```bash
rm -f manifists/argo-application/ecr-secret.yaml
rm -f manifists/argo-application/ecr-secret-for-aiu.yaml
```

## Next Steps

1. **Run the setup script**: `./setup-irsa-ecr.sh`
2. **Verify IRSA setup**: Check service account annotations
3. **Test deployments**: Use `my-app-deployment-irsa.yaml` as reference
4. **Migrate existing deployments**: Update `serviceAccountName` and remove `imagePullSecrets`
5. **Review documentation**: See `MIGRATION_GUIDE.md` for detailed steps

## Documentation Files

- **`QUICK_REFERENCE.md`** - Quick setup and commands (start here!)
- **`IRSA_ECR_SETUP.md`** - Detailed technical documentation
- **`MIGRATION_GUIDE.md`** - Step-by-step migration instructions
- **`setup-irsa-ecr.sh`** - Automated setup script

## Architecture

```
EKS Cluster with OIDC Provider
│
├── ArgoCD Image Updater
│   └── Service Account (with IRSA)
│       └── Assumes IAM Role: my-cluster-argocd-image-updater-role
│           └── Can push/pull from my-repo ECR
│
└── Application Pods
    └── Service Account (with IRSA)
        └── Assumes IAM Role: my-cluster-eks-pods-ecr-access-role
            └── Can pull from my-repo ECR
```

## Security Considerations

✅ **Implemented**:
- OIDC provider for secure token exchange
- Temporary credentials with automatic rotation
- Least privilege IAM policies
- No plaintext credentials stored
- Full CloudTrail audit logging

## Support & Troubleshooting

See the documentation files for:
- Detailed setup instructions: `IRSA_ECR_SETUP.md`
- Quick reference and commands: `QUICK_REFERENCE.md`
- Migration steps: `MIGRATION_GUIDE.md`
- Troubleshooting: All documentation files have sections

## Questions?

1. Check the relevant documentation file
2. Review the example deployment: `manifists/base-app/my-app-deployment-irsa.yaml`
3. Test using the automated script: `setup-irsa-ecr.sh`

---

**Last Updated**: 2025-11-16
**Configuration**: ECR IRSA for ArgoCD and EKS Pods
**Status**: Ready for deployment
