# AWS provider configuration
# This is required to manage AWS resources. The region is dynamically set via a variable.
provider "aws" {
  region = var.cloud_region  
  # Default tags to apply to all resources
  default_tags {
    tags = {
      Created_by = "Mortgage Application AI Agent Terraform script"
      Project     = "Multi-Agent AI Demo"
      owner_email       = var.email
    }
  }
}

# Here we are using the Confluent provider for managing Confluent Cloud resources.
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"                
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

