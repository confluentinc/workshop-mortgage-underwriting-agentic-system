data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "datagen" {
  name              = "/ecs/${var.prefix}-datagen-${var.env_display_id}"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.prefix}-datagen-exec-${var.env_display_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "datagen" {
  name = "${var.prefix}-datagen-${var.env_display_id}"
}

resource "aws_ecs_task_definition" "datagen" {
  family                   = "${var.prefix}-datagen-${var.env_display_id}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "datagen"
    image     = "ghcr.io/ahmedszamzam/datagen:latest"
    essential = true

    environment = [
      { name = "KAFKA_BOOTSTRAP_SERVERS", value = var.kafka_bootstrap_servers },
      { name = "KAFKA_API_KEY", value = var.kafka_api_key },
      { name = "KAFKA_API_SECRET", value = var.kafka_api_secret },
      { name = "SCHEMA_REGISTRY_URL", value = var.schema_registry_url },
      { name = "SCHEMA_REGISTRY_API_KEY", value = var.schema_registry_api_key },
      { name = "SCHEMA_REGISTRY_API_SECRET", value = var.schema_registry_api_secret },
      { name = "PG_HOST", value = var.pg_host },
      { name = "PG_PORT", value = tostring(var.pg_port) },
      { name = "PG_DATABASE", value = var.pg_database },
      { name = "PG_USERNAME", value = var.pg_username },
      { name = "PG_PASSWORD", value = var.pg_password },
      { name = "MORTGAGE_APP_INTERVAL_SECONDS", value = tostring(var.mortgage_app_interval) },
      { name = "MORTGAGE_APP_COUNT", value = tostring(var.mortgage_app_count) },
      { name = "MORTGAGE_APP_STARTUP_DELAY_SECONDS", value = tostring(var.mortgage_app_startup_delay) },
      { name = "CDC_HEARTBEAT_INTERVAL_SECONDS", value = tostring(var.cdc_heartbeat_interval) },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.datagen.name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "datagen"
      }
    }
  }])
}

resource "aws_ecs_service" "datagen" {
  name            = "${var.prefix}-datagen-${var.env_display_id}"
  cluster         = aws_ecs_cluster.datagen.id
  task_definition = aws_ecs_task_definition.datagen.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = true
  }
}
