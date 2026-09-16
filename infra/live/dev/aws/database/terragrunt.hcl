include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "security" {
  config_path = "../security"

  mock_outputs = {
    postgres_security_group_id = "sg-00000000000000001"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules//aws//database"
}

inputs = {
  postgres_security_group_id = dependency.security.outputs.postgres_security_group_id
}
