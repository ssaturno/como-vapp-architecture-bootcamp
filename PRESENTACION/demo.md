# Flujo de la Aplicación — Guía para el Demo

---

## Flujo 1 — Crear un pedido (camino principal)

```
Usuario (browser)
    │
    │  HTTP POST /orders  {"items": [...]}
    ▼
S3 Static Frontend
    │  (el frontend construye el JSON y hace fetch al ALB)
    ▼
Application Load Balancer (ALB)  ← punto de entrada público
    │  El ALB tiene reglas de Ingress configuradas por el AWS Load Balancer Controller
    │  Regla: /orders/* → orders-service:8080
    ▼
orders-service (pod en EKS)
    │  1. Valida los items del pedido
    │  2. Genera un UUID (idPedido)
    │  3. Escribe el pedido en DynamoDB con estado "CREADO"
    │  4. Retorna {"idPedido": "...", "estado": "CREADO"}
    ▼
DynamoDB (tabla como-vapp-dev-orders)
    │  DynamoDB Streams detecta el INSERT automáticamente
    ▼
Lambda Function (event processor)
    │  Lee el stream event de DynamoDB
    │  Construye un mensaje con los datos del pedido
    ▼
SQS (cola como-vapp-dev-notifications)
    │  El mensaje queda en la cola esperando ser consumido
    ▼
notifications-service (pod en EKS)
    │  Hace polling constante a la cola SQS
    │  Consume el mensaje → lo procesa (lógica de notificación)
    │  En producción: enviaría email vía SES
    │  En Academy: USE_SES=false, solo loguea el evento
    └─ Elimina el mensaje de la cola (SQS lo marca como procesado)
```

**Lo que el usuario ve:** el modal con el ID del pedido aparece en ~200ms. Todo lo demás (Lambda → SQS → notifications) pasa en background de forma asíncrona.

---

## Flujo 2 — Consultar estado de un pedido

```
Usuario ingresa el ID en "Seguimiento"
    │
    │  HTTP GET /orders/{idPedido}
    ▼
ALB → orders-service
    │  Busca en DynamoDB por el UUID
    │  Retorna el objeto completo con historial de estados
    ▼
Frontend muestra los estados con timestamps
```

---

## Flujo 3 — Cambiar estado (admin-service, solo tú lo ves en la demo)

```
Tú en CloudShell
    │
    │  curl PATCH localhost:8081/orders/{id}/status  ← port-forward, NO pasa por ALB
    ▼
admin-service (pod en EKS, servicio interno)
    │  1. Valida la transición de estado (máquina de estados)
    │  2. Actualiza DynamoDB con el nuevo estado
    │  3. Agrega entrada al historial con timestamp
    │  4. Publica en SQS para notificar el cambio
    ▼
DynamoDB actualizado → SQS → notifications-service (mismo flujo que arriba)
```

---

## Frase guía para contar en el demo

> *"La solicitud sale del browser, pasa por el ALB que es el único punto público, llega al orders-service que la persiste en DynamoDB. En ese momento DynamoDB dispara automáticamente un Stream que activa una Lambda — el orders-service no sabe nada de esto. La Lambda publica en SQS, y el notifications-service, que vive completamente separado, consume ese mensaje. Si el notifications-service cayera en este momento, los mensajes esperan en la cola hasta que vuelva. Ningún servicio habla directamente con otro — todo pasa por eventos."*
