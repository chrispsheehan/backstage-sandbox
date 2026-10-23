locals {
  aws_region       = "eu-west-2"
  hosted_zone_name = "chrispsheehan.com"
  vpc_name         = "vpc"
}

inputs = {
  aws_region       = local.aws_region
  hosted_zone_name = local.hosted_zone_name
  vpc_name         = local.vpc_name
}
