variable "base_name" {
  type        = string
  description = "Shared name prefix for disposable development resources."
}

variable "vpc_name" {
  type        = string
  description = "Exact Name tag of the existing VPC."
}
