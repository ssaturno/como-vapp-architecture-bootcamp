"""
Lambda handler — DynamoDB Streams → SQS

Triggered by every INSERT or MODIFY on the orders table.
Extracts the relevant fields from the DynamoDB record (NewImage),
formats a notification event, and enqueues it on the SQS notifications queue.

Environment variables (set by Terraform):
  SQS_QUEUE_URL  : URL of the notifications SQS queue
  AWS_REGION     : AWS region (e.g. us-east-1)
"""

import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

sqs = boto3.client("sqs", region_name=AWS_REGION)


def _extract_str(dynamo_value: dict) -> str:
    """Return the string value from a DynamoDB typed attribute."""
    return dynamo_value.get("S", "")


def _extract_map(dynamo_value: dict) -> dict:
    """Return the map value from a DynamoDB typed attribute."""
    return dynamo_value.get("M", {})


def handler(event, context):  # noqa: ARG001
    sent = 0

    for record in event.get("Records", []):
        event_name = record.get("eventName", "")
        if event_name not in ("INSERT", "MODIFY"):
            continue

        new_image = record.get("dynamodb", {}).get("NewImage", {})
        if not new_image:
            logger.warning("Record %s has no NewImage — skipping", record.get("eventID"))
            continue

        id_pedido = _extract_str(new_image.get("idPedido", {}))
        estado = _extract_str(new_image.get("estado", {}))
        timestamp = _extract_str(new_image.get("fechaActualizacion", {}))
        cliente = _extract_map(new_image.get("cliente", {}))
        correo = _extract_str(cliente.get("correo", {}))
        nombre = _extract_str(cliente.get("nombre", {}))

        payload = {
            "idPedido": id_pedido,
            "correoCliente": correo,
            "nombreCliente": nombre,
            "estadoPedido": estado,
            "timestamp": timestamp,
            "origen": "DYNAMO_STREAM",
        }

        sqs.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=json.dumps(payload))

        logger.info(
            "Event queued",
            extra={"idPedido": id_pedido, "estado": estado, "eventName": event_name},
        )
        sent += 1

    logger.info("Processed %d records, sent %d messages", len(event.get("Records", [])), sent)
    return {"statusCode": 200, "sent": sent}
