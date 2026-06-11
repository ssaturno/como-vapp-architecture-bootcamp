"""
Notifications Service — Python/FastAPI

Polls the SQS queue and delivers email notifications via SES (production) or
an outbox file (local development).

Environment variables:
  AWS_REGION          : AWS region (default: us-east-1)
  SQS_QUEUE_URL       : Full SQS queue URL (production)
  SQS_ENDPOINT        : Override for local development (leave unset in EKS)
  SQS_QUEUE_NAME      : Queue name — used only when SQS_ENDPOINT is set (local)
  SES_VERIFIED_SENDER : Verified SES sender address (required in production)
  USE_SES             : "true" to send real emails via SES; "false" for outbox file
  OUTBOX_FILE         : Path to the local outbox file (dev only)
"""

import json
import logging
import os
import threading
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI

# ── Structured logger ─────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("notifications-service")


def log(level: str, message: str, **extra) -> None:
    record = {
        "service": "notifications-service",
        "severity": level,
        "message": message,
        **extra,
    }
    logger.info(json.dumps(record, ensure_ascii=False))


# ── Config ────────────────────────────────────────────────────────────────────

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
SQS_ENDPOINT = os.getenv("SQS_ENDPOINT")
SQS_QUEUE_NAME = os.getenv("SQS_QUEUE_NAME", "notifications-local")
SES_VERIFIED_SENDER = os.getenv("SES_VERIFIED_SENDER", "")
USE_SES = os.getenv("USE_SES", "false").lower() == "true"
OUTBOX_FILE = Path(os.getenv("OUTBOX_FILE", "/tmp/outbox.jsonl"))


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── AWS clients ───────────────────────────────────────────────────────────────

session = boto3.session.Session()
sqs_client = session.client(
    "sqs",
    region_name=AWS_REGION,
    endpoint_url=SQS_ENDPOINT,
)
ses_client = session.client("ses", region_name=AWS_REGION)

app = FastAPI(title="notifications-service", version="0.1.0")
recent_notifications: deque = deque(maxlen=100)
stop_event = threading.Event()
worker_thread: threading.Thread | None = None
effective_queue_url: str | None = None

# ── Notification delivery ─────────────────────────────────────────────────────


def _send_via_ses(body: dict) -> None:
    correo = body.get("correoCliente", "")
    nombre = body.get("nombreCliente", "")
    estado = body.get("estadoPedido", "")
    id_pedido = body.get("idPedido", "")

    subject = f"[Como Vapp] Tu pedido {id_pedido} ahora está: {estado}"
    text_body = (
        f"Hola {nombre},\n\n"
        f"El estado de tu pedido {id_pedido} ha cambiado a: {estado}.\n\n"
        "Gracias por usar Como Vapp."
    )

    ses_client.send_email(
        Source=SES_VERIFIED_SENDER,
        Destination={"ToAddresses": [correo]},
        Message={
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {"Text": {"Data": text_body, "Charset": "UTF-8"}},
        },
    )


def _save_to_outbox(record: dict) -> None:
    OUTBOX_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTBOX_FILE.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=True) + "\n")


def process_message(message: dict) -> None:
    body = json.loads(message["Body"])
    status = "unknown"

    if USE_SES and SES_VERIFIED_SENDER:
        try:
            _send_via_ses(body)
            status = "sent_ses"
        except ClientError as exc:
            log("ERROR", "SES send failed", error=str(exc), idPedido=body.get("idPedido"))
            status = "ses_error"
    else:
        status = "sent_local_simulated"

    record = {
        "processedAt": now_iso(),
        "channel": "email",
        "status": status,
        "payload": body,
    }

    if not USE_SES:
        _save_to_outbox(record)

    recent_notifications.appendleft(record)
    log(
        "INFO",
        "Notification processed",
        idPedido=body.get("idPedido"),
        correo=body.get("correoCliente"),
        estado=body.get("estadoPedido"),
        status=status,
    )


# ── SQS polling loop ──────────────────────────────────────────────────────────


def poll_queue() -> None:
    while not stop_event.is_set():
        if not effective_queue_url:
            time.sleep(1)
            continue

        try:
            response = sqs_client.receive_message(
                QueueUrl=effective_queue_url,
                MaxNumberOfMessages=5,
                WaitTimeSeconds=10,
                VisibilityTimeout=30,
            )
        except ClientError as exc:
            log("ERROR", "SQS receive failed", error=str(exc))
            time.sleep(5)
            continue

        for message in response.get("Messages", []):
            try:
                process_message(message)
                sqs_client.delete_message(
                    QueueUrl=effective_queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )
            except Exception as exc:  # noqa: BLE001
                log("ERROR", "Message processing failed", error=str(exc))


# ── FastAPI lifecycle ─────────────────────────────────────────────────────────


@app.on_event("startup")
def startup() -> None:
    global effective_queue_url, worker_thread

    if SQS_ENDPOINT:
        # Local mode — create queue in ElasticMQ if needed
        sqs_client.create_queue(QueueName=SQS_QUEUE_NAME)
        effective_queue_url = sqs_client.get_queue_url(QueueName=SQS_QUEUE_NAME)["QueueUrl"]
    elif SQS_QUEUE_URL:
        effective_queue_url = SQS_QUEUE_URL
    else:
        log("WARN", "No SQS_QUEUE_URL configured — polling disabled")

    stop_event.clear()
    worker_thread = threading.Thread(target=poll_queue, daemon=True)
    worker_thread.start()

    log(
        "INFO",
        "notifications-service started",
        queueUrl=effective_queue_url,
        useSES=USE_SES,
    )


@app.on_event("shutdown")
def shutdown() -> None:
    stop_event.set()
    if worker_thread and worker_thread.is_alive():
        worker_thread.join(timeout=3)


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "service": "notifications-service",
        "queueConnected": bool(effective_queue_url),
        "sesEnabled": USE_SES,
    }


@app.get("/notifications")
def get_notifications() -> dict:
    return {"count": len(recent_notifications), "items": list(recent_notifications)}
