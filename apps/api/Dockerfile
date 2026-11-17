# Python base image
FROM python:3.11-slim

# Environment configuration
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# Working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy project configuration
COPY pyproject.toml README.md ./

# Copy backend source code
COPY apps ./apps

# Copy demo vault
COPY demo_vault ./demo_vault

# Install backend dependencies
RUN python -m pip install --upgrade pip && \
    pip install ".[postgres,redis,providers,parsers]"

# Create non-root user
RUN useradd --create-home appuser && \
    chown -R appuser:appuser /app

USER appuser

# Backend port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

# Start FastAPI
CMD ["uvicorn", "apps.api.src.main:app", "--host", "0.0.0.0", "--port", "8000"]