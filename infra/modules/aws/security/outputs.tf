output "platform_security_group_id" {
  value = aws_security_group.platform.id
}

output "vpc_id" {
  value = data.aws_vpc.this.id
}
