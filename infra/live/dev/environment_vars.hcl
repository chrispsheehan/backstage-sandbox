locals {
  instance_type         = "t4g.medium"
  root_volume_size      = 30
  ingress_cidrs         = ["0.0.0.0/0"]
  image_expiration_days = 30
}

inputs = {
  instance_type         = local.instance_type
  root_volume_size      = local.root_volume_size
  ingress_cidrs         = local.ingress_cidrs
  image_expiration_days = local.image_expiration_days
}
