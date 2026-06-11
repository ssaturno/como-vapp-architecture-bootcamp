"""
Orders Service — PoC implementation in Python/FastAPI
Production stack: .NET (see Dockerfile comment)

Environment variables:
  AWS_REGION            : AWS region (default: us-east-1)
  DYNAMODB_TABLE_NAME   : DynamoDB table name
  DYNAMODB_ENDPOINT     : Override endpoint for local development (leave unset in EKS)
  REQUEST_ID_HEADER     : Custom header carrying a correlation ID (optional)
"""

import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field

# ── Structured logger ─────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("orders-service")


def log(level: str, message: str, **extra) -> None:
    import json
    record = {"service": "orders-service", "severity": level, "message": message, **extra}
    logger.info(json.dumps(record, ensure_ascii=False))


# ── Config ────────────────────────────────────────────────────────────────────

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE_NAME = os.getenv("DYNAMODB_TABLE_NAME", "como-vapp-dev-orders")
DYNAMODB_ENDPOINT = os.getenv("DYNAMODB_ENDPOINT")  # None → real AWS


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


# ── DynamoDB client ───────────────────────────────────────────────────────────
# When DYNAMODB_ENDPOINT is set (local), boto3 uses it.
# When unset (EKS production), boto3 uses the real AWS endpoint + IRSA credentials.

session = boto3.session.Session()
dynamodb_resource = session.resource(
    "dynamodb",
    region_name=AWS_REGION,
    endpoint_url=DYNAMODB_ENDPOINT,
)
table = dynamodb_resource.Table(DYNAMODB_TABLE_NAME)

# ── Models ────────────────────────────────────────────────────────────────────


class ItemInput(BaseModel):
    producto: str
    cantidad: int = Field(gt=0)
    valor: int = Field(gt=0)


class ClienteInput(BaseModel):
    nombre: str
    correo: EmailStr


class CreateOrderRequest(BaseModel):
    cliente: ClienteInput
    direccion: str
    items: list[ItemInput]


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="orders-service", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup() -> None:
    if DYNAMODB_ENDPOINT:
        # Local mode: auto-create table if missing
        try:
            table.load()
        except ClientError as exc:
            error_code = exc.response.get("Error", {}).get("Code")
            if error_code != "ResourceNotFoundException":
                raise
            dynamodb_resource.create_table(
                TableName=DYNAMODB_TABLE_NAME,
                KeySchema=[{"AttributeName": "idPedido", "KeyType": "HASH"}],
                AttributeDefinitions=[{"AttributeName": "idPedido", "AttributeType": "S"}],
                BillingMode="PAY_PER_REQUEST",
            )
            dynamodb_resource.meta.client.get_waiter("table_exists").wait(
                TableName=DYNAMODB_TABLE_NAME
            )
    log("INFO", "orders-service started", table=DYNAMODB_TABLE_NAME, region=AWS_REGION)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "orders-service"}


@app.post("/orders", status_code=201)
def create_order(payload: CreateOrderRequest, request: Request) -> dict:
    request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))
    order_id = str(uuid.uuid4())
    created_at = now_iso()
    total = sum(item.cantidad * item.valor for item in payload.items)

    item = {
        "idPedido": order_id,
        "cliente": {"nombre": payload.cliente.nombre, "correo": payload.cliente.correo},
        "direccion": payload.direccion,
        "items": [
            {"producto": i.producto, "cantidad": i.cantidad, "valor": i.valor}
            for i in payload.items
        ],
        "total": total,
        "estado": "CREADO",
        "fechaCreacion": created_at,
        "fechaActualizacion": created_at,
        "historialEstados": [
            {
                "estadoAnterior": "N/A",
                "estadoNuevo": "CREADO",
                "timestamp": created_at,
                "origen": "ORDERS_SERVICE",
            }
        ],
    }

    try:
        table.put_item(Item=item)
    except ClientError as exc:
        log("ERROR", "DynamoDB write failed", requestId=request_id, error=str(exc))
        raise HTTPException(status_code=500, detail="Error al guardar el pedido")

    log("INFO", "Order created", requestId=request_id, idPedido=order_id, total=total)
    return {"idPedido": order_id, "estado": "CREADO", "fechaCreacion": created_at}


@app.get("/orders/{id_pedido}")
def get_order(id_pedido: str, request: Request) -> dict:
    request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))

    try:
        response = table.get_item(Key={"idPedido": id_pedido})
    except ClientError as exc:
        log("ERROR", "DynamoDB read failed", requestId=request_id, error=str(exc))
        raise HTTPException(status_code=500, detail="Error al consultar el pedido")

    order = response.get("Item")
    if not order:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")

    log("INFO", "Order retrieved", requestId=request_id, idPedido=id_pedido)
    return decimal_to_native(order)
