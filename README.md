# 🚀 DoclingGPU

> **GPU-accelerated document processing on IBM Cloud Code Engine Serverless Fleets**

[![IBM Cloud](https://img.shields.io/badge/IBM%20Cloud-Code%20Engine-0f62fe?logo=ibm)](https://cloud.ibm.com/codeengine)
[![Docling](https://img.shields.io/badge/Powered%20by-Docling-9f1853)](https://github.com/docling-project/docling)
[![Python](https://img.shields.io/badge/Python-3.11-3776ab?logo=python)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ed?logo=docker)](https://docker.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)

---

## What is DoclingGPU?

**DoclingGPU** demonstrates how to combine two powerful IBM technologies:

| Technology | Role |
|-----------|------|
| [IBM Code Engine Serverless Fleets](https://github.com/IBM/CodeEngine/tree/main/serverless-fleets) | On-demand GPU/CPU worker pools — scale to zero when idle |
| [Docling](https://github.com/docling-project/docling) | State-of-the-art document AI — converts PDFs to structured Markdown |

The result: a **cost-efficient, scalable document processing pipeline** that spins up NVIDIA L40s GPU workers only when needed, processes documents in parallel, and shuts down automatically — **paying only for actual compute time**.

---

## ✨ Key Features

- 🌐 **Web UI** — Drag-and-drop upload, folder batch processing, real-time job monitoring
- 🖥️ **Local Mode** — Run Docling directly on your machine (CPU or GPU)
- ⚡ **Fleet CPU Mode** — Launch Code Engine CPU fleet for moderate workloads
- 🚀 **Fleet GPU Mode** — Launch Code Engine GPU fleet (NVIDIA L40s/H100) for large workloads
- 📄 **Timestamped Output** — Markdown files with YAML frontmatter metadata in `output/`
- 📦 **Batch Processing** — Process entire folders of documents in parallel
- 🔄 **Auto-scaling** — Workers scale to zero when idle, scale up on demand
- 🐳 **Docker + Compose** — Full local development environment
- ☸️ **Kubernetes Ready** — Manifests for self-managed cluster deployments
- 🏗️ **Terraform IaC** — Full IBM Cloud infrastructure as code

---

## 🏗️ Architecture

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
│           ▼                          ▼                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              IBM Cloud Object Storage (COS)              │   │
│  │         /input (documents)  /output (markdown)           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

For detailed Mermaid architecture diagrams, see [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

---

## ⚡ Quick Start

### Local Development (5 minutes)

```bash
# Clone
git clone https://github.com/YOUR_ORG/codeengine-docling-gpu.git
cd codeengine-docling-gpu

# Run with Python venv
chmod +x Scripts/*.sh
./Scripts/local-run.sh --mode python

# Open browser
open http://localhost:8080
```

### Process Documents from CLI

```bash
# Place PDFs in input/
cp your-documents/*.pdf input/

# Run worker directly
python worker/worker.py --input input/ --output output/ --mode cpu

# Results in output/ as timestamped Markdown
ls output/
```

### Deploy to IBM Cloud Code Engine

```bash
export IBMCLOUD_API_KEY="your-api-key"
export ICR_NAMESPACE="your-namespace"
export CE_PROJECT_NAME="doclinggpu-project"

./Scripts/deploy-codeengine.sh
```

---

## 📁 Project Structure

```
codeengine-docling-gpu/
├── app/                          # Flask web application
│   ├── app.py                    # Main application
│   ├── templates/index.html      # Single-page UI
│   ├── static/css/style.css      # IBM Design System styles
│   ├── static/js/app.js          # Frontend JavaScript
│   ├── requirements.txt          # Python dependencies
│   └── Dockerfile                # Web app container
│
├── worker/                       # Docling processing worker
│   ├── worker.py                 # Document processor (GPU/CPU)
│   ├── Dockerfile.gpu            # GPU-enabled container
│   ├── entrypoint.sh             # Container entrypoint
│   └── requirements.txt          # Worker dependencies
│
├── Scripts/                      # Automation scripts
│   ├── deploy-codeengine.sh      # ☁️ IBM Cloud CE deployment
│   ├── build-and-push.sh         # 🐳 Docker build & push
│   ├── local-run.sh              # 🖥️ Local development runner
│   ├── push-to-github.sh         # 📤 GitHub push (excludes _* folders)
│   └── deploy-terraform/         # 🏗️ Terraform IaC
│       ├── main.tf               # IBM Cloud resources
│       ├── variables.tf          # Variable declarations
│       ├── terraform.tfvars.example
│       └── deploy.sh             # Terraform wrapper
│
├── k8s/                          # ☸️ Kubernetes manifests
│   └── deployment.yaml           # Deployment, Service, Ingress, HPA
│
├── Docs/                         # 📚 Documentation
│   ├── README.md                 # Full documentation
│   ├── ARCHITECTURE.md           # Mermaid architecture diagrams
│   ├── DEPLOYMENT.md             # Deployment guide
│   ├── LOCAL_DEVELOPMENT.md      # Local dev guide
│   └── API.md                    # REST API reference
│
├── input/                        # 📥 Local input documents
├── output/                       # 📤 Local output (Markdown)
├── commands.jsonl                # Fleet task definitions example
├── docker-compose.yml            # Multi-service local dev
└── .gitignore                    # Excludes _* folders + secrets
```

---

## 🔄 Processing Modes

| Mode | Description | Best For |
|------|-------------|----------|
| **Local** | Docling runs on the Flask server | Dev, small batches |
| **Fleet CPU** | Code Engine CPU worker pool | 10–100 documents |
| **Fleet GPU** | Code Engine GPU pool (L40s/H100) | 100+ complex documents |

---

## 📊 GPU Profiles

| Profile | GPU | vCPU | RAM | Use Case |
|---------|-----|------|-----|----------|
| `gx3-24x120x1l40s` | 1× NVIDIA L40s 48GB | 24 | 120GB | Standard (recommended) |
| `gx3-48x240x2l40s` | 2× NVIDIA L40s | 48 | 240GB | Large batches |
| `gx3-96x480x4l40s` | 4× NVIDIA L40s | 96 | 480GB | Maximum throughput |

---

## 📜 Scripts Reference

| Script | Description |
|--------|-------------|
| [`Scripts/local-run.sh`](Scripts/local-run.sh) | Run locally (python/docker/docker-gpu/worker modes) |
| [`Scripts/deploy-codeengine.sh`](Scripts/deploy-codeengine.sh) | Full IBM Cloud Code Engine deployment |
| [`Scripts/build-and-push.sh`](Scripts/build-and-push.sh) | Build Docker images and push to registry |
| [`Scripts/push-to-github.sh`](Scripts/push-to-github.sh) | Push to GitHub (ignores `_*` folders) |
| [`Scripts/deploy-terraform/deploy.sh`](Scripts/deploy-terraform/deploy.sh) | Terraform plan/apply/destroy wrapper |

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Docs/README.md](Docs/README.md) | Full project documentation |
| [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Architecture diagrams (Mermaid) |
| [Docs/DEPLOYMENT.md](Docs/DEPLOYMENT.md) | IBM Cloud & Kubernetes deployment guide |
| [Docs/LOCAL_DEVELOPMENT.md](Docs/LOCAL_DEVELOPMENT.md) | Local development setup |
| [Docs/API.md](Docs/API.md) | REST API reference |

---

## 💰 Cost Model

Fleet workers **scale to zero** when idle — you pay only for actual processing time:

| Scenario | Documents | GPU Time | Est. Cost |
|----------|-----------|----------|-----------|
| Small batch | 10 PDFs | ~2 min | ~$0.05 |
| Medium batch | 100 PDFs | ~15 min | ~$0.40 |
| Large batch | 1,000 PDFs | ~2 hours | ~$3.20 |

---

## 🔗 References

- [IBM Code Engine Serverless Fleets](https://github.com/IBM/CodeEngine/tree/main/serverless-fleets)
- [Docling Tutorial on Code Engine](https://github.com/IBM/CodeEngine/blob/main/serverless-fleets/tutorials/docling/README.md)
- [Docling GPU Usage Guide](https://docling-project.github.io/docling/usage/gpu/)
- [Docling GitHub Repository](https://github.com/docling-project/docling)
- [IBM Cloud Code Engine Docs](https://cloud.ibm.com/docs/codeengine)

---

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE) for details.