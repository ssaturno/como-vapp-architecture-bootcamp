# Plan de Implementación Express (4 horas)

## Objetivo
Entregar un PoC híbrido funcional de Como_Vapp con evidencia técnica demostrable, manteniendo EKS como componente obligatorio y respetando restricciones de AWS Academy y presupuesto.

## Alcance del PoC
- Flujo funcional: crear pedido, consultar pedido, actualizar estado, emitir evento y notificar por email.
- Estados mínimos: CREADO, EN_PROGRESO, ENTREGADO, CANCELADO.
- Arquitectura lógica: Frontend React + servicios de pedidos (.NET), administración (Kotlin), notificaciones (Python).
- Despliegue mínimo AWS: EKS + 1 servicio backend + DynamoDB + SQS + SES.
- Réplicas demo: 1 réplica temporal con justificación de costo/tiempo.

## Bloque 1 (0:00-0:30) - Preparación
1. Congelar alcance y exclusiones (sin pagos, sin mapas, sin autenticación).
2. Confirmar prerequisitos de entorno y acceso AWS Academy.
3. Validar configuración mínima para SES sandbox con correos verificados.

Evidencia esperada:
- Alcance final documentado.
- Checklist de prerequisitos en estado OK.
- Lista de endpoints de demo.

## Bloque 2 (0:30-1:45) - Flujo funcional local
1. Levantar servicios localmente (rápido, con enfoque en integración).
2. Probar API de pedidos: crear y consultar.
3. Probar API de administración: actualizar estado.
4. Verificar evento y consumo por servicio de notificaciones.

Evidencia esperada:
- Request/response de endpoints críticos.
- Registro en base de datos del pedido y cambios de estado.
- Evidencia de evento en cola/consumo.
- Evidencia de notificación enviada (correo o log de envío exitoso).

## Bloque 3 (1:45-2:45) - Infraestructura mínima con Terraform
1. Provisionar recursos mínimos del PoC híbrido.
2. Desplegar un backend en EKS y validar conectividad a servicios administrados.
3. Validar estado de pods y servicio.

Evidencia esperada:
- Salida de terraform init/plan/apply.
- Estado Running/Ready del pod.
- Prueba de conectividad a DynamoDB/SQS/SES.
- Nota de justificación de costo por configuración mínima.

## Bloque 4 (2:45-3:30) - Observabilidad y resiliencia
1. Activar/validar logs estructurados con requestId.
2. Mostrar dashboard básico (pods, latencia, errores).
3. Simular caída del notificador y validar cola + recuperación.

Evidencia esperada:
- Muestra de logs JSON.
- Captura de dashboard con al menos 2 métricas.
- Secuencia de resiliencia: antes, durante, después.

## Bloque 5 (3:30-4:00) - Cierre de presentación
1. Preparar narrativa de demo (problema, solución, arquitectura, trade-offs).
2. Consolidar evidencia técnica en un solo paquete.
3. Grabar o dejar lista la demo de 5-10 minutos.

Evidencia esperada:
- Slides finalizadas.
- Guion de demo paso a paso.
- Resumen de costo estimado + limitaciones AWS Academy.
- Video demo o plan de grabación inmediato.

## Criterios de éxito
1. Flujo funcional completo comprobado.
2. Despliegue mínimo en AWS comprobado.
3. Prueba de resiliencia comprobada.
4. Logs y dashboard mostrables.
5. Material de presentación listo para exposición.
