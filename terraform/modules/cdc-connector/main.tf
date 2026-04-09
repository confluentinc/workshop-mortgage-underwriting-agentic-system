terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

resource "confluent_connector" "postgres_cdc_source" {
  environment {
    id = var.environment_id
  }
  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_sensitive = {
    "database.password" = var.db_password
    "kafka.api.secret"  = var.kafka_api_secret
  }

  config_nonsensitive = {
    "connector.class"             = "PostgresCdcSourceV2"
    "name"                        = "${var.db_name}-postgres-cdc-source"
    "kafka.auth.mode"             = "KAFKA_API_KEY"
    "kafka.api.key"               = var.kafka_api_key
    "database.hostname"           = var.db_host
    "database.port"               = tostring(var.db_port)
    "database.user"               = var.db_username
    "database.dbname"             = var.db_name
    "topic.prefix"                = "PROD"
    "table.include.list"          = "public.applicant_credit_score"
    "slot.name"                   = "${var.db_name}_debezium"
    "publication.name"            = "${var.db_name}_dbz_publication"
    "publication.autocreate.mode" = "filtered"
    "output.data.format"          = "AVRO"
    "output.key.format"           = "AVRO"
    "decimal.handling.mode"       = "double"
    "time.precision.mode"         = "connect"
    "tasks.max"                   = "1"
  }
}

# Set upsert mode on CDC table for temporal join support
resource "confluent_flink_statement" "alter_credit_score_upsert" {
  organization {
    id = var.organization_id
  }
  environment {
    id = var.environment_id
  }
  compute_pool {
    id = var.flink_compute_pool_id
  }
  principal {
    id = var.service_account_id
  }
  rest_endpoint = var.flink_rest_endpoint
  credentials {
    key    = var.flink_api_key_id
    secret = var.flink_api_key_secret
  }

  statement_name = "alter-credit-score-primary-key"

  statement = <<-EOT
    ALTER TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`PROD.public.applicant_credit_score` SET ('changelog.mode' = 'upsert');
  EOT

  properties = {
    "sql.current-catalog"  = var.environment_display_name
    "sql.current-database" = var.kafka_cluster_display_name
  }

  depends_on = [
    confluent_connector.postgres_cdc_source
  ]
}

# Add watermark on CDC table using updated_at for temporal join
resource "confluent_flink_statement" "alter_credit_score_watermark" {
  organization {
    id = var.organization_id
  }
  environment {
    id = var.environment_id
  }
  compute_pool {
    id = var.flink_compute_pool_id
  }
  principal {
    id = var.service_account_id
  }
  rest_endpoint = var.flink_rest_endpoint
  credentials {
    key    = var.flink_api_key_id
    secret = var.flink_api_key_secret
  }

  statement_name = "alter-credit-score-watermark"

  statement = <<-EOT
    ALTER TABLE `${var.environment_display_name}`.`${var.kafka_cluster_display_name}`.`PROD.public.applicant_credit_score` MODIFY WATERMARK FOR `updated_at` AS `updated_at` - INTERVAL '5' SECOND;
  EOT

  properties = {
    "sql.current-catalog"  = var.environment_display_name
    "sql.current-database" = var.kafka_cluster_display_name
  }

  depends_on = [
    confluent_flink_statement.alter_credit_score_upsert
  ]
}
