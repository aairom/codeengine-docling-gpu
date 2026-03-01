#!/bin/bash
# ============================================================
# DoclingGPU - IBM Cloud Code Engine Deployment Script
# Deploys the web application as a serverless Code Engine app
# and configures the fleet infrastructure.
# ============================================================

set -euo pipefail

# ============================================================
# Configuration - Edit these or set as environment variables
# ============================================================
CE_REGION="${CE_REGION:-eu-de}"
CE_RESOURCE_GROUP="${CE_RESOURCE_GROUP:-default}"
CE_PROJECT_NAME="${CE_PROJECT_NAME:-doclinggpu-project}"
CE_APP_NAME="${CE_APP_NAME:-doclinggpu-webapp}"
CE_REGISTRY="${CE_REGISTRY:-}"                          # e.g. de.icr.io
CE_REGISTRY_NAMESPACE="${CE_REGISTRY_NAMESPACE:-}"      # e.g. my-namespace
CE_REGISTRY_SECRET="${CE_REGISTRY_SECRET:-ce-auto-icr-private-eu-de}"
COS_INSTANCE_NAME="${COS_INSTANCE_NAME:-doclinggpu-cos}"
COS_INPUT_BUCKET="${COS_INPUT_BUCKET:-doclinggpu-input}"
COS_OUTPUT_BUCKET="${COS_OUTPUT_BUCKET:-doclinggpu-output}"
APP_IMAGE_TAG="${APP_IMAGE_TAG:-latest}"
SECRET_KEY="${SECRET_KEY:-$(openssl rand -hex 32)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================
# Helper functions
# ============================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_step()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

check_prereqs() {
    log_step "Checking prerequisites"
    
    local missing=0
    for cmd in ibmcloud docker; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done
    
    # Check ibmcloud plugins
    for plugin in code-engine container-registry; do
        if ! ibmcloud plugin list | grep -q "$plugin"; then
            log_warn "Installing ibmcloud plugin: $plugin"
            ibmcloud plugin install "$plugin" -f
        fi
    done
    
    [[ $missing -eq 0 ]] && log_success "All prerequisites met"
}

login_ibmcloud() {
    log_step "IBM Cloud Login"
    
    if [[ -n "${IBMCLOUD_API_KEY:-}" ]]; then
        ibmcloud login --apikey "$IBMCLOUD_API_KEY" -r "$CE_REGION" -g "$CE_RESOURCE_GROUP" -q
        log_success "Logged in with API key"
    else
        log_warn "IBMCLOUD_API_KEY not set. Attempting interactive login..."
        ibmcloud login -r "$CE_REGION" -g "$CE_RESOURCE_GROUP"
    fi
    
    ibmcloud target -r "$CE_REGION" -g "$CE_RESOURCE_GROUP"
}

setup_registry() {
    log_step "Container Registry Setup"
    
    if [[ -z "$CE_REGISTRY" ]]; then
        CE_REGISTRY="private.${CE_REGION}.icr.io"
        log_info "Using registry: $CE_REGISTRY"
    fi
    
    if [[ -z "$CE_REGISTRY_NAMESPACE" ]]; then
        CE_REGISTRY_NAMESPACE="doclinggpu-$(openssl rand -hex 4)"
        log_info "Creating registry namespace: $CE_REGISTRY_NAMESPACE"
        ibmcloud cr namespace-add "$CE_REGISTRY_NAMESPACE" || true
    fi
    
    # Login to container registry
    ibmcloud cr login
    log_success "Registry configured: ${CE_REGISTRY}/${CE_REGISTRY_NAMESPACE}"
}

build_and_push_image() {
    log_step "Building and Pushing Web App Image"
    
    local image="${CE_REGISTRY}/${CE_REGISTRY_NAMESPACE}/${CE_APP_NAME}:${APP_IMAGE_TAG}"
    local build_date
    build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log_info "Building image: $image"
    docker build \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VERSION="$APP_IMAGE_TAG" \
        -t "$image" \
        ./app/
    
    log_info "Pushing image: $image"
    docker push "$image"
    
    export APP_IMAGE="$image"
    log_success "Image pushed: $image"
}

setup_cos() {
    log_step "Cloud Object Storage Setup"
    
    # Check if COS instance exists
    if ! ibmcloud resource service-instance "$COS_INSTANCE_NAME" &>/dev/null; then
        log_info "Creating COS instance: $COS_INSTANCE_NAME"
        ibmcloud resource service-instance-create \
            "$COS_INSTANCE_NAME" \
            cloud-object-storage \
            standard \
            global
    else
        log_info "COS instance already exists: $COS_INSTANCE_NAME"
    fi
    
    # Get COS CRN
    COS_CRN=$(ibmcloud resource service-instance "$COS_INSTANCE_NAME" --output json | \
              python3 -c "import sys,json; print(json.load(sys.stdin)[0]['crn'])")
    
    # Create buckets
    for bucket in "$COS_INPUT_BUCKET" "$COS_OUTPUT_BUCKET"; do
        log_info "Creating bucket: $bucket"
        ibmcloud cos bucket-create \
            --bucket "$bucket" \
            --ibm-service-instance-id "$COS_CRN" \
            --region "$CE_REGION" 2>/dev/null || log_warn "Bucket may already exist: $bucket"
    done
    
    log_success "COS configured"
}

setup_ce_project() {
    log_step "Code Engine Project Setup"
    
    # Create or select project
    if ! ibmcloud ce project get --name "$CE_PROJECT_NAME" &>/dev/null; then
        log_info "Creating Code Engine project: $CE_PROJECT_NAME"
        ibmcloud ce project create --name "$CE_PROJECT_NAME"
    fi
    
    ibmcloud ce project select --name "$CE_PROJECT_NAME"
    log_success "Project selected: $CE_PROJECT_NAME"
}

setup_ce_secrets() {
    log_step "Code Engine Secrets & Config"
    
    # Create registry secret if not exists
    if ! ibmcloud ce secret get --name "$CE_REGISTRY_SECRET" &>/dev/null; then
        log_info "Creating registry secret: $CE_REGISTRY_SECRET"
        ibmcloud ce secret create \
            --name "$CE_REGISTRY_SECRET" \
            --format registry \
            --server "$CE_REGISTRY" \
            --username iamapikey \
            --password "$IBMCLOUD_API_KEY"
    fi
    
    # Create app secrets
    ibmcloud ce secret create \
        --name doclinggpu-secrets \
        --from-literal SECRET_KEY="$SECRET_KEY" \
        --from-literal CE_REGION="$CE_REGION" \
        --from-literal CE_REGISTRY_SECRET="$CE_REGISTRY_SECRET" \
        2>/dev/null || \
    ibmcloud ce secret update \
        --name doclinggpu-secrets \
        --from-literal SECRET_KEY="$SECRET_KEY" \
        --from-literal CE_REGION="$CE_REGION"
    
    log_success "Secrets configured"
}

deploy_webapp() {
    log_step "Deploying Web Application to Code Engine"
    
    local image="${APP_IMAGE:-${CE_REGISTRY}/${CE_REGISTRY_NAMESPACE}/${CE_APP_NAME}:${APP_IMAGE_TAG}}"
    
    # Check if app exists
    if ibmcloud ce app get --name "$CE_APP_NAME" &>/dev/null; then
        log_info "Updating existing app: $CE_APP_NAME"
        ibmcloud ce app update \
            --name "$CE_APP_NAME" \
            --image "$image" \
            --registry-secret "$CE_REGISTRY_SECRET" \
            --env PROCESSING_MODE=fleet-gpu \
            --env CE_REGION="$CE_REGION" \
            --env CE_INPUT_STORE=fleet-input-store \
            --env CE_OUTPUT_STORE=fleet-output-store \
            --env CE_FLEET_TASK_STORE=fleet-task-store \
            --env CE_FLEET_SUBNETPOOL=fleet-subnetpool \
            --env CE_REGISTRY_SECRET="$CE_REGISTRY_SECRET" \
            --env-from-secret doclinggpu-secrets \
            --cpu 1 \
            --memory 4G \
            --min-scale 0 \
            --max-scale 5 \
            --port 8080 \
            --timeout 300
    else
        log_info "Creating new app: $CE_APP_NAME"
        ibmcloud ce app create \
            --name "$CE_APP_NAME" \
            --image "$image" \
            --registry-secret "$CE_REGISTRY_SECRET" \
            --env PROCESSING_MODE=fleet-gpu \
            --env CE_REGION="$CE_REGION" \
            --env CE_INPUT_STORE=fleet-input-store \
            --env CE_OUTPUT_STORE=fleet-output-store \
            --env CE_FLEET_TASK_STORE=fleet-task-store \
            --env CE_FLEET_SUBNETPOOL=fleet-subnetpool \
            --env CE_REGISTRY_SECRET="$CE_REGISTRY_SECRET" \
            --env-from-secret doclinggpu-secrets \
            --cpu 1 \
            --memory 4G \
            --min-scale 0 \
            --max-scale 5 \
            --port 8080 \
            --timeout 300
    fi
    
    # Get app URL
    APP_URL=$(ibmcloud ce app get --name "$CE_APP_NAME" --output json | \
              python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('url',''))")
    
    log_success "App deployed: $APP_URL"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  DoclingGPU deployed successfully!               ║${NC}"
    echo -e "${GREEN}║  URL: ${APP_URL}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
}

print_summary() {
    echo ""
    log_step "Deployment Summary"
    echo "  Region:          $CE_REGION"
    echo "  Project:         $CE_PROJECT_NAME"
    echo "  App:             $CE_APP_NAME"
    echo "  Registry:        ${CE_REGISTRY}/${CE_REGISTRY_NAMESPACE}"
    echo "  COS Input:       $COS_INPUT_BUCKET"
    echo "  COS Output:      $COS_OUTPUT_BUCKET"
    echo ""
    echo "Next steps:"
    echo "  1. Upload documents to COS: ibmcloud cos object-put --bucket $COS_INPUT_BUCKET --key pdfs/doc.pdf --body ./input/doc.pdf"
    echo "  2. Open the web app and start processing"
    echo "  3. Monitor fleets: ibmcloud ce fleet list"
    echo ""
}

# ============================================================
# Main
# ============================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  DoclingGPU - IBM Code Engine Deployment         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prereqs
    login_ibmcloud
    setup_registry
    build_and_push_image
    setup_cos
    setup_ce_project
    setup_ce_secrets
    deploy_webapp
    print_summary
}

# Parse arguments
SKIP_BUILD=false
SKIP_COS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)   SKIP_BUILD=true; shift ;;
        --skip-cos)     SKIP_COS=true; shift ;;
        --region)       CE_REGION="$2"; shift 2 ;;
        --project)      CE_PROJECT_NAME="$2"; shift 2 ;;
        --app-name)     CE_APP_NAME="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --skip-build    Skip Docker build and push"
            echo "  --skip-cos      Skip COS bucket creation"
            echo "  --region        IBM Cloud region (default: eu-de)"
            echo "  --project       Code Engine project name"
            echo "  --app-name      Code Engine app name"
            exit 0
            ;;
        *) log_error "Unknown option: $1" ;;
    esac
done

main

# Made with Bob
