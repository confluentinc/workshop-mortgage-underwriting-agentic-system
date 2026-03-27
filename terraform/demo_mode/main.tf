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

  # Demo mode: 1 app per minute, continuous, 10-minute startup delay
  mortgage_app_interval      = 60
  mortgage_app_count         = -1
  mortgage_app_startup_delay = 600
}

module "flink_statements" {
  source = "../modules/flink-statements"

  organization_id            = module.base.organization_id
  environment_id             = module.base.environment_id
  environment_display_name   = module.base.environment_display_name
  kafka_cluster_display_name = module.base.kafka_cluster_display_name
  flink_compute_pool_id      = module.base.flink_compute_pool_id
  flink_rest_endpoint        = module.base.flink_rest_endpoint
  flink_api_key_id           = module.base.flink_api_key_id
  flink_api_key_secret       = module.base.flink_api_key_secret
  service_account_id         = module.base.service_account_id
  email_address              = var.email_address
}
