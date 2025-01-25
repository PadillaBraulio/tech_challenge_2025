# Pin specific Terraform and provider versions to ensure compatibility and control updates
terraform {
  required_version = "= 1.10.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.84.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
  }
}


