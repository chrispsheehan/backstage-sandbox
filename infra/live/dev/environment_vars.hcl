locals {
  instance_type         = "t4g.medium"
  root_volume_size      = 30
  image_expiration_days = 30
}

inputs = {
  instance_type         = local.instance_type
  root_volume_size      = local.root_volume_size
  image_expiration_days = local.image_expiration_days
}
