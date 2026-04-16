#!/usr/bin/env bash
# =============================================================================
# 02_run_2vm_experiments.sh — Run all 4 × 2-VM configuration experiments
# =============================================================================
# Uses Service Weaver's SSH deployer to distribute components across 2 machines.
#
# SETUP REQUIRED BEFORE RUNNING:
# ─────────────────────────────────────────────────────────────────────────────
#  1. Set VM2_HOST to the IP of your second VM:
#       export VM2_HOST="192.168.x.x"
#
#  2. Ensure passwordless SSH from VM1 (this machine) to VM2:
#       ssh-keygen -t ed25519 -f ~/.ssh/id_ssp -N ""
#       ssh-copy-id -i ~/.ssh/id_ssp.pub user@${VM2_HOST}
#       ssh -i ~/.ssh/id_ssp ${VM2_HOST} "echo ok"   # should print "ok"
#
#  3. Copy the boutique binary to VM2 (same path):
#       scp onlineboutique/boutique ${VM2_HOST}:~/ssp/SSP_Online/onlineboutique/boutique
#
#  4. Install Go + weaver on VM2 (run 00_install_deps.sh there too).
#
# Then run:  ./02_run_2vm_experiments.sh
# =============================================================================
set -euo pipefail

export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# ── Configuration ──────────────────────────────────────────────────────────────
VM1_HOST="${VM1_HOST:-127.0.0.1}"      # This machine's IP reachable from VM2
VM2_HOST="${VM2_HOST:-}"               # Second VM's IP — MUST be set!

BOUTIQUE_DIR="onlineboutique"
BINARY="${BOUTIQUE_DIR}/boutique"
CONFIGS_DIR="configs"
RESULTS_DIR="results/2vm"
LOG="experiment.log"
HOST="http://localhost:8080"           # Locust connects to local listener
APP_PORT=8080
SPAWN_DIVISOR=30
RUN_TIME="300s"
WARMUP_SLEEP=10
READINESS_TIMEOUT=90                   # SSH deploy takes a bit longer

WORKLOADS=(500 750 1000 1250 1500 1750 2000)

CONFIGS=(
    "2vm_frontend_colocated"
    "2vm_frontend_distributed"
    "2vm_colocated_colocated"
    "2vm_distributed_distributed"
)

# ── SSH Locations file ─────────────────────────────────────────────────────────
SSH_LOCATIONS_FILE="ssh_locations_2vm.txt"

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; exit 1; }
section() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo -e "  $*"; echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# ── Helpers ────────────────────────────────────────────────────────────────────
wait_for_ready() {
    local url="$1" timeout="$2" elapsed=0
    info "Waiting for ${url} (timeout: ${timeout}s)..."
    while ! curl -sf "${url}" > /dev/null 2>&1; do
        sleep 2; elapsed=$((elapsed + 2))
        [ "$elapsed" -ge "$timeout" ] && error "App not ready within ${timeout}s"
    done
    info "App is ready (${elapsed}s)"
}

kill_app() {
    local pid="$1"
    if kill -0 "$pid" 2>/dev/null; then
        info "Stopping SSH-deployed app (PID ${pid})..."
        kill "$pid" 2>/dev/null || true
        sleep 5
        kill -9 "$pid" 2>/dev/null || true
    fi
}

# ── Preflight checks ───────────────────────────────────────────────────────────
[ -f "$BINARY" ]                     || error "Binary not found. Run 01_clone_build.sh."
command -v weaver     > /dev/null    || error "'weaver' not in PATH."
command -v locust     > /dev/null    || error "'locust' not in PATH."

if [ -z "$VM2_HOST" ]; then
    error "VM2_HOST is not set. Export it first: export VM2_HOST=<ip-of-second-vm>"
fi
info "Using VM1=${VM1_HOST}  VM2=${VM2_HOST}"

# Write / refresh SSH locations file
printf "%s\n%s\n" "$VM1_HOST" "$VM2_HOST" > "$SSH_LOCATIONS_FILE"
info "SSH locations file: ${SSH_LOCATIONS_FILE}"

# Quick SSH connectivity check
ssh -o BatchMode=yes -o ConnectTimeout=5 "$VM2_HOST" echo "SSH to VM2 OK" \
    || error "Cannot SSH to ${VM2_HOST}. Set up passwordless SSH first (see header comments)."

mkdir -p "$RESULTS_DIR"
echo "[$(timestamp)] [2VM] ======== Starting 2-VM experiment suite ========" | tee -a "$LOG"

# ── Main experiment loop ───────────────────────────────────────────────────────
for CONFIG in "${CONFIGS[@]}"; do
    TOML="${CONFIGS_DIR}/${CONFIG}.toml"
    [ -f "$TOML" ] || { warn "Config not found: ${TOML} — skipping"; continue; }

    section "CONFIG: ${CONFIG}"
    echo "[$(timestamp)] [2VM] Config=${CONFIG} START" | tee -a "$LOG"

    for VUS in "${WORKLOADS[@]}"; do
        SPAWN_RATE=$(( VUS / SPAWN_DIVISOR ))
        [ "$SPAWN_RATE" -lt 1 ] && SPAWN_RATE=1

        OUT_DIR="${RESULTS_DIR}/${CONFIG}/${VUS}"
        mkdir -p "$OUT_DIR"
        CSV_PREFIX="${OUT_DIR}/locust"

        info "▶  Config=${CONFIG} | VUs=${VUS} | Spawn=${SPAWN_RATE}/s | Duration=${RUN_TIME}"
        echo "[$(timestamp)] [2VM] Config=${CONFIG} VUs=${VUS} START" | tee -a "$LOG"

        # ── Start app via SSH deployer ─────────────────────────────────────────
        info "Starting SSH-deployed app with: ${TOML}"
        weaver ssh deploy "$TOML" > "${OUT_DIR}/app.log" 2>&1 &
        APP_PID=$!
        info "Deployer PID: ${APP_PID}"

        wait_for_ready "${HOST}" "$READINESS_TIMEOUT"
        info "Warming up ${WARMUP_SLEEP}s..."
        sleep "$WARMUP_SLEEP"

        # ── Run Locust ─────────────────────────────────────────────────────────
        locust \
            -f locustfile.py \
            --headless \
            --host "$HOST" \
            -u "$VUS" \
            -r "$SPAWN_RATE" \
            --run-time "$RUN_TIME" \
            --csv "$CSV_PREFIX" \
            --csv-full-history \
            --only-summary \
            2>&1 | tee "${OUT_DIR}/locust.log"

        STATUS=$?
        if [ $STATUS -eq 0 ]; then
            info "✔  Complete: Config=${CONFIG} VUs=${VUS}"
            echo "[$(timestamp)] [2VM] Config=${CONFIG} VUs=${VUS} SUCCESS" | tee -a "$LOG"
        else
            warn "✘  Partial result (exit=${STATUS})"
            echo "[$(timestamp)] [2VM] Config=${CONFIG} VUs=${VUS} PARTIAL (exit=${STATUS})" | tee -a "$LOG"
        fi

        kill_app "$APP_PID"
        sleep 8   # SSH connections take longer to fully close
    done

    echo "[$(timestamp)] [2VM] Config=${CONFIG} DONE" | tee -a "$LOG"
done

section "2-VM Experiments Complete"
echo "[$(timestamp)] [2VM] ======== All 2-VM experiments complete ========" | tee -a "$LOG"
info "Results saved to: ${RESULTS_DIR}/"
info "Next: ./03_collect_results.sh && python3 04_plot_results.py"
