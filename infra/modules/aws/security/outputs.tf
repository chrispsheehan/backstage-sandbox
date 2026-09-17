output "platform_security_group_id" {
  description = "Security group attached to the platform EC2 host."
  value       = aws_security_group.platform.id
}

output "load_balancer_security_group_id" {
  description = "Security group restricting public ALB access to the current caller."
  value       = aws_security_group.load_balancer.id
}

output "postgres_security_group_id" {
  description = "Security group allowing PostgreSQL traffic only from the platform host."
  value       = aws_security_group.postgres.id
}
