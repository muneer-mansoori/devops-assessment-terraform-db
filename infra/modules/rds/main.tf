locals {
  tags  = merge(var.tags, { Module = "rds" })
  major = split(".", var.engine_version)[0]
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db"
  description = "Isolated database subnets for ${var.name}"
  subnet_ids  = var.database_subnet_ids
  tags        = local.tags
}

################################################################################
# Security group: the only ingress is PostgreSQL from the ECS task security group.
################################################################################

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "RDS PostgreSQL: ingress only from ECS Fargate tasks"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-rds" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_app" {
  # count (not for_each): the ECS security group ID is unknown until apply, but the list length is known.
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from ECS tasks"
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
}

# No egress rules: RDS never needs to initiate connections.

################################################################################
# Parameter group: enforce TLS and log slow queries.
################################################################################

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-pg${local.major}"
  family      = "postgres${local.major}"
  description = "PostgreSQL ${local.major} parameters for ${var.name}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.slow_query_log_ms)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Instance
################################################################################

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.master_username
  port     = var.port

  # RDS generates and rotates the master password in Secrets Manager; it never touches state or tfvars.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  backup_retention_period  = var.backup_retention_days
  backup_window            = "18:30-19:30" # UTC = 00:00-01:00 IST
  maintenance_window       = "sun:20:00-sun:21:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = !var.deletion_protection

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.name}-postgres-final" : null

  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = false
  apply_immediately                   = var.apply_immediately
  iam_database_authentication_enabled = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  tags = local.tags
}
