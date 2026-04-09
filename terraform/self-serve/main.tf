terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
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
  mcp_endpoint               = "https://mcp.zapier.com/api/v1/connect"
  mcp_token                  = var.zapier_token
  db_host                    = module.aws.db_host
  db_port                    = module.aws.db_port
  db_name                    = module.aws.db_name
  db_username                = module.aws.db_username
  db_password                = module.aws.db_password
  bedrock_access_key         = module.aws.bedrock_access_key_id
  bedrock_secret_key         = module.aws.bedrock_secret_access_key
}

module "ecs_datagen" {
  source         = "../modules/ecs-datagen"
  prefix         = var.prefix
  env_display_id = random_id.env_display_id.hex

  subnet_ids        = module.aws.subnet_ids
  security_group_id = module.aws.security_group_id

  kafka_bootstrap_servers    = module.base.kafka_bootstrap_servers
  kafka_api_key              = module.base.kafka_api_key
  kafka_api_secret           = module.base.kafka_api_secret
  schema_registry_url        = module.base.schema_registry_url
  schema_registry_api_key    = module.base.schema_registry_api_key
  schema_registry_api_secret = module.base.schema_registry_api_secret
  pg_host                    = module.aws.db_host
  pg_port                    = module.aws.db_port
  pg_database                = module.aws.db_name
  pg_username                = module.aws.db_username
  pg_password                = module.aws.db_password

  depends_on = [module.base, module.aws]
}

module "cdc_connector" {
  source = "../modules/cdc-connector"

  environment_id             = module.base.environment_id
  kafka_cluster_id           = module.base.kafka_cluster_id
  kafka_api_key              = module.base.kafka_api_key
  kafka_api_secret           = module.base.kafka_api_secret
  organization_id            = module.base.organization_id
  environment_display_name   = module.base.environment_display_name
  kafka_cluster_display_name = module.base.kafka_cluster_display_name
  flink_compute_pool_id      = module.base.flink_compute_pool_id
  flink_rest_endpoint        = module.base.flink_rest_endpoint
  flink_api_key_id           = module.base.flink_api_key_id
  flink_api_key_secret       = module.base.flink_api_key_secret
  service_account_id         = module.base.service_account_id
  db_host                    = module.aws.db_host
  db_port                    = module.aws.db_port
  db_name                    = module.aws.db_name
  db_username                = module.aws.db_username
  db_password                = module.aws.db_password

  depends_on = [module.ecs_datagen]
}

output "resource_ids" {
  value     = module.base.resource_ids
  sensitive = true
}

output "flink_exec_command" {
  value = module.base.flink_exec_command
}

output "webapp_endpoint" {
  value = module.base.webapp_endpoint
}
