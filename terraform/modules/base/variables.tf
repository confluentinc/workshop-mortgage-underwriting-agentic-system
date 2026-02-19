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
