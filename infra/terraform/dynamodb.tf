# ─────────────────────────────────────────────────────────────────────────────
# DynamoDB — orders table (single source of truth)
# Streams capture INSERT + MODIFY events and feed the Lambda processor.
# Server-side encryption uses the AWS-managed key (aws/dynamodb).
# For a CMK, replace server_side_encryption with a custom aws_kms_key resource
# (requires IAM permissions not available in AWS Academy).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "orders" {
  name         = "${local.prefix}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idPedido"

  attribute {
    name = "idPedido"
    type = "S"
  }

  # DynamoDB Streams — captures NEW_AND_OLD_IMAGES so the Lambda can read
  # both the previous and the new state of each item.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # TTL — automatically purge delivered/cancelled orders after retention period
  ttl {
    attribute_name = var.dynamodb_ttl_attribute
    enabled        = true
  }

  # Encryption at rest with AWS-managed key
  server_side_encryption {
    enabled = true
  }

  # Point-in-time recovery — allows restoring the table to any second in the
  # last 35 days without a backup window.
  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}
