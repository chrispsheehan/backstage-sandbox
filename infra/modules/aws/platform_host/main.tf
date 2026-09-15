resource "aws_ssm_document" "run_shell" {
  name          = "${var.base_name}-run-shell"
  document_type = "Session"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Start a Backstage sandbox shell as ec2-user"
    sessionType   = "Standard_Stream"
    inputs = {
      runAsEnabled     = true
      runAsDefaultUser = "ec2-user"
      shellProfile = {
        linux = "export PATH=/usr/local/bin:/usr/bin:/bin; cloud-init status --wait && cd /opt/backstage-sandbox"
      }
    }
  })
}

data "archive_file" "platform_repo" {
  type        = "zip"
  output_path = "${path.root}/.terraform/platform-repo.zip"

  dynamic "source" {
    for_each = var.platform_repo_files

    content {
      content  = source.value
      filename = source.key
    }
  }
}

resource "aws_s3_bucket" "bootstrap" {
  bucket        = "${var.aws_account_id}-${var.aws_region}-${var.base_name}-bootstrap"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "platform_repo" {
  bucket = aws_s3_bucket.bootstrap.id
  key    = "platform-repo.zip"
  source = data.archive_file.platform_repo.output_path
  etag   = data.archive_file.platform_repo.output_md5
}

resource "random_id" "backstage_parameters" {
  byte_length = 4
}

resource "random_password" "backstage_backend_secret" {
  length  = 64
  special = false
}

resource "aws_ssm_parameter" "backstage_backend_secret" {
  name  = "/${var.base_name}/backstage/${random_id.backstage_parameters.hex}/backend-secret"
  type  = "SecureString"
  value = random_password.backstage_backend_secret.result
}

resource "aws_ssm_parameter" "backstage_github_client_id" {
  name  = "/${var.base_name}/backstage/${random_id.backstage_parameters.hex}/github-client-id"
  type  = "SecureString"
  value = var.backstage_github_client_id
}

resource "aws_ssm_parameter" "backstage_github_client_secret" {
  name  = "/${var.base_name}/backstage/${random_id.backstage_parameters.hex}/github-client-secret"
  type  = "SecureString"
  value = var.backstage_github_client_secret
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2023_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.public.ids)[0]
  associate_public_ip_address = false
  vpc_security_group_ids      = [var.platform_security_group_id]
  iam_instance_profile        = var.instance_profile_name

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    aws_region = var.aws_region
    backstage_auth_revision = join(":", [
      aws_ssm_parameter.backstage_backend_secret.version,
      aws_ssm_parameter.backstage_github_client_id.version,
      aws_ssm_parameter.backstage_github_client_secret.version,
    ])
    backstage_parameter_prefix  = "/${var.base_name}/backstage/${random_id.backstage_parameters.hex}"
    bootstrap_script_base64gzip = base64gzip(var.bootstrap_script)
    ecr_repository_url          = var.ecr_repository_url
    git_repository_url          = "https://github.com/${var.github_repo}.git"
    git_revision                = var.git_revision
    platform_repo_content_hash  = data.archive_file.platform_repo.output_sha256
    platform_repo_s3_uri        = "s3://${aws_s3_bucket.bootstrap.bucket}/${aws_s3_object.platform_repo.key}"
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 3
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }

  depends_on = [
    aws_s3_object.platform_repo,
    aws_ssm_parameter.backstage_backend_secret,
    aws_ssm_parameter.backstage_github_client_id,
    aws_ssm_parameter.backstage_github_client_secret,
  ]
}

resource "aws_eip" "this" {
  domain = "vpc"
}

resource "aws_eip_association" "this" {
  allocation_id = aws_eip.this.id
  instance_id   = aws_instance.this.id
}
