output "instance_profile_name" {
  description = "IAM instance profile attached to the platform EC2 host."
  value       = aws_iam_instance_profile.this.name
}
