data "aws_partition" "current" {}

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "platform" {
  statement {
    sid     = "ReadBootstrapArchive"
    actions = ["s3:GetObject"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.aws_account_id}-${var.aws_region}-${var.base_name}-bootstrap/platform-repo.zip",
    ]
  }

  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullBackstageImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid = "DiscoverS3Buckets"
    actions = [
      "s3:GetAccountPublicAccessBlock",
      "s3:ListAllMyBuckets",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ManageGeneratedS3Sites"
    actions = ["s3:*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::*-${var.aws_account_id}-${var.aws_region}",
      "arn:${data.aws_partition.current.partition}:s3:::*-${var.aws_account_id}-${var.aws_region}/*",
    ]
  }
}
