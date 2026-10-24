variable "base_name" {
  type        = string
  description = "Shared name prefix for disposable development resources."
}

variable "vpc_name" {
  type        = string
  description = "Exact Name tag of the existing VPC."
}

variable "allowed_ip_range" {
  type        = string
  description = "IPv4 address or range allowed to access the public load balancer."

  validation {
    condition = (
      can(cidrhost(var.allowed_ip_range, 0)) &&
      !strcontains(var.allowed_ip_range, ":")
    )
    error_message = "allowed_ip_range must be a valid IPv4 address or range, such as 203.0.113.10/32 or 0.0.0.0/0."
  }
}
