FROM python:3.11-slim

WORKDIR /app

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

# ── Layer-cached dependency install ──────────────────────────────────────────
# Copy only the manifest first so this layer rebuilds only when deps change.
COPY pyproject.toml .

# Install all runtime dependencies without building the local package.
# `--no-build-isolation` + pointing pip at the dependency list lets us skip
# needing the source tree at this stage.
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
        "fastapi==0.115.5" \
        "uvicorn[standard]==0.32.1" \
        "python-multipart==0.0.12" \
        "sqlalchemy[asyncio]==2.0.36" \
        "asyncpg==0.30.0" \
        "psycopg2-binary==2.9.10" \
        "alembic==1.14.0" \
        "pydantic==2.10.3" \
        "pydantic-settings==2.6.1" \
        "email-validator==2.2.0" \
        "python-jose[cryptography]==3.3.0" \
        "passlib[bcrypt]==1.7.4" \
        "bcrypt>=4.0,<5" \
        "cryptography==43.0.3" \
        "qrcode[pil]==8.0" \
        "Pillow==11.0.0" \
        "httpx==0.28.1" \
        "google-generativeai==0.8.3" \
        "celery[redis]==5.4.0" \
        "redis==5.2.1" \
        "flower==2.0.1" \
        "twilio==9.3.7" \
        "numpy==2.2.0" \
        "scipy==1.14.1" \
        "pandas==2.2.3" \
        "python-dateutil==2.9.0.post0" \
        "structlog==24.4.0" \
        "tenacity==9.0.0"

# ── Application source ────────────────────────────────────────────────────────
COPY . .

# Register the local package (no dep re-download needed)
RUN pip install --no-cache-dir --no-deps -e .

# Create uploads dir
RUN mkdir -p /app/uploads

EXPOSE 8000
