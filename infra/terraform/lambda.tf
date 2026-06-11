# ─────────────────────────────────────────────────────────────────────────────
# Lambda — DynamoDB Streams → SQS processor
# Triggered automatically on every INSERT/MODIFY in the orders table.
# Packages the handler from infra/lambda/stream_handler.py at plan time.
# ─────────────────────────────────────────────────────────────────────────────

data "archive_file" "stream_handler" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/stream_handler.py"
  output_path = "${path.module}/../../lambda/stream_handler.zip"
}

resource "aws_lambda_function" "stream_processor" {
  function_name    = "${local.prefix}-stream-processor"
  role             = data.aws_iam_role.lab_role.arn
  runtime          = "python3.12"
  handler          = "stream_handler.handler"
  filename         = data.archive_file.stream_handler.output_path
  source_code_hash = data.archive_file.stream_handler.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.notifications.id
      AWS_REGION    = var.aws_region
    }
  }

  # Send Lambda logs to CloudWatch
  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = local.common_tags
}

# ── DynamoDB Streams event source mapping ─────────────────────────────────────

resource "aws_lambda_event_source_mapping" "dynamo_stream" {
  event_source_arn              = aws_dynamodb_table.orders.stream_arn
  function_name                 = aws_lambda_function.stream_processor.arn
  starting_position             = "LATEST"
  batch_size                    = 10
  maximum_retry_attempts        = 3
  bisect_batch_on_function_error = true

  filter_criteria {
    filter {
      # Process only INSERT and MODIFY records — skip REMOVE (TTL purges)
      pattern = jsonencode({
        eventName = [{ prefix = "INSERT" }, { prefix = "MODIFY" }]
      })
    }
  }
}
