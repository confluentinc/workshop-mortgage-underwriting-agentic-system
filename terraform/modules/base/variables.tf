variable "confluent_cloud_api_key" {
  type = string
}

variable "confluent_cloud_api_secret" {
  type = string
}

variable "prefix" {
  type    = string
  default = "agentic"
}

variable "cloud_region" {
  type    = string
  default = "us-east-1"
}

variable "domain_name" {
  type    = string
  default = "example.com"
}

variable "mcp_endpoint" {
  type = string
}

variable "mcp_token" {
  type      = string
  sensitive = true
}

variable "mcp_transport_type" {
  type    = string
  default = "STREAMABLE_HTTP"
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

variable "bedrock_access_key" {
  type      = string
  sensitive = true
}

variable "bedrock_secret_key" {
  type      = string
  sensitive = true
}

variable "mortgage_app_interval" {
  description = "Interval in seconds between mortgage application events"
  type        = number
  default     = 600
}

variable "mortgage_app_count" {
  description = "Number of mortgage applications to generate (-1 for continuous)"
  type        = number
  default     = 20
}

variable "mortgage_app_startup_delay" {
  description = "Delay in seconds before starting mortgage application generation"
  type        = number
  default     = 0
}

variable "cdc_heartbeat_interval" {
  description = "Interval in seconds for CDC heartbeat updates to Postgres (0 to disable). Heartbeat advances CDC topic watermark without inserting new rows."
  type        = number
  default     = 10
}
