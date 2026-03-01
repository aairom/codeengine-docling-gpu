# DoclingGPU — IBM Code Engine Serverless Document Processing

> **GPU-accelerated document conversion at scale using IBM Cloud Code Engine Serverless Fleets and Docling**

---

## Overview

**DoclingGPU** is a production-ready web application that demonstrates how to combine:

- **[IBM Cloud Code Engine Serverless Fleets](https://github.com/IBM/CodeEngine/tree/main/serverless-fleets)** — on-demand GPU/CPU worker pools that scale to zero when idle
- **[Docling](https://github.com/docling-project/docling)** — IBM's state-of-the-art document AI library for converting PDFs, DOCX, PPTX, and more into structured Markdown

The result is a cost-efficient, scalable document processing pipeline that spins up GPU workers only when needed, processes documents in parallel, and shuts down automatically — paying only for actual compute time.

---

## Key Features

| Feature | Description |
|---------|-------------|
| 🌐 **Web UI** | Drag-and-drop upload, folder batch processing, real-time job monitoring |
| 🖥️ **Local Mode** | Run Docling directly on your machine (CPU or GPU) |
| ⚡ **Fleet CPU Mode** | Launch Code Engine CPU fleet for moderate workloads |
| 🚀 **Fleet GPU Mode** | Launch Code Engine GPU fleet (NVIDIA L40s/H100) for large workloads |
| 📄 **Output Formats** | Timestamped Markdown files with YAML frontmatter metadata |
| 📦 **Batch Processing** | Process entire folders of documents in parallel |
| 🔄 **Auto-scaling** | Workers scale to zero when idle, scale up on demand |
| 🐳 **Containerized** | Docker + Docker Compose for local development |
| ☸️ **K8s Ready** | Kubernetes manifests for non-Code Engine deployments |
| 🏗️ **IaC** | Terraform scripts for full IBM Cloud infrastructure provisioning |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    IBM Cloud Code Engine                        │
│                                                                 │
│  ┌──────────────────┐    ┌──────────────────────────────────┐   │
│  │   DoclingGPU     │    │     Serverless Fleet Workers     │   │
│  │   Web App        │───▶│  ┌──────────┐  ┌──────────────┐  │   │
│  │  (min-scale=0)   │    │  │ CPU Pool │  │  GPU Pool    │  │   │
│  │                  │    │  │ docling  │  │ L40s / H100  │  │   │
│  └──────────────────┘    │  └──────────┘  └──────────────┘  │   │
│           │              └──────────────────────────────────┘   │
│           │                          │                          │
│           ▼                          ▼                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              IBM Cloud Object Storage (COS)              │   │
│  │         /input (documents)  /output (markdown)           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

For detailed architecture diagrams (Mermaid format), see [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## Quick Start

### Prerequisites

- Python 3.11+
- Docker & Docker Compose
- IBM Cloud CLI (for cloud deployment)
- `ibmcloud` CLI plugins: `code-engine`, `container-registry`

### Local Development (5 minutes)

```bash
# Clone the repository
git clone https://github.com/YOUR_ORG/codeengine-docling-gpu.git
cd codeengine-docling-gpu

# Run locally with Python venv
./Scripts/local-run.sh --mode python

# OR run with Docker
./Scripts/local-run.sh --mode docker

# Open browser
open http://localhost:8080
```

### Process Documents Locally

```bash
# Place PDFs in the input folder
cp your-documents/*.pdf input/

# Run the worker directly
cd worker
python worker.py --input ../input --output ../output --mode cpu

# Results appear in output/ as timestamped Markdown files
ls output/
```

### Deploy to IBM Cloud Code Engine

```bash
# Set required environment variables
export IBMCLOUD_API_KEY="your-api-key"
export ICR_NAMESPACE="your-namespace"
export CE_PROJECT_NAME="doclinggpu-project"
export COS_INSTANCE_NAME="doclinggpu-cos"

# Run the deployment script
./Scripts/deploy-codeengine.sh
```

---

## Project Structure

```
codeengine-docling-gpu/
├── app/                          # Flask web application
│   ├── app.py                    # Main Flask application
│   ├── templates/
│   │   └── index.html            # Single-page UI
│   ├── static/
│   │   ├── css/style.css         # IBM Design System-inspired styles
│   │   └── js/app.js             # Frontend JavaScript
│   ├── requirements.txt          # Python dependencies
│   └── Dockerfile                # Web app container
│
├── worker/                       # Docling processing worker
│   ├── worker.py                 # Standalone document processor
│   ├── Dockerfile.gpu            # GPU-enabled worker container
│   ├── entrypoint.sh             # Container entrypoint
│   └── requirements.txt          # Worker dependencies
│
├── Scripts/                      # Automation scripts
│   ├── deploy-codeengine.sh      # IBM Cloud Code Engine deployment
│   ├── build-and-push.sh         # Docker build & push
│   ├── local-run.sh              # Local development runner
│   ├── push-to-github.sh         # GitHub push (excludes _* folders)
│   └── deploy-terraform/         # Terraform IaC
│       ├── main.tf               # IBM Cloud resources
│       ├── variables.tf          # Variable declarations
│       ├── terraform.tfvars.example  # Example configuration
│       └── deploy.sh             # Terraform wrapper script
│
├── k8s/                          # Kubernetes manifests
│   └── deployment.yaml           # Deployment, Service, Ingress, HPA
│
├── Docs/                         # Documentation
│   ├── README.md                 # This file
│   ├── ARCHITECTURE.md           # Architecture diagrams (Mermaid)
│   ├── DEPLOYMENT.md             # Deployment guide
│   ├── LOCAL_DEVELOPMENT.md      # Local development guide
│   └── API.md                    # REST API reference
│
├── input/                        # Local input documents
├── output/                       # Local output (timestamped Markdown)
├── docker-compose.yml            # Multi-service local development
├── .gitignore                    # Git ignore (excludes _* folders)
└── README.md                     # Root project README
```

---

## Processing Modes

### 1. Local Mode

Documents are processed directly by the Flask server using Docling. Best for:
- Development and testing
- Small document sets (< 10 documents)
- Machines with local GPU (CUDA/MPS)

```
User → Web UI → Flask App → Docling (local) → Output Folder
```

### 2. Fleet CPU Mode

Documents are processed by a Code Engine CPU fleet. Best for:
- Moderate workloads (10–100 documents)
- Cost-sensitive processing
- Documents that don't require GPU acceleration

```
User → Web UI → Flask App → COS (upload) → CE Fleet (CPU) → COS (output) → Download
```

### 3. Fleet GPU Mode

Documents are processed by a Code Engine GPU fleet. Best for:
- Large workloads (100+ documents)
- Complex PDFs with tables, figures, equations
- Maximum throughput requirements

```
User → Web UI → Flask App → COS (upload) → CE Fleet (GPU L40s/H100) → COS (output) → Download
```

---

## GPU Configuration

DoclingGPU supports three GPU profiles on IBM Cloud Code Engine:

| Profile | GPU | vCPU | RAM | Use Case |
|---------|-----|------|-----|----------|
| `gx3-24x120x1l40s` | 1× NVIDIA L40s (48GB) | 24 | 120GB | Standard processing |
| `gx3-48x240x2l40s` | 2× NVIDIA L40s | 48 | 240GB | Large batch processing |
| `gx3-96x480x4l40s` | 4× NVIDIA L40s | 96 | 480GB | Maximum throughput |

The L40s profile is recommended for most use cases due to faster initialization time compared to H100.

### Docling GPU Pipeline

When GPU is available, Docling uses:
- **EasyOCR** with CUDA acceleration for text extraction
- **TableFormer** GPU model for table structure recognition
- **LayoutLM** GPU model for document layout analysis

```python
# GPU pipeline configuration (from worker/worker.py)
pipeline_options = PdfPipelineOptions()
pipeline_options.do_ocr = True
pipeline_options.do_table_structure = True
pipeline_options.table_structure_options.use_ocr = True
pipeline_options.accelerator_options = AcceleratorOptions(
    num_threads=8,
    device=AcceleratorDevice.CUDA  # or MPS on Apple Silicon
)
```

---

## Output Format

Each processed document produces a timestamped Markdown file:

```markdown
---
source_file: document.pdf
processed_at: 2024-01-15T14:30:00Z
processing_mode: fleet-gpu
gpu_used: true
gpu_device: cuda
processing_time_seconds: 12.4
page_count: 45
file_size_bytes: 2048576
docling_version: 2.x.x
---

# Document Title

## Section 1

Content extracted from the PDF...

| Column A | Column B |
|----------|----------|
| Value 1  | Value 2  |

...
```

Output files are named: `{original_name}_{timestamp}.md`

Example: `report_20240115_143000.md`

---

## Environment Variables

### Web Application

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Server port |
| `SECRET_KEY` | auto-generated | Flask secret key |
| `PROCESSING_MODE` | `local` | Default processing mode |
| `UPLOAD_FOLDER` | `/tmp/uploads` | Temporary upload directory |
| `OUTPUT_FOLDER` | `/tmp/outputs` | Output directory |
| `LOCAL_INPUT_FOLDER` | `./input` | Local input folder |
| `LOCAL_OUTPUT_FOLDER` | `./output` | Local output folder |

### IBM Cloud (Fleet Mode)

| Variable | Required | Description |
|----------|----------|-------------|
| `IBMCLOUD_API_KEY` | Yes | IBM Cloud API key |
| `CE_PROJECT_NAME` | Yes | Code Engine project name |
| `CE_REGION` | Yes | IBM Cloud region (e.g., `eu-de`) |
| `COS_INSTANCE_CRN` | Yes | COS instance CRN |
| `COS_BUCKET_INPUT` | Yes | Input COS bucket name |
| `COS_BUCKET_OUTPUT` | Yes | Output COS bucket name |
| `CE_GPU_PROFILE` | No | GPU profile (default: `gx3-24x120x1l40s`) |
| `CE_MAX_INSTANCES` | No | Max fleet instances (default: `10`) |

---

## API Reference

See [API.md](./API.md) for the complete REST API documentation.

**Quick reference:**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/` | Web UI |
| `POST` | `/upload` | Upload documents |
| `POST` | `/local/process` | Process local folder |
| `GET` | `/jobs` | List all jobs |
| `GET` | `/job/<id>` | Get job status |
| `GET` | `/job/<id>/download` | Download results |
| `GET` | `/fleet/status/<id>` | Get fleet status |
| `GET` | `/health` | Health check |
| `GET` | `/config` | Get configuration |

---

## Deployment Options

| Option | Best For | Guide |
|--------|----------|-------|
| **Local Python** | Development | [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) |
| **Docker Compose** | Local testing | [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) |
| **IBM Code Engine** | Production (recommended) | [DEPLOYMENT.md](./DEPLOYMENT.md) |
| **Kubernetes** | Self-managed clusters | [DEPLOYMENT.md](./DEPLOYMENT.md) |
| **Terraform** | Infrastructure as Code | [DEPLOYMENT.md](./DEPLOYMENT.md) |

---

## Cost Estimation

IBM Cloud Code Engine pricing (approximate, March 2024):

| Scenario | Documents | GPU Time | Estimated Cost |
|----------|-----------|----------|----------------|
| Small batch | 10 PDFs | ~2 min | ~$0.05 |
| Medium batch | 100 PDFs | ~15 min | ~$0.40 |
| Large batch | 1,000 PDFs | ~2 hours | ~$3.20 |
| Enterprise | 10,000 PDFs | ~20 hours | ~$32.00 |

*Costs based on L40s GPU profile. Actual costs vary by document complexity.*

**Key cost advantage**: Fleet workers scale to **zero** when idle. You pay only for actual processing time, not idle capacity.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -m 'Add my feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Open a Pull Request

### Development Setup

```bash
# Install development dependencies
pip install -r app/requirements.txt
pip install -r worker/requirements.txt

# Run tests
python -m pytest tests/

# Lint
flake8 app/ worker/
```

---

## License

Apache License 2.0 — see [LICENSE](../LICENSE) for details.

---

## References

- [IBM Code Engine Documentation](https://cloud.ibm.com/docs/codeengine)
- [Code Engine Serverless Fleets](https://github.com/IBM/CodeEngine/tree/main/serverless-fleets)
- [Docling GitHub Repository](https://github.com/docling-project/docling)
- [Docling GPU Usage Guide](https://docling-project.github.io/docling/usage/gpu/)
- [IBM Cloud Object Storage](https://cloud.ibm.com/docs/cloud-object-storage)
- [Docling Tutorial on Code Engine](https://github.com/IBM/CodeEngine/blob/main/serverless-fleets/tutorials/docling/README.md)