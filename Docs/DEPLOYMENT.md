# DoclingGPU — Deployment Guide

> Complete guide for deploying DoclingGPU to IBM Cloud Code Engine, Kubernetes, and using Terraform.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [IBM Cloud Code Engine Deployment (Recommended)](#2-ibm-cloud-code-engine-deployment-recommended)
3. [Terraform Deployment](#3-terraform-deployment)
4. [Kubernetes Deployment](#4-kubernetes-deployment)
5. [Container Registry Setup](#5-container-registry-setup)
6. [Environment Configuration](#6-environment-configuration)
7. [Serverless Fleet Configuration](#7-serverless-fleet-configuration)
8. [Monitoring and Logging](#8-monitoring-and-logging)
9. [Troubleshooting](#9-troubleshooting)
10. [Updating and Rolling Back](#10-updating-and-rolling-back)

---

## 1. Prerequisites

### Required Tools

```bash
# IBM Cloud CLI
curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
# macOS:
curl -fsSL https://clis.cloud.ibm.com/install/osx | sh

# IBM Cloud CLI plugins
ibmcloud plugin install code-engine
ibmcloud plugin install container-registry
ibmcloud plugin install cloud-object-storage

# Docker (for building images)
# https://docs.docker.com/get-docker/

# Terraform (for IaC deployment)
brew install terraform  # macOS
# or: https://developer.hashicorp.com/terraform/install
```

### Required IBM Cloud Resources

Before deploying, you need:

1. **IBM Cloud Account** with Pay-As-You-Go or Subscription plan
2. **IBM Cloud API Key** with the following permissions:
   - Code Engine: Administrator
   - Container Registry: Manager
   - Cloud Object Storage: Manager
   - Resource Group: Viewer
3. **IBM Container Registry namespace** (or create one during deployment)

### Create an IBM Cloud API Key

```bash
# Login to IBM Cloud
ibmcloud login --sso

# Create an API key
ibmcloud iam api-key-create doclinggpu-key \
  --description "DoclingGPU deployment key" \
  --output json | jq -r '.apikey'

# Save the API key — it won't be shown again!
export IBMCLOUD_API_KEY="your-api-key-here"
```

---

## 2. IBM Cloud Code Engine Deployment (Recommended)

### Option A: Automated Script (Fastest)

The [`Scripts/deploy-codeengine.sh`](../Scripts/deploy-codeengine.sh) script handles the complete deployment:

```bash
# Set required environment variables
export IBMCLOUD_API_KEY="your-api-key"
export ICR_NAMESPACE="your-icr-namespace"        # e.g., "myorg-doclinggpu"
export CE_PROJECT_NAME="doclinggpu-project"
export COS_INSTANCE_NAME="doclinggpu-cos"
export CE_REGION="eu-de"                          # Frankfurt (recommended for GPU)

# Optional overrides
export CE_APP_NAME="doclinggpu-webapp"
export CE_GPU_PROFILE="gx3-24x120x1l40s"
export CE_MAX_INSTANCES="10"

# Run the deployment
chmod +x Scripts/deploy-codeengine.sh
./Scripts/deploy-codeengine.sh
```

The script will:
1. ✅ Check prerequisites (ibmcloud CLI, Docker, plugins)
2. ✅ Login to IBM Cloud
3. ✅ Create/verify ICR namespace
4. ✅ Build and push Docker images
5. ✅ Create COS instance and buckets
6. ✅ Create Code Engine project
7. ✅ Create secrets and configmaps
8. ✅ Deploy the web application
9. ✅ Output the application URL

### Option B: Manual Step-by-Step

#### Step 1: Login and Setup

```bash
# Login to IBM Cloud
ibmcloud login --apikey $IBMCLOUD_API_KEY -r eu-de

# Target resource group
ibmcloud target -g Default

# Login to Container Registry
ibmcloud cr login
ibmcloud cr region-set eu-de
```

#### Step 2: Build and Push Images

```bash
# Create ICR namespace
ibmcloud cr namespace-add your-namespace

# Build webapp image
docker build -t de.icr.io/your-namespace/doclinggpu-webapp:latest ./app/
docker push de.icr.io/your-namespace/doclinggpu-webapp:latest

# Build worker image
docker build -t de.icr.io/your-namespace/doclinggpu-worker:latest \
  -f worker/Dockerfile.gpu ./worker/
docker push de.icr.io/your-namespace/doclinggpu-worker:latest
```

#### Step 3: Create IBM Cloud Object Storage

```bash
# Create COS instance
ibmcloud resource service-instance-create doclinggpu-cos \
  cloud-object-storage standard global

# Get COS instance CRN
COS_CRN=$(ibmcloud resource service-instance doclinggpu-cos \
  --output json | jq -r '.[0].crn')

# Create HMAC credentials
ibmcloud resource service-key-create doclinggpu-cos-key \
  Writer \
  --instance-name doclinggpu-cos \
  --parameters '{"HMAC": true}'

# Get HMAC keys
HMAC_ACCESS_KEY=$(ibmcloud resource service-key doclinggpu-cos-key \
  --output json | jq -r '.[0].credentials.cos_hmac_keys.access_key_id')
HMAC_SECRET_KEY=$(ibmcloud resource service-key doclinggpu-cos-key \
  --output json | jq -r '.[0].credentials.cos_hmac_keys.secret_access_key')

# Create buckets (using ibmcloud cos plugin)
ibmcloud cos bucket-create \
  --bucket doclinggpu-input-$(date +%s) \
  --ibm-service-instance-id $COS_CRN \
  --region eu-de

ibmcloud cos bucket-create \
  --bucket doclinggpu-output-$(date +%s) \
  --ibm-service-instance-id $COS_CRN \
  --region eu-de
```

#### Step 4: Create Code Engine Project

```bash
# Create project
ibmcloud ce project create --name doclinggpu-project

# Select project
ibmcloud ce project select --name doclinggpu-project
```

#### Step 5: Create Secrets

```bash
# Create COS credentials secret
ibmcloud ce secret create \
  --name cos-credentials \
  --from-literal COS_ACCESS_KEY_ID=$HMAC_ACCESS_KEY \
  --from-literal COS_SECRET_ACCESS_KEY=$HMAC_SECRET_KEY \
  --from-literal COS_ENDPOINT="https://s3.eu-de.cloud-object-storage.appdomain.cloud" \
  --from-literal COS_BUCKET_INPUT="doclinggpu-input-XXXXX" \
  --from-literal COS_BUCKET_OUTPUT="doclinggpu-output-XXXXX"

# Create app secrets
ibmcloud ce secret create \
  --name app-secrets \
  --from-literal SECRET_KEY=$(openssl rand -hex 32) \
  --from-literal IBMCLOUD_API_KEY=$IBMCLOUD_API_KEY

# Create registry secret
ibmcloud ce secret create \
  --name icr-secret \
  --format registry \
  --server de.icr.io \
  --username iamapikey \
  --password $IBMCLOUD_API_KEY
```

#### Step 6: Deploy the Application

```bash
# Create the Code Engine application
ibmcloud ce app create \
  --name doclinggpu-webapp \
  --image de.icr.io/your-namespace/doclinggpu-webapp:latest \
  --registry-secret icr-secret \
  --port 8080 \
  --cpu 1 \
  --memory 4G \
  --min-scale 0 \
  --max-scale 5 \
  --env-from-secret cos-credentials \
  --env-from-secret app-secrets \
  --env CE_PROJECT_NAME=doclinggpu-project \
  --env CE_REGION=eu-de \
  --env PROCESSING_MODE=local

# Get the application URL
ibmcloud ce app get --name doclinggpu-webapp --output url
```

#### Step 7: Verify Deployment

```bash
# Check application status
ibmcloud ce app get --name doclinggpu-webapp

# Check logs
ibmcloud ce app logs --name doclinggpu-webapp --follow

# Test health endpoint
APP_URL=$(ibmcloud ce app get --name doclinggpu-webapp --output url)
curl $APP_URL/health
```

---

## 3. Terraform Deployment

### Setup

```bash
cd Scripts/deploy-terraform

# Copy and edit the variables file
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Fill in your values
```

### Required Variables

Edit [`Scripts/deploy-terraform/terraform.tfvars`](../Scripts/deploy-terraform/terraform.tfvars.example):

```hcl
# IBM Cloud credentials
ibmcloud_api_key = "your-api-key-here"
region           = "eu-de"
resource_group   = "Default"

# Container Registry
icr_namespace    = "your-namespace"
webapp_image     = "de.icr.io/your-namespace/doclinggpu-webapp:latest"
worker_image     = "de.icr.io/your-namespace/doclinggpu-worker:latest"

# Code Engine
ce_project_name  = "doclinggpu-project"
ce_app_name      = "doclinggpu-webapp"

# Object Storage
cos_instance_name = "doclinggpu-cos"
cos_bucket_suffix = "unique-suffix-123"  # Must be globally unique
```

### Deploy with Terraform

```bash
# Use the wrapper script (recommended)
chmod +x Scripts/deploy-terraform/deploy.sh
./Scripts/deploy-terraform/deploy.sh plan    # Preview changes
./Scripts/deploy-terraform/deploy.sh apply   # Apply changes
./Scripts/deploy-terraform/deploy.sh destroy # Tear down (careful!)

# OR use Terraform directly
cd Scripts/deploy-terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Terraform State

Terraform state is stored locally by default. For team deployments, configure remote state:

```hcl
# Add to main.tf for IBM Cloud COS backend
terraform {
  backend "s3" {
    bucket                      = "your-terraform-state-bucket"
    key                         = "doclinggpu/terraform.tfstate"
    region                      = "eu-de"
    endpoint                    = "https://s3.eu-de.cloud-object-storage.appdomain.cloud"
    access_key                  = "your-hmac-access-key"
    secret_key                  = "your-hmac-secret-key"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
```

---

## 4. Kubernetes Deployment

For self-managed Kubernetes clusters (not Code Engine).

### Prerequisites

```bash
# kubectl configured for your cluster
kubectl cluster-info

# NGINX Ingress Controller installed
kubectl get pods -n ingress-nginx

# cert-manager installed (optional, for TLS)
kubectl get pods -n cert-manager
```

### Deploy

```bash
# Edit the deployment manifest
nano k8s/deployment.yaml
# Replace YOUR_REGISTRY with your container registry
# Replace YOUR_DOMAIN.com with your domain

# Apply manifests
kubectl apply -f k8s/deployment.yaml

# Verify deployment
kubectl get all -n doclinggpu

# Check pod logs
kubectl logs -n doclinggpu -l app=doclinggpu-webapp -f

# Get ingress URL
kubectl get ingress -n doclinggpu
```

### Configure Container Registry Secret

```bash
# Create registry pull secret
kubectl create secret docker-registry registry-secret \
  --namespace doclinggpu \
  --docker-server=de.icr.io \
  --docker-username=iamapikey \
  --docker-password=$IBMCLOUD_API_KEY

# Update deployment.yaml to reference the secret
# Add under spec.template.spec:
# imagePullSecrets:
#   - name: registry-secret
```

### Configure Secrets

```bash
# Create the secrets
kubectl create secret generic doclinggpu-secrets \
  --namespace doclinggpu \
  --from-literal=SECRET_KEY=$(openssl rand -hex 32) \
  --from-literal=IBMCLOUD_API_KEY=$IBMCLOUD_API_KEY

# Update COS credentials in the secret
kubectl patch secret doclinggpu-secrets \
  --namespace doclinggpu \
  --type merge \
  -p '{"stringData": {"COS_ACCESS_KEY_ID": "your-key", "COS_SECRET_ACCESS_KEY": "your-secret"}}'
```

### Scale the Deployment

```bash
# Manual scaling
kubectl scale deployment doclinggpu-webapp \
  --namespace doclinggpu \
  --replicas=3

# HPA is already configured in deployment.yaml
# It will auto-scale based on CPU/memory
kubectl get hpa -n doclinggpu
```

---

## 5. Container Registry Setup

### IBM Container Registry (ICR)

```bash
# Install plugin
ibmcloud plugin install container-registry

# Login
ibmcloud cr login

# Create namespace
ibmcloud cr namespace-add your-namespace

# List images
ibmcloud cr images --namespace your-namespace

# Set retention policy (keep last 5 images)
ibmcloud cr retention-policy-set \
  --namespace your-namespace \
  --images-per-repo 5
```

### Docker Hub (Alternative)

```bash
# Login
docker login

# Tag and push
docker tag doclinggpu-webapp:latest your-dockerhub-user/doclinggpu-webapp:latest
docker push your-dockerhub-user/doclinggpu-webapp:latest
```

### GitHub Container Registry (Alternative)

```bash
# Login with GitHub token
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin

# Tag and push
docker tag doclinggpu-webapp:latest ghcr.io/YOUR_ORG/doclinggpu-webapp:latest
docker push ghcr.io/YOUR_ORG/doclinggpu-webapp:latest
```

---

## 6. Environment Configuration

### Production Environment Variables

Set these in your Code Engine application or Kubernetes secrets:

```bash
# Core application
SECRET_KEY="$(openssl rand -hex 32)"    # REQUIRED: Flask secret key
PORT="8080"                              # Server port
PROCESSING_MODE="local"                  # Default: local, fleet-cpu, fleet-gpu

# IBM Cloud (required for fleet mode)
IBMCLOUD_API_KEY="your-api-key"
CE_PROJECT_NAME="doclinggpu-project"
CE_REGION="eu-de"

# IBM Cloud Object Storage
COS_ACCESS_KEY_ID="your-hmac-access-key"
COS_SECRET_ACCESS_KEY="your-hmac-secret-key"
COS_ENDPOINT="https://s3.eu-de.cloud-object-storage.appdomain.cloud"
COS_BUCKET_INPUT="doclinggpu-input-xxxxx"
COS_BUCKET_OUTPUT="doclinggpu-output-xxxxx"

# Fleet configuration
CE_GPU_PROFILE="gx3-24x120x1l40s"      # GPU instance type
CE_CPU_PROFILE="cx2-4x8"               # CPU instance type
CE_MAX_INSTANCES="10"                   # Max fleet workers
DOCLING_GPU_IMAGE="de.icr.io/your-ns/doclinggpu-worker:latest"
DOCLING_CPU_IMAGE="quay.io/docling-project/docling-serve-cpu:latest"
```

### Update Code Engine App Configuration

```bash
# Update environment variables
ibmcloud ce app update \
  --name doclinggpu-webapp \
  --env PROCESSING_MODE=fleet-gpu \
  --env CE_MAX_INSTANCES=20

# Update secrets
ibmcloud ce secret update \
  --name cos-credentials \
  --from-literal COS_BUCKET_INPUT=new-bucket-name

# Force restart
ibmcloud ce app restart --name doclinggpu-webapp
```

---

## 7. Serverless Fleet Configuration

### GPU Profiles Available

| Profile | GPU | vCPU | RAM | Best For |
|---------|-----|------|-----|----------|
| `gx3-24x120x1l40s` | 1× L40s 48GB | 24 | 120GB | Standard (recommended) |
| `gx3-48x240x2l40s` | 2× L40s | 48 | 240GB | Large batches |
| `gx3-96x480x4l40s` | 4× L40s | 96 | 480GB | Maximum throughput |

### CPU Profiles Available

| Profile | vCPU | RAM | Best For |
|---------|------|-----|----------|
| `cx2-4x8` | 4 | 8GB | Small batches |
| `cx2-8x16` | 8 | 16GB | Medium batches |
| `cx2-16x32` | 16 | 32GB | Large batches |

### commands.jsonl Format

The fleet uses a `commands.jsonl` file where each line is a JSON object defining one task:

```jsonl
{"command": ["python", "worker.py", "--input", "/input/doc1.pdf", "--output", "/output", "--mode", "gpu"]}
{"command": ["python", "worker.py", "--input", "/input/doc2.pdf", "--output", "/output", "--mode", "gpu"]}
{"command": ["python", "worker.py", "--input", "/input/doc3.pdf", "--output", "/output", "--mode", "gpu"]}
```

### Fleet Lifecycle

```bash
# Create a fleet manually
ibmcloud ce fleet create \
  --name my-fleet \
  --image de.icr.io/your-ns/doclinggpu-worker:latest \
  --instance-type gx3-24x120x1l40s \
  --commands-from-file commands.jsonl \
  --mount-cos-bucket "doclinggpu-input:/input:r" \
  --mount-cos-bucket "doclinggpu-output:/output:rw" \
  --max-instances 10

# Monitor fleet
ibmcloud ce fleet get --name my-fleet

# List all fleets
ibmcloud ce fleet list

# Delete fleet (auto-deletes when complete)
ibmcloud ce fleet delete --name my-fleet --force
```

---

## 8. Monitoring and Logging

### IBM Cloud Logging

```bash
# View application logs
ibmcloud ce app logs --name doclinggpu-webapp --follow

# View fleet logs
ibmcloud ce fleet logs --name my-fleet

# Filter by time
ibmcloud ce app logs --name doclinggpu-webapp \
  --since 1h
```

### IBM Log Analysis (LogDNA)

```bash
# Create Log Analysis instance
ibmcloud resource service-instance-create doclinggpu-logs \
  logdna lite global

# Configure Code Engine to send logs
ibmcloud ce project update \
  --name doclinggpu-project \
  --log-analysis-instance doclinggpu-logs
```

### IBM Cloud Monitoring (Sysdig)

```bash
# Create Monitoring instance
ibmcloud resource service-instance-create doclinggpu-monitoring \
  sysdig-monitor lite global

# Configure Code Engine metrics
ibmcloud ce project update \
  --name doclinggpu-project \
  --monitoring-instance doclinggpu-monitoring
```

### Health Check

```bash
# Check application health
APP_URL=$(ibmcloud ce app get --name doclinggpu-webapp --output url)
curl -s $APP_URL/health | jq .

# Expected response:
# {
#   "status": "healthy",
#   "version": "1.0.0",
#   "processing_mode": "local",
#   "timestamp": "2024-01-15T14:30:00Z"
# }
```

---

## 9. Troubleshooting

### Application Won't Start

```bash
# Check application status
ibmcloud ce app get --name doclinggpu-webapp

# Check recent events
ibmcloud ce app events --name doclinggpu-webapp

# Check logs for errors
ibmcloud ce app logs --name doclinggpu-webapp --tail 100
```

**Common issues:**

| Error | Cause | Fix |
|-------|-------|-----|
| `ImagePullBackOff` | Registry auth failed | Check `icr-secret` is correct |
| `CrashLoopBackOff` | App startup error | Check logs for Python errors |
| `OOMKilled` | Out of memory | Increase `--memory` limit |
| `503 Service Unavailable` | App not ready | Wait for readiness probe |

### Fleet Won't Launch

```bash
# Check fleet status
ibmcloud ce fleet get --name my-fleet

# Check fleet events
ibmcloud ce fleet events --name my-fleet

# Verify COS bucket access
ibmcloud cos objects --bucket doclinggpu-input-xxxxx
```

**Common issues:**

| Error | Cause | Fix |
|-------|-------|-----|
| `InvalidBucketName` | Bucket doesn't exist | Create bucket first |
| `AccessDenied` | Wrong HMAC keys | Regenerate COS credentials |
| `ImageNotFound` | Worker image missing | Build and push worker image |
| `QuotaExceeded` | GPU quota limit | Request quota increase |

### COS Connection Issues

```bash
# Test COS connectivity
aws s3 ls s3://doclinggpu-input-xxxxx \
  --endpoint-url https://s3.eu-de.cloud-object-storage.appdomain.cloud \
  --region eu-de

# Verify HMAC credentials
ibmcloud resource service-key doclinggpu-cos-key --output json | \
  jq '.[] | .credentials.cos_hmac_keys'
```

### Terraform Issues

```bash
# Refresh state
cd Scripts/deploy-terraform
terraform refresh -var-file=terraform.tfvars

# Import existing resource
terraform import ibm_code_engine_project.main \
  "eu-de/existing-project-id"

# Force unlock state (if locked)
terraform force-unlock LOCK_ID
```

---

## 10. Updating and Rolling Back

### Update the Application

```bash
# Build and push new image
./Scripts/build-and-push.sh --tag v1.1.0

# Update Code Engine app
ibmcloud ce app update \
  --name doclinggpu-webapp \
  --image de.icr.io/your-ns/doclinggpu-webapp:v1.1.0

# Monitor rollout
ibmcloud ce app get --name doclinggpu-webapp
```

### Rolling Back

```bash
# List revisions
ibmcloud ce app revision list --app doclinggpu-webapp

# Roll back to previous revision
ibmcloud ce app update \
  --name doclinggpu-webapp \
  --image de.icr.io/your-ns/doclinggpu-webapp:v1.0.0
```

### Blue-Green Deployment

```bash
# Deploy new version as separate app
ibmcloud ce app create \
  --name doclinggpu-webapp-v2 \
  --image de.icr.io/your-ns/doclinggpu-webapp:v2.0.0 \
  [... same config as v1 ...]

# Test new version
curl $(ibmcloud ce app get --name doclinggpu-webapp-v2 --output url)/health

# Switch traffic (update DNS/load balancer)
# Then delete old version
ibmcloud ce app delete --name doclinggpu-webapp --force
ibmcloud ce app update --name doclinggpu-webapp-v2 --name doclinggpu-webapp
```

### Destroy All Resources

```bash
# Using Terraform (recommended)
cd Scripts/deploy-terraform
terraform destroy -var-file=terraform.tfvars

# Manual cleanup
ibmcloud ce app delete --name doclinggpu-webapp --force
ibmcloud ce project delete --name doclinggpu-project --force
ibmcloud resource service-instance-delete doclinggpu-cos --force
ibmcloud cr image-rm de.icr.io/your-ns/doclinggpu-webapp:latest
ibmcloud cr image-rm de.icr.io/your-ns/doclinggpu-worker:latest
```

---

## Deployment Checklist

Before going to production, verify:

- [ ] `SECRET_KEY` is set to a strong random value (not default)
- [ ] All secrets are stored in Code Engine secrets (not env vars)
- [ ] COS buckets have appropriate retention policies
- [ ] Container images are scanned for vulnerabilities (`ibmcloud cr va`)
- [ ] Application health endpoint returns 200
- [ ] Fleet test run completes successfully
- [ ] Monitoring and logging are configured
- [ ] Backup/restore procedure is documented
- [ ] Cost alerts are configured in IBM Cloud

---

For local development setup, see [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md).
For API reference, see [API.md](./API.md).
For architecture diagrams, see [ARCHITECTURE.md](./ARCHITECTURE.md).