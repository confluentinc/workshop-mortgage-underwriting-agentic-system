resource "aws_ecr_repository" "mortgage_webapp" {
  name = "${var.prefix}-mortgage-webapp-${random_id.env_display_id.hex}"
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "mortgage_webapp" {
  repository = aws_ecr_repository.mortgage_webapp.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the latest image"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 1
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# Get ECR login token
data "aws_ecr_authorization_token" "token" {}

# Build and push Docker image
resource "null_resource" "docker_build_push" {
  triggers = {
    always_run = timestamp() # This ensures the build runs every time
  }

  provisioner "local-exec" {
    command = "echo ${data.aws_ecr_authorization_token.token.password} | docker login -u AWS --password-stdin ${data.aws_ecr_authorization_token.token.proxy_endpoint}"
  }

  provisioner "local-exec" {
    command = "docker buildx build --platform linux/amd64 -t ${aws_ecr_repository.mortgage_webapp.repository_url}:latest ${path.module}/../webapp --push"
  }

  depends_on = [aws_ecr_repository.mortgage_webapp]
}

resource "aws_ecs_cluster" "mortgage_cluster" {
  name = "${var.prefix}-mortgage-cluster-${random_id.env_display_id.hex}"
}

resource "aws_ecs_task_definition" "mortgage_webapp" {
  family                   = "${var.prefix}-mortgage-webapp-${random_id.env_display_id.hex}"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = 256
  memory                  = 512
  execution_role_arn      = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "mortgage-webapp"
      image = "${aws_ecr_repository.mortgage_webapp.repository_url}:latest"
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "KAFKA_BOOTSTRAP_SERVERS"
          value = confluent_kafka_cluster.standard.bootstrap_endpoint
        },
        {
          name  = "KAFKA_API_KEY"
          value = confluent_api_key.app-manager-kafka-api-key.id
        },
        {
          name  = "KAFKA_API_SECRET"
          value = confluent_api_key.app-manager-kafka-api-key.secret
        },
        {
          name  = "SCHEMA_REGISTRY_URL"
          value = data.confluent_schema_registry_cluster.sr-cluster.rest_endpoint
        },
        {
          name  = "SCHEMA_REGISTRY_API_KEY"
          value = confluent_api_key.app-manager-schema-registry-api-key.id
        },
        {
          name  = "SCHEMA_REGISTRY_API_SECRET"
          value = confluent_api_key.app-manager-schema-registry-api-key.secret
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.prefix}-mortgage-webapp-${random_id.env_display_id.hex}"
          awslogs-region        = var.cloud_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  depends_on = [null_resource.docker_build_push]
}

resource "aws_lb" "mortgage_webapp" {
  name               = "${var.prefix}-webapp-${random_id.env_display_id.hex}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg.id]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = false
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.mortgage_webapp.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mortgage_webapp.arn
  }
}

resource "aws_ecs_service" "mortgage_webapp" {
  name            = "${var.prefix}-mortgage-webapp-service-${random_id.env_display_id.hex}"
  cluster         = aws_ecs_cluster.mortgage_cluster.id
  task_definition = aws_ecs_task_definition.mortgage_webapp.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mortgage_webapp.arn
    container_name   = "mortgage-webapp"
    container_port   = 5000
  }

  depends_on = [aws_lb.mortgage_webapp]
}

resource "aws_lb_target_group" "mortgage_webapp" {
  name        = "${var.prefix}-webapp-tg-${random_id.env_display_id.hex}"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.prefix}-ecs-tasks-sg-${random_id.env_display_id.hex}"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.prefix}-ecs-execution-role-${random_id.env_display_id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-ecs-task-role-${random_id.env_display_id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "mortgage_webapp" {
  name              = "/ecs/${var.prefix}-mortgage-webapp-${random_id.env_display_id.hex}"
  retention_in_days = 30
}

output "webapp_endpoint" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.mortgage_webapp.dns_name
} 