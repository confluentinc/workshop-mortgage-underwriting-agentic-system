variable "kafka_bootstrap_servers" {
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

variable "schema_registry_url" {
  type = string
}

variable "schema_registry_api_key" {
  type      = string
  sensitive = true
}

variable "schema_registry_api_secret" {
  type      = string
  sensitive = true
}

variable "pg_host" {
  type = string
}

variable "pg_port" {
  type    = number
  default = 5432
}

variable "pg_database" {
  type = string
}

variable "pg_username" {
  type    = string
  default = "postgres"
}

variable "pg_password" {
  type      = string
  sensitive = true
}

variable "mortgage_app_interval" {
  type    = number
  default = 600
}

variable "mortgage_app_count" {
  type    = number
  default = 20
}

variable "mortgage_app_startup_delay" {
  type    = number
  default = 0
}

variable "cdc_heartbeat_interval" {
  type    = number
  default = 10
}
