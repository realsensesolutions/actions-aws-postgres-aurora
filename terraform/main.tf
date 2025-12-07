################################################################################
# Aurora Serverless v2 PostgreSQL
# 
# Best practices applied:
# - Storage encryption enabled
# - SSL connections enforced
# - Credentials stored in Secrets Manager
# - Private subnets only (no public access)
# - Security group restricts to VPC CIDR
################################################################################

locals {
  name_prefix      = var.instance
  cluster_name     = "${local.name_prefix}-aurora"
  parameter_family = "aurora-postgresql${split(".", var.engine_version)[0]}"
}

################################################################################
# Data Sources - VPC and Subnets from Network Action
################################################################################

data "aws_vpc" "main" {
  filter {
    name   = "tag:Instance"
    values = [var.instance]
  }
  filter {
    name   = "tag:ManagedBy"
    values = ["terraform"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
  filter {
    name   = "tag:Instance"
    values = [var.instance]
  }
}

################################################################################
# Password Generation
# Note: Using alphanumeric only to avoid URL encoding issues in connection string
################################################################################

resource "random_password" "master" {
  length  = 32
  special = false
}

################################################################################
# Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "credentials" {
  name                    = "${local.cluster_name}-credentials"
  description             = "Credentials for Aurora cluster ${local.cluster_name}"
  recovery_window_in_days = var.deletion_protection ? 7 : 0

  tags = {
    Name = "${local.cluster_name}-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "credentials" {
  secret_id = aws_secretsmanager_secret.credentials.id
  secret_string = jsonencode({
    host              = aws_rds_cluster.main.endpoint
    port              = aws_rds_cluster.main.port
    username          = var.master_username
    password          = random_password.master.result
    dbname            = var.database_name
    engine            = "postgres"
    connection_string = "postgres://${var.master_username}:${random_password.master.result}@${aws_rds_cluster.main.endpoint}:${aws_rds_cluster.main.port}/${var.database_name}?sslmode=require"
  })
}

################################################################################
# DB Subnet Group
################################################################################

resource "aws_db_subnet_group" "main" {
  name        = "${local.cluster_name}-subnets"
  description = "Subnet group for ${local.cluster_name}"
  subnet_ids  = data.aws_subnets.private.ids

  tags = {
    Name = "${local.cluster_name}-subnets"
  }
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "main" {
  name        = "${local.cluster_name}-sg"
  description = "Security group for ${local.cluster_name}"
  vpc_id      = data.aws_vpc.main.id

  tags = {
    Name = "${local.cluster_name}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.main.id
  description       = "PostgreSQL from VPC"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.main.cidr_block

  tags = {
    Name = "${local.cluster_name}-postgres-ingress"
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.main.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.cluster_name}-all-egress"
  }
}

################################################################################
# Cluster Parameter Group
################################################################################

resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${local.cluster_name}-params"
  family      = local.parameter_family
  description = "Parameter group for ${local.cluster_name}"

  # Force SSL connections
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${local.cluster_name}-params"
  }
}

################################################################################
# Aurora Serverless v2 Cluster
################################################################################

resource "aws_rds_cluster" "main" {
  cluster_identifier = local.cluster_name

  # Engine configuration
  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"
  engine_version = var.engine_version

  # Database configuration
  database_name   = var.database_name
  master_username = var.master_username
  master_password = random_password.master.result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main.id]

  # Parameter group
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # Serverless v2 scaling (0.5 ACU minimum)
  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  # Security
  storage_encrypted = true

  # Backup
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"

  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${local.cluster_name}-final-${formatdate("YYYY-MM-DD", timestamp())}" : null

  # Apply changes immediately
  apply_immediately = true

  tags = {
    Name = local.cluster_name
  }

  lifecycle {
    ignore_changes = [
      availability_zones,
      final_snapshot_identifier
    ]
  }
}

################################################################################
# Aurora Serverless v2 Instance
################################################################################

resource "aws_rds_cluster_instance" "main" {
  identifier         = "${local.cluster_name}-instance"
  cluster_identifier = aws_rds_cluster.main.id

  # Serverless v2 requires db.serverless instance class
  instance_class = "db.serverless"
  engine         = aws_rds_cluster.main.engine
  engine_version = aws_rds_cluster.main.engine_version

  # No public access
  publicly_accessible = false

  # Apply changes immediately
  apply_immediately = true

  tags = {
    Name = "${local.cluster_name}-instance"
  }
}
