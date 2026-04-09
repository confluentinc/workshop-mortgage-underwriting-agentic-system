output "resource_ids" {
  value = <<-EOT
  Environment ID:   ${confluent_environment.staging.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.standard.id}
  Flink Compute pool ID: ${confluent_flink_compute_pool.flinkpool-main.id}

  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-manager.display_name}:                     ${confluent_service_account.app-manager.id}
  ${confluent_service_account.app-manager.display_name}'s Kafka API Key:     "${confluent_api_key.app-manager-kafka-api-key.id}"
  ${confluent_service_account.app-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.app-manager-kafka-api-key.secret}"


  Service Accounts and their Flink management API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-manager.display_name}:                     ${confluent_service_account.app-manager.id}
  ${confluent_service_account.app-manager.display_name}'s Flink management API Key:     "${confluent_api_key.app-manager-flink-api-key.id}"
  ${confluent_service_account.app-manager.display_name}'s Flink management API Secret:  "${confluent_api_key.app-manager-flink-api-key.secret}"


  sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${confluent_api_key.app-manager-kafka-api-key.id}" password="${confluent_api_key.app-manager-kafka-api-key.secret}";
  bootstrap.servers=${confluent_kafka_cluster.standard.bootstrap_endpoint}
  schema.registry.url= ${data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint}
  schema.registry.basic.auth.user.info= "${confluent_api_key.app-manager-schema-registry-api-key.id}:${confluent_api_key.app-manager-schema-registry-api-key.secret}"


  EOT

  sensitive = true
}

output "flink_exec_command" {
  description = "Command to start Flink Table API code"
  value       = "java -jar target/flink-table-api-java-demo-0.1.jar '${confluent_environment.staging.display_name}' '${confluent_kafka_cluster.standard.display_name}'"
}

output "webapp_endpoint" {
  description = "Local webapp URL"
  value       = "http://localhost:5001"
}

output "organization_id" {
  value = data.confluent_organization.confluent_org.id
}

output "environment_id" {
  value = confluent_environment.staging.id
}

output "kafka_cluster_id" {
  value = confluent_kafka_cluster.standard.id
}

output "environment_display_name" {
  value = confluent_environment.staging.display_name
}

output "kafka_cluster_display_name" {
  value = confluent_kafka_cluster.standard.display_name
}

output "flink_compute_pool_id" {
  value = confluent_flink_compute_pool.flinkpool-main.id
}

output "flink_rest_endpoint" {
  value = data.confluent_flink_region.demo_flink_region.rest_endpoint
}

output "flink_api_key_id" {
  value     = confluent_api_key.app-manager-flink-api-key.id
  sensitive = true
}

output "flink_api_key_secret" {
  value     = confluent_api_key.app-manager-flink-api-key.secret
  sensitive = true
}

output "service_account_id" {
  value = confluent_service_account.app-manager.id
}

output "kafka_bootstrap_servers" {
  value = confluent_kafka_cluster.standard.bootstrap_endpoint
}

output "kafka_api_key" {
  value     = confluent_api_key.app-manager-kafka-api-key.id
  sensitive = true
}

output "kafka_api_secret" {
  value     = confluent_api_key.app-manager-kafka-api-key.secret
  sensitive = true
}

output "schema_registry_url" {
  value = data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint
}

output "schema_registry_api_key" {
  value     = confluent_api_key.app-manager-schema-registry-api-key.id
  sensitive = true
}

output "schema_registry_api_secret" {
  value     = confluent_api_key.app-manager-schema-registry-api-key.secret
  sensitive = true
}
