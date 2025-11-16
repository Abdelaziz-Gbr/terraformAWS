# ECR IRSA Configuration - Index

Welcome! This project has been updated to use **IAM Roles for Service Accounts (IRSA)** for secure ECR access. This document will guide you to the right resources.

## 📚 Documentation Index

### Quick Start (5 minutes)
- **Start here if you're in a hurry**
- See: [`QUICK_REFERENCE.md`](QUICK_REFERENCE.md)
- Or: Run `./setup-irsa-ecr.sh` for automated setup

### Detailed Setup (30 minutes)
- **Complete step-by-step guide**
- See: [`IRSA_ECR_SETUP.md`](IRSA_ECR_SETUP.md)
- Includes troubleshooting and verification steps

### Architecture & Design
- **Understand how IRSA works**
- See: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Visual diagrams and flow explanations

### Migration from Secrets to IRSA
- **Step-by-step migration guide**
- See: [`MIGRATION_GUIDE.md`](MIGRATION_GUIDE.md)
- Includes rollback instructions

### Project Overview
- **Summary of all changes**
- See: [`SETUP_SUMMARY.md`](SETUP_SUMMARY.md)
- High-level overview of what was updated

## 🚀 Quick Start Commands

### Automated Setup (Recommended)
```bash
# Run the setup script - it handles everything
./setup-irsa-ecr.sh
```

### Manual Setup
```bash
# 1. Apply Terraform
terraform plan
terraform apply

# 2. Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 3. Update manifests
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/argo-application/*.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/base-app/*.yaml

# 4. Deploy service accounts
kubectl apply -f manifists/argo-application/argocd-image-updater-sa.yaml
kubectl apply -f manifists/argo-application/ecr-access-sa.yaml

# 5. Restart ArgoCD Image Updater
kubectl rollout restart deployment/argocd-image-updater -n argocd

# 6. Verify setup
./validate-irsa-setup.sh
```

## 🔍 Validation

### Quick Validation
```bash
./validate-irsa-setup.sh
```

### Manual Verification
```bash
# Check service account annotations
kubectl get sa argocd-image-updater -n argocd -o yaml
kubectl get sa ecr-access-sa -n test -o yaml

# Check IAM roles
aws iam get-role --role-name my-cluster-argocd-image-updater-role
aws iam get-role --role-name my-cluster-eks-pods-ecr-access-role

# Check ECR repository
aws ecr describe-repositories --repository-names my-repo
```

## 📋 What Changed

### New Files Created
- `modules/eks/ecr.tf` - ECR repository and policy
- `modules/eks/irsa-ecr-roles.tf` - IRSA roles and policies
- `manifists/argo-application/argocd-image-updater-sa.yaml` - Service account
- `manifists/argo-application/ecr-access-sa.yaml` - Service account
- `manifists/base-app/my-app-deployment-irsa.yaml` - Example deployment
- `setup-irsa-ecr.sh` - Automated setup script
- `validate-irsa-setup.sh` - Validation script
- `QUICK_REFERENCE.md` - Quick start guide
- `IRSA_ECR_SETUP.md` - Detailed setup guide
- `MIGRATION_GUIDE.md` - Migration instructions
- `ARCHITECTURE.md` - Architecture diagrams
- `SETUP_SUMMARY.md` - Project overview

### Modified Files
- `main.tf` - Passes `oidc_provider_arn` to EKS module
- `modules/eks/variables.tf` - Added `oidc_provider_arn` variable
- `values/image-updater.yaml` - Removed hardcoded ECR credentials

### Files to Consider Removing (Optional)
- `manifists/argo-application/ecr-secret.yaml` - Old hardcoded secrets
- `manifists/argo-application/ecr-secret-for-aiu.yaml` - Old hardcoded secrets

## 🎯 Key Concepts

### IRSA (IAM Roles for Service Accounts)
- Kubernetes service accounts assume AWS IAM roles
- Uses OIDC provider to exchange service account tokens for AWS credentials
- No need to store or manage AWS credentials in Kubernetes secrets

### How It Works
1. Pod uses a service account with an IRSA annotation
2. IRSA webhook injects AWS credential environment variables
3. AWS SDK (in pod) uses these to assume the IAM role
4. Temporary credentials obtained from STS
5. Pod uses these credentials to access AWS services (ECR)
6. Credentials auto-rotate every ~15 minutes

### Benefits
- ✅ No secrets stored in Kubernetes
- ✅ Automatic credential rotation
- ✅ Fine-grained per-pod access control
- ✅ Full CloudTrail audit logging
- ✅ Least privilege IAM policies

## 🔗 Related AWS Resources

### Terraform Modules
- `modules/eks/cluster.tf` - EKS cluster
- `modules/eks/oidc.tf` - OIDC provider (already existed)
- `modules/eks/ecr.tf` - ECR repository (new)
- `modules/eks/irsa-ecr-roles.tf` - IRSA roles (new)

### Kubernetes Resources
- Service Accounts: `argocd-image-updater`, `ecr-access-sa`
- IRSA WebHook: Automatically injected by AWS EKS

### AWS Resources
- ECR Repository: `my-repo`
- IAM Roles: 
  - `my-cluster-argocd-image-updater-role`
  - `my-cluster-eks-pods-ecr-access-role`
- OIDC Provider: `oidc.eks.<region>.amazonaws.com`

## 🆘 Troubleshooting

### Common Issues

**Issue: Pods can't pull images**
- Check service account has IRSA annotation
- Verify IAM role permissions
- Check pod events: `kubectl describe pod <name>`

**Issue: ArgoCD Image Updater not updating**
- Restart the pod: `kubectl rollout restart deployment/argocd-image-updater -n argocd`
- Check service account: `kubectl get sa argocd-image-updater -n argocd`
- Check logs: `kubectl logs -n argocd deployment/argocd-image-updater`

**Issue: ECR repository access denied**
- Verify IAM policy allows ECR operations
- Check role trust relationship
- Test credentials: `aws sts assume-role-with-web-identity`

See [`IRSA_ECR_SETUP.md`](IRSA_ECR_SETUP.md) for detailed troubleshooting.

## 📞 Support Resources

- **AWS Documentation**: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- **ArgoCD Image Updater**: https://argocd-image-updater.readthedocs.io/
- **ECR Documentation**: https://docs.aws.amazon.com/AmazonECR/latest/userguide/

## ✅ Next Steps

1. **Run Setup**: `./setup-irsa-ecr.sh`
2. **Verify**: `./validate-irsa-setup.sh`
3. **Test**: Try pulling an image from ECR
4. **Migrate**: Update your existing deployments
5. **Monitor**: Check CloudTrail for audit logs

## 📝 Files to Review

| File | Purpose |
|------|---------|
| `QUICK_REFERENCE.md` | Quick start and common commands |
| `IRSA_ECR_SETUP.md` | Detailed technical documentation |
| `MIGRATION_GUIDE.md` | Step-by-step migration instructions |
| `ARCHITECTURE.md` | System architecture and diagrams |
| `SETUP_SUMMARY.md` | High-level overview |
| `setup-irsa-ecr.sh` | Automated setup script |
| `validate-irsa-setup.sh` | Validation and verification |

---

**Status**: ✅ Ready for deployment  
**Version**: 1.0  
**Last Updated**: 2025-11-16

**Questions?** Check [`QUICK_REFERENCE.md`](QUICK_REFERENCE.md) or [`IRSA_ECR_SETUP.md`](IRSA_ECR_SETUP.md)
