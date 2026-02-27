variable "cloud_region" {
  description = "AWS Cloud Region"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "env_display_id" {
  description = "Random ID hex for unique naming"
  type        = string
}

variable "email" {
  description = "Email for tagging AWS resources"
  type        = string
}
