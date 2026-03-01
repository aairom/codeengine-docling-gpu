# ============================================================
# DoclingGPU - Web Application Dockerfile
# IBM Code Engine Serverless Application
# ============================================================

FROM python:3.11-slim AS base

# Build arguments
ARG BUILD_DATE
ARG VERSION=1.0.0

# Labels
LABEL org.opencontainers.image.title="DoclingGPU Web App" \
      org.opencontainers.image.description="IBM Code Engine Serverless Document Processing with Docling" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/IBM/CodeEngine"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser -u 1001 appuser

# Set working directory
WORKDIR /app

# Install Python dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=appuser:appuser . .

# Create required directories
RUN mkdir -p /tmp/uploads /tmp/outputs /app/input /app/output && \
    chown -R appuser:appuser /tmp/uploads /tmp/outputs /app/input /app/output

# Switch to non-root user
USER appuser

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    PROCESSING_MODE=local \
    UPLOAD_FOLDER=/tmp/uploads \
    OUTPUT_FOLDER=/tmp/outputs \
    LOCAL_INPUT_FOLDER=/app/input \
    LOCAL_OUTPUT_FOLDER=/app/output \
    FLASK_ENV=production

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start with gunicorn for production
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "2", \
     "--worker-class", "gevent", \
     "--worker-connections", "100", \
     "--timeout", "300", \
     "--keep-alive", "5", \
     "--log-level", "info", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]