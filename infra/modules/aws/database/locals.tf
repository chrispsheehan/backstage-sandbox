locals {
  database_name             = "backstage"
  database_parameter_prefix = "/${var.base_name}/database/${random_id.database_parameters.hex}"
  database_port             = 5432
  database_username         = "backstage"
  public_subnet_ids         = sort(data.aws_subnets.public.ids)
  public_subnet_azs = distinct([
    for subnet_id in local.public_subnet_ids : data.aws_subnet.public[subnet_id].availability_zone
  ])
}
