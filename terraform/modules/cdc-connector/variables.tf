variable "environment_id" {
  type = string
}

variable "kafka_cluster_id" {
  type = string
}

variable "kafka_api_key" {
  type      = string
  sensitive = true
}

variable "kafka_api_secret" {
  type      = string
  sensitive = true
}

variable "organization_id" {
  type = string
}

variable "environment_display_name" {
  type = string
}

variable "kafka_cluster_display_name" {
  type = string
}

variable "flink_compute_pool_id" {
  type = string
}

variable "flink_rest_endpoint" {
  type = string
}

variable "flink_api_key_id" {
  type      = string
  sensitive = true
}

variable "flink_api_key_secret" {
  type      = string
  sensitive = true
}

variable "service_account_id" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type      = string
  sensitive = true
}
