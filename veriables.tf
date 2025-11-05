variable "AZs" {
  description = "List of Availability Zones"
  type        = list(string)
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}
variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
}
variable "public_subnet_cidrs" {
  description = "The CIDR block for the public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "The CIDR block for the private subnets"
  type        = list(string)
}