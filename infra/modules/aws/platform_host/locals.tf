locals {
  hosted_zone_name   = trimsuffix(var.hosted_zone_name, ".")
  backstage_hostname = "backstage.${local.hosted_zone_name}"
  argocd_hostname    = "argocd.${local.hosted_zone_name}"
  backstage_url      = "https://${local.backstage_hostname}"
  argocd_url         = "https://${local.argocd_hostname}"
  backstage_runtime_revision = join(":", [
    aws_ssm_parameter.backstage_backend_secret.version,
    aws_ssm_parameter.backstage_github_client_id.version,
    aws_ssm_parameter.backstage_github_client_secret.version,
    var.database_parameter_revision,
  ])
  bootstrap_environment = join("\n", [
    "AWS_REGION=${var.aws_region}",
    "ECR_REPOSITORY_URL=${var.ecr_repository_url}",
    "BACKSTAGE_PARAMETER_PREFIX=/${var.base_name}/backstage/${random_id.backstage_parameters.hex}",
    "DATABASE_PARAMETER_PREFIX=${var.database_parameter_prefix}",
    "BACKSTAGE_URL=${local.backstage_url}",
    "ARGOCD_URL=${local.argocd_url}",
    "GIT_REPOSITORY_URL=https://github.com/${var.github_repo}.git",
    "GIT_REVISION=${var.git_revision}",
    "",
  ])
}
