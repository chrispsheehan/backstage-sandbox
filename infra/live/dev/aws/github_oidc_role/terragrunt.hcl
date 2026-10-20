include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr://registry.terraform.io/chrispsheehan/github-oidc-role/aws?version=1.0.3"
}

inputs = {
  deploy_role_name = "backstage-sandbox-github-deploy"
  github_repo      = include.root.locals.github_repo
  state_bucket     = include.root.locals.state_bucket

  deploy_branches     = ["main"]
  deploy_environments = ["dev"]

  allowed_role_actions = [
    "acm:*",
    "ec2:*",
    "ecr:*",
    "elasticloadbalancing:*",
    "iam:*",
    "rds:*",
    "route53:*",
    "s3:*",
    "ssm:*",
    "sts:GetCallerIdentity",
  ]
  allowed_role_resources = ["*"]
}
