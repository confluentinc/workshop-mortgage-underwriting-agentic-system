
variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "agentic"
}

variable "cloud_region"{
  description = "AWS Cloud Region"
  type        = string
  default     = "us-west-2"    
}

variable "db_host"{
  description = "Instructor-provided Postgres DB host"
  type        = string
}

variable "db_port"{
  description = "Instructor-provided Postgres DB port"
  type        = number
  default     = 5432
}

variable "db_name"{
  description = "Instructor-provided Postgres DB name"
  type        = string
}

variable "db_username"{
  description = "Instructor-provided Postgres DB username"
  type        = string
  default     = "postgres"
}

variable "db_password"{
  description = "Instructor-provided Postgres DB password"
  type        = string
  sensitive   = true
}


variable "confluent_cloud_api_key"{
    description = "Confluent Cloud API Key"
    type        = string
}

variable "confluent_cloud_api_secret"{
    description = "Confluent Cloud API Secret"
    type        = string     
}

variable "bedrock_access_key_id" {
  description = "AWS access key ID for Bedrock (used by Confluent Flink connection)"
  type        = string
  sensitive   = true
}

variable "bedrock_secret_access_key" {
  description = "AWS secret access key for Bedrock (used by Confluent Flink connection)"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"  # Change this to your domain
}

variable "zapier_token" {
  description = "Zapier MCP token for Streamable HTTP connection"
  type        = string
}
