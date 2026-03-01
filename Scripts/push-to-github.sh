#!/bin/bash
# ============================================================
# DoclingGPU - Push to GitHub
# Pushes code to GitHub, ignoring all folders starting with "_"
#
# Usage:
#   ./Scripts/push-to-github.sh --repo https://github.com/USER/REPO.git
#   ./Scripts/push-to-github.sh --repo https://github.com/USER/REPO.git --branch main -m "my message"
#   ./Scripts/push-to-github.sh --dry-run
#   ./Scripts/push-to-github.sh --force
# ============================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
log_step()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── Defaults ─────────────────────────────────────────────────
REMOTE="origin"
BRANCH="main"
COMMIT_MSG=""
REPO_URL="${GITHUB_REPO:-}"   # can also be set via env var
DRY_RUN=false
FORCE=false

# ── Argument parsing ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo|-r)        REPO_URL="$2";    shift 2 ;;
        --remote)         REMOTE="$2";      shift 2 ;;
        --branch|-b)      BRANCH="$2";      shift 2 ;;
        --message|-m)     COMMIT_MSG="$2";  shift 2 ;;
        --dry-run|-n)     DRY_RUN=true;     shift   ;;
        --force|-f)       FORCE=true;       shift   ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --repo URL        GitHub repository URL (required on first push)
                    e.g. https://github.com/user/repo.git
  --remote NAME     Git remote name (default: origin)
  --branch NAME     Target branch (default: main)
  --message MSG     Commit message (auto-generated if omitted)
  --dry-run         Show what would happen without executing
  --force           Force push (use with caution)

Environment variables:
  GITHUB_REPO       Same as --repo (alternative to flag)

Examples:
  # First push — provide the repo URL:
  $0 --repo https://github.com/myuser/docling-gpu.git

  # Subsequent pushes — remote is already configured:
  $0 -m "feat: add new feature"

  # Dry run to preview:
  $0 --dry-run
EOF
            exit 0
            ;;
        *) log_error "Unknown option: $1. Run $0 --help for usage." ;;
    esac
done

# ── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  DoclingGPU — Push to GitHub                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Verify git is installed ─────────────────────────
log_step "Checking prerequisites"
command -v git &>/dev/null || log_error "git is not installed. Install it first."
log_success "git $(git --version | awk '{print $3}') found"

# ── Step 2: Ensure we are in a git repo ─────────────────────
log_step "Git repository"

if [[ ! -d ".git" ]]; then
    log_info "No git repository found — initialising..."
    if $DRY_RUN; then
        log_info "[DRY RUN] Would run: git init && git checkout -b $BRANCH"
    else
        git init
        git checkout -b "$BRANCH" 2>/dev/null || git branch -M "$BRANCH"
        log_success "Initialised git repository on branch '$BRANCH'"
    fi
else
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    log_success "Git repository found (branch: $CURRENT_BRANCH)"
fi

# ── Step 3: Configure remote ─────────────────────────────────
log_step "Remote configuration"

if [[ -n "$REPO_URL" ]]; then
    if git remote get-url "$REMOTE" &>/dev/null; then
        EXISTING_URL=$(git remote get-url "$REMOTE")
        if [[ "$EXISTING_URL" != "$REPO_URL" ]]; then
            log_info "Updating remote '$REMOTE': $EXISTING_URL → $REPO_URL"
            if ! $DRY_RUN; then
                git remote set-url "$REMOTE" "$REPO_URL"
            fi
        else
            log_info "Remote '$REMOTE' already points to: $REPO_URL"
        fi
    else
        log_info "Adding remote '$REMOTE' → $REPO_URL"
        if ! $DRY_RUN; then
            git remote add "$REMOTE" "$REPO_URL"
        fi
    fi
    log_success "Remote '$REMOTE' = $REPO_URL"
else
    # No --repo flag — check if remote already exists
    if git remote get-url "$REMOTE" &>/dev/null; then
        EXISTING_URL=$(git remote get-url "$REMOTE")
        log_success "Remote '$REMOTE' = $EXISTING_URL"
    else
        # Prompt interactively if running in a terminal
        if [[ -t 0 ]]; then
            echo ""
            log_warn "No remote '$REMOTE' configured and --repo was not provided."
            echo -e "  Enter your GitHub repository URL (e.g. https://github.com/user/repo.git)"
            echo -n "  > "
            read -r REPO_URL
            if [[ -z "$REPO_URL" ]]; then
                log_error "No URL entered. Aborting."
            fi
            log_info "Adding remote '$REMOTE' → $REPO_URL"
            if ! $DRY_RUN; then
                git remote add "$REMOTE" "$REPO_URL"
            fi
            log_success "Remote '$REMOTE' = $REPO_URL"
        else
            log_error "No remote configured. Run:\n  $0 --repo https://github.com/USER/REPO.git"
        fi
    fi
fi

# ── Step 4: Ensure .gitignore excludes _ folders ─────────────
log_step "Updating .gitignore"

GITIGNORE_FILE=".gitignore"
if [[ ! -f "$GITIGNORE_FILE" ]]; then
    log_info "Creating .gitignore"
    if ! $DRY_RUN; then
        touch "$GITIGNORE_FILE"
    fi
fi

if ! grep -q "^_\*/" "$GITIGNORE_FILE" 2>/dev/null; then
    log_info "Adding underscore-folder exclusion to .gitignore"
    if ! $DRY_RUN; then
        printf '\n# Exclude all folders starting with underscore\n_*/\n' >> "$GITIGNORE_FILE"
    fi
fi
log_success ".gitignore is up to date"

# Show which _ folders are excluded
UNDERSCORE_DIRS=$(find . -maxdepth 1 -type d -name "_*" 2>/dev/null | sort)
if [[ -n "$UNDERSCORE_DIRS" ]]; then
    log_info "Folders excluded (start with '_'):"
    while IFS= read -r dir; do
        echo "    ✗  $dir"
    done <<< "$UNDERSCORE_DIRS"
fi

# ── Step 5: Stage all files ───────────────────────────────────
log_step "Staging files"

if $DRY_RUN; then
    log_info "[DRY RUN] Would run: git add --all"
    log_info "Files that would be staged (excluding _* folders):"
    git status --short | grep -v "^?? _" | head -40 || true
else
    git add --all

    # Safety: unstage anything that slipped through from _ folders
    STAGED_UNDERSCORE=$(git diff --cached --name-only 2>/dev/null | { grep "^_" || true; } | wc -l | tr -d ' ')
    if [[ "$STAGED_UNDERSCORE" -gt 0 ]]; then
        log_warn "Removing $STAGED_UNDERSCORE _ folder file(s) from staging area..."
        git diff --cached --name-only | { grep "^_" || true; } | xargs --no-run-if-empty git reset HEAD -- 2>/dev/null || true
    fi

    STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    log_success "Staged $STAGED file(s)"
fi

# ── Step 6: Check if there is anything to commit ─────────────
log_step "Checking for changes"

# git diff --cached works even on repos with no prior commits
STAGED_COUNT=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

if [[ "$STAGED_COUNT" -eq 0 ]]; then
    log_info "Nothing staged to commit — working tree is clean."
    log_info "Attempting push of existing commits..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would push to $REMOTE $BRANCH"
        exit 0
    fi

    # Push existing commits (may fail if no commits at all)
    if git rev-parse HEAD &>/dev/null; then
        if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" &>/dev/null; then
            git push --set-upstream "$REMOTE" "$BRANCH" $( $FORCE && echo "--force" || true )
        else
            git push "$REMOTE" "$BRANCH" $( $FORCE && echo "--force" || true )
        fi
        log_success "Pushed to $(git remote get-url "$REMOTE") (branch: $BRANCH)"
    else
        log_warn "No commits exist yet and nothing staged. Nothing to push."
    fi
    exit 0
fi

log_success "$STAGED_COUNT file(s) staged and ready to commit"

# ── Step 7: Build commit message ─────────────────────────────
log_step "Preparing commit"

if [[ -z "$COMMIT_MSG" ]]; then
    TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M UTC")
    ADDED=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git diff --cached --name-only --diff-filter=M 2>/dev/null | wc -l | tr -d ' ')
    DELETED=$(git diff --cached --name-only --diff-filter=D 2>/dev/null | wc -l | tr -d ' ')
    COMMIT_MSG="feat: DoclingGPU update (+${ADDED} ~${MODIFIED} -${DELETED} files) [${TIMESTAMP}]"
fi

log_info "Commit message: $COMMIT_MSG"

# ── Step 8: Commit ────────────────────────────────────────────
if $DRY_RUN; then
    log_info "[DRY RUN] Would run: git commit -m \"$COMMIT_MSG\""
else
    git commit -m "$COMMIT_MSG"
    log_success "Committed: $COMMIT_MSG"
fi

# ── Step 9: Push ──────────────────────────────────────────────
log_step "Pushing to GitHub"

REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null || echo "unknown")

if $DRY_RUN; then
    log_info "[DRY RUN] Would run: git push [--set-upstream] [--force] $REMOTE $BRANCH"
    log_info "Target: $REMOTE_URL (branch: $BRANCH)"
    $FORCE && log_warn "[DRY RUN] Force push is enabled"
    echo ""
    log_success "Dry run complete — no changes made."
    exit 0
fi

# Determine if upstream tracking branch exists
# On a brand-new repo (no prior pushes) this will always be false
PUSH_FLAGS=()
if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" &>/dev/null 2>&1; then
    log_info "No upstream tracking branch — adding --set-upstream"
    PUSH_FLAGS+=("--set-upstream")
fi
if $FORCE; then
    log_warn "Force push enabled"
    PUSH_FLAGS+=("--force")
fi

# THE ACTUAL PUSH
git push "${PUSH_FLAGS[@]}" "$REMOTE" "$BRANCH"

echo ""
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Pushed to: $REMOTE_URL"
log_success "Branch:    $BRANCH"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Made with Bob
