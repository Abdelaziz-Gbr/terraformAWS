terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  shared_config_files      = ["conf"]
  shared_credentials_files = ["creds"]
  profile                  = "default"
}