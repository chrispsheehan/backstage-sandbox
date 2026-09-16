resource "random_password" "master" {
  length  = 32
  special = false
}

resource "random_id" "database_parameters" {
  byte_length = 4
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.base_name}-postgres"
  subnet_ids = local.public_subnet_ids

  lifecycle {
    precondition {
      condition     = length(local.public_subnet_azs) >= 2
      error_message = "RDS requires public subnets in at least two availability zones."
    }
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.base_name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.database_name
  username = local.database_username
  password = random_password.master.result
  port     = local.database_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.postgres_security_group_id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period  = 0
  delete_automated_backups = true
  skip_final_snapshot      = true
  deletion_protection      = false

  apply_immediately          = true
  auto_minor_version_upgrade = true
}

resource "aws_ssm_parameter" "host" {
  name  = "${local.database_parameter_prefix}/host"
  type  = "SecureString"
  value = aws_db_instance.this.address
}

resource "aws_ssm_parameter" "port" {
  name  = "${local.database_parameter_prefix}/port"
  type  = "SecureString"
  value = tostring(local.database_port)
}

resource "aws_ssm_parameter" "database" {
  name  = "${local.database_parameter_prefix}/name"
  type  = "SecureString"
  value = local.database_name
}

resource "aws_ssm_parameter" "username" {
  name  = "${local.database_parameter_prefix}/username"
  type  = "SecureString"
  value = local.database_username
}

resource "aws_ssm_parameter" "password" {
  name  = "${local.database_parameter_prefix}/password"
  type  = "SecureString"
  value = random_password.master.result
}
