# ─────────────────────────────────────────────────────────────────────────────
# AWS Config — monitoreo continuo de compliance (Misión 2 Q18)
#
# AWS Academy — cómo habilitarlo manualmente (recomendado):
#   1. Ir a AWS Config en la consola → "Set up AWS Config"
#   2. Seleccionar "Record all resources supported in this region"
#   3. Elegir un S3 bucket existente o crear uno (usar el bucket de config_recordings)
#   4. La consola crea el rol de servicio AWSServiceRoleForConfig automáticamente
#   5. Una vez activo, el bloque de rules a continuación se puede aplicar con TF:
#        terraform apply -target=aws_config_config_rule.restricted_ssh \
#                        -target=aws_config_config_rule.vpc_flow_logs \
#                        -target=aws_config_config_rule.encrypted_volumes \
#                        -target=aws_config_config_rule.dynamodb_encryption
#
# PRODUCCIÓN REAL (fuera de Academy): el recorder y el delivery channel se
# gestionarían completamente en Terraform con un rol IAM personalizado que
# tiene la política AWS_ConfigRole y trust en config.amazonaws.com.
# ─────────────────────────────────────────────────────────────────────────────

# ── Config Rules — se aplican una vez que el recorder está activo ─────────────
# Si el recorder no está activo, terraform apply ignorará estos recursos
# con el warning: "AWS Config is not enabled in this region".

resource "aws_config_config_rule" "restricted_ssh" {
  name        = "${local.prefix}-restricted-ssh"
  description = "Verifica que los security groups no permitan SSH (puerto 22) irrestricto"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}

resource "aws_config_config_rule" "vpc_flow_logs" {
  name        = "${local.prefix}-vpc-flow-logs-enabled"
  description = "Verifica que VPC Flow Logs esté habilitado"

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name        = "${local.prefix}-encrypted-volumes"
  description = "Verifica que los volúmenes EBS estén cifrados"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
}

resource "aws_config_config_rule" "dynamodb_encryption" {
  name        = "${local.prefix}-dynamodb-encryption"
  description = "Verifica que las tablas DynamoDB estén cifradas en reposo"

  source {
    owner             = "AWS"
    source_identifier = "DYNAMODB_TABLE_ENCRYPTED_AT_REST"
  }
}
