# Kubernetes — Guía de Despliegue Como Vapp

> EKS se crea **manualmente** (eksctl o consola). Terraform provisiona la red y los recursos AWS; los manifiestos YAML aquí son los que aplicas con `kubectl`.

---

## 0. Prerequisitos

| Herramienta | Versión mínima |
|---|---|
| AWS CLI | 2.x |
| eksctl | 0.180+ |
| kubectl | 1.29+ |
| helm | 3.x |

```bash
aws configure          # perfil con credenciales de AWS Academy
aws sts get-caller-identity   # verificar acceso
```

---

## 1. Crear el clúster EKS (manual — NO Terraform)

```bash
eksctl create cluster \
  --name como-vapp-eks \
  --region us-east-1 \
  --version 1.29 \
  --vpc-id $(terraform -chdir=../../infra/terraform output -raw vpc_id) \
  --vpc-private-subnets $(terraform -chdir=../../infra/terraform output -json private_subnet_ids | jq -r 'join(",")') \
  --vpc-public-subnets  $(terraform -chdir=../../infra/terraform output -json public_subnet_ids  | jq -r 'join(",")') \
  --nodegroup-name como-vapp-nodes \
  --node-type t3.small \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 4 \
  --managed \
  --asg-access \
  --full-ecr-access \
  --node-security-groups $(terraform -chdir=../../infra/terraform output -raw eks_nodes_security_group_id)
```

> La opción `--full-ecr-access` agrega el managed policy `AmazonEC2ContainerRegistryReadOnly` al rol del node group.

Actualizar kubeconfig:

```bash
aws eks update-kubeconfig --name como-vapp-eks --region us-east-1
kubectl get nodes   # verificar que los nodos están Ready
```

---

## 2. Instalar el AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=como-vapp-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## 3. Obtener los valores de Terraform

```bash
cd ../../infra/terraform

ORDERS_TABLE=$(terraform output -raw orders_table_name)
SQS_URL=$(terraform output -raw notifications_queue_url)
SES_SENDER=$(terraform output -raw ses_verified_sender)
ECR_ORDERS=$(terraform output -json ecr_repository_urls | jq -r '.["orders-service"]')
ECR_ADMIN=$(terraform output -json ecr_repository_urls | jq -r '.["admin-service"]')
ECR_NOTIF=$(terraform output -json ecr_repository_urls | jq -r '.["notifications-service"]')
ECR_FRONT=$(terraform output -json ecr_repository_urls | jq -r '.["frontend"]')

echo "Table: $ORDERS_TABLE"
echo "Queue: $SQS_URL"
```

---

## 4. Build y push de imágenes a ECR

> El **frontend NO se despliega en K8s** — se sube a S3 (Misión 1 Q7).
> Aquí solo se buildean y pushean los tres servicios backend.

```bash
# Login ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Build y push — orders-service
docker build -t $ECR_ORDERS:0.1.0 ../../services/orders-dotnet/
docker push $ECR_ORDERS:0.1.0

# Build y push — admin-service
docker build -t $ECR_ADMIN:0.1.0 ../../services/admin-kotlin/
docker push $ECR_ADMIN:0.1.0

# Build y push — notifications-service
docker build -t $ECR_NOTIF:0.1.0 ../../services/notifications-python/
docker push $ECR_NOTIF:0.1.0
```

### Deploy del frontend a S3

```bash
BUCKET=$(cd ../../infra/terraform && terraform output -raw frontend_bucket_name)
aws s3 sync ../../frontend/react-app/ s3://$BUCKET/ --delete
SITE_URL=$(cd ../../infra/terraform && terraform output -raw frontend_website_url)
echo "Frontend: http://$SITE_URL"
```

---

## 5. Editar los manifiestos con los valores reales

### configmaps.yaml

Reemplazar los tres placeholders `REEMPLAZAR_CON_TF_OUTPUT_*` con los valores del paso 3:

```bash
sed -i "s|REEMPLAZAR_CON_TF_OUTPUT_orders_table_name|$ORDERS_TABLE|g" configmaps.yaml
sed -i "s|REEMPLAZAR_CON_TF_OUTPUT_notifications_queue_url|$SQS_URL|g" configmaps.yaml
sed -i "s|REEMPLAZAR_CON_TF_OUTPUT_ses_verified_sender|$SES_SENDER|g" configmaps.yaml
```

### Deployments — imagen ECR

```bash
sed -i "s|REEMPLAZAR_ECR_URI/como-vapp-dev-orders-service|$ECR_ORDERS|g" orders-deployment.yaml
sed -i "s|REEMPLAZAR_ECR_URI/como-vapp-dev-admin-service|$ECR_ADMIN|g" admin-deployment.yaml
sed -i "s|REEMPLAZAR_ECR_URI/como-vapp-dev-notifications-service|$ECR_NOTIF|g" notifications-deployment.yaml
```

---

## 6. Aplicar manifiestos — orden recomendado

```bash
# 1. Namespace
kubectl apply -f namespace.yaml

# 2. RBAC y ServiceAccounts
kubectl apply -f rbac.yaml

# 3. ConfigMaps (editar REEMPLAZAR_* primero — ver paso 5)
kubectl apply -f configmaps.yaml

# 4. Deployments y Services — SOLO los 3 servicios backend
#    (frontend va a S3, no a K8s)
kubectl apply -f orders-deployment.yaml
kubectl apply -f admin-deployment.yaml
kubectl apply -f notifications-deployment.yaml

# 5. Ingress (ALB — expone solo orders-service al público)
kubectl apply -f ingress.yaml

# secret-provider-class.yaml → referencia de producción, NO aplicar en Academy
```

---

## 7. Verificar el despliegue

```bash
# Estado de los pods (esperar Running)
kubectl -n como-vapp-dev get pods -w

# Descripción de un pod (para ver eventos y probes)
kubectl -n como-vapp-dev describe pod <pod-name>

# Logs de un servicio
kubectl -n como-vapp-dev logs deploy/orders-service
kubectl -n como-vapp-dev logs deploy/orders-service -f   # streaming

# Estado del Ingress (ALB DNS)
kubectl -n como-vapp-dev get ingress como-vapp-ingress

# Eventos recientes del clúster
kubectl -n como-vapp-dev get events --sort-by=.metadata.creationTimestamp
```

---

## 8. Probar los endpoints

### orders-service (público vía ALB)

```bash
ALB_DNS=$(kubectl -n como-vapp-dev get ingress como-vapp-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB_DNS"

# Crear pedido
curl -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -H "X-Request-Id: test-001" \
  -d '{
    "cliente": {"nombre": "Ana Torres", "correo": "ana@demo.com"},
    "direccion": "Calle 123",
    "items": [{"producto": "Pizza", "cantidad": 2, "valor": 15000}]
  }'

# Consultar pedido
curl http://$ALB_DNS/orders/<idPedido>
```

### admin-service y notifications-service (internos — acceso vía port-forward)

```bash
kubectl -n como-vapp-dev port-forward deploy/admin-service 8081:8081 &
kubectl -n como-vapp-dev port-forward deploy/notifications-service 8082:8082 &

# Actualizar estado del pedido
curl -X PATCH http://localhost:8081/orders/<idPedido>/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "EN_PROGRESO", "origen": "CLIENTE"}'

# Ver notificaciones procesadas
curl http://localhost:8082/notifications
```

---

## 10. Simular caída del servicio de notificaciones (prueba de resiliencia)

```bash
# 1. Eliminar pods del notificador (Kubernetes los recreará automáticamente)
kubectl -n como-vapp-dev delete pod -l app=notifications-service

# 2. Crear o actualizar pedidos mientras el servicio está caído
#    Los mensajes quedan encolados en SQS

# 3. Ver la cola SQS crecer desde AWS CLI
aws sqs get-queue-attributes \
  --queue-url $SQS_URL \
  --attribute-names ApproximateNumberOfMessages

# 4. Verificar que los pods vuelven (self-healing)
kubectl -n como-vapp-dev get pods -l app=notifications-service -w

# 5. Verificar que los mensajes encolados se consumen
curl http://localhost:8082/notifications
```

---

## 11. Teardown

```bash
# Eliminar recursos K8s
kubectl delete namespace como-vapp-dev

# Eliminar clúster EKS
eksctl delete cluster --name como-vapp-eks --region us-east-1

# Destruir infraestructura Terraform
cd ../../infra/terraform
terraform destroy -auto-approve
```
