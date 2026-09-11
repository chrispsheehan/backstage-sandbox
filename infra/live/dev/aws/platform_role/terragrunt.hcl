include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "ecr" {
  config_path = "../ecr"

  mock_outputs = {
    repository_arn = "arn:aws:ecr:eu-west-2:000000000000:repository/backstage-sandbox-dev"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../modules//aws//platform_role"
}

inputs = {
  ecr_repository_arn = dependency.ecr.outputs.repository_arn
}
