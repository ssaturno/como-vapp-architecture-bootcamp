variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "como-vapp"
}

variable "environment" {
  description = "Environment name (dev / prod)"
  type        = string
  default     = "dev"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the two public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the two private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "AZs to use (must match the region)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ── EKS (referenced for subnet tagging only — cluster created manually) ──────

variable "eks_cluster_name" {
  description = "EKS cluster name — used for subnet auto-discovery tags"
  type        = string
  default     = "como-vapp-eks"
}

# ── SES ──────────────────────────────────────────────────────────────────────

variable "ses_verified_sender" {
  description = "Email address already verified in SES (sandbox). Replace before apply."
  type        = string
  default     = "samarissaturno@gmail.com"
}

# ── DynamoDB ─────────────────────────────────────────────────────────────────

variable "dynamodb_ttl_attribute" {
  description = "Attribute name for DynamoDB TTL (leave blank to disable)"
  type        = string
  default     = "expireAt"
}

# ── SQS ──────────────────────────────────────────────────────────────────────

variable "sqs_message_retention_days" {
  description = "How many days SQS retains unprocessed messages"
  type        = number
  default     = 14
}

variable "sqs_dlq_max_receives" {
  description = "Number of receive attempts before moving a message to the DLQ"
  type        = number
  default     = 3
}

# ── S3 frontend ───────────────────────────────────────────────────────────────

variable "frontend_index_document" {
  description = "S3 static website index document"
  type        = string
  default     = "index.html"
}
