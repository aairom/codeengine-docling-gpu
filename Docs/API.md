# DoclingGPU — REST API Reference

> Complete REST API documentation for the DoclingGPU web application.

**Base URL (local):** `http://localhost:8080`  
**Base URL (Code Engine):** `https://doclinggpu-webapp.YOUR_CE_DOMAIN.us-south.codeengine.appdomain.cloud`

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [Common Response Formats](#2-common-response-formats)
3. [Health & Configuration](#3-health--configuration)
4. [Document Upload & Processing](#4-document-upload--processing)
5. [Job Management](#5-job-management)
6. [Fleet Operations](#6-fleet-operations)
7. [Error Codes](#7-error-codes)
8. [Examples](#8-examples)

---

## 1. Authentication

The current version uses no authentication (suitable for internal/demo use). For production deployments, add authentication via:

- IBM Cloud IAM token validation
- API key header (`X-API-Key`)
- OAuth 2.0 (via IBM App ID)

All endpoints accept `Content-Type: application/json` or `multipart/form-data` where applicable.

---

## 2. Common Response Formats

### Success Response

```json
{
  "status": "success",
  "data": { ... }
}
```

### Error Response

```json
{
  "error": "Error message describing what went wrong",
  "code": "ERROR_CODE",
  "details": { ... }
}
```

### Job Object

All job-related endpoints return a **Job Object**:

```json
{
  "job_id": "job_20240115_143022_abc123",
  "status": "running",
  "mode": "fleet-gpu",
  "progress": 45,
  "created_at": "2024-01-15T14:30:22Z",
  "updated_at": "2024-01-15T14:31:05Z",
  "completed_at": null,
  "files": ["document1.pdf", "document2.pdf"],
  "file_count": 2,
  "result_files": [],
  "error": null,
  "fleet_id": "doclinggpu-fleet-abc123",
  "download_url": null
}
```

**Job Status Values:**

| Status | Description |
|--------|-------------|
| `pending` | Job created, not yet started |
| `running` | Processing in progress |
| `uploading` | Uploading files to COS (fleet mode) |
| `launching` | Launching fleet workers |
| `fleet_running` | Fleet workers processing documents |
| `downloading` | Downloading results from COS |
| `completed` | Processing complete, results available |
| `failed` | Processing failed (see `error` field) |

---

## 3. Health & Configuration

### `GET /health`

Returns the application health status.

**Response `200 OK`:**

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "processing_mode": "local",
  "timestamp": "2024-01-15T14:30:00Z",
  "uptime_seconds": 3600,
  "active_jobs": 2
}
```

**Example:**

```bash
curl http://localhost:8080/health
```

---

### `GET /config`

Returns the current application configuration (non-sensitive values only).

**Response `200 OK`:**

```json
{
  "processing_mode": "local",
  "gpu_profile": "gx3-24x120x1l40s",
  "max_instances": 10,
  "max_upload_size_mb": 500,
  "supported_extensions": [".pdf", ".docx", ".pptx", ".xlsx", ".html", ".md"],
  "cos_configured": true,
  "ibmcloud_configured": true,
  "local_input_folder": "./input",
  "local_output_folder": "./output"
}
```

**Example:**

```bash
curl http://localhost:8080/config
```

---

## 4. Document Upload & Processing

### `POST /upload`

Upload one or more documents for processing.

**Request:** `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `files` | File[] | Yes | One or more document files |
| `mode` | string | No | Processing mode: `local`, `fleet-cpu`, `fleet-gpu` (default: app config) |
| `output_path` | string | No | Custom output path (local mode only) |
| `gpu_profile` | string | No | GPU profile override (fleet-gpu mode only) |

**Response `202 Accepted`:**

```json
{
  "job_id": "job_20240115_143022_abc123",
  "status": "pending",
  "mode": "fleet-gpu",
  "file_count": 3,
  "files": ["report.pdf", "presentation.pptx", "data.docx"],
  "message": "Job created. Processing will begin shortly.",
  "poll_url": "/job/job_20240115_143022_abc123"
}
```

**Response `400 Bad Request`:**

```json
{
  "error": "No files provided",
  "code": "NO_FILES"
}
```

**Response `413 Payload Too Large`:**

```json
{
  "error": "File size exceeds maximum allowed (500 MB)",
  "code": "FILE_TOO_LARGE",
  "max_size_mb": 500
}
```

**Example:**

```bash
# Upload single file
curl -X POST http://localhost:8080/upload \
  -F "files=@document.pdf" \
  -F "mode=local"

# Upload multiple files
curl -X POST http://localhost:8080/upload \
  -F "files=@doc1.pdf" \
  -F "files=@doc2.pdf" \
  -F "files=@doc3.docx" \
  -F "mode=fleet-gpu"

# Upload with GPU profile override
curl -X POST http://localhost:8080/upload \
  -F "files=@large_batch.pdf" \
  -F "mode=fleet-gpu" \
  -F "gpu_profile=gx3-48x240x2l40s"
```

---

### `POST /local/process`

Process documents from a local folder path (server-side folder).

**Request:** `application/json`

```json
{
  "folder_path": "./input",
  "mode": "local",
  "output_path": "./output",
  "extensions": [".pdf", ".docx"],
  "recursive": false
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `folder_path` | string | Yes | Path to folder containing documents |
| `mode` | string | No | Processing mode (default: `local`) |
| `output_path` | string | No | Output folder path (default: `./output`) |
| `extensions` | string[] | No | File extensions to process |
| `recursive` | boolean | No | Process subfolders (default: `false`) |

**Response `202 Accepted`:**

```json
{
  "job_id": "job_20240115_143022_def456",
  "status": "pending",
  "mode": "local",
  "folder_path": "./input",
  "file_count": 5,
  "files": ["doc1.pdf", "doc2.pdf", "doc3.pdf", "doc4.docx", "doc5.pptx"],
  "message": "Batch processing job created."
}
```

**Response `400 Bad Request`:**

```json
{
  "error": "Folder not found: ./nonexistent",
  "code": "FOLDER_NOT_FOUND"
}
```

**Example:**

```bash
# Process local input folder
curl -X POST http://localhost:8080/local/process \
  -H "Content-Type: application/json" \
  -d '{
    "folder_path": "./input",
    "mode": "local",
    "output_path": "./output"
  }'

# Process with fleet GPU
curl -X POST http://localhost:8080/local/process \
  -H "Content-Type: application/json" \
  -d '{
    "folder_path": "./input",
    "mode": "fleet-gpu",
    "extensions": [".pdf"]
  }'
```

---

## 5. Job Management

### `GET /jobs`

List all jobs (most recent first).

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | all | Filter by status: `pending`, `running`, `completed`, `failed` |
| `limit` | integer | 50 | Maximum number of jobs to return |
| `offset` | integer | 0 | Pagination offset |

**Response `200 OK`:**

```json
{
  "jobs": [
    {
      "job_id": "job_20240115_143022_abc123",
      "status": "completed",
      "mode": "fleet-gpu",
      "progress": 100,
      "created_at": "2024-01-15T14:30:22Z",
      "completed_at": "2024-01-15T14:35:10Z",
      "file_count": 3,
      "download_url": "/job/job_20240115_143022_abc123/download"
    },
    {
      "job_id": "job_20240115_141500_xyz789",
      "status": "running",
      "mode": "local",
      "progress": 67,
      "created_at": "2024-01-15T14:15:00Z",
      "completed_at": null,
      "file_count": 1,
      "download_url": null
    }
  ],
  "total": 2,
  "limit": 50,
  "offset": 0
}
```

**Example:**

```bash
# List all jobs
curl http://localhost:8080/jobs

# List only completed jobs
curl "http://localhost:8080/jobs?status=completed"

# Paginate
curl "http://localhost:8080/jobs?limit=10&offset=20"
```

---

### `GET /job/<job_id>`

Get detailed status of a specific job.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `job_id` | string | Job identifier |

**Response `200 OK`:**

```json
{
  "job_id": "job_20240115_143022_abc123",
  "status": "completed",
  "mode": "fleet-gpu",
  "progress": 100,
  "created_at": "2024-01-15T14:30:22Z",
  "updated_at": "2024-01-15T14:35:10Z",
  "completed_at": "2024-01-15T14:35:10Z",
  "files": ["report.pdf", "presentation.pptx"],
  "file_count": 2,
  "result_files": [
    "report_20240115_143510.md",
    "presentation_20240115_143510.md"
  ],
  "result_count": 2,
  "error": null,
  "fleet_id": "doclinggpu-fleet-abc123",
  "processing_time_seconds": 288,
  "download_url": "/job/job_20240115_143022_abc123/download",
  "summary": {
    "total_pages": 87,
    "total_size_bytes": 5242880,
    "gpu_used": true,
    "gpu_device": "cuda"
  }
}
```

**Response `404 Not Found`:**

```json
{
  "error": "Job not found: job_20240115_143022_abc123",
  "code": "JOB_NOT_FOUND"
}
```

**Example:**

```bash
curl http://localhost:8080/job/job_20240115_143022_abc123
```

---

### `GET /job/<job_id>/download`

Download the results of a completed job as a ZIP archive.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `job_id` | string | Job identifier |

**Response `200 OK`:**

- Content-Type: `application/zip`
- Content-Disposition: `attachment; filename="doclinggpu_results_JOB_ID.zip"`
- Body: ZIP file containing all Markdown result files

**ZIP Contents:**

```
doclinggpu_results_job_20240115_143022_abc123.zip
├── report_20240115_143510.md
├── presentation_20240115_143510.md
└── processing_summary.json
```

**Response `404 Not Found`:**

```json
{
  "error": "Job not found or results not available",
  "code": "JOB_NOT_FOUND"
}
```

**Response `409 Conflict`:**

```json
{
  "error": "Job is not yet completed. Current status: running",
  "code": "JOB_NOT_COMPLETED",
  "current_status": "running",
  "progress": 45
}
```

**Example:**

```bash
# Download results
curl -O http://localhost:8080/job/job_20240115_143022_abc123/download

# Download with custom filename
curl -o my_results.zip \
  http://localhost:8080/job/job_20240115_143022_abc123/download

# Download and extract
curl http://localhost:8080/job/job_20240115_143022_abc123/download | \
  tar -xz -C ./results/
```

---

### `DELETE /job/<job_id>`

Delete a job and its associated files.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `job_id` | string | Job identifier |

**Response `200 OK`:**

```json
{
  "message": "Job deleted successfully",
  "job_id": "job_20240115_143022_abc123"
}
```

**Response `409 Conflict`:**

```json
{
  "error": "Cannot delete a running job. Cancel it first.",
  "code": "JOB_RUNNING"
}
```

**Example:**

```bash
curl -X DELETE http://localhost:8080/job/job_20240115_143022_abc123
```

---

## 6. Fleet Operations

### `GET /fleet/status/<fleet_id>`

Get the status of a Code Engine fleet.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `fleet_id` | string | Fleet identifier (from job object) |

**Response `200 OK`:**

```json
{
  "fleet_id": "doclinggpu-fleet-abc123",
  "status": "running",
  "total_tasks": 10,
  "completed_tasks": 6,
  "failed_tasks": 0,
  "running_tasks": 4,
  "progress_percent": 60,
  "instance_type": "gx3-24x120x1l40s",
  "created_at": "2024-01-15T14:30:22Z",
  "estimated_completion": "2024-01-15T14:38:00Z"
}
```

**Fleet Status Values:**

| Status | Description |
|--------|-------------|
| `pending` | Fleet created, workers initializing |
| `running` | Workers processing tasks |
| `completed` | All tasks finished successfully |
| `failed` | One or more tasks failed |
| `cancelled` | Fleet was manually cancelled |

**Example:**

```bash
curl http://localhost:8080/fleet/status/doclinggpu-fleet-abc123
```

---

### `POST /fleet/cancel/<fleet_id>`

Cancel a running fleet (stops all workers).

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `fleet_id` | string | Fleet identifier |

**Response `200 OK`:**

```json
{
  "message": "Fleet cancellation requested",
  "fleet_id": "doclinggpu-fleet-abc123",
  "status": "cancelling"
}
```

**Example:**

```bash
curl -X POST http://localhost:8080/fleet/cancel/doclinggpu-fleet-abc123
```

---

## 7. Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `NO_FILES` | 400 | No files provided in upload request |
| `INVALID_MODE` | 400 | Invalid processing mode specified |
| `FILE_TOO_LARGE` | 413 | File exceeds maximum size limit |
| `UNSUPPORTED_FORMAT` | 415 | File format not supported |
| `FOLDER_NOT_FOUND` | 400 | Specified folder path does not exist |
| `JOB_NOT_FOUND` | 404 | Job ID does not exist |
| `JOB_NOT_COMPLETED` | 409 | Job is still running (download not available) |
| `JOB_RUNNING` | 409 | Cannot delete a running job |
| `FLEET_LAUNCH_FAILED` | 500 | Failed to launch Code Engine fleet |
| `COS_UPLOAD_FAILED` | 500 | Failed to upload files to COS |
| `COS_DOWNLOAD_FAILED` | 500 | Failed to download results from COS |
| `PROCESSING_FAILED` | 500 | Document processing failed |
| `IBMCLOUD_NOT_CONFIGURED` | 503 | IBM Cloud credentials not configured |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## 8. Examples

### Complete Workflow: Upload and Download

```bash
#!/bin/bash
BASE_URL="http://localhost:8080"

# 1. Upload documents
echo "Uploading documents..."
RESPONSE=$(curl -s -X POST $BASE_URL/upload \
  -F "files=@input/report.pdf" \
  -F "files=@input/presentation.pptx" \
  -F "mode=local")

JOB_ID=$(echo $RESPONSE | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")
echo "Job created: $JOB_ID"

# 2. Poll until complete
echo "Waiting for processing..."
while true; do
  JOB=$(curl -s $BASE_URL/job/$JOB_ID)
  STATUS=$(echo $JOB | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  PROGRESS=$(echo $JOB | python3 -c "import sys,json; print(json.load(sys.stdin)['progress'])")
  
  echo "Status: $STATUS ($PROGRESS%)"
  
  if [ "$STATUS" = "completed" ]; then
    echo "Processing complete!"
    break
  elif [ "$STATUS" = "failed" ]; then
    ERROR=$(echo $JOB | python3 -c "import sys,json; print(json.load(sys.stdin)['error'])")
    echo "Processing failed: $ERROR"
    exit 1
  fi
  
  sleep 3
done

# 3. Download results
echo "Downloading results..."
curl -o results.zip $BASE_URL/job/$JOB_ID/download
unzip results.zip -d results/
echo "Results saved to results/"
ls results/
```

### Python Client Example

```python
import requests
import time
import zipfile
import io

BASE_URL = "http://localhost:8080"

def process_documents(file_paths: list[str], mode: str = "local") -> list[str]:
    """
    Upload documents, wait for processing, and return result file paths.
    
    Args:
        file_paths: List of local file paths to process
        mode: Processing mode ('local', 'fleet-cpu', 'fleet-gpu')
    
    Returns:
        List of paths to downloaded result files
    """
    # Upload files
    files = [("files", (open(fp, "rb"))) for fp in file_paths]
    data = {"mode": mode}
    
    response = requests.post(f"{BASE_URL}/upload", files=files, data=data)
    response.raise_for_status()
    
    job_id = response.json()["job_id"]
    print(f"Job created: {job_id}")
    
    # Poll until complete
    while True:
        job = requests.get(f"{BASE_URL}/job/{job_id}").json()
        status = job["status"]
        progress = job["progress"]
        
        print(f"Status: {status} ({progress}%)")
        
        if status == "completed":
            break
        elif status == "failed":
            raise RuntimeError(f"Processing failed: {job['error']}")
        
        time.sleep(3)
    
    # Download results
    response = requests.get(f"{BASE_URL}/job/{job_id}/download")
    response.raise_for_status()
    
    # Extract ZIP
    result_files = []
    with zipfile.ZipFile(io.BytesIO(response.content)) as zf:
        for name in zf.namelist():
            if name.endswith(".md"):
                zf.extract(name, "results/")
                result_files.append(f"results/{name}")
    
    return result_files


# Usage
results = process_documents(
    file_paths=["input/report.pdf", "input/presentation.pptx"],
    mode="local"
)
print(f"Results: {results}")
```

### JavaScript/Fetch Example

```javascript
async function processDocuments(files, mode = 'local') {
  // Upload files
  const formData = new FormData();
  files.forEach(file => formData.append('files', file));
  formData.append('mode', mode);
  
  const uploadResponse = await fetch('/upload', {
    method: 'POST',
    body: formData
  });
  
  if (!uploadResponse.ok) {
    throw new Error(`Upload failed: ${uploadResponse.statusText}`);
  }
  
  const { job_id } = await uploadResponse.json();
  console.log(`Job created: ${job_id}`);
  
  // Poll until complete
  while (true) {
    const jobResponse = await fetch(`/job/${job_id}`);
    const job = await jobResponse.json();
    
    console.log(`Status: ${job.status} (${job.progress}%)`);
    
    if (job.status === 'completed') {
      return job.download_url;
    } else if (job.status === 'failed') {
      throw new Error(`Processing failed: ${job.error}`);
    }
    
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
}

// Usage
const fileInput = document.getElementById('file-input');
const downloadUrl = await processDocuments(
  Array.from(fileInput.files),
  'fleet-gpu'
);
window.location.href = downloadUrl;
```

---

## Rate Limits

| Endpoint | Limit | Window |
|----------|-------|--------|
| `POST /upload` | 10 requests | per minute |
| `GET /job/*` | 120 requests | per minute |
| `GET /jobs` | 30 requests | per minute |
| `POST /local/process` | 5 requests | per minute |

*Rate limits are not enforced in the current version but are recommended for production deployments.*

---

## Webhook Support (Future)

A future version will support webhooks for job completion notifications:

```json
POST /webhooks
{
  "url": "https://your-app.com/docling-callback",
  "events": ["job.completed", "job.failed"],
  "secret": "your-webhook-secret"
}
```

Webhook payload:
```json
{
  "event": "job.completed",
  "job_id": "job_20240115_143022_abc123",
  "timestamp": "2024-01-15T14:35:10Z",
  "download_url": "https://doclinggpu.example.com/job/job_20240115_143022_abc123/download"
}
```

---

For deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md).
For local development setup, see [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md).
For architecture diagrams, see [ARCHITECTURE.md](./ARCHITECTURE.md).