variable "email" {
  description = "Your email to tag all AWS resources"
  type        = string
}


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

variable "db_username"{
  description = "Postgres DB username"
  type        = string
  default     = "postgres"  
}

variable "db_password"{
  description = "Postgres DB password"
  type        = string
  default     = "Admin123456!!"  
}


variable "confluent_cloud_api_key"{
    description = "Confluent Cloud API Key"
    type        = string
}

variable "confluent_cloud_api_secret"{
    description = "Confluent Cloud API Secret"
    type        = string     
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"  # Change this to your domain
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "credit-check"
}

