# Como Vapp — Sistema de Gestión de Pedidos

Proyecto final del Bootcamp de Arquitectura de Nube. Sistema de seguimiento de pedidos con notificaciones por email, desplegado en AWS con EKS, DynamoDB, SQS, SES y Lambda.

---

## Arquitectura General

```
Internet
   │
   ▼
[WAF + ALB]  ← subnets públicas
   │
   ├─▶ [Frontend React]  ──────────────────────────────────── S3 (static hosting)
   │
   ├─▶ [orders-service (.NET PoC)]  ─── DynamoDB ─── Streams ─── Lambda ─── SQS ─▶ [notifications-service (Python)]
   │          (POST /orders, GET /orders/{id})                                            │
   └─▶ [admin-service (Kotlin PoC)]  ── DynamoDB ─── SQS ──────────────────────────────▶│
              (PATCH /orders/{id}/status)                                                 │
                                                                                          ▼
                                                                                    [SES] → email
Kubernetes (EKS) ← subnets privadas — EC2 t3.small, 2 nodos
```

### Servicios AWS (Terraform)

| Servicio | Rol |
|---|---|
| EKS | Orquestación de contenedores |
| ECR | Registro de imágenes Docker |
| DynamoDB | Persistencia de pedidos (NoSQL) |
| DynamoDB Streams | Eventos de cambio de estado |
| Lambda | Procesador de streams → SQS |
| SQS | Cola de notificaciones desacoplada |
| SES | Envío de emails transaccionales |
| S3 | Frontend estático |
| CloudWatch | Logs centralizados + alarmas |
| AWS Config | Auditoría de compliance |
| VPC | Red privada con endpoints |

---

## Estructura del proyecto

```
Como_Vapp_Project/
├── services/
│   ├── orders-dotnet/          # Servicio de pedidos (PoC Python, prod: .NET)
│   ├── admin-kotlin/           # Servicio de administración (PoC Python, prod: Kotlin)
│   └── notifications-python/  # Servicio de notificaciones (Python)
├── frontend/
│   └── react-app/              # Frontend React (Nginx en K8s; prod: S3)
├── infra/
│   ├── terraform/              # Todo el IaC menos EKS
│   └── lambda/                 # Handler del stream processor
├── deploy/
│   └── k8s/                    # Manifiestos Kubernetes
├── docs/
│   ├── guia-terraform.md       # Guía paso a paso para TF
│   ├── guia-k8s.md             # Guía paso a paso para K8s
│   ├── contratos-api-eventos.md
│   ├── checklist-evidencias.md
│   └── script-demo-5-10min.md
└── docker-compose.yml          # Entorno local (DynamoDB Local + ElasticMQ)
```

---

## Inicio rápido — entorno local (docker-compose)

```bash
cp .env.example .env
docker-compose up -d

# Verificar servicios
curl http://localhost:8080/health   # orders
curl http://localhost:8081/health   # admin
curl http://localhost:8082/health   # notifications

# Crear pedido de prueba
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "cliente": {"nombre": "Ana Torres", "correo": "ana@demo.com"},
    "direccion": "Calle 123",
    "items": [{"producto": "Pizza", "cantidad": 2, "valor": 15000}]
  }'
```

---

## Despliegue en AWS

### 1. Infraestructura (Terraform)

```bash
cd infra/terraform
terraform init
terraform plan -var="ses_verified_sender=tu@email.com" -out=tfplan
terraform apply tfplan
```

Ver [docs/guia-terraform.md](docs/guia-terraform.md) para el flujo completo, tabla de compatibilidad Academy y verificación de recursos.

### 2. Frontend a S3

```bash
# El frontend NO va a K8s — se publica en S3 static website (Misión 1 Q7)
BUCKET=$(cd infra/terraform && terraform output -raw frontend_bucket_name)
aws s3 sync frontend/react-app/ s3://$BUCKET/ --delete
```

### 3. Kubernetes — solo los 3 servicios backend (EKS manual)

```bash
# Crear clúster con eksctl → ver deploy/k8s/README.md

cd deploy/k8s
kubectl apply -f namespace.yaml
kubectl apply -f rbac.yaml
kubectl apply -f configmaps.yaml      # ← editar REEMPLAZAR_* primero
kubectl apply -f orders-deployment.yaml
kubectl apply -f admin-deployment.yaml
kubectl apply -f notifications-deployment.yaml
kubectl apply -f ingress.yaml         # expone solo orders-service al público
```

Ver [docs/guia-k8s.md](docs/guia-k8s.md) y [deploy/k8s/README.md](deploy/k8s/README.md) para el flujo detallado incluyendo build/push de imágenes a ECR.

---

## Seguridad (Misión 2)

### Implementado y desplegable en AWS Academy

| Control | Implementación |
|---|---|
| No credenciales en código | boto3 usa el instance profile del nodo (LabRole) automáticamente |
| Configuración pública | ConfigMaps de K8s |
| Non-root containers | `runAsUser: 1001` en todos los Deployments |
| Read-only filesystem | `readOnlyRootFilesystem: true` + emptyDir para /tmp |
| Capabilities | `drop: ALL` en todos los containers |
| Seccomp | `seccompProfile: RuntimeDefault` |
| RBAC K8s | ServiceAccount por servicio + Role read-only para dev |
| Resource limits (cgroups) | Definidos por Misión 2 Q6 en cada Deployment |
| Cifrado en reposo DynamoDB | SSE con AWS-managed key habilitado |
| Cifrado en reposo SQS | SSE-SQS (SQS-managed encryption) habilitado |
| Cifrado en reposo S3 | AES256 en todos los buckets |
| Cifrado en tránsito | TLS en todos los endpoints AWS |
| Escaneo de imágenes | ECR `scan_on_push = true` en todos los repositorios |
| Auditoría de compliance | AWS Config habilitado manualmente + 4 reglas vía TF |
| VPC privada | Nodos en subnets privadas, ALB en subnets públicas |
| VPC Endpoints | DynamoDB y S3 sin salir a internet |
| 2 réplicas + AZ spread | `replicas: 2` + `topologySpreadConstraints` en todos los pods |

### Documentado como buena práctica (no implementable en Academy)

| Control | Por qué no en Academy | Dónde está documentado |
|---|---|---|
| IRSA — rol IAM por pod | Requiere crear roles IAM personalizados | `deploy/k8s/rbac.yaml` (comentado) |
| Secrets Store CSI Driver | Requiere IRSA | `deploy/k8s/secret-provider-class.yaml` (comentado) |
| KMS Customer Managed Key | Restricción de Academy | `infra/terraform/iam.tf` (comentario) |
| AWS Config vía TF completo | Rol recorder no creable en Academy | `infra/terraform/config.tf` (comentario) |

---

## Observabilidad (Misión 2)

- **Logs JSON estructurados**: todos los servicios emiten `{"service", "severity", "requestId", "message", ...}`
- **CloudWatch Logs**: log groups por servicio con 30 días de retención
- **Alarmas CloudWatch**: DLQ con mensajes, cola principal > 100, Lambda errors
- **Probes K8s**: liveness + readiness en `/health` en todos los pods
- **Prometheus + Grafana**: kube-prometheus-stack para métricas de pods

---

## APIs

Ver [docs/contratos-api-eventos.md](docs/contratos-api-eventos.md) para los contratos completos.

| Endpoint | Método | Servicio | Descripción |
|---|---|---|---|
| `/orders` | POST | orders-service | Crear pedido |
| `/orders/{id}` | GET | orders-service | Consultar pedido |
| `/orders/{id}/status` | PATCH | admin-service | Actualizar estado |
| `/notifications` | GET | notifications-service | Ver notificaciones (demo) |
| `/health` | GET | todos | Health check |

### Estados válidos

```
CREADO → EN_PROGRESO → ENTREGADO
CREADO → CANCELADO
EN_PROGRESO → CANCELADO
```

---

## Restricciones AWS Academy

- **IAM**: No se pueden crear roles IAM personalizados. Todo el proyecto usa el `LabRole` predefinido de Academy (`infra/terraform/iam.tf` lo referencia con un `data` source).
- **IRSA**: No disponible. Los pods obtienen credenciales AWS del instance profile del nodo EC2 (LabRole). Todas las annotations IRSA en `rbac.yaml` están comentadas.
- **SES**: Modo sandbox — solo correos verificados pueden enviar y recibir. Actualizar `var.ses_verified_sender` antes de `terraform apply`.
- **SQS KMS**: Usa SSE-SQS (gratis, sin KMS) en lugar de Customer Managed Key.
- **AWS Config**: Habilitar manualmente en la consola primero; luego `terraform apply -target=aws_config_config_rule.*`.
- **Secrets Store CSI Driver**: El manifiesto `secret-provider-class.yaml` queda comentado — solo referencia para producción.
- Ver [docs/guia-terraform.md](docs/guia-terraform.md) para la tabla completa de compatibilidad Academy.
