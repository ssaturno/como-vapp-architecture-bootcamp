# Contratos mínimos API y eventos (PoC)

## Estados válidos de pedido
- CREADO
- EN_PROGRESO
- ENTREGADO
- CANCELADO

## API - Servicio de pedidos (.NET)
### POST /orders
Request:
```json
{
  "cliente": {
    "nombre": "string",
    "correo": "string"
  },
  "direccion": "string",
  "items": [
    {
      "producto": "string",
      "cantidad": 1,
      "valor": 1000
    }
  ]
}
```
Response 201:
```json
{
  "idPedido": "uuid",
  "estado": "CREADO",
  "fechaCreacion": "2026-06-08T19:00:00Z"
}
```

### GET /orders/{idPedido}
Response 200:
```json
{
  "idPedido": "uuid",
  "cliente": {
    "nombre": "string",
    "correo": "string"
  },
  "direccion": "string",
  "items": [],
  "total": 1000,
  "estado": "EN_PROGRESO",
  "fechaCreacion": "2026-06-08T19:00:00Z",
  "fechaActualizacion": "2026-06-08T19:10:00Z"
}
```

## API - Servicio de administración (Kotlin)
### PATCH /orders/{idPedido}/status
Request:
```json
{
  "estadoNuevo": "ENTREGADO",
  "origen": "CLIENTE"
}
```
Response 200:
```json
{
  "idPedido": "uuid",
  "estadoAnterior": "EN_PROGRESO",
  "estadoNuevo": "ENTREGADO",
  "timestamp": "2026-06-08T19:15:00Z"
}
```

## Evento de cambio de estado
Topic/cola sugerida: SQS notifications

Payload:
```json
{
  "idPedido": "uuid",
  "correoCliente": "cliente@correo.com",
  "nombreCliente": "Nombre",
  "estadoPedido": "ENTREGADO",
  "timestamp": "2026-06-08T19:15:00Z",
  "origen": "ADMIN_SERVICE"
}
```

## Reglas mínimas de transición
- CREADO -> EN_PROGRESO
- EN_PROGRESO -> ENTREGADO
- CREADO -> CANCELADO
- EN_PROGRESO -> CANCELADO
- No se permiten cambios desde ENTREGADO o CANCELADO.
