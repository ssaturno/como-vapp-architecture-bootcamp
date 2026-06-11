# ──────────────────────────────────────────────────────────────────────────────
# admin-service — PoC implementation in Python/FastAPI
# Production target: Kotlin/Spring Boot (eclipse-temurin:21-jre-alpine)
# This Dockerfile uses Python for rapid prototyping only.
# ──────────────────────────────────────────────────────────────────────────────

FROM python:3.12-slim AS base

# Non-root user (Misión 2 Q7)
RUN groupadd --system appgroup && useradd --system --gid appgroup --no-create-home appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

USER appuser

EXPOSE 8081

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8081", "--no-access-log"]
