#!/bin/bash

# Validation script for IRSA ECR setup
# This script checks if all components are correctly configured

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}IRSA ECR Setup Validation${NC}"
echo -e "${BLUE}================================${NC}\n"

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARN_COUNT++))
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        fail "$1 is not installed"
        return 1
    fi
    pass "$1 is installed"
    return 0
}

# 1. Check prerequisites
echo -e "${YELLOW}Checking Prerequisites...${NC}\n"
check_command "aws"
check_command "kubectl"
check_command "terraform"

echo -e "\n${YELLOW}Checking AWS Configuration...${NC}\n"

# Get AWS info
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "ERROR")
AWS_REGION=$(aws configure get region || echo "us-east-1")

if [[ "$AWS_ACCOUNT_ID" != "ERROR" ]]; then
    pass "AWS credentials configured (Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION)"
else
    fail "AWS credentials not configured"
fi

echo -e "\n${YELLOW}Checking Terraform State...${NC}\n"

if [ -f "terraform.tfstate" ]; then
    pass "Terraform state file exists"
    
    if terraform state list | grep -q "module.eks.aws_ecr_repository"; then
        pass "ECR repository created in Terraform"
    else
        warn "ECR repository not found in Terraform state (might not be applied yet)"
    fi
else
    warn "Terraform state file not found (might not be initialized)"
fi

echo -e "\n${YELLOW}Checking Terraform Files...${NC}\n"

if [ -f "modules/eks/ecr.tf" ]; then
    pass "ECR Terraform module exists (modules/eks/ecr.tf)"
else
    fail "ECR Terraform module missing (modules/eks/ecr.tf)"
fi

if [ -f "modules/eks/irsa-ecr-roles.tf" ]; then
    pass "IRSA roles Terraform module exists (modules/eks/irsa-ecr-roles.tf)"
else
    fail "IRSA roles Terraform module missing (modules/eks/irsa-ecr-roles.tf)"
fi

if grep -q "oidc_provider_arn" main.tf; then
    pass "main.tf passes oidc_provider_arn to EKS module"
else
    fail "main.tf does not pass oidc_provider_arn to EKS module"
fi

echo -e "\n${YELLOW}Checking Kubernetes Manifests...${NC}\n"

if [ -f "manifists/argo-application/argocd-image-updater-sa.yaml" ]; then
    pass "ArgoCD Image Updater service account manifest exists"
    
    if grep -q "eks.amazonaws.com/role-arn" manifists/argo-application/argocd-image-updater-sa.yaml; then
        if ! grep -q "ACCOUNT_ID" manifists/argo-application/argocd-image-updater-sa.yaml; then
            pass "ArgoCD Image Updater service account has IRSA annotation (and account ID filled)"
        else
            warn "ArgoCD Image Updater service account needs account ID filled in"
        fi
    else
        fail "ArgoCD Image Updater service account missing IRSA annotation"
    fi
else
    fail "ArgoCD Image Updater service account manifest missing"
fi

if [ -f "manifists/argo-application/ecr-access-sa.yaml" ]; then
    pass "ECR access service account manifest exists"
    
    if grep -q "eks.amazonaws.com/role-arn" manifists/argo-application/ecr-access-sa.yaml; then
        if ! grep -q "ACCOUNT_ID" manifists/argo-application/ecr-access-sa.yaml; then
            pass "ECR access service accounts have IRSA annotation (and account ID filled)"
        else
            warn "ECR access service accounts need account ID filled in"
        fi
    else
        fail "ECR access service accounts missing IRSA annotation"
    fi
else
    fail "ECR access service account manifest missing"
fi

if [ -f "manifists/base-app/my-app-deployment-irsa.yaml" ]; then
    pass "Example deployment with IRSA exists"
else
    warn "Example deployment with IRSA missing (optional)"
fi

echo -e "\n${YELLOW}Checking Kubernetes Cluster...${NC}\n"

if kubectl cluster-info &> /dev/null; then
    pass "Connected to Kubernetes cluster"
    
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | grep -o "[^/]*$" || echo "unknown")
    echo -e "  Current context: $CLUSTER_NAME"
else
    fail "Cannot connect to Kubernetes cluster"
fi

echo -e "\n${YELLOW}Checking Service Accounts in Cluster...${NC}\n"

if kubectl get sa argocd-image-updater -n argocd &> /dev/null; then
    pass "ArgoCD Image Updater service account exists in cluster"
    
    ROLE_ARN=$(kubectl get sa argocd-image-updater -n argocd -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
    if [ -n "$ROLE_ARN" ]; then
        pass "ArgoCD Image Updater service account has IRSA annotation"
        echo -e "  Role ARN: $ROLE_ARN"
    else
        warn "ArgoCD Image Updater service account missing IRSA annotation"
    fi
else
    warn "ArgoCD Image Updater service account not deployed yet"
fi

if kubectl get sa ecr-access-sa -n test &> /dev/null; then
    pass "ECR access service account exists in test namespace"
    
    ROLE_ARN=$(kubectl get sa ecr-access-sa -n test -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
    if [ -n "$ROLE_ARN" ]; then
        pass "ECR access service account has IRSA annotation"
        echo -e "  Role ARN: $ROLE_ARN"
    else
        warn "ECR access service account missing IRSA annotation"
    fi
else
    warn "ECR access service account not deployed in test namespace yet"
fi

echo -e "\n${YELLOW}Checking AWS IAM Roles...${NC}\n"

if aws iam get-role --role-name "my-cluster-argocd-image-updater-role" &> /dev/null; then
    pass "ArgoCD Image Updater IAM role exists"
    
    if aws iam get-role-policy --role-name "my-cluster-argocd-image-updater-role" --policy-name "my-cluster-argocd-image-updater-ecr-policy" &> /dev/null; then
        pass "ArgoCD Image Updater IAM policy exists"
    else
        fail "ArgoCD Image Updater IAM policy missing"
    fi
else
    warn "ArgoCD Image Updater IAM role not created yet"
fi

if aws iam get-role --role-name "my-cluster-eks-pods-ecr-access-role" &> /dev/null; then
    pass "EKS pods ECR access IAM role exists"
    
    if aws iam get-role-policy --role-name "my-cluster-eks-pods-ecr-access-role" --policy-name "my-cluster-eks-pods-ecr-access-policy" &> /dev/null; then
        pass "EKS pods ECR access IAM policy exists"
    else
        fail "EKS pods ECR access IAM policy missing"
    fi
else
    warn "EKS pods ECR access IAM role not created yet"
fi

echo -e "\n${YELLOW}Checking ECR Repository...${NC}\n"

ECR_REPO=$(aws ecr describe-repositories --repository-names "my-repo" --region "$AWS_REGION" 2>/dev/null | jq -r '.repositories[0].repositoryUri' || echo "")

if [ -n "$ECR_REPO" ] && [ "$ECR_REPO" != "null" ]; then
    pass "ECR repository 'my-repo' exists"
    echo -e "  Repository URL: $ECR_REPO"
else
    warn "ECR repository 'my-repo' not found (might not be created yet)"
fi

echo -e "\n${YELLOW}Checking OIDC Provider...${NC}\n"

if aws iam list-open-id-connect-providers &> /dev/null; then
    OIDC_COUNT=$(aws iam list-open-id-connect-providers | jq '.OpenIDConnectProviderList | length')
    if [ "$OIDC_COUNT" -gt 0 ]; then
        pass "OIDC provider configured ($OIDC_COUNT provider(s) found)"
    else
        warn "No OIDC providers found"
    fi
else
    fail "Cannot list OIDC providers"
fi

echo -e "\n${YELLOW}Checking Documentation...${NC}\n"

DOCS=("QUICK_REFERENCE.md" "IRSA_ECR_SETUP.md" "MIGRATION_GUIDE.md" "ARCHITECTURE.md" "SETUP_SUMMARY.md")
for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        pass "Documentation file exists: $doc"
    else
        fail "Documentation file missing: $doc"
    fi
done

echo -e "\n${YELLOW}Checking Helper Scripts...${NC}\n"

if [ -f "setup-irsa-ecr.sh" ]; then
    pass "Setup script exists (setup-irsa-ecr.sh)"
    if [ -x "setup-irsa-ecr.sh" ]; then
        pass "Setup script is executable"
    else
        fail "Setup script is not executable"
    fi
else
    fail "Setup script missing (setup-irsa-ecr.sh)"
fi

echo -e "\n${BLUE}================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}================================${NC}\n"

echo -e "${GREEN}PASSED: $PASS_COUNT${NC}"
echo -e "${YELLOW}WARNINGS: $WARN_COUNT${NC}"
echo -e "${RED}FAILED: $FAIL_COUNT${NC}\n"

if [ "$FAIL_COUNT" -eq 0 ]; then
    if [ "$WARN_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed! Setup is complete.${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Setup is mostly complete but review warnings above.${NC}"
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Run './setup-irsa-ecr.sh' to automate remaining setup"
        echo "2. Or follow QUICK_REFERENCE.md for manual setup"
        exit 0
    fi
else
    echo -e "${RED}✗ Setup incomplete. Review failures above.${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review failed checks above"
    echo "2. Run './setup-irsa-ecr.sh' to complete setup"
    echo "3. Or follow IRSA_ECR_SETUP.md for detailed instructions"
    exit 1
fi
