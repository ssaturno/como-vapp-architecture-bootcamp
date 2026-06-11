# Checklist de Evidencias — Como Vapp (Misiones 1 y 2)

---

## 1. Evidencia funcional

- [ ] Crear pedido — request POST /orders + response 201 con idPedido
- [ ] Consultar pedido — request GET /orders/{id} + response 200
- [ ] Actualizar estado — PATCH /orders/{id}/status: CREADO → EN_PROGRESO
- [ ] Actualizar estado — PATCH /orders/{id}/status: EN_PROGRESO → ENTREGADO
- [ ] Transición inválida rechazada con 400 (ej: ENTREGADO → CANCELADO)
- [ ] Evento publicado en SQS (consola AWS o CLI)
- [ ] Evento consumido por notifications-service (log "Notification processed")
- [ ] Email enviado por SES (sandbox: correo verificado recibe)

---

## 2. Evidencia de infraestructura (Terraform)

- [ ] `terraform init` exitoso
- [ ] `terraform plan` muestra ~35 recursos a crear
- [ ] `terraform apply` exitoso (sin errores)
- [ ] VPC visible en consola (subnets públicas + privadas)
- [ ] ECR: 4 repositorios creados
- [ ] DynamoDB: tabla `como-vapp-dev-orders` con Streams habilitados
- [ ] SQS: cola `como-vapp-dev-notifications` + DLQ visible
- [ ] Lambda: función `como-vapp-dev-stream-processor` activa
- [ ] SES: email verificado en sandbox
- [ ] S3: bucket frontend con static website habilitado
- [ ] CloudWatch: log groups creados + alarmas configuradas
- [ ] AWS Config: recorder en estado "Recording" y reglas en "Compliant"

---

## 3. Evidencia de despliegue

### Frontend en S3 (Misión 1 Q7)
- [ ] Bucket S3 frontend visible en consola
- [ ] Static website habilitado (`aws s3 sync` ejecutado)
- [ ] URL del sitio respondiendo con `index.html`

### Servicios backend en EKS (Kubernetes manual)
- [ ] Clúster EKS `como-vapp-eks` en estado ACTIVE
- [ ] 2 nodos EC2 t3.small en estado Ready
- [ ] Namespace `como-vapp-dev` creado
- [ ] RBAC: ServiceAccounts y Role aplicados
- [ ] ConfigMaps con valores correctos (sin placeholders)
- [ ] 6 pods en estado Running (2 réplicas × 3 servicios backend)
- [ ] Readiness y Liveness probes respondiendo OK (describe pod sin errores)
- [ ] Ingress creado y ALB DNS visible (solo orders-service expuesto al público)
- [ ] orders-service accesible vía ALB: `curl http://<ALB>/orders` → 200/404
- [ ] admin-service accesible vía port-forward: `kubectl port-forward deploy/admin-service 8081:8081`
- [ ] notifications-service accesible vía port-forward: `kubectl port-forward deploy/notifications-service 8082:8082`

---

## 4. Evidencia de seguridad (Misión 2)

### 4.1 Contenedores sin root
- [ ] `kubectl -n como-vapp-dev get pods -o jsonpath='{.items[*].spec.securityContext.runAsNonRoot}'` → `true true true...`
- [ ] `kubectl -n como-vapp-dev exec deploy/orders-service -- id` → `uid=1001(appuser)`

### 4.2 ReadOnly filesystem
- [ ] `kubectl -n como-vapp-dev exec deploy/orders-service -- touch /test` → "Read-only file system"
- [ ] Escritura en /tmp funciona (emptyDir montado)

### 4.3 Capabilities drop ALL
- [ ] `kubectl -n como-vapp-dev get pod <pod> -o yaml | grep -A 5 capabilities`

### 4.4 Seccomp RuntimeDefault
- [ ] `kubectl -n como-vapp-dev get pod <pod> -o yaml | grep seccompProfile`

### 4.5 Resource limits (cgroups)
- [ ] `kubectl -n como-vapp-dev describe pod <pod>` → sección Limits con los valores correctos

### 4.6 Sin secretos en código ni en imágenes
- [ ] Búsqueda en repositorio: `grep -rn "aws_access_key_id\|aws_secret" services/ --include="*.py"` → sin resultados hardcodeados
- [ ] `.env` en .gitignore

### 4.7 Cifrado en reposo
- [ ] DynamoDB: SSE habilitado (consola o `aws dynamodb describe-table`)
- [ ] SQS: KMS key visible en las propiedades de la cola

### 4.8 AWS Config compliance
- [ ] Regla `restricted-ssh`: estado "Compliant"
- [ ] Regla `dynamodb-encryption`: estado "Compliant"
- [ ] Regla `encrypted-volumes`: estado "Compliant"

---

## 5. Evidencia de observabilidad (Misión 2)

- [ ] Log JSON estructurado visible en CloudWatch Logs (`/como-vapp/orders-service`)
- [ ] Campo `requestId` presente en los logs
- [ ] `kubectl -n como-vapp-dev logs deploy/orders-service | grep requestId` → log JSON
- [ ] Dashboard en Grafana/CloudWatch con:
  - [ ] Estado de réplicas activas vs deseadas
  - [ ] CPU por pod
  - [ ] Latencia promedio (si hay métricas custom)
  - [ ] Longitud de cola SQS

---

## 6. Evidencia de resiliencia (Misión 2 Q12)

- [ ] **Caída del notificador**: `kubectl delete pod -l app=notifications-service` → pods recreados automáticamente
- [ ] **Mensajes encolados**: `aws sqs get-queue-attributes --queue-url $SQS_URL --attribute-names ApproximateNumberOfMessages` → > 0 mientras el servicio está caído
- [ ] **Recuperación**: tras reinicio, los mensajes son consumidos y notificaciones procesadas
- [ ] **Transición de pod**: ver en `kubectl get events` los eventos `Killing` → `Created` → `Started`

---

## 7. Evidencia de diagnóstico (Misión 2 Q11)

Comandos usados y su output esperado:

```bash
# Ver estado de todos los pods
kubectl -n como-vapp-dev get pods

# Inspeccionar eventos de fallo
kubectl -n como-vapp-dev describe pod <pod-name>
# Buscar: CrashLoopBackOff, OOMKilled, ImagePullBackOff, Liveness/Readiness probe failed

# Logs de aplicación
kubectl -n como-vapp-dev logs deploy/orders-service

# Últimos eventos del clúster
kubectl -n como-vapp-dev get events --sort-by=.metadata.creationTimestamp | tail -20
```

---

## 8. Material de presentación

- [ ] Slides de arquitectura (diagrama actualizado)
- [ ] Guion de demo 5-10 min (`docs/script-demo-5-10min.md`)
- [ ] Evidencia de Trivy (scan report o pipeline output)
- [ ] Evidencia de AccessDenied (denegación de permisos por IAM/RBAC)
- [ ] AWS Config en estado Compliant (captura de pantalla)
- [ ] Dashboard de observabilidad con tráfico real
- [ ] Resumen de costos estimados y trade-offs de AWS Academy
