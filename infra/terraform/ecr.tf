# ─────────────────────────────────────────────────────────────────────────────
# ECR — one private repository per service
# Image scanning on push is enabled to detect CVEs early (aligns with Trivy
# CI/CD gate defined in Misión 2 Q7).
# ─────────────────────────────────────────────────────────────────────────────

locals {
  ecr_repos = ["orders-service", "admin-service", "notifications-service", "frontend"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_repos)

  name                 = "${local.prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-${each.key}"
  })
}

# ── Lifecycle policy — keep only the last 10 tagged images per repo ───────────

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
