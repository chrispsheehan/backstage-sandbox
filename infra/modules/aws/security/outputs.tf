output "platform_security_group_id" {
  value = aws_security_group.platform.id
}

output "load_balancer_security_group_id" {
  value = aws_security_group.load_balancer.id
}

output "postgres_security_group_id" {
  value = aws_security_group.postgres.id
}

output "vpc_id" {
  value = data.aws_vpc.this.id
}
