terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  
  backend "s3" {
    bucket         = "ramki20-terraform-state-appconfig2"
    key            = "feature-flags/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ramki20-terraform-state-locks2"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  # Comment out default_tags to avoid conflicts with explicit tags
  # default_tags {
  #   tags = {
  #     Project     = "AppConfig-FeatureFlags"
  #     Environment = var.environment
  #     ManagedBy   = "Terraform"
  #   }
  # }
}