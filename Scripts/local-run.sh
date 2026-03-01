#!/bin/bash
# ============================================================
# DoclingGPU - Local Run Script
# Runs the application locally for development/testing
# ============================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_step()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ============================================================
# Configuration
# ============================================================
MODE="${MODE:-local}"          # local | docker | docker-gpu
PORT="${PORT:-8080}"
VENV_DIR="${VENV_DIR:-.venv}"
INPUT_DIR="${INPUT_DIR:-./input}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)     MODE="$2"; shift 2 ;;
        --port)     PORT="$2"; shift 2 ;;
        --docker)   MODE="docker"; shift ;;
        --gpu)      MODE="docker-gpu"; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --mode MODE    Run mode: local|docker|docker-gpu (default: local)"
            echo "  --port PORT    Port to listen on (default: 8080)"
            echo "  --docker       Use Docker (CPU)"
            echo "  --gpu          Use Docker with GPU"
            exit 0
            ;;
        *) log_error "Unknown option: $1" ;;
    esac
done

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  DoclingGPU - Local Run                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure input/output directories exist
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"

# ============================================================
# Mode: Local Python (no Docker)
# ============================================================
run_local() {
    log_step "Running locally with Python"
    
    # Check Python
    if ! command -v python3 &>/dev/null; then
        log_error "Python 3 not found. Please install Python 3.11+"
    fi
    
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    log_info "Python: $PYTHON_VERSION"
    
    # Create/activate virtual environment
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "Creating virtual environment: $VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
    
    # shellcheck disable=SC1090
    source "${VENV_DIR}/bin/activate"
    log_info "Virtual environment activated"
    
    # Install dependencies
    log_info "Installing dependencies..."
    pip install --quiet --upgrade pip
    pip install --quiet -r ./app/requirements.txt
    log_success "Dependencies installed"
    
    # Set environment variables
    export PROCESSING_MODE=local
    export PORT="$PORT"
    export LOCAL_INPUT_FOLDER="$(cd "$INPUT_DIR" && pwd)"
    export LOCAL_OUTPUT_FOLDER="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"
    export UPLOAD_FOLDER=/tmp/doclinggpu-uploads
    export OUTPUT_FOLDER=/tmp/doclinggpu-outputs
    export DEBUG=true
    export FLASK_ENV=development
    
    mkdir -p /tmp/doclinggpu-uploads /tmp/doclinggpu-outputs
    
    log_info "Starting Flask development server on port $PORT..."
    log_info "Open: http://localhost:${PORT}"
    echo ""
    
    cd ./app && python3 app.py
}

# ============================================================
# Mode: Docker CPU
# ============================================================
run_docker() {
    log_step "Running with Docker (CPU)"
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found. Please install Docker."
    fi
    
    # Build image if needed
    if ! docker image inspect doclinggpu-webapp:latest &>/dev/null; then
        log_info "Building Docker image..."
        docker build -t doclinggpu-webapp:latest ./app/
    fi
    
    log_info "Starting container on port $PORT..."
    log_info "Open: http://localhost:${PORT}"
    echo ""
    
    docker run --rm -it \
        --name doclinggpu-webapp \
        -p "${PORT}:8080" \
        -e PROCESSING_MODE=local \
        -e DEBUG=false \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output" \
        doclinggpu-webapp:latest
}

# ============================================================
# Mode: Docker GPU
# ============================================================
run_docker_gpu() {
    log_step "Running with Docker + GPU"
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found."
    fi
    
    # Check NVIDIA runtime
    if ! docker info 2>/dev/null | grep -q "nvidia"; then
        log_warn "NVIDIA Docker runtime not detected. GPU may not be available."
    fi
    
    # Check nvidia-smi
    if command -v nvidia-smi &>/dev/null; then
        log_info "GPU detected:"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    fi
    
    # Build image if needed
    if ! docker image inspect doclinggpu-webapp:latest &>/dev/null; then
        log_info "Building Docker image..."
        docker build -t doclinggpu-webapp:latest ./app/
    fi
    
    log_info "Starting container with GPU on port $PORT..."
    log_info "Open: http://localhost:${PORT}"
    echo ""
    
    docker run --rm -it \
        --name doclinggpu-webapp \
        --gpus all \
        -p "${PORT}:8080" \
        -e PROCESSING_MODE=local \
        -e DOCLING_DEVICE=cuda \
        -e DEBUG=false \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output" \
        doclinggpu-webapp:latest
}

# ============================================================
# Process local input folder directly (no web UI)
# ============================================================
run_worker_local() {
    log_step "Running worker directly on ./input folder"
    
    if [[ ! -d "$INPUT_DIR" ]]; then
        log_error "Input directory not found: $INPUT_DIR"
    fi
    
    FILE_COUNT=$(find "$INPUT_DIR" -type f \( -name "*.pdf" -o -name "*.docx" -o -name "*.pptx" \) | wc -l | tr -d ' ')
    log_info "Found $FILE_COUNT documents in $INPUT_DIR"
    
    if [[ "$FILE_COUNT" -eq 0 ]]; then
        log_warn "No documents found in $INPUT_DIR"
        exit 0
    fi
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_SUBDIR="${OUTPUT_DIR}/${TIMESTAMP}"
    mkdir -p "$OUTPUT_SUBDIR"
    
    log_info "Output directory: $OUTPUT_SUBDIR"
    
    # shellcheck disable=SC1090
    source "${VENV_DIR}/bin/activate" 2>/dev/null || true
    
    python3 ./worker/worker.py \
        --input "$INPUT_DIR" \
        --output "$OUTPUT_SUBDIR" \
        --device auto \
        --summary-file "${OUTPUT_SUBDIR}/summary.json"
    
    log_success "Processing complete. Results in: $OUTPUT_SUBDIR"
}

# ============================================================
# Main
# ============================================================
case "$MODE" in
    local)       run_local ;;
    docker)      run_docker ;;
    docker-gpu)  run_docker_gpu ;;
    worker)      run_worker_local ;;
    *)           log_error "Unknown mode: $MODE. Use: local|docker|docker-gpu|worker" ;;
esac

# Made with Bob
