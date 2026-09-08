output "instance_id" {
  value = aws_instance.this.id
}

output "bootstrap_bucket_name" {
  value = aws_s3_bucket.bootstrap.id
}

output "public_ip" {
  value = aws_eip.this.public_ip
}

output "backstage_url" {
  value = "http://${aws_eip.this.public_ip}"
}

output "session_command" {
  value = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.this.id}"
}
