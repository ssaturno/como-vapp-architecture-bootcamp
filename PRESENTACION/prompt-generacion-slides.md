# Prompt — Generación de Slides con IA

> Copia y pega este prompt en Claude (claude.ai) para generar la presentación de slides.

---

Crea una presentación profesional en formato de slides para una exposición de bootcamp de Arquitectura de Nube. El tema es el despliegue de "Como Vapp", un sistema de gestión de pedidos de comida en AWS.

AUDIENCIA: Compañeros de bootcamp e instructores técnicos.
DURACIÓN: 20 minutos.
TONO: Técnico pero accesible, con énfasis en decisiones de arquitectura y seguridad.

---

ESTRUCTURA DE SLIDES:

**Slide 1 — Portada**
- Título: "Como Vapp en AWS — Arquitectura de Microservicios"
- Subtítulo: "Despliegue completo con EKS, Terraform, y seguridad en capas"
- Autor: Samaris Saturno

**Slide 2 — El problema**
- Sistema de pedidos de comida con 3 actores: cliente, cocina/admin, notificaciones
- Necesidad: servicios independientes, resiliente a fallos, trazable
- Solución: microservicios desacoplados en AWS

**Slide 3 — Arquitectura general (diagrama)**
Mostrar este flujo como diagrama visual:
- Usuario → S3 (frontend estático) → ALB (internet-facing) → EKS orders-service → DynamoDB
- DynamoDB Stream → Lambda → SQS → EKS notifications-service
- EKS admin-service (solo interno, sin exposición pública)
- Infraestructura base: VPC con subnets públicas/privadas, NAT Gateway, VPC Endpoints

**Slide 4 — Los 3 microservicios**
- orders-service (Python/FastAPI): POST /orders, GET /orders/{id} — expuesto vía ALB
- admin-service (Python/FastAPI): PATCH /orders/{id}/status — solo interno
- notifications-service (Python): consume SQS, simula envío de email
- Cada uno: imagen Docker propia en ECR, deployment independiente, 2 réplicas

**Slide 5 — Infraestructura como código (Terraform)**
- Recursos provisionados: VPC, 4 subnets, DynamoDB, SQS + DLQ, Lambda, 4 ECR repos, 2 S3 buckets, CloudWatch, AWS Config
- State en S3 backend (colaborativo, seguro)
- EKS creado manualmente por limitaciones de LabRole en Academy

**Slide 6 — Demo en vivo** (slide de transición)
- Texto: "Veamos el sistema en funcionamiento"
- Checklist visual: Frontend ✓ | ALB ✓ | EKS ✓ | DynamoDB ✓ | SQS ✓

**Slide 7 — Resiliencia: self-healing**
- Kubernetes mantiene el estado deseado: 2 réplicas siempre
- Si un pod cae → Kubernetes lo recrea automáticamente
- Mensajes en SQS persisten mientras el servicio está caído (hasta 14 días)
- Demo: `kubectl delete pod -l app=notifications-service` → pods vuelven solos

**Slide 8 — Seguridad en capas (Misión 2)**
Tabla con dos columnas: "Control de seguridad" y "Implementación":
- Pods sin root: `runAsNonRoot: true`, `runAsUser: 1001`
- Filesystem inmutable: `readOnlyRootFilesystem: true`
- Sin capacidades Linux: `capabilities.drop: ALL`
- Syscalls filtradas: `seccompProfile: RuntimeDefault`
- Nodos en subnets privadas: sin IPs públicas, tráfico solo por NAT
- Security Groups restrictivos: ALB solo 80/443; nodos solo NodePort desde ALB
- ECR scan automático: `scan_on_push: true` (detección de CVEs en cada push)
- ECR tags inmutables: un tag publicado no se puede sobreescribir
- DynamoDB cifrado en reposo: SSE con llave AWS-managed
- DynamoDB PITR: restauración a cualquier segundo en los últimos 35 días
- RBAC por namespace: Role `developer-readonly`, solo get/list/watch
- Service Accounts separados: `orders-sa`, `admin-sa`, `notifications-sa`

**Slide 9 — Academy vs. Producción Real**
Tabla comparativa:

| AWS Academy (lo que hicimos) | Producción real (lo que se haría) |
|---|---|
| LabRole compartido en todos los pods | IRSA: cada ServiceAccount tiene su propio IAM role de mínimo privilegio |
| Credenciales en ConfigMap | AWS Secrets Manager + CSI Driver (`secret-provider-class.yaml` listo en el repo) |
| Cifrado AES256 AWS-managed | CMK con rotación automática cada 90 días |
| ALB solo HTTP puerto 80 | HTTPS + certificado ACM + redirect 301 de HTTP a HTTPS |
| VPC Endpoints solo DynamoDB/S3 | + SQS, Secrets Manager, ECR (tráfico nunca sale de la VPC) |
| AWS Config habilitado manualmente | Config habilitado en CI/CD desde el primer deploy |
| SES no disponible (Academy bloqueado) | SES activo con sender verificado y templates de email |

**Slide 10 — AWS Config — Compliance**
4 reglas activas monitoreando continuamente:
1. `restricted-ssh`: ningún SG con puerto 22 abierto al mundo
2. `vpc-flow-logs-enabled`: tráfico de red registrado
3. `encrypted-volumes`: volúmenes EBS cifrados
4. `dynamodb-encryption`: tabla cifrada en reposo

Si una regla se viola → AWS Config lo registra y puede disparar remediación automática.

**Slide 11 — Desafíos encontrados y soluciones**
Formato "Problema → Solución":
- EKS Auto Mode seleccionó instancias ARM (c6g.large) → Desactivar Auto Mode, usar "Configure manually"
- t3.small sin capacidad suficiente (11 pods máx) → Migrar a t3.medium (17 pods/nodo)
- IMDS hop limit=1: pods no podían obtener credenciales AWS → Aumentar a 2 con `modify-instance-metadata-options`
- AWS Load Balancer Controller CrashLoopBackOff → Agregar `--set region=us-east-1` y `--set vpcId` al helm install
- SES bloqueado en Academy → `USE_SES=false`, notificaciones simuladas localmente

**Slide 12 — Cierre**
- "Infraestructura reproducible: `terraform destroy` + `terraform apply` = mismo sistema en minutos"
- Repositorio: github.com/ssaturno/como-vapp-architecture-bootcamp
- Métricas finales: 3 microservicios | 6 pods | 1 ALB | 1 tabla DynamoDB | 1 cola SQS | 1 Lambda | 4 reglas de compliance

---

ESTILO VISUAL:
- Tema oscuro profesional (azul oscuro o gris oscuro como fondo)
- Acentos en color AWS naranja (#FF9900) o azul AWS (#232F3E)
- Diagramas de arquitectura con iconos de servicios AWS si es posible
- Tablas limpias, sin bordes excesivos
- Código en monospace con fondo oscuro
- Máximo 6 bullets por slide, sin párrafos largos

Genera los slides con contenido completo y notas del presentador para cada uno.
