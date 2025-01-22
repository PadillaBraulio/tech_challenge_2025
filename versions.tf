terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.7"
    }
  }
    backend "s3" {
      bucket = "challengeterraformstate"
      key    = "challenge/state_file"
      region = "us-east-1"
  }
}


