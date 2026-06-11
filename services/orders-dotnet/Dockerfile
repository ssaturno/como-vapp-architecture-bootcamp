# ──────────────────────────────────────────────────────────────────────────────
# orders-service — PoC implementation in Python/FastAPI
# Production target: .NET (mcr.microsoft.com/dotnet/aspnet)
# This Dockerfile uses Python for rapid prototyping only.
# ──────────────────────────────────────────────────────────────────────────────

FROM python:3.12-slim AS base

# Create a non-root user and group (Misión 2 Q7 — run containers as non-root)
RUN groupadd --system appgroup && useradd --system --gid appgroup --no-create-home appuser

WORKDIR /app

# Install dependencies as root, then switch to non-root for runtime
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Drop root privileges
USER appuser

EXPOSE 8080

# Use exec form to receive signals correctly and avoid PID 1 issues
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
