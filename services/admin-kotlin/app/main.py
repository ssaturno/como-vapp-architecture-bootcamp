"""
Admin Service — PoC implementation in Python/FastAPI
Production stack: Kotlin/Spring Boot (see Dockerfile comment)

Environment variables:
  AWS_REGION          : AWS region (default: us-east-1)
  DYNAMODB_TABLE_NAME : DynamoDB table name
  DYNAMODB_ENDPOINT   : Override for local development (leave unset in EKS)
  SQS_QUEUE_URL       : Full SQS queue URL
  SQS_ENDPOINT        : Override for local development (leave unset in EKS)
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

# ── Structured logger ─────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("admin-service")


def log(level: str, message: str, **extra) -> None:
    import json as _json
    record = {"service": "admin-service", "severity": level, "message": message, **extra}
    logger.info(_json.dumps(record, ensure_ascii=False))


# ── Config ────────────────────────────────────────────────────────────────────

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE_NAME = os.getenv("DYNAMODB_TABLE_NAME", "como-vapp-dev-orders")
DYNAMODB_ENDPOINT = os.getenv("DYNAMODB_ENDPOINT")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
SQS_ENDPOINT = os.getenv("SQS_ENDPOINT")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def decimal_to_native(value):
    if isinstance(value, list):
        return [decimal_to_native(item) for item in value]
    if isinstance(value, dict):
        return {k: decimal_to_native(v) for k, v in value.items()}
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return value


ALLOWED_TRANSITIONS = {
    "CREADO": {"EN_PROGRESO", "CANCELADO"},
    "EN_PROGRESO": {"ENTREGADO", "CANCELADO"},
    "ENTREGADO": set(),
    "CANCELADO": set(),
}

# ── AWS clients ───────────────────────────────────────────────────────────────

session = boto3.session.Session()
dynamodb_resource = session.resource(
    "dynamodb",
    region_name=AWS_REGION,
    endpoint_url=DYNAMODB_ENDPOINT,
)
sqs_client = session.client(
    "sqs",
    region_name=AWS_REGION,
    endpoint_url=SQS_ENDPOINT,
)
table = dynamodb_resource.Table(DYNAMODB_TABLE_NAME)

# ── Models ────────────────────────────────────────────────────────────────────


class StatusUpdateRequest(BaseModel):
    estadoNuevo: str
    origen: str = "CLIENTE"


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="admin-service", version="0.1.0")


@app.on_event("startup")
def startup() -> None:
    if DYNAMODB_ENDPOINT:
        # Local mode: auto-create table + queue if missing
        try:
            table.load()
        except ClientError as exc:
            error_code = exc.response.get("Error", {}).get("Code")
            if error_code != "ResourceNotFoundException":
                raise
            try:
                dynamodb_resource.create_table(
                    TableName=DYNAMODB_TABLE_NAME,
                    KeySchema=[{"AttributeName": "idPedido", "KeyType": "HASH"}],
                    AttributeDefinitions=[
                        {"AttributeName": "idPedido", "AttributeType": "S"}
                    ],
                    BillingMode="PAY_PER_REQUEST",
                )
                dynamodb_resource.meta.client.get_waiter("table_exists").wait(
                    TableName=DYNAMODB_TABLE_NAME
                )
            except ClientError as create_exc:
                if create_exc.response.get("Error", {}).get("Code") != "ResourceInUseException":
                    raise

        if SQS_ENDPOINT:
            local_queue_name = SQS_QUEUE_URL.split("/")[-1] if SQS_QUEUE_URL else "notifications-local"
            sqs_client.create_queue(QueueName=local_queue_name)

    log("INFO", "admin-service started", table=DYNAMODB_TABLE_NAME, region=AWS_REGION)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "admin-service"}


@app.patch("/orders/{id_pedido}/status")
def update_status(id_pedido: str, payload: StatusUpdateRequest, request: Request) -> dict:
    request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))

    try:
        response = table.get_item(Key={"idPedido": id_pedido})
    except ClientError as exc:
        log("ERROR", "DynamoDB read failed", requestId=request_id, error=str(exc))
        raise HTTPException(status_code=500, detail="Error al consultar el pedido")

    current_order = response.get("Item")
    if not current_order:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")

    current_status = current_order["estado"]
    next_status = payload.estadoNuevo.upper()

    if next_status not in ALLOWED_TRANSITIONS.get(current_status, set()):
        raise HTTPException(
            status_code=400,
            detail=f"Transicion invalida: {current_status} -> {next_status}",
        )

    timestamp = now_iso()
    history = current_order.get("historialEstados", [])
    history.append(
        {
            "estadoAnterior": current_status,
            "estadoNuevo": next_status,
            "timestamp": timestamp,
            "origen": payload.origen,
        }
    )

    current_order["estado"] = next_status
    current_order["fechaActualizacion"] = timestamp
    current_order["historialEstados"] = history

    try:
        table.put_item(Item=current_order)
    except ClientError as exc:
        log("ERROR", "DynamoDB write failed", requestId=request_id, error=str(exc))
        raise HTTPException(status_code=500, detail="Error al actualizar el pedido")

    event_payload = {
        "idPedido": id_pedido,
        "correoCliente": current_order["cliente"]["correo"],
        "nombreCliente": current_order["cliente"]["nombre"],
        "estadoPedido": next_status,
        "timestamp": timestamp,
        "origen": "ADMIN_SERVICE",
    }

    if SQS_QUEUE_URL:
        try:
            sqs_client.send_message(
                QueueUrl=SQS_QUEUE_URL, MessageBody=json.dumps(event_payload)
            )
            log(
                "INFO",
                "Status updated and event queued",
                requestId=request_id,
                idPedido=id_pedido,
                estadoAnterior=current_status,
                estadoNuevo=next_status,
            )
        except ClientError as exc:
            # Log the error but don't fail the request — DynamoDB Streams → Lambda
            # will pick up the change and enqueue the event as a fallback.
            log(
                "WARN",
                "SQS send failed — stream processor will retry",
                requestId=request_id,
                error=str(exc),
            )

    return decimal_to_native(
        {
            "idPedido": id_pedido,
            "estadoAnterior": current_status,
            "estadoNuevo": next_status,
            "timestamp": timestamp,
            "eventoPublicado": bool(SQS_QUEUE_URL),
        }
    )
