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

variable "platform_repo_files" {
  type        = map(string)
  description = "Contents of the selected repo directories copied to the host."
}
