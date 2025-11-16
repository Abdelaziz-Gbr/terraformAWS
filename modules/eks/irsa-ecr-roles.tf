
# IAM Role for ArgoCD Image Updater (using IRSA)
resource "aws_iam_role" "argocd_image_updater" {
  name = "${var.cluster_name}-argocd-image-updater-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:argocd:argocd-image-updater"
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-argocd-image-updater"
  }
}

# IAM Policy for ArgoCD Image Updater to access ECR
resource "aws_iam_role_policy" "argocd_image_updater_ecr" {
  name = "${var.cluster_name}-argocd-image-updater-ecr-policy"
  role = aws_iam_role.argocd_image_updater.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetLifecyclePolicy",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for EKS Pods to access ECR (using IRSA)
resource "aws_iam_role" "eks_pods_ecr_access" {
  name = "${var.cluster_name}-eks-pods-ecr-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:*:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-eks-pods-ecr-access"
  }
}

# IAM Policy for EKS Pods to access ECR
resource "aws_iam_role_policy" "eks_pods_ecr_access" {
  name = "${var.cluster_name}-eks-pods-ecr-access-policy"
  role = aws_iam_role.eks_pods_ecr_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = "*"
      }
    ]
  })
}

# Data source to get the OIDC provider details
data "aws_iam_openid_connect_provider" "eks" {
  arn = var.oidc_provider_arn
}

output "argocd_image_updater_role_arn" {
  description = "ARN of ArgoCD Image Updater IAM Role"
  value       = aws_iam_role.argocd_image_updater.arn
}

output "eks_pods_ecr_access_role_arn" {
  description = "ARN of EKS Pods ECR Access IAM Role"
  value       = aws_iam_role.eks_pods_ecr_access.arn
}
