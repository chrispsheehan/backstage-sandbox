variable "base_name" {
  type = string
}

variable "force_delete" {
  type    = bool
  default = true
}

variable "image_expiration_days" {
  type    = number
  default = 30
}

