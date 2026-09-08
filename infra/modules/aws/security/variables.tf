variable "base_name" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
