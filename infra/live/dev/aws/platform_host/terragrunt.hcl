include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  repo_root = get_repo_root()
  platform_repo_paths = setunion(
    fileset(local.repo_root, "config/**"),
    fileset(local.repo_root, "k8s/**"),
    fileset(local.repo_root, "scripts/lab/**"),
  )
}

dependencies {
  paths = ["../ecr"]
}

dependency "security" {
  config_path = "../security"

  mock_outputs = {
    platform_security_group_id = "sg-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../modules//aws//platform_host"
}

inputs = {
  bootstrap_script           = file("${local.repo_root}/scripts/aws/bootstrap-platform-host.sh")
  platform_repo_files        = { for path in local.platform_repo_paths : path => file("${local.repo_root}/${path}") }
  platform_security_group_id = dependency.security.outputs.platform_security_group_id
}
