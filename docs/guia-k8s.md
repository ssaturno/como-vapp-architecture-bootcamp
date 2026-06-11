# Guía de Despliegue — Kubernetes (EKS)

El clúster EKS se crea **manualmente** — no con Terraform. Una vez creado, todos los manifiestos se aplican con `kubectl`. Ver el archivo `deploy/k8s/README.md` para los comandos detallados.

---

## Resumen del flujo

```
1. terraform apply          → VPC, ECR, DynamoDB, SQS, SES, Lambda, S3
2. eksctl create cluster    → EKS en la VPC de Terraform
3. docker build + push      → Imágenes a ECR
4. Editar manifiestos       → Reemplazar placeholders con outputs de TF
5. kubectl apply            → Namespace → RBAC → ConfigMaps → Deployments → Ingress
6. Verificar                → kubectl get pods, logs, describe
```

---

## Manifiesto por manifiesto

### namespace.yaml
Crea el namespace `como-vapp-dev`. Siempre el primer apply.

### rbac.yaml
Crea:
- Un `ServiceAccount` por servicio (orders-sa, admin-sa, notifications-sa)
- Un `Role` de solo lectura para desarrolladores dentro del namespace
- El `RoleBinding` correspondiente

> **AWS Academy — credenciales AWS en los pods**: IRSA no está disponible.
> Los pods obtienen credenciales AWS del **instance profile del nodo EC2** (LabRole).
> Todos los pods del clúster comparten esas credenciales. Los ServiceAccounts
> aquí son útiles para el RBAC de K8s (acceso a recursos del clúster), no para AWS.
>
> **Producción real**: descomentar la annotation `eks.amazonaws.com/role-arn` en
> cada ServiceAccount con el ARN del rol IAM específico por servicio.

### configmaps.yaml
Configuración pública (no sensible): región, nombre de tabla DynamoDB, URL de SQS.

**Editar antes de aplicar**: reemplazar los valores `REEMPLAZAR_*` con los outputs de Terraform.

### secret-provider-class.yaml (solo producción real — NO aplicar en Academy)
Monta secretos de AWS Secrets Manager dentro de los pods via el CSI Driver.

**Por qué no funciona en Academy**: requiere IRSA (roles IAM por ServiceAccount),
que no está disponible. El archivo se deja como referencia de producción con todo
el contenido comentado.

**Alternativa en Academy**: los valores no sensibles (como el email SES verificado)
se pasan en `configmaps.yaml`. Las credenciales reales de AWS vienen automáticamente
del instance profile del nodo (LabRole).

### orders-deployment.yaml / admin-deployment.yaml / notifications-deployment.yaml / frontend-deployment.yaml
Cada uno incluye:
- 2 réplicas
- `securityContext` con non-root, `readOnlyRootFilesystem`, `seccompProfile: RuntimeDefault`, `capabilities: drop ALL`
- Resource requests y limits según la tabla de Misión 2 Q6
- Liveness y Readiness probes en `/health`
- `topologySpreadConstraints` para distribuir réplicas entre AZs

**Editar antes de aplicar**: reemplazar `REEMPLAZAR_ECR_URI` con las URIs reales de ECR.

### ingress.yaml
Crea un ALB via el AWS Load Balancer Controller con rutas:

| Path | Servicio |
|---|---|
| `/orders` | orders-service |
| `/admin` | admin-service |
| `/notifications` | notifications-service |
| `/` | frontend |

---

## Seguridad implementada (Misión 2)

| Medida | Dónde |
|---|---|
| Non-root user (UID 1001) | `securityContext.runAsUser` en todos los Deployments |
| `readOnlyRootFilesystem: true` | `securityContext` + emptyDir para /tmp |
| `capabilities: drop ALL` | `securityContext.capabilities` |
| Seccomp `RuntimeDefault` | `securityContext.seccompProfile` |
| RBAC por namespace | `rbac.yaml` |
| ServiceAccount por servicio | Preparados para IRSA |
| Secretos vía CSI Driver | `secret-provider-class.yaml` |
| 2 réplicas + spread entre AZs | `replicas: 2` + `topologySpreadConstraints` |
| Resource limits (cgroups) | `resources.requests` y `resources.limits` |

---

## Observabilidad (Misión 2)

### Logs estructurados en CloudWatch

Los pods escriben JSON estructurado en stdout. Fluent Bit (instalado como DaemonSet por defecto en EKS) los envía a CloudWatch Logs:
- `/como-vapp/orders-service`
- `/como-vapp/admin-service`
- `/como-vapp/notifications-service`

```bash
# Instalar CloudWatch Observability add-on
aws eks create-addon \
  --cluster-name como-vapp-eks \
  --addon-name amazon-cloudwatch-observability
```

### Verificar pods y probes

```bash
# Estado general
kubectl -n como-vapp-dev get pods

# Ver todos los eventos (útil para diagnosticar CrashLoopBackOff, OOMKilled)
kubectl -n como-vapp-dev get events --sort-by=.metadata.creationTimestamp

# Inspeccionar un pod específico
kubectl -n como-vapp-dev describe pod <pod-name>

# Logs en tiempo real
kubectl -n como-vapp-dev logs -f deploy/orders-service

# Buscar errores en logs
kubectl -n como-vapp-dev logs deploy/orders-service | grep '"severity":"ERROR"'
```

---

## Pruebas de resiliencia (Misión 2 Q12)

### Stress test de CPU/memoria

```bash
# Conectarse a un pod
kubectl -n como-vapp-dev exec -it deploy/orders-service -- bash

# Dentro del pod:
apt-get install -y stress-ng 2>/dev/null || true
stress-ng --cpu 2 --vm 1 --vm-bytes 200M --timeout 30s
```

Observar en CloudWatch o Grafana que el pod alcanza el límite y es throttleado pero no muere.

### Simular caída del notificador

```bash
# Eliminar ambas réplicas
kubectl -n como-vapp-dev delete pod -l app=notifications-service

# Verificar que K8s recrea los pods (self-healing)
kubectl -n como-vapp-dev get pods -l app=notifications-service -w

# Mientras están caídos, enviar actualizaciones de estado (mensajes en SQS)
# Después de que los pods vuelvan, verificar que los mensajes se consumen
```

### Rollback a versión anterior

```bash
kubectl -n como-vapp-dev rollout history deployment/orders-service
kubectl -n como-vapp-dev rollout undo deployment/orders-service
kubectl -n como-vapp-dev rollout status deployment/orders-service
```

---

## Monitoreo con Prometheus + Grafana (Misión 2 Q14-16)

```bash
# Instalar kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# Port-forward al Grafana local
kubectl -n monitoring port-forward svc/kube-prometheus-grafana 3001:80
# Usuario: admin / Contraseña: prom-operator (por defecto)
```

Dashboards recomendados (ID de Grafana.com):
- `6417` — Kubernetes Cluster
- `7249` — Kubernetes Pods
- `15760` — Kubernetes / Compute Resources / Namespace (Pods)

Métricas clave para el dashboard de Como Vapp (Misión 2 Q16):
- `kube_deployment_status_replicas_available` → réplicas activas
- `rate(container_cpu_usage_seconds_total[5m])` → CPU por pod
- `container_memory_usage_bytes` → RAM por pod
- `aws_sqs_number_of_messages_received_sum` (CloudWatch) → mensajes procesados
