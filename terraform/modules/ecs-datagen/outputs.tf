output "cluster_arn" {
  value = aws_ecs_cluster.datagen.arn
}

output "service_name" {
  value = aws_ecs_service.datagen.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.datagen.name
}
