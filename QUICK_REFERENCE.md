# Quick Reference: ECR IRSA Configuration

## TL;DR - Quick Setup

```bash
# 1. Run the setup script (automated)
./setup-irsa-ecr.sh

# OR

# 2. Manual setup
terraform plan
terraform apply

# 3. Update manifests with your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/argo-application/argocd-image-updater-sa.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/argo-application/ecr-access-sa.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" manifists/base-app/my-app-deployment-irsa.yaml

# 4. Deploy service accounts
kubectl apply -f manifists/argo-application/argocd-image-updater-sa.yaml
kubectl apply -f manifists/argo-application/ecr-access-sa.yaml

# 5. Restart ArgoCD Image Updater to pick up the new service account
kubectl rollout restart deployment/argocd-image-updater -n argocd
```

## What Gets Created

### Terraform Resources

1. **ECR Repository**: `my-repo`
   - Auto-scanned on push
   - Mutable tags

2. **IAM Roles**:
   - `my-cluster-argocd-image-updater-role`: For ArgoCD Image Updater
   - `my-cluster-eks-pods-ecr-access-role`: For EKS pods

3. **OIDC Provider Connection**: Already exists, now used by new roles

### Kubernetes Resources

1. **Service Accounts**:
   - `argocd-image-updater` in `argocd` namespace (for ArgoCD Image Updater)
   - `ecr-access-sa` in `default` namespace (for regular pods)
   - `ecr-access-sa` in `test` namespace (for test pods)

## Using IRSA in Your Deployments

### Basic Deployment with ECR Image

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: ecr-access-sa  # <-- Use this service account
      containers:
      - name: my-app
        image: 579385932895.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
        imagePullPolicy: IfNotPresent
```

### Key Points

- **No imagePullSecrets needed** - IRSA handles authentication automatically
- **No base64 encoded credentials** - Everything is managed by AWS IAM
- **Automatic credential refresh** - STS provides temporary credentials that auto-rotate

## Verification Commands

```bash
# Check service account has IRSA annotation
kubectl describe sa argocd-image-updater -n argocd
kubectl describe sa ecr-access-sa -n test

# Check IAM roles exist
aws iam get-role --role-name my-cluster-argocd-image-updater-role
aws iam get-role --role-name my-cluster-eks-pods-ecr-access-role

# Check ECR repository
aws ecr describe-repositories --repository-names my-repo --region us-east-1

# Test pod can pull from ECR
kubectl run test-pull --image=579385932895.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest \
  --serviceaccount=ecr-access-sa -n test --rm -it

# Check ArgoCD Image Updater logs
kubectl logs -n argocd deployment/argocd-image-updater
```

## Troubleshooting

### Pod can't pull images

```bash
# Check service account
kubectl get sa ecr-access-sa -n test -o yaml

# Check pod events
kubectl describe pod <pod-name> -n test

# Check AWS IAM role permissions
aws iam get-role-policy --role-name my-cluster-eks-pods-ecr-access-role \
  --policy-name my-cluster-eks-pods-ecr-access-policy

# Test ECR credentials
aws ecr get-authorization-token --region us-east-1
```

### ArgoCD Image Updater not updating

```bash
# Restart the pod
kubectl rollout restart deployment/argocd-image-updater -n argocd

# Check service account
kubectl get sa argocd-image-updater -n argocd -o yaml

# Check pod logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

## Cleanup (if reverting to secrets)

```bash
# Delete service accounts
kubectl delete sa ecr-access-sa -n default
kubectl delete sa ecr-access-sa -n test
kubectl delete sa argocd-image-updater -n argocd

# Destroy Terraform resources
terraform destroy
```

## Files Modified/Created

### New Files
- `modules/eks/ecr.tf` - ECR repository and policy
- `modules/eks/irsa-ecr-roles.tf` - IAM roles and IRSA configuration
- `manifists/argo-application/argocd-image-updater-sa.yaml` - Service account with IRSA
- `manifists/argo-application/ecr-access-sa.yaml` - General ECR access service accounts
- `manifists/base-app/my-app-deployment-irsa.yaml` - Example deployment
- `setup-irsa-ecr.sh` - Automated setup script
- `IRSA_ECR_SETUP.md` - Detailed documentation

### Updated Files
- `main.tf` - Passes OIDC provider ARN to EKS module
- `modules/eks/variables.tf` - Added `oidc_provider_arn` variable
- `values/image-updater.yaml` - Removed hardcoded credentials

### Old Files (Optional to remove)
- `manifists/argo-application/ecr-secret.yaml` - Contains hardcoded base64 credentials
- `manifists/argo-application/ecr-secret-for-aiu.yaml` - Contains hardcoded base64 credentials

## Security Checklist

- ✅ No stored credentials in Kubernetes secrets
- ✅ Uses temporary STS tokens (auto-rotating)
- ✅ Least privilege IAM policies
- ✅ CloudTrail audit logging
- ✅ Pod-level access control
- ✅ No need for docker config files

## Important Notes

1. **Replace ACCOUNT_ID**: The setup script does this automatically, but check manifests if done manually
2. **ECR Registry URL**: Should match your AWS account and region
3. **Namespace**: Create additional `ecr-access-sa` in other namespaces as needed
4. **Role Permissions**: ArgoCD Image Updater needs more permissions than regular pods (for push)
