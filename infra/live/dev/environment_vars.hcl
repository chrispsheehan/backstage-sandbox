locals {
  instance_type                   = "t4g.medium"
  root_volume_size                = 30
  ingress_cidrs                   = ["0.0.0.0/0"]
  image_expiration_days           = 30
  force_delete                    = true
  repository_revision             = "main"
  backstage_secret_parameter_name = "/backstage-sandbox/dev/backstage"
}

inputs = {
  instance_type                   = local.instance_type
  root_volume_size                = local.root_volume_size
  ingress_cidrs                   = local.ingress_cidrs
  image_expiration_days           = local.image_expiration_days
  force_delete                    = local.force_delete
  repository_revision             = local.repository_revision
  backstage_secret_parameter_name = local.backstage_secret_parameter_name
}
