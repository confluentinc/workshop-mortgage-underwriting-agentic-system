# ------------------------------------------------------
# Networking
# ------------------------------------------------------

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc-${var.env_display_id}"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.cloud_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-public-subnet-1-${var.env_display_id}"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.cloud_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-public-subnet-2-${var.env_display_id}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.prefix}-igw-${var.env_display_id}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.prefix}-public-rt-${var.env_display_id}"
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-sg-${var.env_display_id}"
  }
}

# ------------------------------------------------------
# EC2 Postgres with Debezium CDC support
# ------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "tf_key" {
  key_name   = "${var.prefix}-key-${var.env_display_id}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "tf_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = join("/", [path.root, "sshkey-${aws_key_pair.tf_key.key_name}.pem"])
}

resource "aws_instance" "postgres_instance" {
  ami             = data.aws_ami.al2023.id
  instance_type   = "t3.small"
  key_name        = aws_key_pair.tf_key.key_name
  security_groups = [aws_security_group.sg.id]
  subnet_id       = aws_subnet.public_subnet.id

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Update system and install Docker
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker

    # Create custom Postgres config for Debezium CDC
    mkdir -p /opt/postgres/config /opt/postgres/data /opt/postgres/init

    cat > /opt/postgres/config/postgresql.conf <<'PGCONF'
    listen_addresses = '*'
    wal_level = logical
    max_wal_senders = 5
    max_replication_slots = 5
    PGCONF

    cat > /opt/postgres/config/pg_hba.conf <<'PGHBA'
    # TYPE  DATABASE  USER  ADDRESS      METHOD
    local   all       all                trust
    host    all       all   0.0.0.0/0    md5
    host    replication all 0.0.0.0/0    md5
    PGHBA

    # Init script to grant replication to postgres user
    cat > /opt/postgres/init/01-init-replication.sql <<'INITDB'
    ALTER ROLE postgres WITH REPLICATION;
    INITDB

    # Run Postgres container with CDC-enabled config
    docker run -d \
      --name postgres \
      --restart always \
      -p 5432:5432 \
      -e POSTGRES_PASSWORD=password \
      -e POSTGRES_DB=app1 \
      -v /opt/postgres/data:/var/lib/postgresql/data \
      -v /opt/postgres/config/postgresql.conf:/etc/postgresql/postgresql.conf \
      -v /opt/postgres/config/pg_hba.conf:/etc/postgresql/pg_hba.conf \
      -v /opt/postgres/init:/docker-entrypoint-initdb.d \
      postgres:15 \
      -c config_file=/etc/postgresql/postgresql.conf \
      -c hba_file=/etc/postgresql/pg_hba.conf

    # Wait for Postgres to be ready
    echo "Waiting for Postgres to start..."
    until docker exec postgres pg_isready -U postgres 2>/dev/null; do
      sleep 2
    done

    echo "Postgres with Debezium CDC support is ready."
  EOF
  )

  tags = {
    Name = "${var.prefix}-postgres-${var.env_display_id}"
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
