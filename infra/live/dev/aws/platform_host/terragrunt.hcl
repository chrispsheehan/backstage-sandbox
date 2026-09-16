include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  repo_root = get_repo_root()
  platform_repo_paths = setunion(
    fileset(local.repo_root, "config/**"),
    fileset(local.repo_root, "crossplane/providers/**"),
    fileset(local.repo_root, "crossplane/providerconfigs/ec2/**"),
    fileset(local.repo_root, "k8s/**"),
    fileset(local.repo_root, "scripts/lab/**"),
  )
}

dependency "security" {
  config_path = "../security"

  mock_outputs = {
    platform_security_group_id      = "sg-00000000000000000"
    load_balancer_security_group_id = "sg-00000000000000001"
  }
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "platform_role" {
  config_path = "../platform_role"

  mock_outputs = {
    instance_profile_name = "backstage-sandbox-dev-ec2"
    role_name             = "backstage-sandbox-dev-ec2"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "ecr" {
  config_path = "../ecr"

  mock_outputs = {
    repository_url = "000000000000.dkr.ecr.eu-west-2.amazonaws.com/backstage-sandbox-dev"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "database" {
  config_path = "../database"

  mock_outputs = {
    parameter_prefix   = "/backstage-sandbox-dev/database/00000000"
    parameter_revision = "1:1:1:1:1"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules//aws//platform_host"
}

inputs = {
  bootstrap_script                = file("${local.repo_root}/scripts/aws/bootstrap-platform-host.sh")
  ecr_repository_url              = dependency.ecr.outputs.repository_url
  hosted_zone_name                = "chrispsheehan.com"
  instance_profile_name           = dependency.platform_role.outputs.instance_profile_name
  load_balancer_security_group_id = dependency.security.outputs.load_balancer_security_group_id
  platform_repo_files             = { for path in local.platform_repo_paths : path => file("${local.repo_root}/${path}") }
  platform_security_group_id      = dependency.security.outputs.platform_security_group_id
  database_parameter_prefix       = dependency.database.outputs.parameter_prefix
  database_parameter_revision     = dependency.database.outputs.parameter_revision
}
