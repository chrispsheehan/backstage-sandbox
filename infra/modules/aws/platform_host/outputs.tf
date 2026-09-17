output "instance_id" {
  description = "EC2 instance hosting the disposable k3d platform."
  value       = aws_instance.this.id
}

output "session_document_name" {
  description = "Session Manager document used by the root shell recipe."
  value       = aws_ssm_document.run_shell.name
}

output "bootstrap_bucket_name" {
  description = "Private S3 bucket containing the platform bootstrap archive."
  value       = aws_s3_bucket.bootstrap.id
}

output "public_ip" {
  description = "Ephemeral EC2 public IPv4 used only for outbound access."
  value       = aws_instance.this.public_ip
}

output "load_balancer_dns_name" {
  description = "AWS-generated DNS name of the public Application Load Balancer."
  value       = aws_lb.platform.dns_name
}

output "backstage_url" {
  description = "Public HTTPS URL for Backstage."
  value       = local.backstage_url
}

output "argocd_url" {
  description = "Public HTTPS URL for Argo CD."
  value       = local.argocd_url
}

output "backstage_parameter_prefix" {
  description = "Randomized SSM path containing the Backstage runtime parameters."
  value       = "/${var.base_name}/backstage/${random_id.backstage_parameters.hex}"
}
