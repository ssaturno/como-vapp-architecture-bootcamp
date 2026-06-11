# ─────────────────────────────────────────────────────────────────────────────
# S3 — two buckets
#   frontend   : static website hosting for the React SPA
#   config     : AWS Config delivery channel recordings
#
# Misión 2 Q5: frontend content is not sensitive personal data, so AWS-managed
# encryption (SSE-S3) is used instead of KMS.  If the bucket were to hold
# personal or financial data, SSE-KMS with a CMK would be required.
# ─────────────────────────────────────────────────────────────────────────────

# ── Frontend static website ───────────────────────────────────────────────────

resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.prefix}-frontend"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document { suffix = var.frontend_index_document }
  error_document { key    = var.frontend_index_document }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

# ── AWS Config delivery bucket ────────────────────────────────────────────────

resource "aws_s3_bucket" "config_recordings" {
  bucket        = "${local.prefix}-config-recordings"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "config_recordings" {
  bucket = aws_s3_bucket.config_recordings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_recordings" {
  bucket = aws_s3_bucket.config_recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "config_recordings" {
  bucket     = aws_s3_bucket.config_recordings.id
  depends_on = [aws_s3_bucket_public_access_block.config_recordings]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConfigWrite"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
        ]
        Resource = "${aws_s3_bucket.config_recordings.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid    = "AllowConfigAclCheck"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_recordings.arn
      }
    ]
  })
}
