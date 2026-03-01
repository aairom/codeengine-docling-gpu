# DoclingGPU — Architecture Documentation

> Detailed architecture diagrams for the DoclingGPU application using Mermaid format.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Component Architecture](#2-component-architecture)
3. [Data Flow — Local Mode](#3-data-flow--local-mode)
4. [Data Flow — Fleet CPU Mode](#4-data-flow--fleet-cpu-mode)
5. [Data Flow — Fleet GPU Mode](#5-data-flow--fleet-gpu-mode)
6. [Deployment Architecture — IBM Code Engine](#6-deployment-architecture--ibm-code-engine)
7. [Deployment Architecture — Kubernetes](#7-deployment-architecture--kubernetes)
8. [Sequence Diagram — Document Processing](#8-sequence-diagram--document-processing)
9. [Sequence Diagram — Fleet Lifecycle](#9-sequence-diagram--fleet-lifecycle)
10. [State Machine — Job Lifecycle](#10-state-machine--job-lifecycle)
11. [Infrastructure — Terraform Provisioning](#11-infrastructure--terraform-provisioning)
12. [Container Architecture](#12-container-architecture)
13. [Network Architecture](#13-network-architecture)
14. [Security Architecture](#14-security-architecture)

---

## 1. System Overview

High-level view of the entire DoclingGPU system and its integration with IBM Cloud services.

```mermaid
graph TB
    subgraph Users["👤 Users"]
        Browser["Web Browser"]
        CLI["CLI / Scripts"]
    end

    subgraph DoclingGPU["DoclingGPU Application"]
        WebApp["🌐 Flask Web App\n(Code Engine App)"]
        LocalWorker["🖥️ Local Worker\n(Docling CPU/GPU)"]
    end

    subgraph IBMCloud["☁️ IBM Cloud"]
        subgraph CodeEngine["IBM Cloud Code Engine"]
            CEApp["CE Application\n(min-scale=0)"]
            subgraph Fleets["Serverless Fleets"]
                CPUFleet["CPU Fleet\ndocling-serve-cpu"]
                GPUFleet["GPU Fleet\ndocling-serve\n(L40s / H100)"]
            end
        end

        subgraph Storage["IBM Cloud Object Storage"]
            InputBucket["📥 Input Bucket\n(documents)"]
            OutputBucket["📤 Output Bucket\n(markdown)"]
        end

        ICR["IBM Container Registry\n(Docker Images)"]
        IAM["IBM IAM\n(Authentication)"]
    end

    Browser -->|"HTTPS"| WebApp
    CLI -->|"Direct"| LocalWorker
    WebApp --> CEApp
    CEApp -->|"Upload docs"| InputBucket
    CEApp -->|"Launch fleet"| CPUFleet
    CEApp -->|"Launch fleet"| GPUFleet
    CPUFleet -->|"Read"| InputBucket
    CPUFleet -->|"Write"| OutputBucket
    GPUFleet -->|"Read"| InputBucket
    GPUFleet -->|"Write"| OutputBucket
    CEApp -->|"Download results"| OutputBucket
    ICR -->|"Pull images"| CEApp
    ICR -->|"Pull images"| CPUFleet
    ICR -->|"Pull images"| GPUFleet
    IAM -->|"Authenticate"| CEApp

    style DoclingGPU fill:#0f62fe,color:#fff
    style IBMCloud fill:#161616,color:#fff
    style CodeEngine fill:#262626,color:#fff
    style Storage fill:#262626,color:#fff
    style Fleets fill:#393939,color:#fff
```

---

## 2. Component Architecture

Internal component breakdown of the DoclingGPU application.

```mermaid
graph TB
    subgraph WebApp["🌐 Flask Web Application (app/app.py)"]
        direction TB
        Routes["HTTP Routes\n/upload /jobs /health"]
        JobManager["Job Manager\n(in-memory store)"]
        FleetLauncher["Fleet Launcher\n(ibmcloud CLI)"]
        LocalProcessor["Local Processor\n(Docling direct)"]
        COSClient["COS Client\n(ibm-cos-sdk)"]
        BGThread["Background Thread\n(job execution)"]

        Routes --> JobManager
        Routes --> FleetLauncher
        Routes --> LocalProcessor
        FleetLauncher --> COSClient
        LocalProcessor --> BGThread
        FleetLauncher --> BGThread
    end

    subgraph Frontend["🖥️ Frontend (templates + static)"]
        HTML["index.html\n(Single Page)"]
        CSS["style.css\n(IBM Design System)"]
        JS["app.js\n(Polling + Upload)"]

        HTML --> CSS
        HTML --> JS
    end

    subgraph Worker["⚙️ Docling Worker (worker/worker.py)"]
        ArgParser["Argument Parser\n(--input --output --mode)"]
        DeviceDetect["Device Detector\n(CUDA / MPS / CPU)"]
        DocConverter["DocumentConverter\n(Docling)"]
        PipelineOpts["Pipeline Options\n(OCR + TableFormer)"]
        MarkdownWriter["Markdown Writer\n(YAML frontmatter)"]
        SummaryWriter["Summary Writer\n(JSON report)"]

        ArgParser --> DeviceDetect
        DeviceDetect --> PipelineOpts
        PipelineOpts --> DocConverter
        DocConverter --> MarkdownWriter
        DocConverter --> SummaryWriter
    end

    subgraph Docling["📚 Docling Library"]
        PDFParser["PDF Parser\n(pdfminer / pypdf)"]
        OCREngine["OCR Engine\n(EasyOCR / Tesseract)"]
        TableFormer["TableFormer\n(GPU model)"]
        LayoutModel["Layout Model\n(LayoutLM)"]
        MDExporter["Markdown Exporter"]

        PDFParser --> OCREngine
        PDFParser --> TableFormer
        PDFParser --> LayoutModel
        OCREngine --> MDExporter
        TableFormer --> MDExporter
        LayoutModel --> MDExporter
    end

    Frontend -->|"HTTP/REST"| WebApp
    WebApp -->|"subprocess / direct"| Worker
    Worker -->|"Python API"| Docling

    style WebApp fill:#0f62fe,color:#fff
    style Frontend fill:#6929c4,color:#fff
    style Worker fill:#005d5d,color:#fff
    style Docling fill:#9f1853,color:#fff
```

---

## 3. Data Flow — Local Mode

How documents flow through the system when processing locally.

```mermaid
flowchart LR
    subgraph Input["📥 Input"]
        Upload["File Upload\n(drag & drop)"]
        FolderPath["Folder Path\n(batch)"]
        LocalInput["input/ folder\n(pre-placed)"]
    end

    subgraph Processing["⚙️ Local Processing"]
        Flask["Flask App\n(app.py)"]
        BGJob["Background Job\n(threading)"]
        DoclingLocal["Docling\n(local CPU/GPU)"]
        DeviceCheck{"GPU\nAvailable?"}
        CUDA["CUDA\n(NVIDIA)"]
        MPS["MPS\n(Apple Silicon)"]
        CPU["CPU\n(fallback)"]
    end

    subgraph Output["📤 Output"]
        TmpOutput["Temp Output\n(/tmp/outputs)"]
        LocalOutput["output/ folder\n(timestamped .md)"]
        Download["Browser Download\n(ZIP)"]
        JobStatus["Job Status\n(polling /job/<id>)"]
    end

    Upload -->|"multipart/form-data"| Flask
    FolderPath -->|"POST /local/process"| Flask
    LocalInput -->|"POST /local/process"| Flask

    Flask -->|"create job"| BGJob
    BGJob --> DoclingLocal
    DoclingLocal --> DeviceCheck
    DeviceCheck -->|"Yes - NVIDIA"| CUDA
    DeviceCheck -->|"Yes - Apple"| MPS
    DeviceCheck -->|"No"| CPU
    CUDA --> TmpOutput
    MPS --> TmpOutput
    CPU --> TmpOutput

    TmpOutput -->|"copy"| LocalOutput
    TmpOutput -->|"GET /job/<id>/download"| Download
    BGJob -->|"update"| JobStatus

    style Input fill:#0043ce,color:#fff
    style Processing fill:#005d5d,color:#fff
    style Output fill:#6929c4,color:#fff
```

---

## 4. Data Flow — Fleet CPU Mode

How documents flow through the system when using Code Engine CPU fleet.

```mermaid
flowchart TD
    subgraph UserAction["👤 User Action"]
        UploadUI["Upload Documents\n(Web UI)"]
        SelectCPU["Select: Fleet CPU\n(radio button)"]
    end

    subgraph WebApp["🌐 Flask Web App (Code Engine)"]
        ReceiveFiles["Receive Files\n(POST /upload)"]
        CreateJob["Create Job\n(job_id)"]
        UploadCOS["Upload to COS\n(input bucket)"]
        GenCommands["Generate\ncommands.jsonl"]
        LaunchFleet["Launch CE Fleet\n(ibmcloud ce fleet create)"]
        PollFleet["Poll Fleet Status\n(ibmcloud ce fleet get)"]
        DownloadResults["Download Results\n(from COS output)"]
    end

    subgraph CEFleet["⚡ Code Engine CPU Fleet"]
        FleetMgr["Fleet Manager\n(CE control plane)"]
        Worker1["Worker Instance 1\ndocling-serve-cpu"]
        Worker2["Worker Instance 2\ndocling-serve-cpu"]
        WorkerN["Worker Instance N\ndocling-serve-cpu"]
    end

    subgraph COS["☁️ IBM Cloud Object Storage"]
        InputBucket["📥 Input Bucket\n(uploaded PDFs)"]
        CommandsFile["commands.jsonl\n(task definitions)"]
        OutputBucket["📤 Output Bucket\n(markdown results)"]
    end

    UploadUI --> ReceiveFiles
    SelectCPU --> ReceiveFiles
    ReceiveFiles --> CreateJob
    CreateJob --> UploadCOS
    UploadCOS --> InputBucket
    CreateJob --> GenCommands
    GenCommands --> CommandsFile
    CommandsFile --> LaunchFleet
    LaunchFleet --> FleetMgr
    FleetMgr --> Worker1
    FleetMgr --> Worker2
    FleetMgr --> WorkerN
    Worker1 -->|"read"| InputBucket
    Worker2 -->|"read"| InputBucket
    WorkerN -->|"read"| InputBucket
    Worker1 -->|"write"| OutputBucket
    Worker2 -->|"write"| OutputBucket
    WorkerN -->|"write"| OutputBucket
    LaunchFleet --> PollFleet
    PollFleet -->|"completed"| DownloadResults
    DownloadResults -->|"from"| OutputBucket

    style UserAction fill:#0043ce,color:#fff
    style WebApp fill:#0f62fe,color:#fff
    style CEFleet fill:#005d5d,color:#fff
    style COS fill:#9f1853,color:#fff
```

---

## 5. Data Flow — Fleet GPU Mode

How documents flow through the system when using Code Engine GPU fleet (L40s/H100).

```mermaid
flowchart TD
    subgraph UserAction["👤 User Action"]
        UploadUI["Upload Documents\n(Web UI)"]
        SelectGPU["Select: Fleet GPU\n(radio button)"]
        GPUProfile["Choose GPU Profile\n(L40s / H100)"]
    end

    subgraph WebApp["🌐 Flask Web App"]
        ReceiveFiles["Receive Files"]
        CreateJob["Create Job"]
        UploadCOS["Upload to COS"]
        GenCommands["Generate commands.jsonl\n(with GPU flags)"]
        LaunchGPUFleet["Launch GPU Fleet\n(--instance-type gx3-24x120x1l40s)"]
        PollFleet["Poll Fleet Status"]
        DownloadResults["Download Results"]
    end

    subgraph CEGPUFleet["🚀 Code Engine GPU Fleet"]
        FleetMgr["Fleet Manager"]
        subgraph GPUWorker1["GPU Worker 1 (L40s 48GB)"]
            Container1["docling-serve\ncontainer"]
            GPU1["NVIDIA L40s\n48GB VRAM"]
            CUDA1["CUDA 12.x\nRuntime"]
        end
        subgraph GPUWorker2["GPU Worker 2 (L40s 48GB)"]
            Container2["docling-serve\ncontainer"]
            GPU2["NVIDIA L40s\n48GB VRAM"]
            CUDA2["CUDA 12.x\nRuntime"]
        end
    end

    subgraph DoclingGPU["📚 Docling GPU Pipeline"]
        PDFLoad["PDF Loading\n(pdfminer)"]
        OCR["EasyOCR\n(CUDA accelerated)"]
        TableFormer["TableFormer\n(GPU model)"]
        Layout["Layout Analysis\n(LayoutLM GPU)"]
        MDExport["Markdown Export\n(structured output)"]
    end

    subgraph COS["☁️ IBM Cloud Object Storage"]
        InputBucket["📥 Input Bucket"]
        OutputBucket["📤 Output Bucket"]
    end

    UploadUI --> ReceiveFiles
    SelectGPU --> ReceiveFiles
    GPUProfile --> LaunchGPUFleet
    ReceiveFiles --> CreateJob
    CreateJob --> UploadCOS
    UploadCOS --> InputBucket
    CreateJob --> GenCommands
    GenCommands --> LaunchGPUFleet
    LaunchGPUFleet --> FleetMgr
    FleetMgr --> GPUWorker1
    FleetMgr --> GPUWorker2
    GPUWorker1 -->|"read"| InputBucket
    GPUWorker2 -->|"read"| InputBucket
    Container1 --> DoclingGPU
    PDFLoad --> OCR
    PDFLoad --> TableFormer
    PDFLoad --> Layout
    OCR --> MDExport
    TableFormer --> MDExport
    Layout --> MDExport
    MDExport -->|"write"| OutputBucket
    LaunchGPUFleet --> PollFleet
    PollFleet -->|"completed"| DownloadResults
    DownloadResults -->|"from"| OutputBucket

    style UserAction fill:#0043ce,color:#fff
    style WebApp fill:#0f62fe,color:#fff
    style CEGPUFleet fill:#198038,color:#fff
    style DoclingGPU fill:#9f1853,color:#fff
    style COS fill:#6929c4,color:#fff
```

---

## 6. Deployment Architecture — IBM Code Engine

Full IBM Cloud Code Engine deployment topology.

```mermaid
graph TB
    subgraph Internet["🌐 Internet"]
        Users["Users\n(browsers)"]
    end

    subgraph IBMCloud["☁️ IBM Cloud (eu-de region)"]
        subgraph IAM["🔐 IBM IAM"]
            APIKey["API Key"]
            ServiceID["Service ID"]
            Policies["IAM Policies"]
        end

        subgraph ICR["📦 IBM Container Registry"]
            WebAppImage["doclinggpu-webapp:latest"]
            WorkerImage["doclinggpu-worker:latest"]
        end

        subgraph CodeEngine["🚀 IBM Cloud Code Engine Project: doclinggpu"]
            subgraph App["Application (serverless)"]
                AppInstance1["App Instance 1\n(Flask + Gunicorn)"]
                AppInstance2["App Instance 2\n(auto-scaled)"]
                AppConfig["CE App Config\nmin-scale=0\nmax-scale=5\ncpu=1 mem=4G"]
            end

            subgraph Secrets["Secrets & ConfigMaps"]
                CosSecret["cos-credentials\n(HMAC keys)"]
                AppSecret["app-secrets\n(SECRET_KEY)"]
                AppConfig2["app-config\n(env vars)"]
            end

            subgraph FleetCPU["CPU Fleet (on-demand)"]
                CPUWorker1["CPU Worker 1\ndocling-serve-cpu"]
                CPUWorker2["CPU Worker 2\ndocling-serve-cpu"]
                CPUWorkerN["CPU Worker N\n(auto-scaled)"]
            end

            subgraph FleetGPU["GPU Fleet (on-demand)"]
                GPUWorker1["GPU Worker 1\nL40s 48GB"]
                GPUWorker2["GPU Worker 2\nL40s 48GB"]
                GPUWorkerN["GPU Worker N\n(auto-scaled)"]
            end
        end

        subgraph COS["☁️ IBM Cloud Object Storage"]
            COSInstance["COS Instance\n(Standard)"]
            InputBucket["doclinggpu-input\nbucket"]
            OutputBucket["doclinggpu-output\nbucket"]
        end

        subgraph Monitoring["📊 IBM Cloud Monitoring"]
            LogDNA["IBM Log Analysis\n(application logs)"]
            SysDig["IBM Monitoring\n(metrics)"]
        end
    end

    Users -->|"HTTPS"| AppInstance1
    Users -->|"HTTPS"| AppInstance2
    AppInstance1 -->|"pull"| WebAppImage
    AppInstance2 -->|"pull"| WebAppImage
    AppInstance1 -->|"read"| CosSecret
    AppInstance1 -->|"upload"| InputBucket
    AppInstance1 -->|"download"| OutputBucket
    AppInstance1 -->|"launch"| FleetCPU
    AppInstance1 -->|"launch"| FleetGPU
    CPUWorker1 -->|"pull"| WorkerImage
    GPUWorker1 -->|"pull"| WorkerImage
    CPUWorker1 -->|"read"| InputBucket
    CPUWorker1 -->|"write"| OutputBucket
    GPUWorker1 -->|"read"| InputBucket
    GPUWorker1 -->|"write"| OutputBucket
    APIKey -->|"auth"| AppInstance1
    AppInstance1 -->|"logs"| LogDNA
    AppInstance1 -->|"metrics"| SysDig

    style Internet fill:#0043ce,color:#fff
    style IBMCloud fill:#161616,color:#fff
    style IAM fill:#6929c4,color:#fff
    style ICR fill:#005d5d,color:#fff
    style CodeEngine fill:#0f62fe,color:#fff
    style COS fill:#9f1853,color:#fff
    style Monitoring fill:#b28600,color:#fff
```

---

## 7. Deployment Architecture — Kubernetes

Alternative Kubernetes deployment topology for self-managed clusters.

```mermaid
graph TB
    subgraph Internet["🌐 Internet"]
        Users["Users"]
    end

    subgraph K8sCluster["☸️ Kubernetes Cluster"]
        subgraph Ingress["Ingress Layer"]
            NginxIngress["NGINX Ingress Controller"]
            TLS["TLS Termination\n(cert-manager)"]
        end

        subgraph Namespace["Namespace: doclinggpu"]
            subgraph WebTier["Web Tier"]
                WebDeploy["Deployment\ndoclinggpu-webapp\nreplicas: 2"]
                WebSvc["Service\nClusterIP :80"]
                WebHPA["HPA\nmin:1 max:10\nCPU: 70%"]
            end

            subgraph Config["Configuration"]
                ConfigMap["ConfigMap\ndoclinggpu-config"]
                Secret["Secret\ndoclinggpu-secrets"]
                PVC["PVC\ndoclinggpu-output\n10Gi"]
            end

            subgraph Storage["Storage"]
                OutputVol["Output Volume\n(PVC)"]
                UploadVol["Upload Volume\n(emptyDir)"]
                InputVol["Input Volume\n(hostPath)"]
            end
        end

        subgraph NodePool["Node Pool"]
            Node1["Node 1\n(CPU)"]
            Node2["Node 2\n(CPU)"]
            GPUNode["GPU Node\n(NVIDIA)"]
        end
    end

    subgraph Registry["Container Registry"]
        Images["Docker Images\n(webapp + worker)"]
    end

    Users -->|"HTTPS :443"| NginxIngress
    TLS --> NginxIngress
    NginxIngress -->|":80"| WebSvc
    WebSvc --> WebDeploy
    WebHPA -->|"scale"| WebDeploy
    WebDeploy -->|"read"| ConfigMap
    WebDeploy -->|"read"| Secret
    WebDeploy -->|"mount"| OutputVol
    WebDeploy -->|"mount"| UploadVol
    WebDeploy -->|"mount"| InputVol
    OutputVol --> PVC
    WebDeploy -->|"schedule"| Node1
    WebDeploy -->|"schedule"| Node2
    Images -->|"pull"| WebDeploy

    style Internet fill:#0043ce,color:#fff
    style K8sCluster fill:#161616,color:#fff
    style Namespace fill:#262626,color:#fff
    style WebTier fill:#0f62fe,color:#fff
    style Config fill:#6929c4,color:#fff
    style Storage fill:#005d5d,color:#fff
    style NodePool fill:#393939,color:#fff
```

---

## 8. Sequence Diagram — Document Processing

End-to-end sequence for processing documents via the web UI.

```mermaid
sequenceDiagram
    actor User
    participant UI as Web UI (Browser)
    participant App as Flask App
    participant BG as Background Thread
    participant Worker as Docling Worker
    participant COS as IBM COS
    participant Fleet as CE Fleet

    User->>UI: Upload PDF files
    UI->>App: POST /upload (multipart)
    App->>App: Save files to /tmp/uploads
    App->>App: Create job (job_id, status=pending)
    App-->>UI: 200 OK {job_id}

    UI->>App: POST /upload (mode=fleet-gpu)
    App->>BG: Start background thread
    App-->>UI: 202 Accepted {job_id}

    UI->>App: GET /job/{job_id} (polling every 3s)
    App-->>UI: {status: "running", progress: 0}

    BG->>COS: Upload documents to input bucket
    COS-->>BG: Upload complete

    BG->>BG: Generate commands.jsonl
    BG->>Fleet: ibmcloud ce fleet create --commands-from-file
    Fleet-->>BG: Fleet ID

    loop Poll fleet status
        BG->>Fleet: ibmcloud ce fleet get --name {fleet_id}
        Fleet-->>BG: {status: "running", completed: N/total}
        BG->>App: Update job progress
        UI->>App: GET /job/{job_id}
        App-->>UI: {status: "running", progress: N%}
    end

    Fleet->>Worker: Execute worker.py for each document
    Worker->>COS: Read document from input bucket
    Worker->>Worker: Run Docling (GPU pipeline)
    Worker->>COS: Write markdown to output bucket

    Fleet-->>BG: {status: "completed"}
    BG->>COS: Download results from output bucket
    BG->>App: Update job status=completed

    UI->>App: GET /job/{job_id}
    App-->>UI: {status: "completed", download_url: "/job/{id}/download"}

    User->>UI: Click Download
    UI->>App: GET /job/{job_id}/download
    App-->>UI: ZIP file (markdown results)
    UI-->>User: Download ZIP
```

---

## 9. Sequence Diagram — Fleet Lifecycle

How Code Engine Serverless Fleets are created, run, and terminated.

```mermaid
sequenceDiagram
    participant App as Flask App
    participant CE as Code Engine Control Plane
    participant ICR as Container Registry
    participant COS as IBM COS
    participant GPU1 as GPU Worker 1
    participant GPU2 as GPU Worker 2

    Note over App,GPU2: Fleet Creation Phase

    App->>COS: Upload commands.jsonl
    App->>CE: ibmcloud ce fleet create\n--name doclinggpu-fleet-{id}\n--instance-type gx3-24x120x1l40s\n--commands-from-file commands.jsonl\n--mount-cos-bucket input:/input\n--mount-cos-bucket output:/output

    CE->>CE: Parse commands.jsonl\n(N tasks)
    CE->>ICR: Pull doclinggpu-worker:latest
    ICR-->>CE: Image pulled

    Note over App,GPU2: Worker Initialization Phase

    CE->>GPU1: Provision GPU instance\n(L40s 48GB)
    CE->>GPU2: Provision GPU instance\n(L40s 48GB)
    GPU1->>GPU1: CUDA runtime init\n(~30s for L40s)
    GPU2->>GPU2: CUDA runtime init\n(~30s for L40s)
    GPU1->>COS: Mount /input bucket
    GPU1->>COS: Mount /output bucket
    GPU2->>COS: Mount /input bucket
    GPU2->>COS: Mount /output bucket

    Note over App,GPU2: Processing Phase

    CE->>GPU1: Execute task 1: worker.py doc1.pdf
    CE->>GPU1: Execute task 2: worker.py doc2.pdf
    CE->>GPU2: Execute task 3: worker.py doc3.pdf
    CE->>GPU2: Execute task 4: worker.py doc4.pdf

    GPU1->>COS: Read doc1.pdf from /input
    GPU1->>GPU1: Docling GPU pipeline\n(OCR + TableFormer)
    GPU1->>COS: Write doc1_result.md to /output

    GPU2->>COS: Read doc3.pdf from /input
    GPU2->>GPU2: Docling GPU pipeline
    GPU2->>COS: Write doc3_result.md to /output

    Note over App,GPU2: Completion & Cleanup Phase

    GPU1-->>CE: Task 1 complete (exit 0)
    GPU2-->>CE: Task 3 complete (exit 0)
    CE-->>App: Fleet status: completed
    CE->>GPU1: Terminate instance
    CE->>GPU2: Terminate instance

    Note over GPU1,GPU2: Workers scale to ZERO — no idle cost
```

---

## 10. State Machine — Job Lifecycle

State transitions for a document processing job.

```mermaid
stateDiagram-v2
    [*] --> Pending : POST /upload (job created)

    Pending --> Running : Background thread starts processing

    Running --> UploadingToCOS : Fleet mode - uploading documents

    UploadingToCOS --> LaunchingFleet : Documents uploaded to COS input bucket

    LaunchingFleet --> FleetRunning : Fleet created (ibmcloud ce fleet create)

    FleetRunning --> FleetRunning : Polling fleet status every 10s

    FleetRunning --> DownloadingResults : Fleet completed - all tasks done

    DownloadingResults --> Completed : Results downloaded from COS

    Running --> Completed : Local mode - Docling finished

    Pending --> Failed : Startup error
    Running --> Failed : Processing error
    UploadingToCOS --> Failed : COS upload error
    LaunchingFleet --> Failed : Fleet launch error
    FleetRunning --> Failed : Fleet task error
    DownloadingResults --> Failed : COS download error

    Completed --> [*] : Job archived - results available
    Failed --> [*] : Error logged - retry available

    note right of FleetRunning
        Progress updates:
        0 percent = fleet launching
        10-90 percent = tasks completing
        100 percent = all tasks done
    end note

    note right of Completed
        Results available at
        GET /job/{id}/download
        Returns ZIP of markdown files
    end note
```

---

## 11. Infrastructure — Terraform Provisioning

IBM Cloud resources provisioned by Terraform.

```mermaid
graph TB
    subgraph Terraform["🏗️ Terraform (Scripts/deploy-terraform/)"]
        TFMain["main.tf\n(resource definitions)"]
        TFVars["variables.tf\n(input variables)"]
        TFTfvars["terraform.tfvars\n(values)"]
    end

    subgraph IBMCloudResources["☁️ IBM Cloud Resources Created"]
        subgraph ResourceGroup["Resource Group"]
            RG["ibm_resource_group\ndoclinggpu-rg"]
        end

        subgraph COSResources["Object Storage"]
            COSInstance["ibm_resource_instance\n(COS Standard)"]
            InputBucket["ibm_cos_bucket\ndoclinggpu-input-{suffix}"]
            OutputBucket["ibm_cos_bucket\ndoclinggpu-output-{suffix}"]
            COSCredentials["ibm_resource_key\n(HMAC credentials)"]
        end

        subgraph CEResources["Code Engine"]
            CEProject["ibm_code_engine_project\ndoclinggpu-project"]
            CESecret["ibm_code_engine_secret\ncos-credentials"]
            CEApp["ibm_code_engine_app\ndoclinggpu-webapp\n(min-scale=0, max-scale=5)"]
        end
    end

    TFMain -->|"creates"| RG
    TFMain -->|"creates"| COSInstance
    TFMain -->|"creates"| InputBucket
    TFMain -->|"creates"| OutputBucket
    TFMain -->|"creates"| COSCredentials
    TFMain -->|"creates"| CEProject
    TFMain -->|"creates"| CESecret
    TFMain -->|"creates"| CEApp
    TFVars -->|"defines"| TFMain
    TFTfvars -->|"values"| TFVars
    COSCredentials -->|"stored in"| CESecret
    CESecret -->|"mounted by"| CEApp
    InputBucket -->|"referenced by"| CEApp
    OutputBucket -->|"referenced by"| CEApp
    COSInstance -->|"contains"| InputBucket
    COSInstance -->|"contains"| OutputBucket
    CEProject -->|"hosts"| CEApp

    style Terraform fill:#6929c4,color:#fff
    style IBMCloudResources fill:#161616,color:#fff
    style ResourceGroup fill:#393939,color:#fff
    style COSResources fill:#9f1853,color:#fff
    style CEResources fill:#0f62fe,color:#fff
```

---

## 12. Container Architecture

Docker container structure and relationships.

```mermaid
graph TB
    subgraph BaseImages["📦 Base Images"]
        PythonBase["python:3.11-slim\n(webapp base)"]
        DoclingBase["quay.io/docling-project/docling-serve\n(GPU worker base)"]
        DoclingCPUBase["quay.io/docling-project/docling-serve-cpu\n(CPU worker base)"]
    end

    subgraph BuildImages["🔨 Built Images"]
        WebAppImage["doclinggpu-webapp:latest\n(app/Dockerfile)\n\nFlask + Gunicorn + Gevent\nPort 8080\nUser: 1001 (non-root)"]
        GPUWorkerImage["doclinggpu-worker:latest\n(worker/Dockerfile.gpu)\n\nDocling + CUDA\nworker.py entrypoint\nGPU: L40s / H100"]
    end

    subgraph DockerCompose["🐳 Docker Compose Services"]
        WebService["webapp\n(doclinggpu-webapp)\nport: 8080:8080\nprofile: default"]
        CPUWorkerService["cpu-worker\n(doclinggpu-worker)\nprofile: cpu-worker\nmode: cpu"]
        GPUWorkerService["gpu-worker\n(doclinggpu-worker)\nprofile: gpu-worker\nruntime: nvidia\nmode: gpu"]
    end

    subgraph Volumes["💾 Volumes"]
        InputVol["./input:/app/input\n(read-only)"]
        OutputVol["./output:/app/output\n(read-write)"]
        UploadVol["uploads_data\n(named volume)"]
    end

    PythonBase -->|"FROM"| WebAppImage
    DoclingBase -->|"FROM"| GPUWorkerImage
    DoclingCPUBase -->|"used by"| CPUWorkerService

    WebAppImage -->|"image"| WebService
    GPUWorkerImage -->|"image"| CPUWorkerService
    GPUWorkerImage -->|"image"| GPUWorkerService

    WebService -->|"mount"| InputVol
    WebService -->|"mount"| OutputVol
    WebService -->|"mount"| UploadVol
    CPUWorkerService -->|"mount"| InputVol
    CPUWorkerService -->|"mount"| OutputVol
    GPUWorkerService -->|"mount"| InputVol
    GPUWorkerService -->|"mount"| OutputVol

    style BaseImages fill:#393939,color:#fff
    style BuildImages fill:#0f62fe,color:#fff
    style DockerCompose fill:#005d5d,color:#fff
    style Volumes fill:#6929c4,color:#fff
```

---

## 13. Network Architecture

Network topology and communication paths.

```mermaid
graph TB
    subgraph External["🌐 External Network"]
        Browser["User Browser\n(HTTPS :443)"]
        GitHubActions["GitHub Actions\n(CI/CD)"]
    end

    subgraph IBMCloudNetwork["☁️ IBM Cloud Network"]
        subgraph PublicEndpoint["Public Endpoint"]
            CEIngress["Code Engine\nIngress\n(auto-provisioned)"]
        end

        subgraph PrivateNetwork["Private Network (10.x.x.x)"]
            subgraph CEProject["Code Engine Project VPC"]
                WebApp["Web App\n:8080"]
                FleetWorkers["Fleet Workers\n(ephemeral)"]
            end

            subgraph COSEndpoint["COS Private Endpoint"]
                COSPrivate["s3.private.eu-de\n.cloud-object-storage\n.appdomain.cloud"]
            end
        end

        subgraph ICREndpoint["Container Registry"]
            ICRPrivate["de.icr.io\n(private endpoint)"]
        end
    end

    Browser -->|"HTTPS :443"| CEIngress
    CEIngress -->|"HTTP :8080"| WebApp
    GitHubActions -->|"docker push"| ICRPrivate
    WebApp -->|"private :443"| COSPrivate
    FleetWorkers -->|"private :443"| COSPrivate
    WebApp -->|"ibmcloud CLI"| FleetWorkers
    ICRPrivate -->|"image pull"| WebApp
    ICRPrivate -->|"image pull"| FleetWorkers

    style External fill:#0043ce,color:#fff
    style IBMCloudNetwork fill:#161616,color:#fff
    style PublicEndpoint fill:#198038,color:#fff
    style PrivateNetwork fill:#262626,color:#fff
    style CEProject fill:#0f62fe,color:#fff
    style COSEndpoint fill:#9f1853,color:#fff
    style ICREndpoint fill:#6929c4,color:#fff
```

---

## 14. Security Architecture

Security controls and authentication flows.

```mermaid
graph TB
    subgraph AuthFlow["🔐 Authentication Flow"]
        User["User\n(browser)"]
        CEApp["Code Engine App\n(HTTPS only)"]
        IAMAuth["IBM IAM\n(API Key auth)"]
        COSAuth["COS HMAC\n(S3-compatible)"]
        ICRAuth["ICR\n(registry auth)"]
    end

    subgraph Secrets["🔑 Secret Management"]
        CESecrets["Code Engine Secrets\n(encrypted at rest)"]
        EnvVars["Environment Variables\n(injected at runtime)"]
        NoHardcode["❌ No hardcoded\ncredentials in code"]
    end

    subgraph NetworkSec["🛡️ Network Security"]
        TLSOnly["TLS 1.2+ only\n(HTTPS enforced)"]
        PrivateEndpoints["Private COS endpoints\n(no public internet)"]
        NonRoot["Non-root container\n(UID 1001)"]
        ReadOnly["Read-only input\n(volume mount)"]
    end

    subgraph DataSec["🔒 Data Security"]
        EncryptRest["COS encryption\nat rest (AES-256)"]
        EncryptTransit["TLS encryption\nin transit"]
        TempFiles["Temp files in\n/tmp (ephemeral)"]
        NoLogs["No document content\nin logs"]
    end

    User -->|"HTTPS"| CEApp
    CEApp -->|"API Key"| IAMAuth
    IAMAuth -->|"authorize"| COSAuth
    CEApp -->|"HMAC keys"| COSAuth
    CEApp -->|"registry token"| ICRAuth
    IAMAuth -->|"stored in"| CESecrets
    COSAuth -->|"stored in"| CESecrets
    CESecrets -->|"injected as"| EnvVars
    EnvVars -->|"used by"| CEApp

    style AuthFlow fill:#6929c4,color:#fff
    style Secrets fill:#9f1853,color:#fff
    style NetworkSec fill:#005d5d,color:#fff
    style DataSec fill:#0043ce,color:#fff
```

---

## Summary

The DoclingGPU architecture is designed around three core principles:

1. **Cost Efficiency**: Fleet workers scale to zero when idle. GPU instances are provisioned only for the duration of document processing, then terminated automatically.

2. **Scalability**: The Code Engine application auto-scales from 0 to N instances based on HTTP traffic. Fleet workers scale horizontally based on the number of documents in `commands.jsonl`.

3. **Flexibility**: Three processing modes (local, fleet-cpu, fleet-gpu) allow the same application to run on a developer laptop, a CPU cluster, or a GPU-accelerated cloud fleet — with no code changes.

For deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md).
For local development setup, see [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md).
For API reference, see [API.md](./API.md).