terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "aws" {
  region = var.cloud_region

  default_tags {
    tags = {
      Created_by  = "Mortgage Application AI Agent Terraform script"
      Project     = "Multi-Agent AI Demo"
      owner_email = var.email
    }
  }
}

resource "random_id" "env_display_id" {
  byte_length = 4
}

module "aws" {
  source         = "../modules/aws"
  cloud_region   = var.cloud_region
  prefix         = var.prefix
  env_display_id = random_id.env_display_id.hex
  email          = var.email
}

module "base" {
  source                     = "../modules/base"
  confluent_cloud_api_key    = var.confluent_cloud_api_key
  confluent_cloud_api_secret = var.confluent_cloud_api_secret
  prefix                     = var.prefix
  cloud_region               = var.cloud_region
  domain_name                = var.domain_name
  zapier_token               = var.zapier_token
  db_host                    = module.aws.db_host
  db_port                    = module.aws.db_port
  db_name                    = module.aws.db_name
  db_username                = module.aws.db_username
  db_password                = module.aws.db_password
  bedrock_access_key         = module.aws.bedrock_access_key_id
  bedrock_secret_key         = module.aws.bedrock_secret_access_key
}

output "resource_ids" {
  value     = module.base.resource_ids
  sensitive = true
}

output "postgres_cdc_connector" {
  value     = module.base.postgres_cdc_connector
  sensitive = true
}

output "flink_exec_command" {
  value = module.base.flink_exec_command
}

output "webapp_endpoint" {
  value = module.base.webapp_endpoint
}
