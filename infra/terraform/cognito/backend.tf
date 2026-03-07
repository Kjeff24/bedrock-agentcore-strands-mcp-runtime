# Terraform remote backend configuration.
# NOTE: You must create the S3 bucket (and optional DynamoDB lock table)
# manually before running `terraform init`, and update the values below.

terraform {
  backend "s3" {
    bucket       = "account-vending-terraform-state" # TODO: replace
    key          = "agentcore/cognito/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment_name
      ManagedBy   = "terraform"
    }
  }
}
