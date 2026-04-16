#!/usr/bin/env bash
# =============================================================================
# 00_install_deps.sh — Install all dependencies for the granularity study
# =============================================================================
# Installs: Go 1.22, Service Weaver CLI, Locust, matplotlib, pandas
# Run as your normal user (uses sudo where needed).
# =============================================================================
set -euo pipefail

LOG="experiment.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] [SETUP] Starting dependency installation" | tee -a "$LOG"

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. System packages ────────────────────────────────────────────────────────
info "Updating apt and installing base packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl wget git build-essential python3 python3-pip python3-venv \
    openssh-client openssh-server

# ── 2. Go 1.22 ───────────────────────────────────────────────────────────────
GO_VERSION="1.22.3"
GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"

if command -v go &>/dev/null && go version | grep -q "go1.2[2-9]"; then
    info "Go $(go version | awk '{print $3}') already installed — skipping."
else
    info "Downloading Go ${GO_VERSION}..."
    wget -q "$GO_URL" -O "/tmp/${GO_TAR}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${GO_TAR}"
    rm -f "/tmp/${GO_TAR}"
    info "Go ${GO_VERSION} installed at /usr/local/go"
fi

# Ensure Go is in PATH for this session and future sessions
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

if ! grep -q '/usr/local/go/bin' "$HOME/.bashrc"; then
    {
        echo ''
        echo '# ── Service Weaver / Go PATH ──'
        echo 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"'
        echo 'export GOPATH="$HOME/go"'
    } >> "$HOME/.bashrc"
    info "Added Go to ~/.bashrc"
fi

go version || error "Go installation failed"

# ── 3. Service Weaver CLI ─────────────────────────────────────────────────────
info "Installing Service Weaver CLI (weaver)..."
go install github.com/ServiceWeaver/weaver/cmd/weaver@latest
go install github.com/ServiceWeaver/weaver-multi/cmd/weaver-multi@latest   2>/dev/null || true
go install github.com/ServiceWeaver/weaver-ssh/cmd/weaver-ssh@latest       2>/dev/null || true

# The multi and ssh deployers ship inside the main weaver cmd in recent versions
weaver version || error "weaver CLI installation failed"
info "weaver CLI installed: $(weaver version)"

# ── 4. Python venv + Locust + plotting libs ───────────────────────────────────
VENV_DIR="$HOME/ssp_venv"
info "Creating Python venv at ${VENV_DIR}..."
python3 -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

pip install --quiet --upgrade pip
pip install --quiet locust matplotlib pandas seaborn tomli

locust --version || error "Locust installation failed"
info "Locust installed: $(locust --version)"

# Persist venv activation
if ! grep -q 'ssp_venv' "$HOME/.bashrc"; then
    {
        echo ''
        echo '# ── SSP Study Python venv ──'
        echo "source ${VENV_DIR}/bin/activate"
    } >> "$HOME/.bashrc"
fi

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo ""
info "All dependencies installed successfully."
info "Go:     $(go version)"
info "weaver: $(weaver version 2>/dev/null || echo 'check PATH')"
info "locust: $(locust --version)"
echo ""
warn "ACTION REQUIRED: Run  'source ~/.bashrc'  or open a new terminal before proceeding."
echo "[$TIMESTAMP] [SETUP] Dependency installation complete" | tee -a "$LOG"
