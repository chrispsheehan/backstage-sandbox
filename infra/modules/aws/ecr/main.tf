resource "aws_ecr_repository" "this" {
  name         = var.base_name
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove old development images"
      selection = {
        tagStatus   = "any"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.image_expiration_days
      }
      action = {
        type = "expire"
      }
    }]
  })
}

