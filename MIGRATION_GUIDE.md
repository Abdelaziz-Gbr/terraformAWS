# Migration Guide: From ECR Secrets to IRSA

## Why Migrate to IRSA?

| Aspect | ECR Secrets | IRSA |
|--------|-----------|------|
| Credentials Storage | Kubernetes Secret (base64 encoded) | AWS STS (temporary tokens) |
| Security | Lower (plaintext in etcd) | Higher (encrypted, temporary) |
| Rotation | Manual or via operator | Automatic (hourly) |
| Audit Trail | Limited | Full CloudTrail logging |
| Complexity | Simple setup | Initial setup, then simple usage |
| Per-pod Control | Limited | Full per-pod/namespace control |

## Step-by-Step Migration

### Phase 1: Preparation (No Downtime)

1. **Verify OIDC Provider Exists**
   ```bash
   aws iam list-open-id-connect-providers
   ```

2. **Apply New Terraform Configuration**
   ```bash
   # This creates IAM roles but doesn't affect running pods
   terraform plan
   terraform apply
   ```

3. **Deploy New Service Accounts**
   ```bash
   kubectl apply -f manifists/argo-application/argocd-image-updater-sa.yaml
   kubectl apply -f manifists/argo-application/ecr-access-sa.yaml
   ```

### Phase 2: Migration (Minimal Downtime)

#### Option A: Gradual Migration (Recommended)

1. **Update ArgoCD Image Updater First**
   ```bash
   # Update values to use the new service account
   kubectl rollout restart deployment/argocd-image-updater -n argocd
   
   # Verify it's working
   kubectl logs -n argocd deployment/argocd-image-updater
   ```

2. **Update Your Deployments**
   ```yaml
   # Old deployment
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-app
   spec:
     template:
       spec:
         imagePullSecrets:
         - name: ecr-secret  # <-- Remove this
         containers:
         - image: 579385932895.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
   
   # New deployment
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-app
   spec:
     template:
       spec:
         serviceAccountName: ecr-access-sa  # <-- Add this
         # imagePullSecrets removed
         containers:
         - image: 579385932895.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
   ```

3. **Verify New Deployments**
   ```bash
   kubectl apply -f manifists/base-app/myapp-deployment.yaml
   kubectl get pods
   ```

#### Option B: Big Bang Migration (One-off)

```bash
# 1. Update ArgoCD
kubectl rollout restart deployment/argocd-image-updater -n argocd

# 2. Update all deployments at once
kubectl set serviceaccount deployment/my-app ecr-access-sa -n test

# 3. Restart deployments
kubectl rollout restart deployment/my-app -n test
```

### Phase 3: Cleanup (After Verification)

1. **Verify All Pods Are Running**
   ```bash
   kubectl get pods -n test -o wide
   kubectl get pods -n argocd -o wide
   ```

2. **Delete Old ECR Secrets** (if no longer needed)
   ```bash
   kubectl delete secret ecr-secret -n argocd
   kubectl delete secret ecr-secret -n test
   ```

3. **Remove Old Files**
   ```bash
   rm -f manifists/argo-application/ecr-secret.yaml
   rm -f manifists/argo-application/ecr-secret-for-aiu.yaml
   ```

## Migration Checklist

### Pre-Migration
- [ ] OIDC provider configured and working
- [ ] Terraform backend initialized
- [ ] Kubeconfig updated
- [ ] Backed up current secrets
- [ ] Identified all deployments using ECR

### During Migration
- [ ] Created ECR repository
- [ ] Created IAM roles
- [ ] Deployed service accounts
- [ ] Verified service account annotations
- [ ] Tested image pull with IRSA

### Post-Migration
- [ ] All deployments using IRSA
- [ ] ArgoCD Image Updater working
- [ ] Old secrets deleted
- [ ] CloudTrail logs verified
- [ ] Team trained on new process

## Troubleshooting Migration Issues

### Pods Still Can't Pull Images

```bash
# Check if WebHook is injecting AWS credentials
kubectl get pods -n test -o yaml | grep -A 5 AWS_ROLE_ARN

# If missing, check webhook
kubectl get pods -n kube-system | grep pod-identity-webhook

# Restart pods to trigger webhook injection
kubectl delete pods -n test --all
```

### ArgoCD Image Updater Not Updating Images

```bash
# Check if using new service account
kubectl get deployment argocd-image-updater -n argocd -o yaml | grep serviceAccountName

# Check role annotation
kubectl get sa argocd-image-updater -n argocd -o yaml

# View detailed logs
kubectl logs -n argocd deployment/argocd-image-updater -f
```

### IAM Role Not Working

```bash
# Verify role exists
aws iam get-role --role-name my-cluster-eks-pods-ecr-access-role

# Check role policy
aws iam get-role-policy --role-name my-cluster-eks-pods-ecr-access-role \
  --policy-name my-cluster-eks-pods-ecr-access-policy

# Test AssumeRole
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/my-cluster-eks-pods-ecr-access-role \
  --role-session-name test \
  --web-identity-token $(kubectl create token ecr-access-sa -n test)
```

## Rollback Plan

If issues occur during migration:

```bash
# 1. Restore old deployment
kubectl rollout undo deployment/my-app -n test

# 2. Restore old secrets
kubectl apply -f manifists/argo-application/ecr-secret.yaml

# 3. Set imagePullSecrets back
kubectl patch deployment my-app -n test -p \
  '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ecr-secret"}]}}}}'
```

## Performance Impact

- **Negative**: Slight increase in first pod startup (additional OIDC call)
- **Positive**: No more managing/storing secrets in Kubernetes
- **Overall**: Negligible performance difference after initial testing

## Cost Considerations

- No additional AWS costs for IAM roles or OIDC provider
- Possible reduction in secret rotation/management overhead
- No change to ECR costs

## Questions?

Refer to:
- `IRSA_ECR_SETUP.md` - Detailed setup guide
- `QUICK_REFERENCE.md` - Quick commands
- AWS Documentation - https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
