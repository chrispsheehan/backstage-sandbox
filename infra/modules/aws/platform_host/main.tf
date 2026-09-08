resource "aws_iam_role" "this" {
  name               = "${var.base_name}-platform-host"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "platform" {
  name   = "${var.base_name}-platform"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.platform.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.base_name}-platform-host"
  role = aws_iam_role.this.name
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

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2023_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.public.ids)[0]
  associate_public_ip_address = false
  vpc_security_group_ids      = [var.platform_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    aws_region                  = var.aws_region
    bootstrap_script_base64gzip = base64gzip(var.bootstrap_script)
    platform_repo_content_hash  = data.archive_file.platform_repo.output_sha256
    platform_repo_s3_uri        = "s3://${aws_s3_bucket.bootstrap.bucket}/${aws_s3_object.platform_repo.key}"
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }

  depends_on = [
    aws_iam_role_policy.platform,
    aws_iam_role_policy_attachment.ssm,
    aws_s3_object.platform_repo,
  ]
}

resource "aws_eip" "this" {
  domain = "vpc"
}

resource "aws_eip_association" "this" {
  allocation_id = aws_eip.this.id
  instance_id   = aws_instance.this.id
}
