# Notas de Presentación — Como Vapp en AWS

**Duración total:** ~20 minutos  
**Formato:** Slides + demo en vivo  
**Audiencia:** Bootcamp de Arquitectura de Nube

---

## Parte 1 — Arquitectura y despliegue (5 min)

### Slide: Qué es Como Vapp

> "Como Vapp es un sistema de gestión de pedidos de comida desplegado completamente en AWS. Tiene tres microservicios, cada uno con una responsabilidad clara: crear pedidos, administrarlos y enviar notificaciones. Lo interesante no es solo que funciona — es cómo está construido para ser resiliente, seguro y reproducible."

### Slide: Diagrama de arquitectura

> "Un usuario crea un pedido desde el frontend en S3. Esa petición llega al Application Load Balancer, que la enruta al orders-service corriendo en EKS. El servicio escribe en DynamoDB y ahí se dispara un evento automático: DynamoDB Streams llama a una Lambda que publica en SQS. El notifications-service está escuchando la cola y procesa el evento. Todo desacoplado — si cae el notifications-service, los mensajes se quedan en SQS y se procesan cuando vuelve."

### Slide: Infraestructura como código

> "Toda la infraestructura — VPC, subnets, DynamoDB, SQS, Lambda, ECR, S3, CloudWatch — está en Terraform. Esto significa que en una cuenta nueva, con un solo comando se puede recrear el mismo ambiente. El estado de Terraform vive en S3 para que el equipo pueda colaborar sin conflictos."

---

## Parte 2 — Demo en vivo (8 min)

### ⚠️ Si el ambiente AWS estaba apagado — Reactivación previa

> El frontend (S3) siempre está disponible, pero el backend (EKS + ALB) se apaga con la sesión de Academy. Si los pods no están corriendo, los botones del frontend darán error. Hacer esto **antes** de la demo.

**1. Renovar credenciales de Academy**

En AWS Academy → Launch AWS Learner Lab → copiar las credenciales de AWS CLI y pegarlas en CloudShell:
```bash
# Pegar el bloque completo de credenciales (aws configure o export de variables)
aws sts get-caller-identity   # Verificar que funcionan
```

**2. Verificar que los nodos EKS están activos**

```bash
aws eks update-kubeconfig --name como-vapp-eks --region us-east-1
kubectl get nodes
```
- Si aparecen 2 nodos en estado `Ready` → continuar al paso 3.
- Si no hay nodos o están en `NotReady` → el node group se eliminó. Recrearlo desde la consola:
  AWS Console → EKS → `como-vapp-eks` → Compute → Add node group con los mismos parámetros (`t3.medium`, `AL2023_x86_64_STANDARD`, subnets privadas). Esperar ~5 min.

**3. Verificar/levantar los pods**

```bash
kubectl get pods -n como-vapp-dev
```
- Si aparecen 6 pods en `Running` → todo listo, saltar al paso 4.
- Si no hay pods o están en error → re-aplicar los manifiestos:
```bash
kubectl apply -f k8s/
# Esperar ~1 minuto
kubectl get pods -n como-vapp-dev -w
```

> **Problema conocido — pod en `Pending`:** Si después de aplicar los manifiestos algún pod queda en `Pending` (usualmente `notifications-service`), verificar la causa:
> ```bash
> kubectl describe pod <nombre-pod> -n como-vapp-dev | tail -15
> ```
> Si el evento dice `Too many pods` o `didn't match pod topology spread constraints`, el node group necesita un nodo extra. Escalar a 3 nodos:
> ```bash
> aws eks update-nodegroup-config \
>   --cluster-name como-vapp-eks \
>   --nodegroup-name como-vapp-nodes-med \
>   --scaling-config minSize=2,maxSize=4,desiredSize=3 \
>   --region us-east-1
> ```
> Esperar ~3 minutos. El pod se scheduleará automáticamente.

**4. Verificar que el ALB tiene targets healthy**

```bash
# Obtener el DNS del ALB (puede haber cambiado si se recreó)
kubectl get ingress -n como-vapp-dev
```
Copiar el ADDRESS del ingress. Luego verificar:
```bash
export ALB_DNS=k8s-comovapp-comovapp-df69069754-1646076730.us-east-1.elb.amazonaws.com 
curl -s http://$ALB_DNS/orders | head -c 100
# Debe responder JSON, no "Connection refused" ni 502
```
> El ALB puede tardar 2-3 minutos en marcar los targets como healthy después de que los pods estén Running. Si da 502, esperar y reintentar.

> **Problema conocido — ALB responde 503:** El AWS Load Balancer Controller perdió credenciales por IMDS hop limit en 1 (ocurre cuando se agrega un nodo nuevo al escalar el node group). Diagnóstico: `kubectl describe ingress -n como-vapp-dev | tail -10` mostrará `FailedBuildModel ... no EC2 IMDS role found`. Fix:
> ```bash
> # 1. Actualizar hop limit a 2 en todos los nodos
> for id in $(aws ec2 describe-instances \
>   --filters "Name=tag:eks:nodegroup-name,Values=como-vapp-nodes-med" \
>             "Name=instance-state-name,Values=running" \
>   --query "Reservations[].Instances[].InstanceId" \
>   --output text); do
>   aws ec2 modify-instance-metadata-options \
>     --instance-id $id \
>     --http-put-response-hop-limit 2 \
>     --http-endpoint enabled
>   echo "Fixed: $id"
> done
> ```
> ```bash
> # 2. Reiniciar el Load Balancer Controller
> kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
> kubectl rollout status deployment aws-load-balancer-controller -n kube-system
> ```
> Esperar ~1 minuto y reintentar. **Nota:** `{"detail":"Method Not Allowed"}` en `GET /orders` es comportamiento esperado — el endpoint solo acepta `POST`. El ALB está funcionando correctamente.

> **Problema conocido — POST /orders responde 500 (`NoCredentialsError`):** Los pods de los servicios no pueden obtener credenciales de IMDS. Ocurre cuando un nodo nuevo se agrega al escalar el node group (hop limit 1 por defecto) y algún pod se scheduleó en él. Diagnóstico: `kubectl logs -n como-vapp-dev -l app=orders-service --tail=20 --prefix` mostrará `botocore.exceptions.NoCredentialsError: Unable to locate credentials`. Fix:
> ```bash
> # 1. Re-aplicar hop limit a 2 en todos los nodos
> for id in $(aws ec2 describe-instances \
>   --filters "Name=tag:eks:nodegroup-name,Values=como-vapp-nodes-med" \
>             "Name=instance-state-name,Values=running" \
>   --query "Reservations[].Instances[].InstanceId" \
>   --output text); do
>   aws ec2 modify-instance-metadata-options \
>     --instance-id $id \
>     --http-put-response-hop-limit 2 \
>     --http-endpoint enabled
>   echo "Fixed: $id"
> done
> ```
> ```bash
> # 2. Reiniciar todos los servicios
> kubectl rollout restart deployment orders-service admin-service notifications-service -n como-vapp-dev
> kubectl rollout status deployment orders-service -n como-vapp-dev
> ```
> Esperar ~1 minuto y reintentar el POST.

**5. Actualizar la URL del frontend si el ALB_DNS cambió**

Si el DNS del ALB es diferente al original, hay que actualizar el frontend en S3:
```bash
# En el repo local, editar el archivo de configuración del frontend con el nuevo DNS
# Luego hacer sync a S3
aws s3 sync frontend/dist/ s3://como-vapp-dev-frontend/ --delete
```

---

### Antes de la demo — verificar que está listo:
- [ ] Port-forward al admin-service activo en CloudShell: `kubectl -n como-vapp-dev port-forward deploy/admin-service 8081:8081 &`
- [ ] Tab 1: Frontend abierto — `http://como-vapp-dev-frontend.s3-website-us-east-1.amazonaws.com`
- [ ] Tab 2: DynamoDB → Explore items (tabla `como-vapp-dev-orders`)
- [ ] Tab 3: SQS → cola `como-vapp-dev-notifications` → Send and receive messages
- [ ] Tab 4: CloudShell lista

---

### Paso 1 — Crear pedido desde el frontend

**Acción:** Abrir el frontend, completar el formulario y crear un pedido.

> "Este es el frontend estático en S3. Un cliente llena el formulario, hace clic en 'Crear pedido' y la petición sale hacia el ALB. El ALB la enruta al orders-service en EKS, que valida los datos, genera un UUID, guarda el pedido en DynamoDB y retorna la respuesta en menos de 200ms."

**Copiar el ID del pedido que aparece en el modal.**

---

### Paso 2 — Mostrar DynamoDB en tiempo real

**Acción:** Ir al Tab de DynamoDB → Scan → Run → mostrar el item recién creado.

> "El pedido ya está en DynamoDB. Pueden ver el UUID, el estado 'CREADO', el historial de estados con timestamps y los ítems con su valor. Todo estructurado, sin servidor de base de datos que administrar."

---

### Paso 3 — Mostrar SQS y Lambda

**Acción:** Ir al Tab de SQS → Poll for messages o mostrar ApproximateNumberOfMessages.

> "Al mismo tiempo que se guardó en DynamoDB, el stream disparó la Lambda. La Lambda leyó el evento y publicó un mensaje en esta cola SQS. El notifications-service ya lo consumió — por eso el contador puede estar en cero. El flujo fue completamente automático, sin que el orders-service supiera que existía el notifications-service."

---

### Paso 4 — Cambiar estado con admin-service

**Acción:** En CloudShell, ejecutar el PATCH a EN_PROGRESO.

```bash
curl -s -X PATCH http://localhost:8081/orders/92122f20-9324-4577-ad61-b61c793fafd3/status \
  -H "Content-Type: application/json" \
  -d '{"estadoNuevo": "EN_PROGRESO", "origen": "ADMIN"}' | python3 -m json.tool
```

> "El admin-service es un servicio interno — no está expuesto al público vía ALB. Solo el equipo de operaciones puede acceder a él. Acabo de cambiar el estado del pedido a EN_PROGRESO. Noten que el campo 'eventoPublicado' es true — eso significa que también se notificó por SQS."

---

### Paso 5 — Ver historial en el frontend

**Acción:** En el frontend, ir a Seguimiento, pegar el ID del pedido.

> "El cliente puede consultar su pedido en cualquier momento. Aquí están todos los cambios de estado con sus timestamps, quién lo cambió y cuándo. Esto viene directo de DynamoDB."

---

### Paso 6 — Self-healing de Kubernetes

**Acción:** En CloudShell, eliminar los pods del notifications-service.

```bash
kubectl -n como-vapp-dev delete pod -l app=notifications-service
kubectl -n como-vapp-dev get pods -w
```

> "Acabo de eliminar todos los pods del notifications-service — esto simula una caída del servicio. Observen lo que hace Kubernetes: detecta que el estado deseado son 2 réplicas, y en segundos levanta los pods nuevamente. Los mensajes que llegaron mientras estaba caído siguen en SQS — cuando el servicio vuelve, los procesa todos. Esto es lo que diferencia a Kubernetes de simplemente correr contenedores en EC2."

---

## Parte 3 — Seguridad — Misión 2 (5 min)

### Slide: Seguridad en el clúster (lo implementado)

> "La seguridad en Kubernetes no es opcional — es configuración. En todos los deployments aplicamos el principio de mínimo privilegio: los pods corren con usuario 1001, sin permisos de root, con el filesystem en modo lectura y sin ninguna Linux capability. Si un atacante compromete el contenedor, no puede escalar privilegios."

**Mencionar específicamente:**
- `runAsNonRoot: true` — el proceso no puede ser root
- `readOnlyRootFilesystem: true` — no puede escribir archivos maliciosos
- `capabilities.drop: ALL` — sin acceso a operaciones del kernel
- `seccompProfile: RuntimeDefault` — syscalls filtradas por el OS

---

### Slide: Red y acceso

> "Los nodos de EKS están en subnets privadas — no tienen IP pública. Solo el ALB está en la subnet pública. Los Security Groups permiten únicamente tráfico del ALB hacia los nodos en puertos específicos. Para que los pods accedan a DynamoDB y SQS, el tráfico pasa por VPC Endpoints — nunca sale a internet."

---

### Slide: Gestión de identidades

> "Aquí hay una distinción importante entre lo que se hizo en Academy y lo que se haría en producción."

**Academy:**
> "En AWS Academy el LabRole no permite crear roles IAM personalizados. Todos los pods comparten el instance profile del nodo — eso significa que técnicamente cualquier pod podría acceder a cualquier recurso AWS. Es un trade-off aceptable para un ambiente de lab."

**Producción:**
> "En una cuenta real, cada ServiceAccount tendría su propio IAM role via IRSA — IAM Roles for Service Accounts. El orders-service solo podría hacer PutItem y GetItem en su tabla específica de DynamoDB. El notifications-service solo podría hacer ReceiveMessage en su cola. Si un pod es comprometido, el radio de impacto está contenido."

---

### Slide: Gestión de secretos

> "El archivo `secret-provider-class.yaml` ya está en el repositorio pero no se aplica en Academy porque requiere IRSA. En producción, este manifiesto conecta el Secrets Manager de AWS con los pods vía el CSI Driver — los secretos se montan como archivos en el contenedor y se rotan automáticamente sin necesidad de reiniciar los pods. Sin credenciales en variables de entorno, sin credenciales en ConfigMaps."

---

### Slide: Compliance con AWS Config

> "AWS Config monitorea continuamente cuatro reglas: que ningún Security Group tenga SSH abierto al mundo, que los volúmenes EBS estén cifrados, que DynamoDB tenga cifrado activo, y que los VPC Flow Logs estén habilitados. Si alguna regla se viola, AWS Config lo registra y puede disparar una remediación automática."

---

### Slide: Resumen de seguridad — Academy vs. Producción

| Lo que hicimos (Academy) | Lo que se haría en producción |
|---|---|
| LabRole compartido para todos los pods | IRSA con roles de mínimo privilegio por servicio |
| Credenciales en ConfigMap | AWS Secrets Manager + CSI Driver |
| Cifrado AWS-managed (AES256) | CMK con rotación automática cada 90 días |
| ALB solo HTTP | HTTPS + certificado ACM + redirect 301 |
| VPC Endpoints solo DynamoDB/S3 | + SQS, Secrets Manager, ECR |
| AWS Config activado manualmente | Config activado en pipeline de CI/CD desde el primer deploy |

---

## Parte 4 — Cierre (2 min)

### Slide: Lo que logramos

> "Desplegamos un sistema de microservicios completo en AWS: frontend en S3, backend en EKS con ALB, persistencia en DynamoDB, mensajería con SQS, procesamiento serverless con Lambda, y monitoreo de compliance con AWS Config. Todo desde cero, completamente automatizado con Terraform."

### Slide: Reproducibilidad

> "Quiero cerrar con esto: si mañana esta cuenta desaparece, con dos comandos tenemos todo de vuelta. `terraform apply` recrea toda la infraestructura. `kubectl apply` levanta todos los servicios. Eso es lo que significa infraestructura como código — no documentación de lo que hiciste, sino el sistema en sí."

---

## Preguntas frecuentes (prepararse)

**¿Por qué no usar ECS en lugar de EKS?**
> "EKS es más portable — los manifiestos de Kubernetes funcionan igual en cualquier nube o on-premise. ECS es propiedad de AWS. Para un sistema que podría migrar o necesitar multi-cloud, Kubernetes es la elección correcta."

**¿Por qué SQS y no SNS directo?**
> "SQS da durabilidad — si el consumidor está caído, los mensajes esperan hasta 14 días. SNS dispara y olvida. Para notificaciones críticas donde no podemos perder eventos, SQS es la elección correcta."

**¿Cuánto cuesta esto por mes en producción?**
> "Para este tamaño: EKS ~$73/mes (control plane) + 2x t3.medium ~$60 + NAT Gateway ~$32 + DynamoDB pay-per-request ~$1-5. Alrededor de $170-180/mes para un ambiente de desarrollo. En producción con reservas y spot instances se puede reducir un 40%."

**¿Qué pasa si DynamoDB se cae?**
> "DynamoDB tiene SLA de 99.999% de disponibilidad. Tiene PITR activo para restaurar a cualquier segundo de los últimos 35 días. Para protección adicional, se podría activar replicación en otra región con Global Tables."
