# Get current AWS account ID
data "aws_caller_identity" "current" {}

# -------------------------------
# Networking
# -------------------------------

# -------------------------------
#  VPC and Subnets
# -------------------------------

# VPC
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.cloud_region}a"
  map_public_ip_on_launch = true
}

# Second Public Subnet
resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.cloud_region}b"
  map_public_ip_on_launch = true
}

# -------------------------------
# Internet Gateway
# -------------------------------

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}


# -------------------------------
# Public Route Table
# -------------------------------

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"  # This route allows all outbound traffic
    gateway_id = aws_internet_gateway.igw.id  # Route to the Internet Gateway
  }
}

# -------------------------------
# Associate Public Route Table with Public Subnet
# -------------------------------

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate Second Public Subnet with Route Table
resource "aws_route_table_association" "public_route_table_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}


# -------------------------------
# Security Group for ECS
# -------------------------------

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1521
    to_port     = 1521
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
}

# -------------------------------
# Oracle DB AMI and Key
# -------------------------------


# Get AMI based on region
data "aws_ami" "oracle_ami" {
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


resource "aws_key_pair" "tf_key" {
  key_name   = "${var.prefix}-key-${random_id.env_display_id.hex}"
  public_key = tls_private_key.rsa-4096-example.public_key_openssh
}

# RSA key of size 4096 bits
resource "tls_private_key" "rsa-4096-example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store SSH private key locally (Windows-friendly)
resource "local_file" "tf_key" {
  content  = tls_private_key.rsa-4096-example.private_key_pem
  filename = join("/", [path.module, "sshkey-${aws_key_pair.tf_key.key_name}.pem"])
}

# -------------------------------
# Oracle DB Instance 
# -------------------------------


# EC2 instance for Oracle

resource "aws_instance" "oracle_instance" {
  ami           = data.aws_ami.oracle_ami.id
  instance_type = "t3.large"
  key_name      = aws_key_pair.tf_key.key_name 
  security_groups = [aws_security_group.sg.id]
  subnet_id = aws_subnet.public_subnet.id 
  root_block_device {
    volume_size = 30  # Oracle XE needs at least 12GB, adding extra space
    volume_type = "gp3"
  }
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    # Update system
    dnf update -y
    
    # Install Docker
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create directory for Oracle data
    mkdir -p /opt/oracle/oradata
    chmod -R 777 /opt/oracle/oradata
    
    # Create docker-compose.yml file
    cat > /opt/oracle/docker-compose.yml <<'DOCKER_COMPOSE'
    version: '3'
    services:
      oracle-xe:
        image: container-registry.oracle.com/database/express:21.3.0-xe
        container_name: oracle-xe
        ports:
          - "1521:1521"
          - "5500:5500"
        environment:
          - ORACLE_PWD=Welcome1
          - ORACLE_CHARACTERSET=AL32UTF8
        volumes:
          - /opt/oracle/oradata:/opt/oracle/oradata
        restart: always
    DOCKER_COMPOSE
    
    # Pull Oracle XE image and start container
    cd /opt/oracle
    docker-compose up -d
    
    # Set up a welcome message
    echo "Oracle XE 21c setup complete. Connect using:"
    echo "Hostname: $(curl -s http://169.254.169.254/latest/meta-data/public-hostname)"
    echo "Port: 1521"
    echo "SID: XE"
    echo "PDB: XEPDB1"
    echo "Username: system"
    echo "Password: Welcome1"
    echo "EM Express URL: https://$(curl -s http://169.254.169.254/latest/meta-data/public-hostname):5500/em"

    echo "Waiting for oracle-xe container to become healthy"
    until [ "$(sudo docker inspect -f '{{.State.Health.Status}}' oracle-xe 2>/dev/null)" == "healthy" ]; do
      echo -n "."
      sleep 10
    done

    echo "Writing XStream setup script"
    cat > /opt/oracle/setup-xstream.sh <<'SCRIPT_EOF'
    #!/bin/bash
    set -e
    log() { echo "[XSTREAM] $1"; }

    log "Enable Oracle XStream"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
    SHOW PARAMETER GOLDEN;
    EXIT;
    SQL_EOF

    log "Configure ARCHIVELOG mode"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    SHUTDOWN IMMEDIATE;
    STARTUP MOUNT;
    ALTER DATABASE ARCHIVELOG;
    ALTER DATABASE OPEN;
    EXIT;
    SQL_EOF

    log "Configure supplemental logging"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER SESSION SET CONTAINER = CDB\$ROOT;
    ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
    SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V\\$DATABASE;
    EXIT;
    SQL_EOF

    log "Create XStream tablespaces in CDB"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/XE/xstream_adm_tbs.dbf'
    SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

    CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/XE/xstream_tbs.dbf'
    SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;
    EXIT;
    SQL_EOF

    log "Create PDB objects and sample user"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER SESSION SET CONTAINER=XEPDB1;

    CREATE USER sample IDENTIFIED BY password;
    GRANT CONNECT, RESOURCE TO sample;
    ALTER USER sample QUOTA UNLIMITED ON USERS;

    CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_adm_tbs.dbf'
    SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

    CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_tbs.dbf'
    SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;
    EXIT;
    SQL_EOF

    log "Create XStream admin user"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    CREATE USER c##cfltadmin IDENTIFIED BY password
    DEFAULT TABLESPACE xstream_adm_tbs
    QUOTA UNLIMITED ON xstream_adm_tbs
    CONTAINER=ALL;

    GRANT CREATE SESSION TO c##cfltadmin CONTAINER=ALL;
    GRANT SET CONTAINER TO c##cfltadmin CONTAINER=ALL;

    BEGIN
      DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
        grantee                 => 'c##cfltadmin',
        privilege_type          => 'CAPTURE',
        grant_select_privileges => TRUE,
        container               => 'ALL'
      );
    END;
    /
    EXIT;
    SQL_EOF

    log "Create XStream connect user"
    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    CREATE USER c##cfltuser IDENTIFIED BY password
    DEFAULT TABLESPACE xstream_tbs
    QUOTA UNLIMITED ON xstream_tbs
    CONTAINER=ALL;

    GRANT CREATE SESSION TO c##cfltuser CONTAINER=ALL;
    GRANT SET CONTAINER TO c##cfltuser CONTAINER=ALL;
    GRANT SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;
    GRANT CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER TO c##cfltuser CONTAINER=ALL;
    GRANT FLASHBACK ANY TABLE, SELECT ANY TABLE, LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
    EXIT;
    SQL_EOF

    log "Create XStream Outbound Server"
    sudo docker exec -i oracle-xe sqlplus c\#\#cfltadmin/password@//localhost:1521/XE <<'SQL_EOF'
    DECLARE
      tables  DBMS_UTILITY.UNCL_ARRAY;
      schemas DBMS_UTILITY.UNCL_ARRAY;
    BEGIN
      tables(1) := NULL;
      schemas(1) := 'sample';
      DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
        server_name => 'xout',
        source_container_name => 'XEPDB1',
        table_names => tables,
        schema_names => schemas);
    END;
    /
    EXIT;
    SQL_EOF

    sudo docker exec -i oracle-xe bash -c "ORACLE_SID=XE; export ORACLE_SID; sqlplus /nolog" <<'SQL_EOF'
    CONNECT sys/Welcome1 AS SYSDBA
    BEGIN
      DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
        server_name  => 'xout',
        connect_user => 'c##cfltuser');
    END;
    /
    EXIT;
    SQL_EOF

    log "XStream configuration complete"

    SCRIPT_EOF

    chmod +x /opt/oracle/setup-xstream.sh
    bash /opt/oracle/setup-xstream.sh >> /var/log/xstream-setup.log 2>&1

    echo "Oracle XE with XStream configured." | tee -a /var/log/user-data.log
  EOF
  )
  tags = {
    Name        = "${var.prefix}-oracle-xe"
  }
} 


# ------------------------------------------------------
# Agent 1: Lambda Function Deployment
# ------------------------------------------------------


# ECR Repository
resource "aws_ecr_repository" "lambda_repo" {
  name = "${var.prefix}-fraud-credit-check-${random_id.env_display_id.hex}"
  force_delete = true
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.prefix}-lambda-role-${random_id.env_display_id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# Create client.properties file for Lambda function
resource "local_file" "lambda_properties_file" {
  filename = "${path.module}/code/agent1/client.properties"
  content  = <<-EOT
# Required connection configs for Kafka producer, consumer, and admin
bootstrap.servers=${confluent_kafka_cluster.standard.bootstrap_endpoint}
security.protocol=SASL_SSL
sasl.mechanisms=PLAIN
sasl.username=${confluent_api_key.app-manager-kafka-api-key.id}
sasl.password=${confluent_api_key.app-manager-kafka-api-key.secret}

# Best practice for higher availability in librdkafka clients prior to 1.7
session.timeout.ms=45000

client.id=CreditFraudCheckAgent
EOT
}

locals {
  # True if Windows (pathexpand("~") starts with drive letter, not "/")
  is_windows = substr(pathexpand("~"), 0, 1) != "/"
}

# Windows-specific build
resource "null_resource" "docker_build_windows" {
  count = local.is_windows ? 1 : 0

  triggers = {
    dockerfile_hash       = filemd5(join("/", [path.module, "code", "agent1", "Dockerfile"]))
    requirements_hash     = filemd5(join("/", [path.module, "code", "agent1", "requirements.txt"]))
    source_code_hash      = filemd5(join("/", [path.module, "code", "agent1", "credit_and_fraud_check.py"]))
    properties_file_hash  = local_file.lambda_properties_file.content
  }

  depends_on = [
    local_file.lambda_properties_file
  ]

  provisioner "local-exec" {
    command = "echo ${data.aws_ecr_authorization_token.token.password} | docker login -u AWS --password-stdin ${data.aws_ecr_authorization_token.token.proxy_endpoint}"
  }

  provisioner "local-exec" {
    command = "docker buildx build --platform linux/amd64 -t ${aws_ecr_repository.lambda_repo.repository_url}:latest ${path.module}/code/agent1 --push --provenance=false --sbom=false"
  }
}

# macOS/Linux-specific build
resource "null_resource" "docker_build_unix" {
  count = local.is_windows ? 0 : 1

  triggers = {
    dockerfile_hash       = filemd5(join("/", [path.module, "code", "agent1", "Dockerfile"]))
    requirements_hash     = filemd5(join("/", [path.module, "code", "agent1", "requirements.txt"]))
    source_code_hash      = filemd5(join("/", [path.module, "code", "agent1", "credit_and_fraud_check.py"]))
    properties_file_hash  = local_file.lambda_properties_file.content
  }

  depends_on = [
    local_file.lambda_properties_file
  ]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      aws ecr get-login-password --region ${var.cloud_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.lambda_repo.repository_url} && \
      docker buildx build --platform linux/amd64 --push -t ${aws_ecr_repository.lambda_repo.repository_url}:latest ./code/agent1 --provenance=false --sbom=false
    EOT
    on_failure = fail
  }
}









# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.credit_check.function_name}"
  retention_in_days = 14
}

# Lambda Function
resource "aws_lambda_function" "credit_check" {
  function_name = aws_ecr_repository.lambda_repo.name
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.lambda_repo.repository_url}:latest"
  role          = aws_iam_role.lambda_execution_role.arn
  timeout       = 900
  memory_size   = 512

  environment {
    variables = {
      LANGCHAIN_TRACING_V2 = "true"
      # Note: Sensitive environment variables should be managed through AWS Secrets Manager
      # or AWS Systems Manager Parameter Store
    }
  }

    depends_on = [
    null_resource.docker_build_windows,
    null_resource.docker_build_unix
  ]
}

# IAM Role for Confluent Lambda Invocation
resource "aws_iam_role" "confluent_lambda_role" {
  name = "${var.prefix}-confluent-lambda-role-${random_id.env_display_id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = confluent_provider_integration.main.aws[0].iam_role_arn
          
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = confluent_provider_integration.main.aws[0].external_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = confluent_provider_integration.main.aws[0].iam_role_arn
          
        }
        Action = "sts:TagSession"
      }
    ]
  })
}

# IAM Policy for Confluent Lambda Invocation
resource "aws_iam_policy" "confluent_lambda_policy" {
  name        = "${var.prefix}-confluent-lambda-policy-${random_id.env_display_id.hex}"
  description = "Policy allowing Confluent to invoke Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.credit_check.arn
        ]
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "confluent_lambda_policy_attachment" {
  role       = aws_iam_role.confluent_lambda_role.name
  policy_arn = aws_iam_policy.confluent_lambda_policy.arn
}