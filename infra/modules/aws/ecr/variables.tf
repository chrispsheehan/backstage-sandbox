variable "base_name" {
  type        = string
  description = "Name of the development Backstage image repository."
}

variable "force_delete" {
  type        = bool
  description = "Whether Terraform may delete the repository while it contains images."
  default     = true
}

variable "image_expiration_days" {
  type        = number
  description = "Age in days after which development images expire."
  default     = 30
}
