# ------------------------------------------------------
# Networking
# ------------------------------------------------------

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.cloud_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.cloud_region}b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_route_table_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# ------------------------------------------------------
# Security Group
# ------------------------------------------------------

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------
# RDS Postgres
# ------------------------------------------------------

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.prefix}-postgres-subnet-${var.env_display_id}"
  subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
}

resource "aws_db_parameter_group" "postgres_cdc" {
  family = "postgres15"
  name   = "${var.prefix}-postgres-cdc-${var.env_display_id}"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "${var.prefix}-postgres-${var.env_display_id}"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t3.small"
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = "app1"
  username                = "postgres"
  password                = "password"
  parameter_group_name    = aws_db_parameter_group.postgres_cdc.name
  db_subnet_group_name    = aws_db_subnet_group.postgres.name
  vpc_security_group_ids  = [aws_security_group.sg.id]
  publicly_accessible     = true
  skip_final_snapshot     = true
  backup_retention_period = 1

  tags = {
    Name = "${var.prefix}-postgres"
  }
}

# ------------------------------------------------------
# IAM user for Confluent Flink Bedrock access
# ------------------------------------------------------

resource "aws_iam_user" "confluent_bedrock_user" {
  name = "${var.prefix}-bedrock-user-${var.env_display_id}"
}

resource "aws_iam_user_policy_attachment" "confluent_bedrock_user_policy" {
  user       = aws_iam_user.confluent_bedrock_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

resource "aws_iam_access_key" "confluent_bedrock_access_key" {
  user = aws_iam_user.confluent_bedrock_user.name
  depends_on = [
    aws_iam_user_policy_attachment.confluent_bedrock_user_policy
  ]
}
