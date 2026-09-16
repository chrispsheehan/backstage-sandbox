output "address" {
  value = aws_db_instance.this.address
}

output "database_name" {
  value = local.database_name
}

output "port" {
  value = local.database_port
}

output "username" {
  value = local.database_username
}

output "parameter_prefix" {
  description = "Randomized SSM path containing the database connection settings."
  value       = local.database_parameter_prefix
}

output "parameter_revision" {
  description = "Changes whenever a database connection parameter changes."
  value = join(":", [
    aws_ssm_parameter.host.version,
    aws_ssm_parameter.port.version,
    aws_ssm_parameter.database.version,
    aws_ssm_parameter.username.version,
    aws_ssm_parameter.password.version,
  ])
}
