resource "aws_ecr_repository" "my_repo" {
  name                 = "my-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "my-repo"
  }
}

resource "aws_ecr_repository_policy" "my_repo" {
  repository = aws_ecr_repository.my_repo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullPush"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.argocd_image_updater.arn,
            aws_iam_role.eks_pods_ecr_access.arn,
            aws_iam_role.eks_nodes.arn
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetLifecyclePolicy",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages"
        ]
      }
    ]
  })
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.my_repo.repository_url
}

output "ecr_repository_arn" {
  description = "ECR Repository ARN"
  value       = aws_ecr_repository.my_repo.arn
}
