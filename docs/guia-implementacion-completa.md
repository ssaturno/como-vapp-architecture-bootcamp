# Guía de Implementación Completa — Como Vapp

Esta guía cubre el camino completo desde cero hasta un sistema funcionando en AWS Academy, incluyendo infraestructura, despliegue y verificación end-to-end.

**Tiempo estimado total:** ~90 minutos  
**Costo estimado AWS Academy:** ~$2–4 USD (NAT Gateway + EKS + EC2 t3.small × 2 nodos durante la demo)

---

## Índice

1. [Prerequisitos](#1-prerequisitos)
2. [Verificar email en SES](#2-verificar-email-en-ses)
3. [Terraform — provisionar infraestructura AWS](#3-terraform--provisionar-infraestructura-aws)
4. [AWS Config — activar en consola](#4-aws-config--activar-en-consola)
5. [EKS — crear clúster manual](#5-eks--crear-clúster-manual)
6. [AWS Load Balancer Controller](#6-aws-load-balancer-controller)
7. [Docker — build y push a ECR](#7-docker--build-y-push-a-ecr)
8. [Kubernetes — editar manifiestos](#8-kubernetes--editar-manifiestos)
9. [Kubernetes — aplicar manifiestos](#9-kubernetes--aplicar-manifiestos)
10. [Frontend — deploy a S3](#10-frontend--deploy-a-s3)
11. [Verificación end-to-end](#11-verificación-end-to-end)
12. [Simular resiliencia](#12-simular-resiliencia)
13. [Teardown](#13-teardown)

---

## 1. Prerequisitos

### Herramientas necesarias

| Herramienta | Versión | Instalar |
|---|---|---|
| AWS CLI | v2.x | `https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html` |
| Terraform | >= 1.5 | `https://developer.hashicorp.com/terraform/install` |
| eksctl | >= 0.180 | `https://eksctl.io/installation/` |
| kubectl | >= 1.35 | `https://kubernetes.io/docs/tasks/tools/` |
| helm | >= 3.x | `https://helm.sh/docs/intro/install/` |
| Docker Desktop | >= 24 | `https://www.docker.com/products/docker-desktop/` |
| jq | cualquier | `https://jqlang.github.io/jq/download/` |

### Configurar credenciales AWS Academy

AWS Academy genera credenciales temporales con `aws_session_token` que expiran al reiniciar el lab.

#### Opción A — Perfil dedicado `academy` (recomendado si ya tienes otra cuenta AWS configurada)

Esto evita sobreescribir tu perfil `[default]` existente.

**1. Obtener credenciales:** Ir a AWS Academy → Launch AWS Academy Learner Lab → "AWS Details" → copiar el bloque de credenciales (viene con header `[default]`).

**2. Abrir el archivo de credenciales:** `C:\Users\<tu-usuario>\.aws\credentials`

**3. Pegar al final del archivo**, cambiando `[default]` por `[academy]`:

```ini
[academy]
aws_access_key_id=ASIA44XXXXXXXXXXXXXXXXX
aws_secret_access_key=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
aws_session_token=IQoJb3JpZ2lu...  (token completo)
```

**4. Agregar el perfil en** `C:\Users\<tu-usuario>\.aws\config`:

```ini
[profile academy]
region = us-east-1
```

**5. Activar el perfil para toda la sesión** (hacer esto cada vez que abras una terminal nueva):

```powershell
# PowerShell (Windows)
$env:AWS_PROFILE = "academy"

# bash / CloudShell / macOS
export AWS_PROFILE=academy
```

**6. Verificar acceso:**

```bash
aws sts get-caller-identity
# Debe mostrar tu Account ID y el ARN del LabRole
```

> Con `AWS_PROFILE` activo, todos los comandos `aws`, `terraform` y `eksctl` usan automáticamente el perfil `academy` sin necesidad de agregar `--profile academy` en cada uno.

---

#### Opción B — Perfil default (si no tienes otra cuenta AWS)

```bash
# Abrir AWS Academy → Launch AWS Academy Learner Lab
# Click en "AWS Details" → copiar las credenciales

aws configure
# AWS Access Key ID: (pegar de Academy)
# AWS Secret Access Key: (pegar de Academy)
# Default region name: us-east-1
# Default output format: json

# Verificar acceso
aws sts get-caller-identity
# Debe mostrar tu Account ID y el ARN del LabRole
```

---

> **Importante:** Las credenciales de AWS Academy expiran cada vez que se reinicia el lab. Ver la sección de [Troubleshooting — Credenciales expiradas](#credenciales-aws-academy-expiradas) para renovarlas.

### Verificar herramientas

```bash
terraform version     # debe ser >= 1.5.0
eksctl version        # debe ser >= 0.180
kubectl version --client
helm version
docker info           # Docker Desktop debe estar corriendo
```

---

## 2. Verificar email en SES

> **AWS Academy — SES no disponible**
>
> El LabRole de AWS Academy **no tiene permisos para SES** (`ses:VerifyEmailIdentity` está bloqueado tanto por CLI como por consola). Este paso no se puede completar en un lab de Academy.
>
> **Impacto:** El servicio de notificaciones recibe y procesa mensajes desde SQS normalmente, pero no enviará emails reales. El resto de la arquitectura (EKS, DynamoDB, SQS, Lambda, AWS Config, S3) funciona sin restricciones.
>
> En una cuenta AWS real (fuera de Academy), los comandos serían:
>
> ```powershell
> aws ses verify-email-identity --email-address samarissaturno@gmail.com --region us-east-1
>
> # Confirmar el link que llega al email, luego verificar:
> aws ses get-identity-verification-attributes --identities samarissaturno@gmail.com --region us-east-1
> # "VerificationStatus": "Success"
> ```

**Continuar directamente al paso 3.**

---

## 3. Terraform — provisionar infraestructura AWS

**Tiempo estimado: ~10 minutos**

```bash
cd infra/terraform
```

### Inicializar

```bash
terraform init
# Debe descargar los providers: aws (~5.0) y archive (~2.0)
```

### Planear

```bash
terraform plan \
  -var="ses_verified_sender=samarissaturno@gmail.com" \
  -out=tfplan
```

Revisar el resumen. Debe mostrar aproximadamente **25–30 resources to add**:
- 1 VPC + 4 subnets + IGW + NAT + route tables + VPC Endpoints
- 2 Security Groups (ALB + EKS nodes)
- 4 ECR repositories
- 1 DynamoDB table
- 2 SQS queues (main + DLQ)
- 1 SES email identity
- 1 Lambda function + event source mapping
- 2 S3 buckets (frontend + config recordings)
- Log groups + CloudWatch alarms
- 4 AWS Config rules

### Aplicar

```bash
terraform apply tfplan
```

> Si algún recurso falla, ver la sección de troubleshooting al final de este archivo.

### Guardar outputs

```bash
# Ver todos los outputs
terraform output

# Guardar en variables de shell para usar después
export TF_ORDERS_TABLE=$(terraform output -raw orders_table_name)
export TF_SQS_URL=$(terraform output -raw notifications_queue_url)
export TF_SES_SENDER=$(terraform output -raw ses_verified_sender)
export TF_VPC_ID=$(terraform output -raw vpc_id)
export TF_PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids | jq -r 'join(",")')
export TF_PUBLIC_SUBNETS=$(terraform output -json public_subnet_ids | jq -r 'join(",")')
export TF_NODES_SG=$(terraform output -raw eks_nodes_security_group_id)
export TF_CONFIG_BUCKET=$(terraform output -raw config_recordings_bucket)
export TF_FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
export TF_FRONTEND_URL=$(terraform output -raw frontend_website_url)

# ECR URIs por servicio
export ECR_ORDERS=$(terraform output -json ecr_repository_urls | jq -r '.["orders-service"]')
export ECR_ADMIN=$(terraform output -json ecr_repository_urls | jq -r '.["admin-service"]')
export ECR_NOTIF=$(terraform output -json ecr_repository_urls | jq -r '.["notifications-service"]')

echo "✓ Outputs guardados"
echo "  Tabla DynamoDB : $TF_ORDERS_TABLE"
echo "  SQS URL        : $TF_SQS_URL"
echo "  ECR orders     : $ECR_ORDERS"
```

---

## 4. AWS Config — activar en consola

**Tiempo estimado: ~3 minutos** (manual en consola)

> AWS Academy no permite crear el rol de servicio de Config via Terraform, pero la consola lo crea automáticamente.

1. Ir a **AWS Console → AWS Config → Get started**
2. Configurar:
   - **Recording**: *Record all resources supported in this region*
   - **S3 bucket**: seleccionar el bucket `$TF_CONFIG_BUCKET` (creado por Terraform)
   - **IAM role**: dejar que la consola cree el service-linked role
3. Click **Confirm**
4. Esperar que el estado cambie a **Recording**

### Aplicar las reglas de compliance vía Terraform

```bash
# Volver al directorio de terraform (si saliste)
cd infra/terraform

terraform apply \
  -var="ses_verified_sender=$TF_SES_SENDER" \
  -target=aws_config_config_rule.restricted_ssh \
  -target=aws_config_config_rule.vpc_flow_logs \
  -target=aws_config_config_rule.encrypted_volumes \
  -target=aws_config_config_rule.dynamodb_encryption

# Verificar reglas activas
aws configservice describe-config-rules \
  --query 'ConfigRules[*].{Name:ConfigRuleName,State:ConfigRuleState}' \
  --output table
```

---

## 5. EKS — crear clúster manual

**Tiempo estimado: ~15–20 minutos** (EKS tarda en provisionar)

> EKS NO se crea con Terraform en este proyecto (el LabRole de Academy tiene restricciones IAM). Se crea desde la consola de AWS apuntando a la VPC que Terraform ya creó.

### Concepto: Node Pool vs Servicio

Un **Node Pool** (o Node Group) es un grupo de máquinas EC2. Los pods de todos los servicios se distribuyen entre esas máquinas — **no se necesita un node pool por servicio**.

```
Node Pool único (2× t3.small)
├── Nodo 1 → pod: orders-service + pod: notifications-service
└── Nodo 2 → pod: orders-service (réplica) + pod: admin-service
```

Múltiples node pools solo tienen sentido cuando hay requisitos de hardware muy distintos (GPU, alta memoria, spot instances). Para 3 microservicios ligeros, **un solo node pool es lo correcto**. El aislamiento entre servicios se logra con namespaces y resource limits.

> **AWS Academy — Auto Mode:** Al crear el clúster, **desactivar EKS Auto Mode**. Con Auto Mode activo, AWS elige instancias ARM (Graviton) que son incompatibles con imágenes Docker construidas en x86.

---

### Paso 1 — Crear el control plane

1. **AWS Console → EKS → Create cluster**
2. Completar el formulario:

| Campo | Valor |
|---|---|
| Name | `como-vapp-eks` |
| Kubernetes version | `1.35` |
| Cluster service role | `LabRole` |
| **EKS Auto Mode** | **Desactivado** (seleccionar "Configure manually") |

3. **Networking:**
   - VPC: `vpc-01c2081877a103408` (creada por Terraform)
   - Subnets: seleccionar las **4** (2 públicas + 2 privadas)
   - Security group del clúster: dejar el que crea por defecto
   - Cluster endpoint access: `Public and private`

4. Click **Next → Next → Create**

> Tarda ~10 minutos. Esperar hasta que el estado sea **Active**.

---

### Paso 2 — Agregar el Node Group

Una vez el clúster esté **Active**, desde la tab **Compute → Add node group**:

| Campo | Valor |
|---|---|
| Name | `como-vapp-nodes` |
| Node IAM role | `LabRole` |
| AMI type | `Amazon Linux 2` **(x86_64 — NO ARM)** |
| Instance type | `t3.small` |
| Disk size | `20 GB` |
| Min size | `2` |
| Desired size | `2` |
| Max size | `4` |

- **Subnets:** seleccionar **solo las 2 privadas** (`subnet-0ae8342a0d3da1f7a`, `subnet-0103e2f7c432c90aa`)
- Click **Next → Next → Create**

> Tarda ~5 minutos adicionales.

---

### Paso 3 — Conectar kubectl

```powershell
aws eks update-kubeconfig --name como-vapp-eks --region us-east-1

# Verificar nodos (esperar hasta ver 2 en estado "Ready")
kubectl get nodes

# Verificar el clúster
kubectl cluster-info
```

---

## 6. AWS Load Balancer Controller

**Tiempo estimado: ~3 minutos**

Este controlador es necesario para que el `Ingress` cree automáticamente un ALB en AWS.

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=como-vapp-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

# Verificar que el controlador está corriendo
kubectl -n kube-system get deployment aws-load-balancer-controller
# READY debe mostrar 2/2
```

---

## 7. Docker — build y push a ECR

**Tiempo estimado: ~5–8 minutos** (depende de la conexión)

```bash
# Pararse en la raíz del proyecto
cd ../../   # si sigues desde infra/terraform

# Login a ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Build y push — orders-service
docker build -t $ECR_ORDERS:0.1.0 services/orders-dotnet/
docker push $ECR_ORDERS:0.1.0

# Build y push — admin-service
docker build -t $ECR_ADMIN:0.1.0 services/admin-kotlin/
docker push $ECR_ADMIN:0.1.0

# Build y push — notifications-service
docker build -t $ECR_NOTIF:0.1.0 services/notifications-python/
docker push $ECR_NOTIF:0.1.0

# Verificar las imágenes en ECR
aws ecr list-images --repository-name como-vapp-dev-orders-service
aws ecr list-images --repository-name como-vapp-dev-admin-service
aws ecr list-images --repository-name como-vapp-dev-notifications-service
```

---

## 8. Kubernetes — editar manifiestos

**Tiempo estimado: ~2 minutos**

Reemplazar los placeholders en los manifiestos con los valores reales de Terraform.

```bash
cd deploy/k8s

# Reemplazar valores en configmaps.yaml
sed -i "s|REEMPLAZAR_CON_TF_OUTPUT_orders_table_name|$TF_ORDERS_TABLE|g" configmaps.yaml
sed -i "s|REEMPLAZAR_CON_TF_OUTPUT_notifications_queue_url|$TF_SQS_URL|g" configmaps.yaml
sed -i "s|REEMPLAZAR_CON_TF_OUTPUT_ses_verified_sender|$TF_SES_SENDER|g" configmaps.yaml

# Reemplazar URIs ECR en los deployments
sed -i "s|REEMPLAZAR_ECR_URI/como-vapp-dev-orders-service|$ECR_ORDERS|g" orders-deployment.yaml
sed -i "s|REEMPLAZAR_ECR_URI/como-vapp-dev-admin-service|$ECR_ADMIN|g" admin-deployment.yaml
sed -i "s|REEMPLAZAR_ECR_URI/como-vapp-dev-notifications-service|$ECR_NOTIF|g" notifications-deployment.yaml

# Verificar que no quedan placeholders
grep -r "REEMPLAZAR" *.yaml
# No debe aparecer ningún resultado
```

---

## 9. Kubernetes — aplicar manifiestos

**Tiempo estimado: ~5 minutos** (pods tardan en iniciar)

```bash
# Desde deploy/k8s/

# 1. Namespace
kubectl apply -f namespace.yaml
kubectl get namespace como-vapp-dev

# 2. RBAC + ServiceAccounts
kubectl apply -f rbac.yaml

# 3. ConfigMaps
kubectl apply -f configmaps.yaml
kubectl -n como-vapp-dev get configmaps

# 4. Deployments + Services (los 3 backends)
kubectl apply -f orders-deployment.yaml
kubectl apply -f admin-deployment.yaml
kubectl apply -f notifications-deployment.yaml

# 5. Ingress (crea el ALB — tarda ~2 min en aparecer el DNS)
kubectl apply -f ingress.yaml
```

### Esperar que los pods estén Ready

```bash
# Esperar hasta ver 6/6 Running (2 réplicas × 3 servicios)
kubectl -n como-vapp-dev get pods -w
# Ctrl+C cuando todos estén Running

# Si algún pod no arranca, diagnosticar
kubectl -n como-vapp-dev describe pod <nombre-del-pod>
kubectl -n como-vapp-dev logs <nombre-del-pod>
```

### Obtener el DNS del ALB

```bash
# El ALB tarda ~2 minutos en ser provisionado por AWS
kubectl -n como-vapp-dev get ingress como-vapp-ingress

# Esperar hasta que la columna ADDRESS tenga un valor
kubectl -n como-vapp-dev get ingress como-vapp-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

export ALB_DNS=$(kubectl -n como-vapp-dev get ingress como-vapp-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB_DNS"
```

---

## 10. Frontend — deploy a S3

**Tiempo estimado: ~1 minuto**

```bash
# Desde la raíz del proyecto
aws s3 sync frontend/react-app/ s3://$TF_FRONTEND_BUCKET/ --delete

echo "Frontend disponible en: http://$TF_FRONTEND_URL"
```

Verificar que el sitio carga abriendo `http://$TF_FRONTEND_URL` en el navegador.

---

## 11. Verificación end-to-end

### Health checks de todos los servicios

```bash
# orders-service (vía ALB público)
curl http://$ALB_DNS/health
# {"status":"ok","service":"orders-service"}

# admin-service (vía port-forward — servicio interno)
kubectl -n como-vapp-dev port-forward deploy/admin-service 8081:8081 &
curl http://localhost:8081/health
# {"status":"ok","service":"admin-service"}

# notifications-service (vía port-forward — servicio interno)
kubectl -n como-vapp-dev port-forward deploy/notifications-service 8082:8082 &
curl http://localhost:8082/health
# {"status":"ok","service":"notifications-service","queueConnected":true,"sesEnabled":true}
```

### Flujo completo de un pedido

#### Paso 1 — Crear pedido

```bash
RESPONSE=$(curl -s -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -H "X-Request-Id: demo-001" \
  -d '{
    "cliente": {
      "nombre": "Ana Torres",
      "correo": "samarissaturno@gmail.com"
    },
    "direccion": "Calle 123 # 45-67",
    "items": [
      {"producto": "Pizza Margarita", "cantidad": 2, "valor": 25000},
      {"producto": "Coca-Cola", "cantidad": 1, "valor": 5000}
    ]
  }')

echo $RESPONSE | jq .
export PEDIDO_ID=$(echo $RESPONSE | jq -r '.idPedido')
echo "Pedido creado: $PEDIDO_ID"
# {"idPedido":"uuid","estado":"CREADO","fechaCreacion":"2026-..."}
```

#### Paso 2 — Consultar pedido

```bash
curl -s http://$ALB_DNS/orders/$PEDIDO_ID | jq .
# Debe mostrar el pedido completo con estado CREADO
```

#### Paso 3 — Actualizar estado: CREADO → EN_PROGRESO

```bash
curl -s -X PATCH http://localhost:8081/orders/$PEDIDO_ID/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "EN_PROGRESO", "origen": "ADMIN"}' | jq .
# {"idPedido":"...","estadoAnterior":"CREADO","estadoNuevo":"EN_PROGRESO",...}
```

#### Paso 4 — Actualizar estado: EN_PROGRESO → ENTREGADO

```bash
curl -s -X PATCH http://localhost:8081/orders/$PEDIDO_ID/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "ENTREGADO", "origen": "ADMIN"}' | jq .
```

#### Paso 5 — Verificar notificaciones procesadas

```bash
curl -s http://localhost:8082/notifications | jq .
# Debe mostrar los eventos procesados con status "sent_ses"
```

#### Paso 6 — Verificar email recibido

- Abrir `samarissaturno@gmail.com`
- Buscar emails de Amazon SES con asunto `[Como Vapp] Tu pedido ... ahora está: EN_PROGRESO`

#### Paso 7 — Verificar transición inválida (demo de validación)

```bash
# Intentar cambiar desde ENTREGADO (estado terminal) → debe retornar 400
curl -s -X PATCH http://localhost:8081/orders/$PEDIDO_ID/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "CANCELADO", "origen": "ADMIN"}' | jq .
# {"detail":"Transicion invalida: ENTREGADO -> CANCELADO"}
```

### Verificar logs estructurados en CloudWatch

```bash
# Ver los últimos logs del orders-service
aws logs tail /como-vapp/orders-service --follow --format short

# Buscar un request específico por ID
aws logs filter-log-events \
  --log-group-name /como-vapp/orders-service \
  --filter-pattern '"demo-001"' \
  --query 'events[*].message' \
  --output text
```

### Verificar AWS Config (compliance)

```bash
aws configservice describe-compliance-by-config-rule \
  --query 'ComplianceByConfigRules[*].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}' \
  --output table
# Las reglas deben aparecer como COMPLIANT o NON_COMPLIANT
```

### Verificar DynamoDB directamente

```bash
aws dynamodb scan \
  --table-name $TF_ORDERS_TABLE \
  --query 'Items[*].{id:idPedido.S,estado:estado.S}' \
  --output table
```

---

## 12. Simular resiliencia

### Eliminar pods del notificador y verificar self-healing

```bash
# 1. Enviar una actualización de estado mientras el notificador sigue activo
curl -s -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -d '{
    "cliente": {"nombre": "Carlos Ruiz", "correo": "samarissaturno@gmail.com"},
    "direccion": "Av. Siempreviva 742",
    "items": [{"producto": "Hamburgesa", "cantidad": 1, "valor": 18000}]
  }' | jq .idPedido

# 2. Eliminar los pods del notificador (simular caída)
kubectl -n como-vapp-dev delete pod -l app=notifications-service

# 3. Actualizar estado mientras el servicio está caído
#    Los mensajes quedan en SQS sin ser consumidos
NUEVO_ID="<idPedido del paso 1>"
curl -s -X PATCH http://localhost:8081/orders/$NUEVO_ID/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "EN_PROGRESO", "origen": "ADMIN"}' | jq .

# 4. Ver que el mensaje está encolado en SQS
aws sqs get-queue-attributes \
  --queue-url $TF_SQS_URL \
  --attribute-names ApproximateNumberOfMessages
# ApproximateNumberOfMessages > 0

# 5. Verificar que Kubernetes recrea los pods automáticamente
kubectl -n como-vapp-dev get pods -l app=notifications-service -w
# Los pods deben pasar por Terminating → Pending → Running

# 6. Una vez que los pods vuelven a Running, verificar que el mensaje fue consumido
curl -s http://localhost:8082/notifications | jq '.count'
# Debe ser > 0 (mensajes procesados post-recuperación)
```

### Verificar los Security Group rules con AWS Config

```bash
# Ver si algún SG tiene SSH abierto (debe ser NON_COMPLIANT si tienes el puerto 22 abierto)
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name como-vapp-dev-restricted-ssh \
  --compliance-types NON_COMPLIANT
```

---

## 13. Teardown

> Hacer esto al finalizar la demo para evitar costos adicionales en AWS Academy.

```bash
# 1. Eliminar recursos de K8s
kubectl delete namespace como-vapp-dev
# Esto elimina todos los pods, services, configmaps, ingress (y el ALB creado)

# 2. Esperar que el ALB sea eliminado (puede tardar ~2 min)
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `como-vapp`)].State'

# 3. Eliminar el clúster EKS (tarda ~5–10 min)
eksctl delete cluster --name como-vapp-eks --region us-east-1

# 4. Destruir toda la infraestructura de Terraform
cd infra/terraform
terraform destroy -var="ses_verified_sender=$TF_SES_SENDER"
# Escribir "yes" cuando se pida confirmación

# 5. Verificar que no quedan recursos (para evitar cargos)
aws ec2 describe-instances --query 'Reservations[*].Instances[?State.Name!=`terminated`]'
aws dynamodb list-tables
aws sqs list-queues
```

---

## Troubleshooting

### Credenciales AWS Academy expiradas

```bash
# Síntoma: "ExpiredTokenException" o "InvalidClientTokenId"
```

**Si usas perfil `academy`** (Opción A): abrir `C:\Users\<tu-usuario>\.aws\credentials`, reemplazar las 3 líneas del bloque `[academy]` con las nuevas credenciales de AWS Details. Luego verificar:

```bash
aws sts get-caller-identity   # (con $env:AWS_PROFILE="academy" activo)
```

**Si usas perfil `default`** (Opción B): volver a ejecutar `aws configure` con los nuevos valores.

### Pods en estado `ImagePullBackOff`

```bash
kubectl -n como-vapp-dev describe pod <pod>
# Buscar: "Failed to pull image"
# Causa: URI de ECR incorrecto en el manifest o credenciales ECR expiradas

# Solución: verificar que sed reemplazó correctamente
grep "image:" orders-deployment.yaml   # debe mostrar la URI completa de ECR, no REEMPLAZAR_*

# Re-hacer el login ECR si las credenciales expiraron
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
```

### Pods en `CrashLoopBackOff`

```bash
kubectl -n como-vapp-dev logs <pod> --previous
# Buscar el error en los logs

# Causas comunes:
# - DYNAMODB_TABLE_NAME no coincide con la tabla creada por TF
# - SQS_QUEUE_URL mal formateada
# - El pod no puede acceder a AWS (verifcar que los nodos tienen el LabRole)
```

### ALB no se crea (Ingress sin ADDRESS)

```bash
kubectl -n kube-system logs deploy/aws-load-balancer-controller | tail -30
# Causas comunes:
# - Las subnets no tienen el tag kubernetes.io/role/elb=1 (lo pone TF)
# - El serviceAccount del controlador no tiene permisos (usar LabRole del nodo)
```

### Lambda no procesa eventos de DynamoDB Streams

```bash
aws lambda get-event-source-mapping \
  --uuid $(aws lambda list-event-source-mappings \
    --function-name como-vapp-dev-stream-processor \
    --query 'EventSourceMappings[0].UUID' --output text)
# State debe ser "Enabled"

# Ver logs de la Lambda
aws logs tail /aws/lambda/como-vapp-dev-stream-processor --format short
```

### terraform apply falla en IAM

```bash
# Error: "not authorized to perform: iam:CreateRole"
# Esto no debería ocurrir — iam.tf solo usa un data source (LabRole)
# Si ocurre, verificar que el archivo iam.tf contiene solo:
#   data "aws_iam_role" "lab_role" { name = "LabRole" }
```

### AWS Config rules fallan al aplicar

```bash
# Error: "AWS Config is not enabled in this region"
# Solución: completar el paso 4 (habilitar Config manualmente en la consola) antes de aplicar las reglas
```
