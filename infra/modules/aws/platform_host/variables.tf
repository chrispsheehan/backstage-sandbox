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

variable "platform_repo_files" {
  type        = map(string)
  description = "Contents of the selected repo directories copied to the host."
}
