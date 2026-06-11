# ─────────────────────────────────────────────────────────────────────────────
# Security Groups — principle of least privilege
#   ALB SG  : public internet → 80/443 only
#   EKS SG  : ALB SG → node port range only; nodes egress to reach AWS APIs
# ─────────────────────────────────────────────────────────────────────────────

# ── ALB Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb-sg"
  description = "Allow HTTP/HTTPS inbound from internet; forward to EKS nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to EKS node ports"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-alb-sg"
  })
}

# ── EKS Node Security Group ───────────────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name        = "${local.prefix}-eks-nodes-sg"
  description = "EKS worker nodes: accept traffic from ALB only; full egress for AWS APIs"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NodePort traffic from ALB"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Intra-node communication (all ports within VPC)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Full egress for AWS service APIs (DynamoDB, SQS, SES, ECR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-eks-nodes-sg"
  })
}
