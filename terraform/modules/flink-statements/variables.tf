variable "organization_id" {
  description = "Confluent Cloud organization ID"
  type        = string
}

variable "environment_id" {
  description = "Confluent Cloud environment ID"
  type        = string
}

variable "environment_display_name" {
  description = "Confluent Cloud environment display name (used as Flink catalog)"
  type        = string
}

variable "kafka_cluster_display_name" {
  description = "Kafka cluster display name (used as Flink database)"
  type        = string
}

variable "flink_compute_pool_id" {
  description = "Flink compute pool ID"
  type        = string
}

variable "flink_rest_endpoint" {
  description = "Flink REST endpoint URL"
  type        = string
}

variable "flink_api_key_id" {
  description = "Flink management API key ID"
  type        = string
  sensitive   = true
}

variable "flink_api_key_secret" {
  description = "Flink management API key secret"
  type        = string
  sensitive   = true
}

variable "service_account_id" {
  description = "Service account ID for Flink statements"
  type        = string
}

variable "email_address" {
  description = "Email address for mortgage decision notifications"
  type        = string
}
