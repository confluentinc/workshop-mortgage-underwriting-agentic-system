output "db_host" {
  value = aws_db_instance.postgres.address
}

output "db_port" {
  value = aws_db_instance.postgres.port
}

output "db_name" {
  value = aws_db_instance.postgres.db_name
}

output "db_username" {
  value = aws_db_instance.postgres.username
}

output "db_password" {
  value     = aws_db_instance.postgres.password
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
