# Script de Demo (5-10 min)

## 1) Problema y objetivo (1 min)
- Mostrar necesidad: seguimiento de pedidos y notificación de cambios sin contacto manual con soporte.
- Resumir solución: arquitectura de eventos con AWS + servicios desacoplados.

## 2) Flujo funcional (3-4 min)
1. Crear pedido (POST /orders).
2. Consultar pedido (GET /orders/{id}).
3. Cambiar estado (PATCH /orders/{id}/status).
4. Mostrar evento procesado.
5. Mostrar email de notificación recibido (SES sandbox con correo verificado).

## 3) Infraestructura e IaC (1-2 min)
- Mostrar recursos Terraform creados: DynamoDB, SQS, SES identity, base para EKS.
- Mostrar estado de despliegue en Kubernetes (pod Running).

## 4) Observabilidad y resiliencia (1-2 min)
- Mostrar logs estructurados con requestId.
- Simular caída controlada del notificador, validar mensajes en cola y recuperación.

## 5) Cierre (1 min)
- Costos y trade-offs por AWS Academy (sin IAM personalizado, alcance híbrido).
- Próximos pasos para endurecimiento productivo.

## Evidencia mínima a mostrar en pantalla
- Requests/responses de endpoints.
- Estado en persistencia.
- Mensajes/eventos en cola.
- Notificación email.
- Logs + dashboard.
- Recursos IaC aplicados.
