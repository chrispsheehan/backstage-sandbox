variable "aws_region" {
  type        = string
  description = "AWS region in which the development platform runs."
}

variable "aws_account_id" {
  type        = string
  description = "AWS account that owns the development platform resources."
}

variable "base_name" {
  type        = string
  description = "Shared name prefix for disposable development resources."
}

variable "vpc_name" {
  type        = string
  description = "Exact Name tag of the existing VPC."
}

variable "hosted_zone_name" {
  type        = string
  description = "Existing public Route 53 hosted zone used for platform URLs."
}

variable "instance_type" {
  type        = string
  description = "ARM64 EC2 instance type used for the single-node platform host."
  default     = "t4g.medium"
}

variable "root_volume_size" {
  type        = number
  description = "Size in GiB of the encrypted gp3 EC2 root volume."
  default     = 30
}

variable "platform_security_group_id" {
  type        = string
  description = "Security group allowing application traffic only from the platform ALB."
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "Security group accepting public HTTPS on the platform load balancer."
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile attached to the platform host."
}

variable "ecr_repository_url" {
  type        = string
  description = "Private ECR repository containing the Backstage runtime image."
}

variable "backstage_github_client_id" {
  type        = string
  description = "GitHub OAuth client ID loaded by Backstage on the EC2 lab."
  sensitive   = true
}

variable "backstage_github_client_secret" {
  type        = string
  description = "GitHub OAuth client secret loaded by Backstage on the EC2 lab."
  sensitive   = true
}

variable "database_parameter_prefix" {
  type        = string
  description = "Randomized SSM path containing the database connection settings."
}

variable "database_parameter_revision" {
  type        = string
  description = "Opaque revision that replaces the host when database parameters change."
}

variable "platform_repo_files" {
  type        = map(string)
  description = "Contents of the Argo bootstrap and script directories copied to the host."
}
