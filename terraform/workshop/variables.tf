variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "agentic"
}

variable "cloud_region" {
  description = "AWS Cloud Region"
  type        = string
  default     = "us-east-1"
}

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"
}

variable "mode" {
  description = "Deployment mode: workshop or self-serve"
  type        = string
  default     = "workshop"
}

variable "mcp_url" {
  description = "MCP server URL provided by the workshop host"
  type        = string
}

variable "mcp_token" {
  description = "MCP server token provided by the workshop host"
  type        = string
  sensitive   = true
}

# --- Instructor-provided credentials ---

variable "db_host" {
  description = "Instructor-provided Postgres DB host"
  type        = string
}

variable "db_port" {
  description = "Instructor-provided Postgres DB port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Instructor-provided Postgres DB name"
  type        = string
}

variable "db_username" {
  description = "Instructor-provided Postgres DB username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Instructor-provided Postgres DB password"
  type        = string
  sensitive   = true
}

variable "bedrock_access_key_id" {
  description = "AWS access key ID for Bedrock"
  type        = string
  sensitive   = true
}

variable "bedrock_secret_access_key" {
  description = "AWS secret access key for Bedrock"
  type        = string
  sensitive   = true
}
