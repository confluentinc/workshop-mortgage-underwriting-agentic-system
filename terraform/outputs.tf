output "resource-ids" {
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


# Create Shaddow Traffic Connection Files terraform varaible file based on variables used in this script
resource "local_file" "mortgage-applictation-kafka-json" {
filename = "${path.module}/data-gen/connections/mortgage-application-kafka.json"
  content  = <<-EOT
{
    "kind": "kafka",
    "continueOnRuleException": true,
    "producerConfigs": {
        "bootstrap.servers" : "${confluent_kafka_cluster.standard.bootstrap_endpoint}",
        "client.id": "mortgage-application-producer",
        "basic.auth.user.info": "${confluent_api_key.app-manager-schema-registry-api-key.id}:${confluent_api_key.app-manager-schema-registry-api-key.secret}",
        "schema.registry.url": "${data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint}",
        "basic.auth.credentials.source": "USER_INFO",
        "key.serializer": "io.shadowtraffic.kafka.serdes.JsonSerializer",
        "value.serializer": "io.confluent.kafka.serializers.KafkaAvroSerializer",
        "sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username='${confluent_api_key.app-manager-kafka-api-key.id}' password='${confluent_api_key.app-manager-kafka-api-key.secret}';",
        "sasl.mechanism": "PLAIN",
        "security.protocol": "SASL_SSL"
    }
}
  EOT 
  }

resource "local_file" "payments-kafka-json" {
filename = "${path.module}/data-gen/connections/payments-kafka.json"
  content  = <<-EOT
{
    "kind": "kafka",
    "continueOnRuleException": true,
    "producerConfigs": {
        "bootstrap.servers" : "${confluent_kafka_cluster.standard.bootstrap_endpoint}",
        "client.id": "historical-payments-producer",
        "basic.auth.user.info": "${confluent_api_key.app-manager-schema-registry-api-key.id}:${confluent_api_key.app-manager-schema-registry-api-key.secret}",
        "schema.registry.url": "${data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint}",
        "basic.auth.credentials.source": "USER_INFO",
        "key.serializer": "io.shadowtraffic.kafka.serdes.JsonSerializer",
        "value.serializer": "io.confluent.kafka.serializers.KafkaAvroSerializer",
        "sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username='${confluent_api_key.app-manager-kafka-api-key.id}' password='${confluent_api_key.app-manager-kafka-api-key.secret}';",
        "sasl.mechanism": "PLAIN",
        "security.protocol": "SASL_SSL"
    }
}
  EOT 
  }

resource "local_file" "oracle-json" {
filename = "${path.module}/data-gen/connections/oracle.json"
  content  = <<-EOT
  {
    "kind": "oracle",
    "connectionConfigs": {
        "host": "${aws_instance.oracle_instance.public_dns}",
        "port": 1521,
        "username": "sample",
        "password": "password",
        "db": "XEPDB1"
    }
}
  EOT 
  }
