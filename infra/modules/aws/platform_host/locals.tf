locals {
  hosted_zone_name   = trimsuffix(var.hosted_zone_name, ".")
  backstage_hostname = "backstage.${local.hosted_zone_name}"
  argocd_hostname    = "argocd.${local.hosted_zone_name}"
  backstage_url      = "https://${local.backstage_hostname}"
  argocd_url         = "https://${local.argocd_hostname}"
}
