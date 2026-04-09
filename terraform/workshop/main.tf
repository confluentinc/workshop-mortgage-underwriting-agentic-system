terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

module "base" {
  source                     = "../modules/base"
  confluent_cloud_api_key    = var.confluent_cloud_api_key
  confluent_cloud_api_secret = var.confluent_cloud_api_secret
  prefix                     = var.prefix
  cloud_region               = var.cloud_region
  domain_name                = var.domain_name
  mcp_endpoint               = var.mcp_url
  mcp_token                  = var.mcp_token
  mcp_transport_type         = ""
  db_host                    = var.db_host
  db_port                    = var.db_port
  db_name                    = var.db_name
  db_username                = var.db_username
  db_password                = var.db_password
  bedrock_access_key         = var.bedrock_access_key_id
  bedrock_secret_key         = var.bedrock_secret_access_key
}

module "local_datagen" {
  source = "../modules/local-datagen"

  kafka_bootstrap_servers    = module.base.kafka_bootstrap_servers
  kafka_api_key              = module.base.kafka_api_key
  kafka_api_secret           = module.base.kafka_api_secret
  schema_registry_url        = module.base.schema_registry_url
  schema_registry_api_key    = module.base.schema_registry_api_key
  schema_registry_api_secret = module.base.schema_registry_api_secret
  pg_host                    = var.db_host
  pg_port                    = var.db_port
  pg_database                = var.db_name
  pg_username                = var.db_username
  pg_password                = var.db_password

  depends_on = [module.base]
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
