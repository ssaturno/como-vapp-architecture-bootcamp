# Guía de Implementación Completa — Como Vapp

Esta guía cubre el camino completo desde cero hasta un sistema funcionando en AWS Academy, incluyendo infraestructura, despliegue y verificación end-to-end.

**Tiempo estimado total:** ~90 minutos  
**Costo estimado AWS Academy:** ~$3–5 USD (NAT Gateway + EKS + EC2 t3.medium × 2 nodos durante la demo)

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

### Paso 2 — Agregar el Node Group desde CloudShell

> **AWS Academy — usar CloudShell** para todos los comandos siguientes. CloudShell ya está autenticado y tiene `kubectl`, `helm` y `docker` preinstalados.

Desde **CloudShell**, crear el node group con AWS CLI:

```bash
aws eks create-nodegroup \
  --cluster-name como-vapp-eks \
  --nodegroup-name como-vapp-nodes \
  --node-role arn:aws:iam::886240425170:role/LabRole \
  --subnets subnet-0ae8342a0d3da1f7a subnet-0103e2f7c432c90aa \
  --instance-types t3.medium \
  --ami-type AL2023_x86_64_STANDARD \
  --scaling-config minSize=2,maxSize=4,desiredSize=2 \
  --disk-size 20 \
  --region us-east-1
```

> **Notas importantes:**
> - Usar `t3.medium` (no `t3.small`) — `t3.small` tiene límite de 11 pods por nodo, insuficiente para los pods del sistema + los 3 servicios. `t3.medium` soporta 17 pods por nodo.
> - Usar `AL2023_x86_64_STANDARD` — EKS 1.33+ ya no soporta Amazon Linux 2 (`AL2_x86_64`).
> - Subnets **privadas** únicamente — los nodos no deben tener IPs públicas.

Tarda ~5 minutos. Monitorear con:

```bash
aws eks describe-nodegroup \
  --cluster-name como-vapp-eks \
  --nodegroup-name como-vapp-nodes \
  --query 'nodegroup.status' --output text \
  --region us-east-1
```

---

### Paso 3 — Conectar kubectl

```bash
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

> Todos los comandos desde **CloudShell**. Si Helm no está instalado: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=como-vapp-eks \
  --set region=us-east-1 \
  --set vpcId=vpc-01c2081877a103408 \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

# Verificar que el controlador está corriendo (~30 seg)
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
# Ambos pods deben estar en Running
```

> **AWS Academy — parámetros críticos:**
> - `--set region` y `--set vpcId` son **obligatorios** — sin ellos el controlador no puede detectar la región desde EC2 metadata y entra en CrashLoopBackOff.
> - `--set serviceAccount.create=true` — el controlador crea su propio service account en `kube-system`. Usando `false` el controlador falla si el SA no preexiste en ese namespace. Los pods usan el instance profile del nodo (LabRole) via IMDS en lugar de IRSA.

---

## 7. Docker — build y push a ECR

**Tiempo estimado: ~5–8 minutos** (depende de la conexión)

> Hacer desde **AWS CloudShell** — tiene Docker preinstalado y ya está autenticado con la cuenta Academy. No requiere Docker Desktop local.

```bash
# Clonar el repo en CloudShell (si no está clonado)
git clone https://github.com/ssaturno/como-vapp-architecture-bootcamp.git
cd como-vapp-architecture-bootcamp

# Si ya está clonado, traer últimos cambios
# git pull

# Login a ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  886240425170.dkr.ecr.us-east-1.amazonaws.com

# Build y push — orders-service
docker build -t 886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-orders-service:0.1.0 services/orders-dotnet/
docker push 886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-orders-service:0.1.0

# Build y push — admin-service
docker build -t 886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-admin-service:0.1.0 services/admin-kotlin/
docker push 886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-admin-service:0.1.0

# Build y push — notifications-service
docker build -t 886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-notifications-service:0.1.0 services/notifications-python/
docker push 886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-notifications-service:0.1.0
```

---

## 8. Kubernetes — editar manifiestos

> Los manifiestos ya tienen los valores reales de Terraform hardcodeados en el repo (actualizados durante el setup). No es necesario hacer reemplazos manuales. Verificar que no queden placeholders:

```bash
cd ~/como-vapp-architecture-bootcamp/deploy/k8s
grep -r "REEMPLAZAR" *.yaml
# No debe aparecer ningún resultado
```

Si aparece algún placeholder, reemplazarlo manualmente en el archivo correspondiente con los valores del output de Terraform:

| Placeholder | Valor real |
|---|---|
| `REEMPLAZAR_CON_TF_OUTPUT_orders_table_name` | `como-vapp-dev-orders` |
| `REEMPLAZAR_CON_TF_OUTPUT_notifications_queue_url` | `https://sqs.us-east-1.amazonaws.com/886240425170/como-vapp-dev-notifications` |
| `REEMPLAZAR_CON_TF_OUTPUT_ses_verified_sender` | `samarissaturno@gmail.com` |
| `REEMPLAZAR_ECR_URI/como-vapp-dev-orders-service` | `886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-orders-service` |
| `REEMPLAZAR_ECR_URI/como-vapp-dev-admin-service` | `886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-admin-service` |
| `REEMPLAZAR_ECR_URI/como-vapp-dev-notifications-service` | `886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-notifications-service` |

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
# Esperar hasta ver los pods en Running (2 réplicas × 3 servicios = 6 pods)
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

# ALB DNS actual (cuenta Academy 886240425170)
# k8s-comovapp-comovapp-df69069754-1646076730.us-east-1.elb.amazonaws.com

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

> **Nota sobre el endpoint `/health` y el ALB:**
> El path `/health` está configurado como `alb.ingress.kubernetes.io/healthcheck-path` — es el chequeo **interno** del ALB hacia los pods. No está en las reglas de enrutamiento del ingress (solo `/orders` está expuesto). Un `curl http://$ALB_DNS/health` retorna 404 porque el ALB no tiene regla para ese path. Para verificar que los targets están sanos, usar `describe-target-health`.

```bash
# Verificar que los targets del ALB están healthy
TG_ARN=$(aws elbv2 describe-target-groups \
  --query 'TargetGroups[?contains(TargetGroupName, `como`)].TargetGroupArn' \
  --output text --region us-east-1)
aws elbv2 describe-target-health --target-group-arn $TG_ARN --region us-east-1
# Ambos targets deben mostrar "State": "healthy"

# orders-service — health check directo (vía port-forward)
kubectl -n como-vapp-dev port-forward deploy/orders-service 8080:8080 &
sleep 2
curl http://localhost:8080/health
# {"status":"ok","service":"orders-service"}

# admin-service (vía port-forward — servicio interno)
kubectl -n como-vapp-dev port-forward deploy/admin-service 8081:8081 &
sleep 2
curl http://localhost:8081/health
# {"status":"ok","service":"admin-service"}

# notifications-service (vía port-forward — servicio interno)
kubectl -n como-vapp-dev port-forward deploy/notifications-service 8082:8082 &
sleep 2
curl http://localhost:8082/health
# {"status":"ok","service":"notifications-service"}

# Matar los port-forwards cuando termines
kill %1 %2 %3 2>/dev/null
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

# 3. Eliminar el node group y el clúster EKS (tarda ~10 min)
aws eks delete-nodegroup --cluster-name como-vapp-eks --nodegroup-name como-vapp-nodes --region us-east-1
# Esperar que el node group se elimine, luego:
aws eks delete-cluster --name como-vapp-eks --region us-east-1

# 4. Destruir toda la infraestructura de Terraform
cd infra/terraform
terraform destroy -auto-approve
# Con S3 backend: el state queda en S3, no es necesario pasarlo manualmente

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
kubectl -n kube-system logs deploy/aws-load-balancer-controller | grep -i "error\|warn" | tail -30
```

**Causa 1 — `no EC2 IMDS role found`:** El hop limit de IMDS en los nodos es 1 (default). Los pods necesitan 2. Fix:

```bash
INSTANCE_IDS=$(kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | tr ' ' '\n' | sed 's/.*\///')
for ID in $INSTANCE_IDS; do
  aws ec2 modify-instance-metadata-options \
    --instance-id $ID \
    --http-put-response-hop-limit 2 \
    --http-endpoint enabled \
    --region us-east-1
done
# Reiniciar pods del LBC después del fix
kubectl -n kube-system rollout restart deployment/aws-load-balancer-controller
```

**Causa 2 — Service account no existe:** El LBC fue instalado con `serviceAccount.create=false` pero el SA no existía. Fix: reinstalar con `serviceAccount.create=true`.

**Causa 3 — Ingress atascado con finalizer:** Si el ingress no puede eliminarse:

```bash
kubectl -n como-vapp-dev patch ingress como-vapp-ingress \
  -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl -n como-vapp-dev delete ingress como-vapp-ingress
kubectl -n como-vapp-dev apply -f deploy/k8s/ingress.yaml
```

### Pods con `NoCredentialsError` (botocore)

```bash
# Síntoma en logs: botocore.exceptions.NoCredentialsError: Unable to locate credentials
# Causa: IMDS hop limit = 1, los pods no pueden obtener credenciales del LabRole
```

**Fix:** Aplicar el fix de hop limit (ver sección anterior) y reiniciar los pods:

```bash
kubectl -n como-vapp-dev rollout restart deployment/orders-service
kubectl -n como-vapp-dev rollout restart deployment/admin-service
kubectl -n como-vapp-dev rollout restart deployment/notifications-service
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

### Errores de X-Ray en los logs de pods

```
SamplingRuleRecords is missing in getSamplingRules response:
'User: ...assumed-role/LabRole/... is not authorized to perform: xray:GetSamplingRules'
```

**Esto es ruido — no afecta la funcionalidad.** Los pods tienen OpenTelemetry auto-instrumentation inyectado que intenta conectarse a X-Ray, pero el LabRole de Academy no tiene permisos para X-Ray. Los servicios responden peticiones HTTP con normalidad. No requiere acción.
