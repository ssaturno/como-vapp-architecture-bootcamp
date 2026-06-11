# ─────────────────────────────────────────────────────────────────────────────
# SQS — main notifications queue + dead-letter queue
#
# Cifrado: SSE-SQS (SQS-managed encryption) — gratuito, no requiere permisos
# KMS adicionales, compatible con AWS Academy.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ PRODUCCIÓN REAL: usar SSE-KMS con alias/aws/sqs o CMK para control      │
# │ total del ciclo de vida de la clave (Misión 1 Q8 / Misión 2 Q19).       │
# └─────────────────────────────────────────────────────────────────────────┘
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "${local.prefix}-notifications-dlq"
  message_retention_seconds = 1209600 # 14 days

  # SSE-SQS: cifrado en reposo gestionado por SQS (sin costo adicional)
  sqs_managed_sse_enabled = true

  tags = local.common_tags
}

resource "aws_sqs_queue" "notifications" {
  name                       = "${local.prefix}-notifications"
  message_retention_seconds  = var.sqs_message_retention_days * 86400
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20 # long-polling ahorra llamadas a la API

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = var.sqs_dlq_max_receives
  })

  tags = local.common_tags
}
