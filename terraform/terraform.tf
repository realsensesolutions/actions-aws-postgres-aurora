################################################################################
# Terraform Configuration
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }

  backend "s3" {}
}

################################################################################
# Provider Configuration
################################################################################

provider "aws" {
  # Region inherited from AWS_REGION environment variable or AWS config

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Instance  = var.instance
    }
  }
}


