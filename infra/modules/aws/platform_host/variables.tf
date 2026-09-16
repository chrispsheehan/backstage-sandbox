variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "base_name" {
  type = string
}

variable "bootstrap_script" {
  type        = string
  description = "Tracked shell script run automatically during initial host bootstrap."
}

variable "github_repo" {
  type        = string
  description = "GitHub owner and repository scanned by the Argo CD ApplicationSet."
}

variable "git_revision" {
  type        = string
  description = "Git revision scanned by the Argo CD ApplicationSet."
  default     = "main"
}

variable "vpc_name" {
  type = string
}

variable "hosted_zone_name" {
  type        = string
  description = "Existing public Route 53 hosted zone used for platform URLs."
}

variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "root_volume_size" {
  type    = number
  default = 30
}

variable "platform_security_group_id" {
  type = string
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "Security group accepting public HTTPS on the platform load balancer."
}

variable "instance_profile_name" {
  type = string
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
  description = "Contents of the selected repo directories copied to the host."
}
