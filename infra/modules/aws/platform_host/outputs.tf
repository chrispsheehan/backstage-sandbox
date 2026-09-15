output "instance_id" {
  value = aws_instance.this.id
}

output "session_document_name" {
  value = aws_ssm_document.run_shell.name
}

output "bootstrap_bucket_name" {
  value = aws_s3_bucket.bootstrap.id
}

output "public_ip" {
  value = aws_eip.this.public_ip
}

output "backstage_url" {
  value = local.backstage_url
}

output "argocd_url" {
  value = local.argocd_url
}

output "backstage_parameter_prefix" {
  description = "Randomized SSM path containing the Backstage runtime parameters."
  value       = "/${var.base_name}/backstage/${random_id.backstage_parameters.hex}"
}
