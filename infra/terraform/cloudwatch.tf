# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch — log groups, metric alarms
# Pods in EKS send logs to these groups via the CloudWatch agent (Fluent Bit).
# ─────────────────────────────────────────────────────────────────────────────

locals {
  service_log_groups = {
    "orders-service"        = "/como-vapp/orders-service"
    "admin-service"         = "/como-vapp/admin-service"
    "notifications-service" = "/como-vapp/notifications-service"
  }
}

resource "aws_cloudwatch_log_group" "services" {
  for_each          = local.service_log_groups
  name              = each.value
  retention_in_days = 30

  tags = local.common_tags
}

# Separate log group for the Lambda function — referenced in lambda.tf
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.prefix}-stream-processor"
  retention_in_days = 30

  tags = local.common_tags
}

# ── SQS — alarm when the DLQ receives a message ───────────────────────────────

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${local.prefix}-dlq-messages"
  alarm_description   = "Messages landed in the DLQ — notification processing is failing"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.notifications_dlq.name
  }

  tags = local.common_tags
}

# ── SQS — alarm when main queue depth exceeds 100 ────────────────────────────

resource "aws_cloudwatch_metric_alarm" "notifications_queue_depth" {
  alarm_name          = "${local.prefix}-notifications-queue-depth"
  alarm_description   = "Notifications queue depth is high — consumer may be falling behind"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.notifications.name
  }

  tags = local.common_tags
}

# ── Lambda — alarm on errors ──────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.prefix}-lambda-errors"
  alarm_description   = "Lambda stream processor is throwing errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  tags = local.common_tags
}
