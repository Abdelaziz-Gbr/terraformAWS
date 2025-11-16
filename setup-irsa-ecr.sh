#!/bin/bash

# Script to set up ECR access with IRSA for ArgoCD and EKS pods
# This script automates the configuration of IRSA for ECR access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}================================${NC}"
echo -e "${YELLOW}ECR IRSA Setup Script${NC}"
echo -e "${YELLOW}================================${NC}\n"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}AWS Account ID: $AWS_ACCOUNT_ID${NC}"

# Get AWS Region
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi
echo -e "${GREEN}AWS Region: $AWS_REGION${NC}"

# Get ECR Registry URL
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo -e "${GREEN}ECR Registry: $ECR_REGISTRY${NC}\n"

# Update manifest files with actual values
echo -e "${YELLOW}Updating manifest files with actual AWS account ID...${NC}"

FILES_TO_UPDATE=(
    "manifists/argo-application/argocd-image-updater-sa.yaml"
    "manifists/argo-application/ecr-access-sa.yaml"
    "manifists/base-app/my-app-deployment-irsa.yaml"
)

for file in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file" ]; then
        sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" "$file"
        sed -i "s|579385932895.dkr.ecr.us-east-1.amazonaws.com|$ECR_REGISTRY|g" "$file"
        echo -e "${GREEN}✓ Updated $file${NC}"
    else
        echo -e "${RED}✗ File not found: $file${NC}"
    fi
done

echo -e "\n${YELLOW}Running Terraform plan...${NC}"
terraform plan -out=tfplan

echo -e "\n${YELLOW}Do you want to apply the Terraform configuration? (yes/no)${NC}"
read -r response

if [ "$response" = "yes" ]; then
    echo -e "${YELLOW}Applying Terraform configuration...${NC}"
    terraform apply tfplan
    rm tfplan
    
    echo -e "\n${YELLOW}Updating kubeconfig...${NC}"
    aws eks update-kubeconfig --name my-cluster --region $AWS_REGION
    
    echo -e "\n${YELLOW}Deploying service accounts...${NC}"
    kubectl apply -f manifists/argo-application/argocd-image-updater-sa.yaml
    kubectl apply -f manifists/argo-application/ecr-access-sa.yaml
    
    echo -e "\n${YELLOW}Verifying IRSA setup...${NC}"
    
    echo -e "\n${GREEN}ArgoCD Image Updater Service Account:${NC}"
    kubectl get sa argocd-image-updater -n argocd -o yaml | grep -A 2 "eks.amazonaws.com/role-arn"
    
    echo -e "\n${GREEN}EKS Pods ECR Access Service Account (default):${NC}"
    kubectl get sa ecr-access-sa -n default -o yaml | grep -A 2 "eks.amazonaws.com/role-arn"
    
    echo -e "\n${GREEN}EKS Pods ECR Access Service Account (test):${NC}"
    kubectl get sa ecr-access-sa -n test -o yaml | grep -A 2 "eks.amazonaws.com/role-arn"
    
    echo -e "\n${GREEN}✓ IRSA setup completed successfully!${NC}"
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "1. Verify that the service accounts have the correct role annotations"
    echo "2. Deploy your applications using the 'ecr-access-sa' service account"
    echo "3. Test image pull from ECR"
    
else
    echo -e "${YELLOW}Terraform apply cancelled. Plan file saved as tfplan${NC}"
    echo -e "${YELLOW}Run 'terraform apply tfplan' when ready${NC}"
fi
