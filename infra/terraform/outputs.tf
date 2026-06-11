# ── Region / project ─────────────────────────────────────────────────────────

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "project" {
  description = "Project name"
  value       = var.project_name
}

output "prefix" {
  description = "Common resource prefix"
  value       = local.prefix
}

# ── VPC ──────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID — pass to eksctl when creating the EKS cluster"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for EKS node group)"
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "ALB security group — attach when creating the ALB via K8s Ingress"
  value       = aws_security_group.alb.id
}

output "eks_nodes_security_group_id" {
  description = "EKS node group security group"
  value       = aws_security_group.eks_nodes.id
}

# ── DynamoDB ─────────────────────────────────────────────────────────────────

output "orders_table_name" {
  description = "DynamoDB table name — set as DYNAMODB_TABLE_NAME in K8s ConfigMap"
  value       = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.orders.arn
}

output "orders_table_stream_arn" {
  description = "DynamoDB Streams ARN (used by Lambda event source mapping)"
  value       = aws_dynamodb_table.orders.stream_arn
}

# ── SQS ──────────────────────────────────────────────────────────────────────

output "notifications_queue_url" {
  description = "SQS queue URL — set as SQS_QUEUE_URL in K8s ConfigMap"
  value       = aws_sqs_queue.notifications.id
}

output "notifications_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.notifications.arn
}

output "notifications_dlq_url" {
  description = "Dead-letter queue URL"
  value       = aws_sqs_queue.notifications_dlq.id
}

# ── ECR ──────────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "ECR repository URLs — use as base image tags in CI/CD"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

# ── Lambda ───────────────────────────────────────────────────────────────────

output "lambda_function_arn" {
  description = "Lambda stream processor ARN"
  value       = aws_lambda_function.stream_processor.arn
}

# ── S3 ───────────────────────────────────────────────────────────────────────

output "frontend_bucket_name" {
  description = "S3 bucket name for the static frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_website_url" {
  description = "S3 static website endpoint"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

# ── SES ──────────────────────────────────────────────────────────────────────

output "ses_verified_sender" {
  description = "Verified SES sender address"
  value       = var.ses_verified_sender
}

# ── IAM (AWS Academy) ────────────────────────────────────────────────────────

output "lab_role_arn" {
  description = "LabRole ARN — usado por Lambda y nodos EKS en Academy"
  value       = data.aws_iam_role.lab_role.arn
}

# ── S3 Config recordings ─────────────────────────────────────────────────────

output "config_recordings_bucket" {
  description = "S3 bucket para las grabaciones de AWS Config (apuntar en la consola)"
  value       = aws_s3_bucket.config_recordings.bucket
}
