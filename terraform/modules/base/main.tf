terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

resource "random_id" "env_display_id" {
    byte_length = 4
}

# ------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------


resource "confluent_environment" "staging" {
  display_name = "${var.prefix}-RIVERBANK-ENVIRONMENT-${random_id.env_display_id.hex}"

  stream_governance {
    package = "ADVANCED"
  }
}

# ------------------------------------------------------
# KAFKA Cluster
# ------------------------------------------------------

data "confluent_schema_registry_cluster" "sr-cluster" {
  environment {
    id = confluent_environment.staging.id
  }

  depends_on = [
    confluent_kafka_cluster.standard
  ]
}

# Update the config to use a cloud provider and region of your choice.
# https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster
resource "confluent_kafka_cluster" "standard" {
  display_name = "${var.prefix}-RIVERBANK-CLUSTER-${random_id.env_display_id.hex}"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.cloud_region
  standard {}
  environment {
    id = confluent_environment.staging.id
  }
}

# ------------------------------------------------------
# SERVICE ACCOUNTS
# ------------------------------------------------------

resource "confluent_service_account" "app-manager" {
  display_name = "${var.prefix}-app-manager-${random_id.env_display_id.hex}"
  description  = "Service account to manage 'inventory' Kafka cluster"
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.staging.resource_name
}


# ------------------------------------------------------
# Flink Compute Pool
# ------------------------------------------------------

resource "confluent_flink_compute_pool" "flinkpool-main" {
  display_name     = "${var.prefix}_standard_compute_pool_${random_id.env_display_id.hex}"
  cloud            = "AWS"
  region           = var.cloud_region
  max_cfu          = 20
  environment {
    id = confluent_environment.staging.id
  }
}

# ------------------------------------------------------
# API Keys
# ------------------------------------------------------

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}


resource "confluent_api_key" "app-manager-schema-registry-api-key" {
  display_name = "env-manager-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'env-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.sr-cluster.id
    api_version = data.confluent_schema_registry_cluster.sr-cluster.api_version
    kind        = data.confluent_schema_registry_cluster.sr-cluster.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}

data "confluent_flink_region" "demo_flink_region" {
  cloud   = "AWS"
  region  = var.cloud_region
}



# Flink management API Keys

resource "confluent_api_key" "app-manager-flink-api-key" {
  display_name = "env-manager-flink-api-key"
  description  = "Flink API Key that is owned by 'env-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.demo_flink_region.id
    api_version = data.confluent_flink_region.demo_flink_region.api_version
    kind        = data.confluent_flink_region.demo_flink_region.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
}



# ------------------------------------------------------
# ACLS
# ------------------------------------------------------




resource "confluent_kafka_acl" "app-manager-read-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-manager.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-manager-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-manager.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}


resource "confluent_kafka_acl" "app-manager-write-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-manager.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-manager-create-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-manager.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-manager-read-on-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "GROUP"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-manager.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

# ------------------------------------------------------
# Connectors
# ------------------------------------------------------

resource "confluent_connector" "postgres_cdc_source" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  config_sensitive = {
    "database.password" = var.db_password
    "kafka.api.secret"  = confluent_api_key.app-manager-kafka-api-key.secret
  }

  config_nonsensitive = {
    "connector.class"             = "PostgresCdcSourceV2"
    "name"                        = "${var.db_name}-postgres-cdc-source"
    "kafka.auth.mode"             = "KAFKA_API_KEY"
    "kafka.api.key"               = confluent_api_key.app-manager-kafka-api-key.id
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
    "tasks.max"                   = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-manager-read-on-topic,
    confluent_kafka_acl.app-manager-write-on-topic,
    confluent_kafka_acl.app-manager-create-topic,
    confluent_kafka_acl.app-manager-read-on-group,
    confluent_kafka_acl.app-manager-describe-on-cluster,
    null_resource.datagen_container_unix,
    null_resource.datagen_container_windows,
  ]
}

# Set changelog mode on the CDC topic for joining with mortgage_applications
resource "confluent_flink_statement" "alter_credit_score_table" {
  organization {
    id = data.confluent_organization.confluent_org.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  rest_endpoint = data.confluent_flink_region.demo_flink_region.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-flink-api-key.id
    secret = confluent_api_key.app-manager-flink-api-key.secret
  }

  statement_name = "alter-credit-score-changelog-mode"

  statement = <<-EOT
    ALTER TABLE `${confluent_environment.staging.display_name}`.`${confluent_kafka_cluster.standard.display_name}`.`PROD.public.applicant_credit_score` SET ('changelog.mode' = 'append', 'value.format' = 'avro-registry');
  EOT

  properties = {
    "sql.current-catalog"  = confluent_environment.staging.display_name
    "sql.current-database" = confluent_kafka_cluster.standard.display_name
  }

  depends_on = [
    confluent_connector.postgres_cdc_source
  ]
}

# ------------------------------------------------------
# MCP Connection
# ------------------------------------------------------

# Drop existing MCP connection to allow recreation
resource "confluent_flink_statement" "mcp_connection_drop" {

  organization {
    id = data.confluent_organization.confluent_org.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  rest_endpoint = data.confluent_flink_region.demo_flink_region.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-flink-api-key.id
    secret = confluent_api_key.app-manager-flink-api-key.secret
  }

  statement_name = "mcp-connection-drop"

  statement = <<-EOT
    DROP CONNECTION IF EXISTS `${confluent_environment.staging.display_name}`.`${confluent_kafka_cluster.standard.display_name}`.`mcp_connection`;
  EOT

  properties = {
    "sql.current-catalog"  = confluent_environment.staging.display_name
    "sql.current-database" = confluent_kafka_cluster.standard.display_name
  }
}

resource "confluent_flink_statement" "mcp_connection" {

  organization {
    id = data.confluent_organization.confluent_org.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  rest_endpoint = data.confluent_flink_region.demo_flink_region.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-flink-api-key.id
    secret = confluent_api_key.app-manager-flink-api-key.secret
  }

  statement_name = "mcp-connection-create"

  statement = <<-EOT
    CREATE CONNECTION `${confluent_environment.staging.display_name}`.`${confluent_kafka_cluster.standard.display_name}`.`mcp_connection`
    WITH (
      'type' = 'mcp_server',
      'endpoint' = '${var.mcp_endpoint}',
      'token' = '${var.mcp_token}'${var.mcp_transport_type != "" ? ",\n      'transport-type' = '${var.mcp_transport_type}'" : ""}
    );
  EOT

  properties = {
    "sql.current-catalog"  = confluent_environment.staging.display_name
    "sql.current-database" = confluent_kafka_cluster.standard.display_name
  }

  depends_on = [
    confluent_flink_statement.mcp_connection_drop
  ]

  lifecycle {
    ignore_changes = [statement]
  }
}

# ------------------------------------------------------
# LLM Connections and Models
# ------------------------------------------------------

# ------------------------------------------------------
# AWS Module removed — base module receives credentials directly
# ------------------------------------------------------

locals {
  model_prefix = length(regexall("^us-", var.cloud_region)) > 0 ? "us" : (length(regexall("^eu-", var.cloud_region)) > 0 ? "eu" : "apac")
  is_windows   = substr(pathexpand("~"), 0, 1) != "/"
}

# Bedrock Text Generation Connection
resource "confluent_flink_connection" "bedrock_connection" {

  organization {
    id = data.confluent_organization.confluent_org.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  rest_endpoint = data.confluent_flink_region.demo_flink_region.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-flink-api-key.id
    secret = confluent_api_key.app-manager-flink-api-key.secret
  }

  display_name   = "llm-textgen-connection"
  type           = "BEDROCK"
  endpoint       = "https://bedrock-runtime.${var.cloud_region}.amazonaws.com/model/${local.model_prefix}.anthropic.claude-3-7-sonnet-20250219-v1:0/invoke"
  aws_access_key = var.bedrock_access_key
  aws_secret_key = var.bedrock_secret_key

  depends_on = [
    confluent_api_key.app-manager-flink-api-key,
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]

  lifecycle {
    create_before_destroy = false
  }
}


# Core LLM Model - Text Generation
resource "confluent_flink_statement" "llm_textgen_model_aws" {

  organization {
    id = data.confluent_organization.confluent_org.id
  }
  environment {
    id = confluent_environment.staging.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.flinkpool-main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  rest_endpoint = data.confluent_flink_region.demo_flink_region.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-flink-api-key.id
    secret = confluent_api_key.app-manager-flink-api-key.secret
  }

  statement = <<-SQL
  CREATE MODEL `${confluent_environment.staging.display_name}`.`${confluent_kafka_cluster.standard.display_name}`.`llm_textgen_model`
  INPUT (prompt STRING)
  OUTPUT (response STRING)
  WITH (
    'provider' = 'bedrock',
    'task' = 'text_generation',
    'bedrock.connection' = '${confluent_flink_connection.bedrock_connection.display_name}',
    'bedrock.params.max_tokens' = '50000',
    'bedrock.system_prompt' = 'You''re a Credit and Fraud Risk Analyst at River Banking, a leading financial institution specializing in personalized mortgage solutions. River Banking is committed to responsible lending and fraud prevention through advanced risk analysis and data-driven decision-making.
    Your role is to assess a mortgage applicant''s financial and risk profile to determine loan eligibility and recommend an appropriate interest rate. You will analyze key indicators such as verified income, credit score, and fraud score. Based on these inputs, you will evaluate the applicant''s ability to repay the loan, identify any potential red flags, and assign a risk category that will inform underwriting decisions.
    All responses should be formatted as JSON and JSON only according to the output format guidance.'
  );
  SQL

  properties = {
    "sql.current-catalog"  = confluent_environment.staging.display_name
    "sql.current-database" = "default"
  }

  depends_on = [
    confluent_flink_connection.bedrock_connection
  ]
}


# ------------------------------------------------------
# Topics
# ------------------------------------------------------

resource "confluent_kafka_topic" "incomplete-mortgage-applications-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name         = "incomplete_mortgage_applications"
  rest_endpoint      = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "mortgage-application-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name         = "mortgage_applications"
  rest_endpoint      = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}


resource "confluent_kafka_topic" "payment-history-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name         = "payment_history"
  rest_endpoint      = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_schema" "avro-mortgage_applications" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.sr-cluster.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint
  subject_name = "mortgage_applications-value"
  format = "AVRO"
  schema = file("${path.module}/schemas/avro/mortgage_applications-value.avsc")
  hard_delete = true
  credentials {
    key    = confluent_api_key.app-manager-schema-registry-api-key.id
    secret = confluent_api_key.app-manager-schema-registry-api-key.secret
  }
  ruleset {
    domain_rules {
      name = "validatePayslipURI"
      kind = "CONDITION"
      mode = "WRITEREAD"
      type = "CEL"
      expr = "message.payslips.matches('^s3://riverbank-payslip-bucket/[a-zA-Z0-9._/-]+$')"
      on_failure = "DLQ"
      params = {
        "dlq.topic" = confluent_kafka_topic.incomplete-mortgage-applications-topic.topic_name
        "dlq.auto.flush" = "true"
      }
    }
  }
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin,
  ]
}


resource "confluent_schema" "avro-payment_history" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.sr-cluster.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint
  subject_name = "payment_history-value"
  format = "AVRO"
  schema = file("${path.module}/schemas/avro/payment_history-value.avsc")
  hard_delete = true
  credentials {
    key    = confluent_api_key.app-manager-schema-registry-api-key.id
    secret = confluent_api_key.app-manager-schema-registry-api-key.secret
  }
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin,
  ]
}

# ------------------------------------------------------
# Flink TableAPI properties file
# ------------------------------------------------------

data "confluent_organization" "confluent_org" {}

resource "local_file" "flink_table_api_prop_file" {
filename = "${path.root}/../code/FlinkTableAPI/src/main/resources/prod.properties"
  content  = <<-EOT

# Cloud region
client.cloud=aws
client.region=${var.cloud_region}

# Access & compute resources
client.flink-api-key=${confluent_api_key.app-manager-flink-api-key.id}
client.flink-api-secret=${confluent_api_key.app-manager-flink-api-key.secret}
client.organization-id=${data.confluent_organization.confluent_org.id}
client.environment-id=${confluent_environment.staging.id}
client.compute-pool-id=${confluent_flink_compute_pool.flinkpool-main.id}

  EOT
  }
