output "repository_arn" {
  description = "ARN used to scope the platform host's ECR pull permissions."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Registry URL used to publish and deploy Backstage images."
  value       = aws_ecr_repository.this.repository_url
}
