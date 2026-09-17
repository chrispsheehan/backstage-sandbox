variable "base_name" {
  type        = string
  description = "Shared name prefix for disposable development resources."
}

variable "vpc_name" {
  type        = string
  description = "Exact Name tag of the existing VPC."
}

variable "postgres_security_group_id" {
  type        = string
  description = "Security group that permits PostgreSQL only from the platform host security group."
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL major version."
  default     = "16"
}

variable "instance_class" {
  type        = string
  description = "Disposable Single-AZ RDS instance class."
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated gp3 storage in GiB."
  default     = 20
}
