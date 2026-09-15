terraform {
  required_version = ">= 1.11.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "= 2.7.1"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "= 6.40.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0"
    }
  }
}
