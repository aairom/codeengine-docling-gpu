#!/bin/bash
# ============================================================
# DoclingGPU Worker Entrypoint
# IBM Code Engine Serverless Fleet Worker
# ============================================================

set -e

echo "============================================"
echo "DoclingGPU Worker Starting"
echo "Task Index: ${CE_TASK_INDEX:-0}"
echo "Task ID: ${CE_TASK_ID:-local}"
echo "Device: ${DOCLING_DEVICE:-auto}"
echo "Input: ${INPUT_DIR:-/input}"
echo "Output: ${OUTPUT_DIR:-/output}"
echo "============================================"

# Check if GPU is available
if command -v nvidia-smi &> /dev/null; then
    echo "GPU Info:"
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader
    echo "--------------------------------------------"
fi

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR:-/output}"

# If arguments are passed (from commands.jsonl via fleet), use them directly
# Otherwise run the worker.py with defaults
if [ "$#" -gt 0 ]; then
    # Called with explicit docling command from commands.jsonl
    exec "$@"
else
    # Run our custom worker
    exec python /app/worker.py \
        --input "${INPUT_DIR:-/input}" \
        --output "${OUTPUT_DIR:-/output}" \
        --device "${DOCLING_DEVICE:-auto}" \
        --threads "${DOCLING_NUM_THREADS:-4}"
fi

# Made with Bob
