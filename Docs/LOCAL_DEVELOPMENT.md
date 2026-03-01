# DoclingGPU — Local Development Guide

> Complete guide for running DoclingGPU on your local machine for development and testing.

---

## Table of Contents

1. [System Requirements](#1-system-requirements)
2. [Quick Start](#2-quick-start)
3. [Python Virtual Environment Setup](#3-python-virtual-environment-setup)
4. [Docker Development Setup](#4-docker-development-setup)
5. [GPU Setup (Optional)](#5-gpu-setup-optional)
6. [Processing Documents Locally](#6-processing-documents-locally)
7. [Development Workflow](#7-development-workflow)
8. [Testing](#8-testing)
9. [Configuration Reference](#9-configuration-reference)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. System Requirements

### Minimum Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | macOS 12+, Ubuntu 20.04+, Windows 11 (WSL2) | Ubuntu 22.04 LTS |
| CPU | 4 cores | 8+ cores |
| RAM | 8 GB | 16+ GB |
| Disk | 10 GB free | 50+ GB free |
| Python | 3.11 | 3.11 |
| Docker | 24.0+ | Latest |

### GPU Requirements (Optional)

| GPU | Driver | CUDA | Notes |
|-----|--------|------|-------|
| NVIDIA (any) | 525+ | 12.0+ | Full GPU acceleration |
| Apple M1/M2/M3 | macOS 13+ | N/A | MPS acceleration |
| AMD (ROCm) | ROCm 5.6+ | N/A | Experimental |

### Software Dependencies

```bash
# Check Python version
python3 --version  # Must be 3.11+

# Check Docker
docker --version   # Must be 24.0+
docker compose version  # Must be 2.x

# Check Git
git --version
```

---

## 2. Quick Start

### Using the Local Run Script (Easiest)

```bash
# Clone the repository
git clone https://github.com/YOUR_ORG/codeengine-docling-gpu.git
cd codeengine-docling-gpu

# Make scripts executable
chmod +x Scripts/*.sh

# Option 1: Run with Python venv (fastest startup)
./Scripts/local-run.sh --mode python

# Option 2: Run with Docker
./Scripts/local-run.sh --mode docker

# Option 3: Run with Docker + GPU (requires NVIDIA GPU)
./Scripts/local-run.sh --mode docker-gpu

# Option 4: Run worker only (process documents directly)
./Scripts/local-run.sh --mode worker

# Open the web UI
open http://localhost:8080
```

### Place Documents for Processing

```bash
# Copy your PDFs to the input folder
cp /path/to/your/documents/*.pdf input/

# The web UI will show these files for processing
# Results will appear in output/ as timestamped Markdown files
```

---

## 3. Python Virtual Environment Setup

### Create and Activate Virtual Environment

```bash
# Create virtual environment
python3.11 -m venv .venv

# Activate (macOS/Linux)
source .venv/bin/activate

# Activate (Windows)
.venv\Scripts\activate

# Verify activation
which python  # Should show .venv/bin/python
```

### Install Dependencies

```bash
# Install web application dependencies
pip install -r app/requirements.txt

# Install worker dependencies (includes Docling)
pip install -r worker/requirements.txt

# For development (linting, testing)
pip install flake8 pytest pytest-cov black isort
```

### Run the Web Application

```bash
# Set environment variables
export FLASK_ENV=development
export FLASK_DEBUG=1
export SECRET_KEY="dev-secret-key-not-for-production"
# Use absolute paths — the Flask app runs from ./app/, so relative paths
# like ./input would resolve to ./app/input instead of the project root.
export LOCAL_INPUT_FOLDER="$(pwd)/input"
export LOCAL_OUTPUT_FOLDER="$(pwd)/output"
export PORT=8080

# Run Flask development server
cd app
python app.py

# OR with gunicorn (production-like)
gunicorn --bind 0.0.0.0:8080 \
  --workers 2 \
  --worker-class gevent \
  --timeout 300 \
  app:app
```

### Run the Worker Directly

```bash
# Activate venv
source .venv/bin/activate

# Process a single document
python worker/worker.py \
  --input input/document.pdf \
  --output output/ \
  --mode cpu

# Process all documents in a folder (all Docling-supported formats auto-detected)
python worker/worker.py \
  --input input/ \
  --output output/ \
  --mode cpu

# With GPU (if available)
python worker/worker.py \
  --input input/ \
  --output output/ \
  --mode gpu

# Check output
ls -la output/
cat output/document_*.md
```

---

## 4. Docker Development Setup

### Build Images Locally

```bash
# Build the web application image
docker build -t doclinggpu-webapp:dev ./app/

# Build the worker image (CPU version for local dev)
docker build -t doclinggpu-worker:dev \
  -f worker/Dockerfile.gpu ./worker/

# Verify images
docker images | grep doclinggpu
```

### Run with Docker Compose

```bash
# Start the web application only
docker compose up webapp

# Start with CPU worker
docker compose --profile cpu-worker up

# Start with GPU worker (requires NVIDIA Docker runtime)
docker compose --profile gpu-worker up

# Run in background
docker compose up -d webapp

# View logs
docker compose logs -f webapp

# Stop all services
docker compose down

# Stop and remove volumes
docker compose down -v
```

### Docker Compose Profiles

| Profile | Services | Use Case |
|---------|----------|----------|
| (default) | `webapp` | Web UI only, local processing |
| `cpu-worker` | `webapp` + `cpu-worker` | Test CPU fleet locally |
| `gpu-worker` | `webapp` + `gpu-worker` | Test GPU fleet locally |

### Environment File for Docker

Create a `.env` file in the project root:

```bash
# .env (do not commit to git!)
SECRET_KEY=dev-secret-key-change-in-production
FLASK_ENV=development
PORT=8080
LOCAL_INPUT_FOLDER=/app/input
LOCAL_OUTPUT_FOLDER=/app/output

# Optional: IBM Cloud credentials for fleet mode testing
# IBMCLOUD_API_KEY=your-api-key
# CE_PROJECT_NAME=doclinggpu-project
# CE_REGION=eu-de
```

---

## 5. GPU Setup (Optional)

### NVIDIA GPU Setup (Linux)

```bash
# Check NVIDIA driver
nvidia-smi

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# Verify GPU access in Docker
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

### NVIDIA GPU Setup (macOS)

NVIDIA GPUs are not supported on macOS. Use Apple Silicon MPS instead.

### Apple Silicon MPS Setup (macOS)

```bash
# MPS is automatically detected on Apple Silicon
# No additional setup required

# Verify MPS availability
python3 -c "import torch; print(torch.backends.mps.is_available())"
# Should print: True

# Run worker with MPS
python worker/worker.py \
  --input input/ \
  --output output/ \
  --mode gpu  # Will auto-detect MPS
```

### Verify GPU Detection

```bash
# Run the worker with verbose output
python worker/worker.py \
  --input input/test.pdf \
  --output output/ \
  --mode gpu \
  --verbose

# Expected output:
# [INFO] Checking GPU availability...
# [INFO] CUDA available: True (or MPS available: True)
# [INFO] Using device: cuda (or mps)
# [INFO] GPU: NVIDIA GeForce RTX 3080 (or Apple M2)
```

### GPU Memory Requirements

| Document Type | Pages | GPU Memory |
|---------------|-------|------------|
| Simple text PDF | 10 | ~1 GB |
| Complex PDF (tables) | 50 | ~4 GB |
| Large PDF (images) | 200 | ~8 GB |
| Batch (10 PDFs) | 500 total | ~12 GB |

---

## 6. Processing Documents Locally

### Via Web UI

1. Open `http://localhost:8080`
2. Drag and drop PDF files onto the upload area
3. Select processing mode: **Local (CPU/GPU)**
4. Click **Process Documents**
5. Monitor progress in the **Job Monitor** section
6. Download results as ZIP when complete

### Via Folder Path (Batch)

1. Place documents in `input/` folder
2. In the web UI, enter the folder path: `./input`
3. Select processing mode
4. Click **Process Folder**

### Via Command Line

```bash
# Single file
python worker/worker.py \
  --input input/report.pdf \
  --output output/

# Entire folder (all Docling-supported formats are processed automatically)
python worker/worker.py \
  --input input/ \
  --output output/

# Force GPU mode
python worker/worker.py \
  --input input/ \
  --output output/ \
  --mode gpu

# Force CPU mode
python worker/worker.py \
  --input input/ \
  --output output/ \
  --mode cpu
```

### Output Files

Results are saved to `output/` with timestamps:

```
output/
├── report_20240115_143022.md          # Converted document
├── presentation_20240115_143045.md    # Converted document
└── processing_summary_task0.json      # Processing metadata
```

**Markdown output format:**

```markdown
---
source_file: report.pdf
processed_at: 2024-01-15T14:30:22Z
processing_mode: local
gpu_used: true
gpu_device: cuda
processing_time_seconds: 8.3
page_count: 24
file_size_bytes: 1048576
docling_version: 2.x.x
---

# Report Title

## Executive Summary

Content extracted from the PDF...
```

---

## 7. Development Workflow

### Project Structure for Development

```
codeengine-docling-gpu/
├── app/
│   ├── app.py          ← Main Flask app (edit this)
│   ├── templates/
│   │   └── index.html  ← UI template (edit this)
│   └── static/
│       ├── css/style.css  ← Styles (edit this)
│       └── js/app.js      ← Frontend JS (edit this)
├── worker/
│   └── worker.py       ← Docling worker (edit this)
├── input/              ← Place test PDFs here
└── output/             ← Results appear here
```

### Hot Reload Development

```bash
# Flask auto-reloads on file changes
export FLASK_DEBUG=1
cd app && python app.py

# Watch for changes in templates/static
# Flask will automatically reload when you save files
```

### Making Changes to the Worker

```bash
# Test worker changes directly
python worker/worker.py \
  --input input/test.pdf \
  --output output/ \
  --mode cpu

# Check output
cat output/test_*.md
```

### Code Style

```bash
# Format code with Black
black app/app.py worker/worker.py

# Sort imports
isort app/app.py worker/worker.py

# Lint with flake8
flake8 app/ worker/ --max-line-length=120

# Type checking (optional)
mypy app/app.py worker/worker.py
```

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes...

# Stage and commit
git add .
git commit -m "feat: add my feature"

# Push to GitHub (excludes _* folders)
./Scripts/push-to-github.sh

# OR push manually
git push origin feature/my-feature
```

---

## 8. Testing

### Unit Tests

```bash
# Run all tests
python -m pytest tests/ -v

# Run with coverage
python -m pytest tests/ --cov=app --cov=worker --cov-report=html

# Run specific test file
python -m pytest tests/test_worker.py -v
```

### Manual API Testing

```bash
# Health check
curl http://localhost:8080/health

# Upload a document
curl -X POST http://localhost:8080/upload \
  -F "files=@input/test.pdf" \
  -F "mode=local"

# Check job status
curl http://localhost:8080/job/JOB_ID

# List all jobs
curl http://localhost:8080/jobs

# Get configuration
curl http://localhost:8080/config
```

### Integration Test: Full Pipeline

```bash
# 1. Start the application
./Scripts/local-run.sh --mode python &

# 2. Wait for startup
sleep 5

# 3. Upload a test document
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/upload \
  -F "files=@input/bob-docs_v3.pdf" \
  -F "mode=local")

JOB_ID=$(echo $JOB_RESPONSE | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")
echo "Job ID: $JOB_ID"

# 4. Poll until complete
while true; do
  STATUS=$(curl -s http://localhost:8080/job/$JOB_ID | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  echo "Status: $STATUS"
  if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
    break
  fi
  sleep 3
done

# 5. Download results
curl -o results.zip http://localhost:8080/job/$JOB_ID/download
unzip results.zip -d results/
ls results/
```

---

## 9. Configuration Reference

### Flask Application (`app/app.py`)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP server port |
| `SECRET_KEY` | auto | Flask session secret |
| `UPLOAD_FOLDER` | `/tmp/uploads` | Temp upload directory |
| `OUTPUT_FOLDER` | `/tmp/outputs` | Temp output directory |
| `LOCAL_INPUT_FOLDER` | `./input` | Local input folder — use an absolute path when running manually (the Flask app runs from `./app/`, so relative paths resolve relative to that directory) |
| `LOCAL_OUTPUT_FOLDER` | `./output` | Local output folder — same absolute path recommendation applies |
| `PROCESSING_MODE` | `local` | Default processing mode |
| `MAX_CONTENT_LENGTH` | `500MB` | Max upload size |

### Worker (`worker/worker.py`)

| Argument | Default | Description |
|----------|---------|-------------|
| `--input` | required | Input file or folder — all Docling-supported formats are detected automatically |
| `--output` | required | Output folder |
| `--mode` | `auto` | `auto`, `cpu`, `gpu` |
| `--task-index` | `0` | Fleet task index |
| `--verbose` | `false` | Verbose logging |

### Docker Compose

| Service | Port | Profile | Description |
|---------|------|---------|-------------|
| `webapp` | `8080` | default | Flask web application |
| `cpu-worker` | - | `cpu-worker` | CPU Docling worker |
| `gpu-worker` | - | `gpu-worker` | GPU Docling worker |

---

## 10. Troubleshooting

### Port Already in Use

```bash
# Find process using port 8080
lsof -i :8080
# or
ss -tlnp | grep 8080

# Kill the process
kill -9 PID

# Or use a different port
PORT=8081 python app/app.py
```

### Docling Import Errors

```bash
# Reinstall Docling
pip uninstall docling docling-core docling-ibm-models -y
pip install docling

# Check installation
python -c "import docling; print(docling.__version__)"
```

### Out of Memory During Processing

```bash
# Reduce batch size (process fewer files at once)
python worker/worker.py \
  --input input/single_file.pdf \
  --output output/ \
  --mode cpu

# Force CPU mode (uses less memory than GPU)
python worker/worker.py \
  --input input/ \
  --output output/ \
  --mode cpu
```

### Docker Build Fails

```bash
# Clear Docker cache
docker system prune -a

# Build with no cache
docker build --no-cache -t doclinggpu-webapp:dev ./app/

# Check Docker disk space
docker system df
```

### GPU Not Detected

```bash
# Check NVIDIA driver
nvidia-smi

# Check CUDA in Python
python3 -c "import torch; print(torch.cuda.is_available())"

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi

# Restart Docker daemon
sudo systemctl restart docker
```

### Slow Processing

Processing speed depends on:
- **Document complexity**: Tables and images take longer
- **GPU availability**: GPU is 5-10x faster than CPU
- **Document size**: More pages = more time

Expected processing times (CPU):
- Simple 10-page PDF: ~30 seconds
- Complex 50-page PDF: ~3 minutes
- Large 200-page PDF: ~15 minutes

Expected processing times (GPU L40s):
- Simple 10-page PDF: ~5 seconds
- Complex 50-page PDF: ~30 seconds
- Large 200-page PDF: ~2 minutes

---

For deployment to IBM Cloud, see [DEPLOYMENT.md](./DEPLOYMENT.md).
For API reference, see [API.md](./API.md).
For architecture overview, see [ARCHITECTURE.md](./ARCHITECTURE.md).