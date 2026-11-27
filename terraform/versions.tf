terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in S3 so that every pipeline run sees the same infrastructure
  # (without it each run would try to create a brand-new server).
  # bucket / key / region are passed at `terraform init` time via -backend-config,
  # so no account-specific values are stored in Git. See backend.hcl.example.
  # `use_lockfile` = native S3 state locking (no DynamoDB table needed).
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
