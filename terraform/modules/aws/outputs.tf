output "db_host" {
  value = aws_instance.postgres_instance.public_dns
}

output "db_port" {
  value = 5432
}

output "db_name" {
  value = "app1"
}

output "db_username" {
  value = "postgres"
}

output "db_password" {
  value     = "password"
  sensitive = true
}

output "bedrock_access_key_id" {
  value     = aws_iam_access_key.confluent_bedrock_access_key.id
  sensitive = true
}

output "bedrock_secret_access_key" {
  value     = aws_iam_access_key.confluent_bedrock_access_key.secret
  sensitive = true
}
