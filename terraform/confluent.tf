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


output "oracle_xstream_connector" {
  value = {
    database_hostname = aws_instance.oracle_instance.public_dns
    database_port = 1521
    database_username = "c##cfltuser"
    database_password = "password"
    database_name = "XE"
    database_service_name = "XE"
    pluggable_database_name = "XEPDB1"
    xstream_outbound_server = "xout"
    table_inclusion_regex = "SAMPLE.*"
    topic_prefix = "PROD"
    decimal_handling_mode = "double"
  }
}

output "lambda_connector" {
  value = {
    AWS_Lambda_function_configuration_mode = "single"
    AWS_Lambda_function_name = aws_lambda_function.credit_check.function_name
    Authentication_method = "IAM Roles"
    provider_integration_name = confluent_provider_integration.main.display_name
  }
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

resource "confluent_kafka_topic" "validated-mortgage-apps-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name         = "mortgage_validated_apps"
  rest_endpoint      = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}




# ------------------------------------------------------
# Schemas
# ------------------------------------------------------

# Schema Registry Subject (Value Schema)
resource "confluent_schema" "mortgage_validated_apps_value" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.sr-cluster.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint
  subject_name  = "mortgage_validated_apps-value"
  format        = "JSON"
  schema = jsonencode({
    type = "object"
    additionalProperties = false
    title = "MortgageValidatedApps"
    properties = {
      agent_reasoning = {
        type = "string"
      }
      applicant_id = {
        type = "string"
      }
      application_id = {
        type = "string"
      }
      application_ts = {
        type = "number"
        title = "org.apache.kafka.connect.data.Timestamp"
        "flink.precision" = 2
        "connect.type" = "int64"
        "flink.version" = "1"
      }
      borrower_name = {
        type = "string"
      }
      credit_score = {
        type = "integer"
      }
      credit_utilization = {
        type = "number"
      }
      customer_email = {
        type = "string"
        format = "email"
      }
      debt_to_income_ratio = {
        type = "number"
      }
      employment_status = {
        type = "string"
      }
      fraud_risk_score = {
        type = "integer"
      }
      income = {
        type = "integer"
      }
      loan_amount = {
        type = "integer"
      }
      loan_stack_risk = {
        type = "string"
      }
      payslips = {
        type = "string"
      }
      property_address = {
        type = "string"
      }
      property_state = {
        type = "string"
      }
      property_value = {
        type = "integer"
      }
      risk_category = {
        type = "string"
      }
    }
    required = [
      "application_id",
      "applicant_id",
      "customer_email",
      "borrower_name",
      "income",
      "payslips",
      "loan_amount",
      "property_address",
      "property_state",
      "property_value",
      "employment_status",
      "credit_score",
      "credit_utilization",
      "debt_to_income_ratio",
      "fraud_risk_score",
      "loan_stack_risk",
      "risk_category",
      "agent_reasoning",
      "application_ts"
    ]
  })
  credentials {
    key    = confluent_api_key.app-manager-schema-registry-api-key.id
    secret = confluent_api_key.app-manager-schema-registry-api-key.secret
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
# Lambda Provider Integration
# ------------------------------------------------------

locals {
  customer_lambda_access_role_name = "${var.prefix}-confluent-lambda-role-${random_id.env_display_id.hex}"
  customer_lambda_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.customer_lambda_access_role_name}"
}

resource "confluent_provider_integration" "main" {
  environment {
    id = confluent_environment.staging.id
  }
  aws {
    customer_role_arn = local.customer_lambda_access_role_arn
  }
  display_name = "${var.prefix}_provider_integration"
}


# ------------------------------------------------------
# Flink TableAPI properties file
# ------------------------------------------------------

data "confluent_organization" "confluent_org" {}

resource "local_file" "flink_table_api_prop_file" {
filename = "${path.module}/code/FlinkTableAPI/src/main/resources/prod.properties"
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


output "Flink_exec_command" {
  description = "Command to start Flink Table API code"
  value       = "java -jar target/flink-table-api-java-demo-0.1.jar '${confluent_environment.staging.display_name}' '${confluent_kafka_cluster.standard.display_name}'"
}



