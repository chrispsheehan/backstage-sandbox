locals {
  aws_region = "eu-west-2"
  vpc_name   = "vpc"
}

inputs = {
  aws_region = local.aws_region
  vpc_name   = local.vpc_name
}
