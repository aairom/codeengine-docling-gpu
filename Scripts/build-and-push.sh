#!/bin/bash
# ============================================================
# DoclingGPU - Build and Push Container Images
# Builds webapp and worker images, pushes to registry
# ============================================================

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
REGISTRY="${REGISTRY:-de.icr.io}"
NAMESPACE="${NAMESPACE:-doclinggpu}"
VERSION="${VERSION:-latest}"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

WEBAPP_IMAGE="${REGISTRY}/${NAMESPACE}/doclinggpu-webapp:${VERSION}"
WORKER_GPU_IMAGE="${REGISTRY}/${NAMESPACE}/doclinggpu-worker-gpu:${VERSION}"

# Colors
GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_step()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

BUILD_WEBAPP=true
BUILD_WORKER=true
PUSH=true
PLATFORM="${PLATFORM:-linux/amd64}"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --webapp-only)  BUILD_WORKER=false; shift ;;
        --worker-only)  BUILD_WEBAPP=false; shift ;;
        --no-push)      PUSH=false; shift ;;
        --version)      VERSION="$2"; shift 2 ;;
        --registry)     REGISTRY="$2"; shift 2 ;;
        --namespace)    NAMESPACE="$2"; shift 2 ;;
        --platform)     PLATFORM="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --webapp-only    Build only the web app image"
            echo "  --worker-only    Build only the worker image"
            echo "  --no-push        Build but don't push"
            echo "  --version TAG    Image tag (default: latest)"
            echo "  --registry REG   Container registry"
            echo "  --namespace NS   Registry namespace"
            echo "  --platform PLAT  Build platform (default: linux/amd64)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Recalculate image names after arg parsing
WEBAPP_IMAGE="${REGISTRY}/${NAMESPACE}/doclinggpu-webapp:${VERSION}"
WORKER_GPU_IMAGE="${REGISTRY}/${NAMESPACE}/doclinggpu-worker-gpu:${VERSION}"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  DoclingGPU - Build & Push                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
log_info "Registry:  $REGISTRY/$NAMESPACE"
log_info "Version:   $VERSION"
log_info "Platform:  $PLATFORM"
echo ""

# ============================================================
# Build Web App
# ============================================================
if $BUILD_WEBAPP; then
    log_step "Building Web Application"
    log_info "Image: $WEBAPP_IMAGE"
    
    docker build \
        --platform "$PLATFORM" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VERSION="$VERSION" \
        --tag "$WEBAPP_IMAGE" \
        --tag "${REGISTRY}/${NAMESPACE}/doclinggpu-webapp:latest" \
        --file ./app/Dockerfile \
        ./app/
    
    log_success "Web app image built: $WEBAPP_IMAGE"
    
    if $PUSH; then
        log_info "Pushing: $WEBAPP_IMAGE"
        docker push "$WEBAPP_IMAGE"
        docker push "${REGISTRY}/${NAMESPACE}/doclinggpu-webapp:latest"
        log_success "Web app image pushed"
    fi
fi

# ============================================================
# Build GPU Worker
# ============================================================
if $BUILD_WORKER; then
    log_step "Building GPU Worker"
    log_info "Image: $WORKER_GPU_IMAGE"
    
    docker build \
        --platform "$PLATFORM" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VERSION="$VERSION" \
        --tag "$WORKER_GPU_IMAGE" \
        --tag "${REGISTRY}/${NAMESPACE}/doclinggpu-worker-gpu:latest" \
        --file ./worker/Dockerfile.gpu \
        ./worker/
    
    log_success "GPU worker image built: $WORKER_GPU_IMAGE"
    
    if $PUSH; then
        log_info "Pushing: $WORKER_GPU_IMAGE"
        docker push "$WORKER_GPU_IMAGE"
        docker push "${REGISTRY}/${NAMESPACE}/doclinggpu-worker-gpu:latest"
        log_success "GPU worker image pushed"
    fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
log_step "Build Summary"
if $BUILD_WEBAPP; then
    echo "  Web App:    $WEBAPP_IMAGE"
fi
if $BUILD_WORKER; then
    echo "  GPU Worker: $WORKER_GPU_IMAGE"
fi
echo ""
log_success "Done!"

# Made with Bob
