# ──────────────────────────────────────────────────────────────────────────────
# notifications-service — Python/FastAPI
# ──────────────────────────────────────────────────────────────────────────────

FROM python:3.12-slim AS base

# Non-root user (Misión 2 Q7)
RUN groupadd --system appgroup && useradd --system --gid appgroup --no-create-home appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# /tmp is writable by all users; the outbox file goes there in production.
# In local dev the /app/data volume is mounted — uvicorn creates it if missing.
USER appuser

EXPOSE 8082

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8082", "--no-access-log"]
