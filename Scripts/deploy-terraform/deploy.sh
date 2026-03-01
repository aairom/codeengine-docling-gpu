#!/usr/bin/env bash
# ============================================================
# DoclingGPU — Terraform Deployment Wrapper Script
# Usage: ./deploy.sh [plan|apply|destroy|output|refresh]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS_FILE="${SCRIPT_DIR}/terraform.tfvars"
TFVARS_EXAMPLE="${SCRIPT_DIR}/terraform.tfvars.example"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

# ── Usage ────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}DoclingGPU Terraform Deployment Script${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  plan      Preview infrastructure changes"
    echo "  apply     Apply infrastructure changes"
    echo "  destroy   Destroy all infrastructure (CAREFUL!)"
    echo "  output    Show Terraform outputs"
    echo "  refresh   Refresh Terraform state"
    echo "  validate  Validate Terraform configuration"
    echo "  init      Initialize Terraform (run first time)"
    echo "  fmt       Format Terraform files"
    echo ""
    echo "Options:"
    echo "  --auto-approve    Skip confirmation prompts (apply/destroy)"
    echo "  --var-file FILE   Use custom tfvars file (default: terraform.tfvars)"
    echo "  --target RESOURCE Target specific resource"
    echo ""
    echo "Examples:"
    echo "  $0 init"
    echo "  $0 plan"
    echo "  $0 apply"
    echo "  $0 apply --auto-approve"
    echo "  $0 destroy --auto-approve"
    echo "  $0 output"
    echo ""
    exit 1
}

# ── Parse Arguments ──────────────────────────────────────────
COMMAND="${1:-}"
AUTO_APPROVE=""
CUSTOM_VAR_FILE=""
TARGET_RESOURCE=""

shift || true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-approve)
            AUTO_APPROVE="-auto-approve"
            shift
            ;;
        --var-file)
            CUSTOM_VAR_FILE="$2"
            shift 2
            ;;
        --target)
            TARGET_RESOURCE="-target=$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    usage
fi

# ── Use custom var file if provided ─────────────────────────
if [[ -n "$CUSTOM_VAR_FILE" ]]; then
    TFVARS_FILE="$CUSTOM_VAR_FILE"
fi

# ── Check Prerequisites ──────────────────────────────────────
check_prerequisites() {
    header "Checking Prerequisites"

    # Check Terraform
    if ! command -v terraform &>/dev/null; then
        error "Terraform is not installed."
        echo "Install from: https://developer.hashicorp.com/terraform/install"
        exit 1
    fi
    TF_VERSION=$(terraform version -json | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null || terraform version | head -1 | awk '{print $2}')
    ok "Terraform: $TF_VERSION"

    # Check IBM Cloud CLI (optional, for post-deploy verification)
    if command -v ibmcloud &>/dev/null; then
        ok "IBM Cloud CLI: $(ibmcloud version 2>/dev/null | head -1)"
    else
        warn "IBM Cloud CLI not found (optional for verification)"
    fi

    # Check tfvars file
    if [[ "$COMMAND" != "init" && "$COMMAND" != "fmt" && "$COMMAND" != "validate" ]]; then
        if [[ ! -f "$TFVARS_FILE" ]]; then
            error "terraform.tfvars not found at: $TFVARS_FILE"
            echo ""
            echo "Create it from the example:"
            echo "  cp $TFVARS_EXAMPLE $TFVARS_FILE"
            echo "  nano $TFVARS_FILE  # Fill in your values"
            exit 1
        fi
        ok "tfvars file: $TFVARS_FILE"
    fi
}

# ── Terraform Init ───────────────────────────────────────────
run_init() {
    header "Initializing Terraform"
    cd "$SCRIPT_DIR"

    terraform init \
        -upgrade \
        -reconfigure

    ok "Terraform initialized successfully"
}

# ── Terraform Validate ───────────────────────────────────────
run_validate() {
    header "Validating Terraform Configuration"
    cd "$SCRIPT_DIR"

    terraform validate
    ok "Configuration is valid"
}

# ── Terraform Format ─────────────────────────────────────────
run_fmt() {
    header "Formatting Terraform Files"
    cd "$SCRIPT_DIR"

    terraform fmt -recursive
    ok "Files formatted"
}

# ── Terraform Plan ───────────────────────────────────────────
run_plan() {
    header "Planning Infrastructure Changes"
    cd "$SCRIPT_DIR"

    log "Running: terraform plan"
    log "Using vars: $TFVARS_FILE"
    echo ""

    terraform plan \
        -var-file="$TFVARS_FILE" \
        ${TARGET_RESOURCE} \
        -out=tfplan

    echo ""
    ok "Plan saved to: tfplan"
    echo ""
    echo "To apply this plan, run:"
    echo "  $0 apply"
    echo "  OR: terraform apply tfplan"
}

# ── Terraform Apply ──────────────────────────────────────────
run_apply() {
    header "Applying Infrastructure Changes"
    cd "$SCRIPT_DIR"

    # Check if saved plan exists
    if [[ -f "tfplan" && -z "$AUTO_APPROVE" ]]; then
        log "Found saved plan: tfplan"
        echo -n "Apply saved plan? [y/N] "
        read -r USE_SAVED
        if [[ "$USE_SAVED" =~ ^[Yy]$ ]]; then
            terraform apply tfplan
            rm -f tfplan
            show_outputs
            return
        fi
    fi

    log "Running: terraform apply"
    log "Using vars: $TFVARS_FILE"
    echo ""

    if [[ -z "$AUTO_APPROVE" ]]; then
        echo -e "${YELLOW}⚠️  This will create/modify IBM Cloud resources and may incur costs.${NC}"
        echo -n "Continue? [y/N] "
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log "Aborted."
            exit 0
        fi
    fi

    terraform apply \
        -var-file="$TFVARS_FILE" \
        ${TARGET_RESOURCE} \
        ${AUTO_APPROVE}

    echo ""
    ok "Infrastructure applied successfully!"
    show_outputs
}

# ── Terraform Destroy ────────────────────────────────────────
run_destroy() {
    header "Destroying Infrastructure"
    cd "$SCRIPT_DIR"

    echo -e "${RED}⚠️  WARNING: This will PERMANENTLY DELETE all DoclingGPU infrastructure!${NC}"
    echo -e "${RED}   This includes COS buckets (and all stored documents/results)!${NC}"
    echo ""

    if [[ -z "$AUTO_APPROVE" ]]; then
        echo -n "Type 'destroy' to confirm: "
        read -r CONFIRM
        if [[ "$CONFIRM" != "destroy" ]]; then
            log "Aborted."
            exit 0
        fi
    fi

    log "Running: terraform destroy"
    log "Using vars: $TFVARS_FILE"
    echo ""

    terraform destroy \
        -var-file="$TFVARS_FILE" \
        ${TARGET_RESOURCE} \
        ${AUTO_APPROVE}

    echo ""
    ok "Infrastructure destroyed."
    warn "All IBM Cloud resources have been deleted."
}

# ── Terraform Output ─────────────────────────────────────────
show_outputs() {
    header "Terraform Outputs"
    cd "$SCRIPT_DIR"

    if terraform output &>/dev/null 2>&1; then
        terraform output
    else
        warn "No outputs available yet. Run 'apply' first."
    fi
}

# ── Terraform Refresh ────────────────────────────────────────
run_refresh() {
    header "Refreshing Terraform State"
    cd "$SCRIPT_DIR"

    terraform refresh \
        -var-file="$TFVARS_FILE"

    ok "State refreshed"
}

# ── Post-Apply Verification ──────────────────────────────────
verify_deployment() {
    if ! command -v ibmcloud &>/dev/null; then
        return
    fi

    header "Verifying Deployment"

    # Get outputs
    APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
    CE_PROJECT=$(terraform output -raw ce_project_name 2>/dev/null || echo "")

    if [[ -n "$APP_URL" ]]; then
        log "Testing health endpoint: $APP_URL/health"
        if curl -sf "$APP_URL/health" &>/dev/null; then
            ok "Application is healthy: $APP_URL"
        else
            warn "Health check failed. App may still be starting up."
            log "Check status with: ibmcloud ce app get --name doclinggpu-webapp"
        fi
    fi

    if [[ -n "$CE_PROJECT" ]]; then
        log "Code Engine project: $CE_PROJECT"
    fi
}

# ── Main ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   DoclingGPU — Terraform Deployment      ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    case "$COMMAND" in
        init)
            run_init
            ;;
        validate)
            check_prerequisites
            run_validate
            ;;
        fmt|format)
            run_fmt
            ;;
        plan)
            check_prerequisites
            # Auto-init if .terraform doesn't exist
            if [[ ! -d "$SCRIPT_DIR/.terraform" ]]; then
                log "Terraform not initialized. Running init first..."
                run_init
            fi
            run_plan
            ;;
        apply)
            check_prerequisites
            if [[ ! -d "$SCRIPT_DIR/.terraform" ]]; then
                log "Terraform not initialized. Running init first..."
                run_init
            fi
            run_apply
            verify_deployment
            ;;
        destroy)
            check_prerequisites
            run_destroy
            ;;
        output|outputs)
            check_prerequisites
            show_outputs
            ;;
        refresh)
            check_prerequisites
            run_refresh
            ;;
        *)
            error "Unknown command: $COMMAND"
            usage
            ;;
    esac
}

main "$@"

# Made with Bob
