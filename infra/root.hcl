locals {
  git_remote                   = run_cmd("--terragrunt-quiet", "git", "remote", "get-url", "origin")
  github_repo                  = trimsuffix(regex("[:/]([^/:]+/[^/]+)$", local.git_remote)[0], ".git")
  aws_account_id               = get_env("AWS_ACCOUNT_ID")
  allowed_read_aws_account_ids = [local.aws_account_id]

  path_parts  = split("/", get_terragrunt_dir())
  module      = local.path_parts[length(local.path_parts) - 1]
  provider    = local.path_parts[length(local.path_parts) - 2]
  environment = local.path_parts[length(local.path_parts) - 3]

  global_vars      = read_terragrunt_config(find_in_parent_folders("global_vars.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment_vars.hcl"))

  project_name = element(split("/", local.github_repo), 1)
  project_slug = replace(local.project_name, ".", "-")

  aws_region   = local.global_vars.inputs.aws_region
  base_name    = "${local.project_slug}-${local.environment}"
  state_bucket = "${local.aws_account_id}-${local.aws_region}-${local.project_slug}-tfstate"
  state_key    = "${local.environment}/${local.provider}/${local.module}/terraform.tfstate"
}

remote_state {
  backend = "s3"
  config = {
    bucket       = local.state_bucket
    key          = local.state_key
    region       = local.aws_region
    use_lockfile = true
    encrypt      = true
  }
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "skip"
  contents  = <<EOF
terraform {
  backend "s3" {}
}
EOF
}

generate "aws_provider" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region              = "${local.aws_region}"
  allowed_account_ids = ["${local.aws_account_id}"]

  default_tags {
    tags = {
      Project     = "${local.project_name}"
      Environment = "${local.environment}"
      ManagedBy   = "terraform"
      Name        = "${local.base_name}-platform"
    }
  }
}
EOF
  disable   = local.provider != "aws"
}

inputs = merge(
  local.global_vars.inputs,
  local.environment_vars.inputs,
  {
    aws_account_id               = local.aws_account_id
    allowed_read_aws_account_ids = local.allowed_read_aws_account_ids
    project_name                 = local.project_name
    environment                  = local.environment
    github_repo                  = local.github_repo
    base_name                    = local.base_name
    state_bucket                 = local.state_bucket
  }
)
