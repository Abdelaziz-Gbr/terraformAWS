output "cluster_endpoint" {
  description = "Endpoint for EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "jenkins_role_arn" {
  description = "IAM role ARN for Jenkins service account"
  value       = aws_iam_role.jenkins.arn
}

output "jenkins_role_name" {
  description = "IAM role name for Jenkins"
  value       = aws_iam_role.jenkins.name
}
