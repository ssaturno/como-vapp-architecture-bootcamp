# ─────────────────────────────────────────────────────────────────────────────
# IAM — AWS Academy compatible
#
# AWS Academy proporciona un único rol preconfigurado llamado "LabRole".
# NO se pueden crear roles IAM personalizados en este entorno.
# Tanto la función Lambda como los nodos EKS usarán LabRole.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ PRODUCCIÓN REAL (fuera de Academy) — lo que se implementaría:           │
# │  - Rol IRSA por microservicio con mínimo privilegio:                    │
# │    orders-role    → DynamoDB: PutItem, GetItem (solo tabla orders)      │
# │    admin-role     → DynamoDB: UpdateItem + SQS: SendMessage             │
# │    notif-role     → SQS: ReceiveMessage/DeleteMessage + SES: SendEmail  │
# │    lambda-role    → DynamoDB Streams read + SQS: SendMessage            │
# │    alb-ctrl-role  → ELB + EC2 (para el ALB Ingress Controller)          │
# │  - IRSA vincula cada ServiceAccount de K8s a su rol IAM específico      │
# │  - Ningún pod tiene más permisos de los que necesita                    │
# └─────────────────────────────────────────────────────────────────────────┘
#
# En Academy: todos los servicios usan LabRole, que tiene permisos amplios.
# Esta es la restricción del entorno, no una buena práctica de producción.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}
