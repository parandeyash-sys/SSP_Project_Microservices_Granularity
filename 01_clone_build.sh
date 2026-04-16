#!/usr/bin/env bash
# =============================================================================
# 01_clone_build.sh — Clone Online Boutique (Service Weaver) & build binary
# =============================================================================
set -euo pipefail

export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
export GOPATH="$HOME/go"

LOG="experiment.log"
REPO_DIR="onlineboutique"
REPO_URL="https://github.com/ServiceWeaver/onlineboutique.git"
BINARY="boutique"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo "[$TIMESTAMP] [BUILD] Starting clone & build" | tee -a "$LOG"

# ── 1. Clone repo ─────────────────────────────────────────────────────────────
if [ -d "$REPO_DIR/.git" ]; then
    info "Repository already cloned. Pulling latest..."
    git -C "$REPO_DIR" pull --ff-only
else
    info "Cloning ${REPO_URL}..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# ── 2. Check Go version ───────────────────────────────────────────────────────
go version || error "Go not found. Run 00_install_deps.sh first."

# ── 3. Download module dependencies ──────────────────────────────────────────
info "Downloading Go module dependencies..."
go mod download

# ── 4. Generate Service Weaver boilerplate ────────────────────────────────────
info "Running weaver generate..."
go generate ./... || {
    # Some versions embed generate in go:generate, others need explicit call
    weaver generate ./...
}

# ── 5. Build binary ───────────────────────────────────────────────────────────
info "Building binary: ${BINARY}..."
go build -o "${BINARY}" .
ls -lh "${BINARY}"

cd ..

echo ""
info "Build complete!"
info "Binary: onlineboutique/${BINARY}"
info "Next step: Run  ./02_run_1vm_experiments.sh  to start 1-VM experiments."
echo "[$TIMESTAMP] [BUILD] Build complete → onlineboutique/${BINARY}" | tee -a "$LOG"
