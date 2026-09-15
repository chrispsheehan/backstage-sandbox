locals {
  hosted_zone_name   = trimsuffix(var.hosted_zone_name, ".")
  backstage_hostname = "backstage.${local.hosted_zone_name}"
  argocd_hostname    = "argocd.${local.hosted_zone_name}"
  backstage_url      = "https://${local.backstage_hostname}"
  argocd_url         = "https://${local.argocd_hostname}"

  # Caddy temporarily manages TXT records at these exact names to complete
  # ACME DNS-01 validation; listing them keeps its Route 53 IAM access narrow.
  acme_record_names = [
    "_acme-challenge.argocd.${local.hosted_zone_name}",
    "_acme-challenge.backstage.${local.hosted_zone_name}",
  ]
}
