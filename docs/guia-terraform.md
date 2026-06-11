# Guía de Infraestructura — Terraform

Todos los recursos AWS del proyecto (excepto el clúster EKS) se provisionan con Terraform. EKS se crea manualmente con `eksctl`; Terraform sólo crea la red y los servicios AWS que EKS usa.

---

## Recursos que provisiona Terraform

| Archivo | Recurso |
|---|---|
| `vpc.tf` | VPC, subnets públicas/privadas, IGW, NAT Gateway, route tables, VPC Endpoints |
| `security_groups.tf` | SG del ALB, SG de los nodos EKS |
| `ecr.tf` | 4 repositorios ECR con scan on push y lifecycle policies |
| `dynamodb.tf` | Tabla `orders` con Streams, TTL, SSE y PITR habilitados |
| `sqs.tf` | Cola de notificaciones + DLQ con encryption KMS |
| `ses.tf` | Identidad de email verificada en SES |
| `iam.tf` | Rol de ejecución para Lambda (con política de mínimo privilegio) |
| `lambda.tf` | Función Python que procesa DynamoDB Streams → SQS |
| `s3.tf` | Bucket de frontend (static website) + bucket para AWS Config |
| `cloudwatch.tf` | Log groups (30 días retención) + alarmas SQS/Lambda |
| `config.tf` | AWS Config recorder + reglas de compliance |

---

## Prerequisitos

```bash
# Instalar Terraform >= 1.5
# https://developer.hashicorp.com/terraform/install

terraform version   # debe ser >= 1.5.0

# Configurar credenciales AWS Academy
aws configure
aws sts get-caller-identity
```

---

## Variables importantes

| Variable | Default | Descripción |
|---|---|---|
| `aws_region` | `us-east-1` | Región AWS |
| `project_name` | `como-vapp` | Prefijo de todos los recursos |
| `environment` | `dev` | Ambiente (`dev` / `prod`) |
| `ses_verified_sender` | *placeholder* | **Reemplazar** con tu email verificado en SES |
| `eks_cluster_name` | `como-vapp-eks` | Nombre del clúster EKS (para tags de subnets) |

---

## Pasos para aplicar la infraestructura

### 1. Preparar el email SES

Antes de correr `apply`, actualiza el email en `variables.tf` (o pásalo por variable):

```bash
# Verificar el email en SES (recibirás un link de confirmación)
aws ses verify-email-identity --email-address tu@email.com --region us-east-1
```

### 2. Inicializar y planear

```bash
cd infra/terraform

terraform init

terraform plan \
  -var="ses_verified_sender=tu@email.com" \
  -out=tfplan
```

Revisar el plan antes de aplicar. Número esperado de recursos a crear: ~35-40.

### 3. Aplicar

```bash
terraform apply tfplan
```

> **Nota sobre AWS Academy**: si `apply` falla en recursos IAM o AWS Config,
> ve a la sección de solución de problemas más abajo.

### 4. Guardar los outputs

```bash
terraform output -json > ../../artifacts/tf-outputs.json
```

Los outputs más importantes para los manifiestos K8s:

```bash
terraform output orders_table_name        # → DYNAMODB_TABLE_NAME en ConfigMap
terraform output notifications_queue_url  # → SQS_QUEUE_URL en ConfigMap
terraform output ses_verified_sender      # → SES_VERIFIED_SENDER en ConfigMap
terraform output -json ecr_repository_urls # → URIs para las imágenes Docker
terraform output vpc_id                   # → para eksctl create cluster
terraform output private_subnet_ids       # → nodos EKS
terraform output public_subnet_ids        # → ALB
```

---

## Estructura de archivos Terraform

```
infra/
├── terraform/
│   ├── versions.tf          # Providers y versiones requeridas
│   ├── variables.tf         # Variables con defaults y descripciones
│   ├── main.tf              # Provider AWS + locals (prefix, common_tags)
│   ├── vpc.tf               # Red completa + VPC Endpoints
│   ├── security_groups.tf   # SG ALB y SG nodos EKS
│   ├── ecr.tf               # Repositorios de imágenes
│   ├── dynamodb.tf          # Tabla de pedidos
│   ├── sqs.tf               # Cola de notificaciones + DLQ
│   ├── ses.tf               # Identidad de email
│   ├── iam.tf               # Rol Lambda
│   ├── lambda.tf            # Función stream processor
│   ├── s3.tf                # Frontend + Config recordings
│   ├── cloudwatch.tf        # Log groups + alarmas
│   ├── config.tf            # AWS Config recorder + reglas
│   └── outputs.tf           # Todos los outputs
└── lambda/
    └── stream_handler.py    # Código del Lambda (empaquetado por Terraform)
```

---

## Cómo verificar los recursos creados

```bash
# DynamoDB
aws dynamodb describe-table --table-name $(terraform output -raw orders_table_name)

# SQS
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw notifications_queue_url) \
  --attribute-names All

# ECR
aws ecr describe-repositories --query 'repositories[*].repositoryName'

# Lambda
aws lambda get-function --function-name $(terraform output -raw prefix)-stream-processor

# S3 website
echo "Frontend URL: http://$(terraform output -raw frontend_website_url)"
```

---

## Cómo hacer deploy del frontend estático a S3

```bash
BUCKET=$(terraform output -raw frontend_bucket_name)

# Copiar los archivos compilados del frontend
aws s3 sync ../../frontend/react-app/ s3://$BUCKET/ --delete

echo "Sitio disponible en: http://$(terraform output -raw frontend_website_url)"
```

---

## Compatibilidad con AWS Academy

### Lo que funciona directamente con `terraform apply`

| Recurso | Estado | Nota |
|---|---|---|
| VPC, subnets, NAT, IGW | ✓ | Sin restricciones |
| Security Groups | ✓ | Sin restricciones |
| ECR repositorios | ✓ | Sin restricciones |
| DynamoDB tabla + Streams | ✓ | Sin restricciones |
| SQS colas (SSE-SQS) | ✓ | Sin KMS custom |
| SES email identity | ✓ | Solo sandbox |
| Lambda (con LabRole) | ✓ | `iam.tf` usa `data.aws_iam_role.lab_role` |
| S3 buckets | ✓ | Sin restricciones |
| CloudWatch log groups + alarmas | ✓ | Sin restricciones |
| AWS Config **rules** | ✓ | Solo después de habilitar Config manualmente |

### Lo que NO funciona en Academy (implementado como referencia)

| Recurso | Por qué | Alternativa en Academy |
|---|---|---|
| Roles IAM personalizados | No se pueden crear/modificar | Usar LabRole pre-existente |
| IRSA por pod | Requiere crear roles IAM | Todos los pods usan LabRole del nodo |
| AWS Config recorder vía TF | Requiere rol IAM con trust en config.amazonaws.com | Habilitar manualmente en consola |
| Secrets Store CSI Driver | Requiere IRSA | Valores en ConfigMap (no sensibles) o LabRole |
| KMS CMK (Customer Managed Key) | Restricción de Academy | SSE-SQS y AWS-managed DynamoDB key |

### Habilitar AWS Config manualmente (paso necesario en Academy)

```bash
# 1. Obtener el nombre del bucket de recordings desde TF
terraform output config_recordings_bucket

# 2. En la consola AWS: ir a AWS Config → "Set up AWS Config"
#    - Recording: "Record all resources"
#    - S3: usar el bucket del paso anterior
#    - Role: dejar que la consola cree el service-linked role automáticamente

# 3. Después de habilitarlo, aplicar las reglas de Config:
terraform apply \
  -target=aws_config_config_rule.restricted_ssh \
  -target=aws_config_config_rule.vpc_flow_logs \
  -target=aws_config_config_rule.encrypted_volumes \
  -target=aws_config_config_rule.dynamodb_encryption
```

---

## Destroy (limpieza)

```bash
terraform destroy \
  -var="ses_verified_sender=tu@email.com"
```

> Destruir en este orden si hay dependencias manuales:
> 1. Eliminar el clúster EKS (`eksctl delete cluster`)
> 2. Vaciar los buckets S3 manualmente (si `force_destroy = false`)
> 3. `terraform destroy`
