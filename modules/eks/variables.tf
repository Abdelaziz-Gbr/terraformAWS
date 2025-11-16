variable "cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "The Kubernetes version for the EKS cluster."
  type        = string
}

variable "private_subnet_ids" {
  description = "A list of private subnet IDs for the EKS cluster."
  type        = list(string)
}

variable "vpc_id" {
  description = "The VPC ID where the EKS cluster will be deployed."
  type        = string
}


variable "node_desired_size" {
  description = "The desired number of worker nodes in the EKS node group."
  type        = number
}
variable "node_max_size" {
  description = "The maximum number of worker nodes in the EKS node group."
  type        = number
}
variable "node_min_size" {
  description = "The minimum number of worker nodes in the EKS node group."
  type        = number
}

variable "node_instance_types" {
  description = "The instance types for the EKS worker nodes."
  type        = list(string)
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster."
  type        = string
}