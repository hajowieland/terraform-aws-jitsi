# --------------------------------------------------------------------------
# Generate random username
# --------------------------------------------------------------------------
resource "random_string" "db_username" {
  length  = 12
  special = false
  upper   = false
  number  = false

  keepers = {
    cluster_identifier = var.name
  }
}

# --------------------------------------------------------------------------
# Generate safe random password
# --------------------------------------------------------------------------
resource "random_string" "db_password" {
  length  = 28
  special = false

  keepers = {
    cluster_identifier = var.name
  }
}


# --------------------------------------------------------------------------
# SecurityGroup
# --------------------------------------------------------------------------
resource "aws_security_group" "aurora" {
  name_prefix = "${var.name}-"
  description = "${var.name} - Aurora"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.vpc_id == "" ? aws_subnet.public.*.cidr_block : data.aws_subnet.subnet.*.cidr_block
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:AWS009
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}


# --------------------------------------------------------------------------
# KMS Key for encryption-at-rest
# --------------------------------------------------------------------------
data "aws_kms_key" "kms" {
  count = var.kms_key != null ? 1 : 0

  key_id = var.kms_key
}

data "aws_kms_alias" "kms" {
  name = "alias/aws/rds"
}

resource "random_integer" "final_identifier" {
  min = 1000
  max = 9999

  keepers = {
    cluster_identifier = var.name
  }
}


# --------------------------------------------------------------------------
# AWS RDS Aurora Serverless
# --------------------------------------------------------------------------
resource "aws_db_subnet_group" "default" {
  count = var.db_subnet_group_name == null ? 1 : 0

  name       = "${var.name}-public"
  subnet_ids = var.public_subnet_ids == [""] ? aws_subnet.public.*.id : var.public_subnet_ids

  tags = local.tags
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = var.name
  #availability_zones = data.aws_availability_zones.available.names

  # Engine
  engine         = "aurora"
  engine_mode    = "serverless"
  engine_version = "5.6.10a"

  # Database
  database_name   = var.db_name
  master_username = random_string.db_username.result
  master_password = random_string.db_password.result

  db_subnet_group_name      = var.db_subnet_group_name == null ? aws_db_subnet_group.default[0].name : var.db_subnet_group_name
  vpc_security_group_ids    = [aws_security_group.aurora.id]
  final_snapshot_identifier = "final-${var.name}-${random_integer.final_identifier.result}"

  scaling_configuration {
    auto_pause               = var.serverless_auto_pause
    max_capacity             = var.serverless_max
    min_capacity             = var.serverless_min
    seconds_until_auto_pause = var.serverless_seconds_pause
    timeout_action           = var.serverless_timeout_action
  }

  enable_http_endpoint = var.serverless_http_endpoint

  # Encryption, Logging, Protection
  storage_encrypted   = true
  kms_key_id          = var.kms_key == null ? data.aws_kms_alias.kms.target_key_arn : data.aws_kms_key.kms[0].arn
  deletion_protection = var.deletion_protection

  # Backup
  backup_retention_period = var.backup_retention_days
  preferred_backup_window = var.backup_window

  # Maintenance
  apply_immediately            = var.apply_immediately
  preferred_maintenance_window = var.preferred_maintenance_window

  copy_tags_to_snapshot = true

  tags = local.tags
}


# --------------------------------------------------------------------------
# SSM Parameter Store
# --------------------------------------------------------------------------
resource "aws_ssm_parameter" "username" {
  name        = "/rds/${var.name}/username"
  value       = aws_rds_cluster.aurora.master_username
  description = "Aurora DB username for ${var.name}"
  type        = "SecureString"
  overwrite   = true

  tags = local.tags
}

resource "aws_ssm_parameter" "password" {
  name        = "/rds/${var.name}/password"
  value       = aws_rds_cluster.aurora.master_password
  description = "Aurora DB password for ${var.name}"
  type        = "SecureString"
  overwrite   = true

  tags = local.tags
}

resource "aws_ssm_parameter" "endpoint" {
  name        = "/rds/${var.name}/instance_endpoint"
  value       = aws_rds_cluster.aurora.endpoint
  description = "Aurora Endpoint for ${var.name}"
  type        = "String"
  overwrite   = true

  tags = local.tags
}

resource "aws_ssm_parameter" "database" {
  name        = "/rds/${var.name}/database"
  value       = aws_rds_cluster.aurora.database_name
  description = "Aurora DB name for ${var.name}"
  type        = "String"
  overwrite   = true

  tags = local.tags
}