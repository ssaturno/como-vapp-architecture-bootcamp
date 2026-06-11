# Kubernetes — Guía de Despliegue Como Vapp

> EKS se crea **manualmente** (consola AWS + AWS CLI). Terraform provisiona la red y los recursos AWS; los manifiestos YAML aquí son los que aplicas con `kubectl`.
>
> Todos los comandos se ejecutan desde **AWS CloudShell** — ya tiene `kubectl`, `helm` y `docker` preinstalados y está autenticado con la cuenta Academy.

---

## 0. Prerequisitos

| Herramienta | Disponible en |
|---|---|
| AWS CLI | CloudShell (preinstalado) |
| kubectl | CloudShell (preinstalado) |
| helm | CloudShell — instalar con: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| docker | CloudShell (preinstalado) |

```bash
# Verificar acceso a la cuenta correcta
aws sts get-caller-identity
# Debe mostrar Account: 886240425170 y ARN del LabRole

# Conectar kubectl al clúster
aws eks update-kubeconfig --name como-vapp-eks --region us-east-1
kubectl get nodes
```

---

## 1. Crear el clúster EKS (consola + AWS CLI — NO eksctl)

### 1a. Control plane — desde la consola AWS

1. **AWS Console → EKS → Create cluster**
2. Completar el formulario:

| Campo | Valor |
|---|---|
| Name | `como-vapp-eks` |
| Kubernetes version | `1.35` |
| Cluster service role | `LabRole` |
| **EKS Auto Mode** | **Desactivado** ("Configure manually") |

3. **Networking:**
   - VPC: `vpc-01c2081877a103408`
   - Subnets: las 4 (2 públicas + 2 privadas)
   - Cluster endpoint access: `Public and private`

4. Click **Next → Next → Create** — tarda ~10 minutos.

> **IMPORTANTE — Auto Mode:** Desactivar EKS Auto Mode. Con Auto Mode activo AWS elige instancias ARM (Graviton) incompatibles con imágenes x86 construidas en CloudShell.

---

### 1b. Node Group — desde CloudShell

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

> **Notas:**
> - `t3.medium` — no usar `t3.small` (límite de 11 pods/nodo, insuficiente). `t3.medium` soporta 17 pods/nodo.
> - `AL2023_x86_64_STANDARD` — EKS 1.33+ no soporta `AL2_x86_64`.
> - Subnets **privadas** únicamente.

Monitorear creación:

```bash
aws eks describe-nodegroup \
  --cluster-name como-vapp-eks \
  --nodegroup-name como-vapp-nodes \
  --query 'nodegroup.status' --output text --region us-east-1
# Esperar hasta: ACTIVE
```

### 1c. Configurar IMDS hop limit (crítico para credenciales en pods)

Por defecto, el IMDS hop limit en instancias EC2 es 1. Los pods necesitan 2 para acceder al LabRole vía IMDS. Sin este fix los pods fallan con `NoCredentialsError`.

```bash
INSTANCE_IDS=$(kubectl get nodes \
  -o jsonpath='{.items[*].spec.providerID}' | tr ' ' '\n' | sed 's/.*\///')

for ID in $INSTANCE_IDS; do
  aws ec2 modify-instance-metadata-options \
    --instance-id $ID \
    --http-put-response-hop-limit 2 \
    --http-endpoint enabled \
    --region us-east-1
done
```

---

## 2. Instalar el AWS Load Balancer Controller

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

# Verificar (~30 seg)
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
# Ambos pods deben estar Running
```

> **Parámetros críticos para Academy:**
> - `--set region` y `--set vpcId` son obligatorios — sin ellos el controlador no puede detectar la región desde EC2 metadata (CrashLoopBackOff).
> - `--set serviceAccount.create=true` — el LBC crea su propio SA en `kube-system` y usa el instance profile del nodo (LabRole) via IMDS en lugar de IRSA.

---

## 3. Obtener los valores de Terraform

```bash
cd ~/como-vapp-architecture-bootcamp/infra/terraform

export ORDERS_TABLE=$(terraform output -raw orders_table_name)
export SQS_URL=$(terraform output -raw notifications_queue_url)
export ECR_ORDERS=$(terraform output -json ecr_repository_urls | jq -r '.["orders-service"]')
export ECR_ADMIN=$(terraform output -json ecr_repository_urls | jq -r '.["admin-service"]')
export ECR_NOTIF=$(terraform output -json ecr_repository_urls | jq -r '.["notifications-service"]')

echo "Tabla DynamoDB : $ORDERS_TABLE"
echo "SQS URL        : $SQS_URL"
echo "ECR orders     : $ECR_ORDERS"
```

Valores reales (cuenta Academy 886240425170):

| Variable | Valor |
|---|---|
| `ORDERS_TABLE` | `como-vapp-dev-orders` |
| `SQS_URL` | `https://sqs.us-east-1.amazonaws.com/886240425170/como-vapp-dev-notifications` |
| `ECR_ORDERS` | `886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-orders-service` |
| `ECR_ADMIN` | `886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-admin-service` |
| `ECR_NOTIF` | `886240425170.dkr.ecr.us-east-1.amazonaws.com/como-vapp-dev-notifications-service` |

---

## 4. Build y push de imágenes a ECR

> El **frontend NO se despliega en K8s** — se sube a S3.
> Aquí solo se buildean y pushean los tres servicios backend.

```bash
cd ~/como-vapp-architecture-bootcamp

# Login ECR
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

### Deploy del frontend a S3

```bash
aws s3 sync frontend/react-app/ s3://como-vapp-dev-frontend/ --delete
echo "Frontend: http://como-vapp-dev-frontend.s3-website-us-east-1.amazonaws.com"
```

---

## 5. Verificar manifiestos (los valores ya están hardcodeados)

Los manifiestos en este directorio ya tienen los valores reales de Terraform. Verificar que no queden placeholders:

```bash
cd ~/como-vapp-architecture-bootcamp/deploy/k8s
grep -r "REEMPLAZAR" *.yaml
# No debe aparecer ningún resultado
```

---

## 6. Aplicar manifiestos — orden recomendado

```bash
cd ~/como-vapp-architecture-bootcamp/deploy/k8s

# 1. Namespace
kubectl apply -f namespace.yaml

# 2. RBAC y ServiceAccounts
kubectl apply -f rbac.yaml

# 3. ConfigMaps
kubectl apply -f configmaps.yaml

# 4. Deployments y Services (los 3 backends)
kubectl apply -f orders-deployment.yaml
kubectl apply -f admin-deployment.yaml
kubectl apply -f notifications-deployment.yaml

# 5. Ingress (crea el ALB — tarda ~2 min en aparecer el DNS)
kubectl apply -f ingress.yaml

# secret-provider-class.yaml → referencia de producción, NO aplicar en Academy
```

---

## 7. Verificar el despliegue

```bash
# Estado de los pods (esperar 6 pods Running: 2 réplicas × 3 servicios)
kubectl -n como-vapp-dev get pods -w

# Obtener el DNS del ALB
export ALB_DNS=$(kubectl -n como-vapp-dev get ingress como-vapp-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB_DNS"
# ALB actual: k8s-comovapp-comovapp-df69069754-1646076730.us-east-1.elb.amazonaws.com

# Verificar que los targets del ALB están healthy
TG_ARN=$(aws elbv2 describe-target-groups \
  --query 'TargetGroups[?contains(TargetGroupName, `como`)].TargetGroupArn' \
  --output text --region us-east-1)
aws elbv2 describe-target-health --target-group-arn $TG_ARN --region us-east-1
# "State": "healthy"
```

---

## 8. Probar los endpoints

### orders-service (público vía ALB)

```bash
export ALB_DNS=$(kubectl -n como-vapp-dev get ingress como-vapp-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Crear pedido
curl -s -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -d '{
    "cliente": {"nombre": "Ana Torres", "correo": "ana@demo.com"},
    "direccion": "Calle 123",
    "items": [{"producto": "Pizza", "cantidad": 2, "valor": 15000}]
  }' | python3 -m json.tool
# {"idPedido": "uuid", "estado": "CREADO", "fechaCreacion": "..."}

# Consultar pedido
export PEDIDO_ID="<idPedido del paso anterior>"
curl -s http://$ALB_DNS/orders/$PEDIDO_ID | python3 -m json.tool
```

> **Nota:** `curl http://$ALB_DNS/health` retorna 404 — el path `/health` es para el health check **interno** del ALB (no está en las reglas del ingress). El único path expuesto públicamente es `/orders`.

### admin-service y notifications-service (internos — acceso vía port-forward)

```bash
kubectl -n como-vapp-dev port-forward deploy/admin-service 8081:8081 &
kubectl -n como-vapp-dev port-forward deploy/notifications-service 8082:8082 &
sleep 2

# Actualizar estado del pedido
curl -s -X PATCH http://localhost:8081/orders/$PEDIDO_ID/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "EN_PROGRESO", "origen": "ADMIN"}' | python3 -m json.tool

# Ver notificaciones procesadas
curl -s http://localhost:8082/notifications | python3 -m json.tool
```

---

## 9. Verificar persistencia en DynamoDB y SQS

```bash
# Ver pedidos en DynamoDB
aws dynamodb scan \
  --table-name como-vapp-dev-orders \
  --query 'Items[*].{id:idPedido.S,estado:estado.S}' \
  --output table --region us-east-1

# Ver mensajes en cola (0 = notifications-service ya los procesó)
aws sqs get-queue-attributes \
  --queue-url "https://sqs.us-east-1.amazonaws.com/886240425170/como-vapp-dev-notifications" \
  --attribute-names ApproximateNumberOfMessages \
  --region us-east-1
```

---

## 10. Simular caída del servicio de notificaciones (prueba de resiliencia)

```bash
# 1. Crear un pedido de prueba
NEW_ID=$(curl -s -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -d '{"cliente":{"nombre":"Carlos Ruiz","correo":"test@demo.com"},"direccion":"Av. Test 1","items":[{"producto":"Burger","cantidad":1,"valor":18000}]}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['idPedido'])")

# 2. Eliminar pods del notificador (simular caída)
kubectl -n como-vapp-dev delete pod -l app=notifications-service

# 3. Actualizar estado (mensaje queda en SQS sin ser consumido)
curl -s -X PATCH http://localhost:8081/orders/$NEW_ID/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "EN_PROGRESO", "origen": "ADMIN"}'

# 4. Ver mensaje encolado
aws sqs get-queue-attributes \
  --queue-url "https://sqs.us-east-1.amazonaws.com/886240425170/como-vapp-dev-notifications" \
  --attribute-names ApproximateNumberOfMessages
# ApproximateNumberOfMessages > 0

# 5. Kubernetes recrea los pods automáticamente
kubectl -n como-vapp-dev get pods -l app=notifications-service -w
# Terminating → Pending → Running

# 6. Una vez Running, el mensaje fue consumido
curl -s http://localhost:8082/notifications | python3 -m json.tool
```

---

## 11. Teardown

```bash
# 1. Eliminar recursos K8s (también elimina el ALB)
kubectl delete namespace como-vapp-dev

# 2. Esperar que el ALB desaparezca (~2 min)
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `como`)].State' \
  --region us-east-1

# 3. Eliminar node group
aws eks delete-nodegroup \
  --cluster-name como-vapp-eks \
  --nodegroup-name como-vapp-nodes \
  --region us-east-1

# Esperar que el node group se elimine
aws eks describe-nodegroup \
  --cluster-name como-vapp-eks \
  --nodegroup-name como-vapp-nodes \
  --query 'nodegroup.status' --output text --region us-east-1
# Cuando retorne error "No nodegroup found" → continuar

# 4. Eliminar el clúster EKS
aws eks delete-cluster --name como-vapp-eks --region us-east-1

# 5. Destruir infraestructura Terraform
cd ~/como-vapp-architecture-bootcamp/infra/terraform
terraform destroy -auto-approve
```
