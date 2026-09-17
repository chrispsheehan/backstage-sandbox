variable "aws_region" {
  type        = string
  description = "AWS region containing the platform resources."
}

variable "aws_account_id" {
  type        = string
  description = "AWS account that owns the platform resources."
}

variable "base_name" {
  type        = string
  description = "Shared name prefix for disposable development resources."
}

variable "ecr_repository_arn" {
  type        = string
  description = "Backstage ECR repository the platform host may pull from."
}
