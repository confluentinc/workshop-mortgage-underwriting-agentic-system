variable "mode" {
  description = "Deployment mode: 'workshop' (instructor provides DB and Bedrock keys) or 'self-serve' (Terraform provisions everything)"
  type        = string
  default     = "workshop"

  validation {
    condition     = contains(["workshop", "self-serve"], var.mode)
    error_message = "The mode variable must be either 'workshop' or 'self-serve'."
  }
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "agentic"
}

variable "cloud_region" {
  description = "AWS Cloud Region"
  type        = string
  default     = "us-west-2"
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

variable "zapier_token" {
  description = "Zapier MCP token for Streamable HTTP connection"
  type        = string
}

# --- Workshop-mode variables (instructor provides these) ---

variable "db_host" {
  description = "Instructor-provided Postgres DB host (required when mode=workshop)"
  type        = string
  default     = ""
}

variable "db_port" {
  description = "Instructor-provided Postgres DB port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Instructor-provided Postgres DB name (required when mode=workshop)"
  type        = string
  default     = ""
}

variable "db_username" {
  description = "Instructor-provided Postgres DB username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Instructor-provided Postgres DB password (required when mode=workshop)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "bedrock_access_key_id" {
  description = "AWS access key ID for Bedrock (required when mode=workshop)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "bedrock_secret_access_key" {
  description = "AWS secret access key for Bedrock (required when mode=workshop)"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Self-serve-mode variables ---

variable "email" {
  description = "Your email to tag all AWS resources (required when mode=self-serve)"
  type        = string
  default     = ""
}
