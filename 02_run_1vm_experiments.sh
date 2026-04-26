#!/usr/bin/env bash
# =============================================================================
# 02_run_1vm_experiments.sh — Run all 4 × 1-VM configuration experiments
# =============================================================================
# For each configuration:
#   • Starts the Online Boutique with `weaver multi deploy`
#   • Waits for HTTP readiness on :8080
#   • Iterates workload levels: 500, 750, 1000, 1250, 1500, 1750, 2000 VUs
#   • Each level: 5 minutes of load, spawn rate = VUs/30
#   • Saves Locust CSV to results/1vm/<config>/<vus>/
#   • Stops the app, logs to experiment.log
#
# Prerequisites:
#   • Go, weaver, locust installed (run 00_install_deps.sh)
#   • Online Boutique binary built (run 01_clone_build.sh)
#   • Python venv activated: source ~/ssp_venv/bin/activate
# =============================================================================
set -euo pipefail

export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# ── Configuration ──────────────────────────────────────────────────────────────
BOUTIQUE_DIR="onlineboutique"
BINARY="${BOUTIQUE_DIR}/boutique"
CONFIGS_DIR="configs"
RESULTS_DIR="results/1vm"
LOG="experiment.log"
MK_PROFILE="ssp-study"   # Use isolated profile to avoid driver conflicts
HOST="http://localhost:8080"
APP_PORT=8080
SPAWN_DIVISOR=30          # spawn rate = VUs / SPAWN_DIVISOR  (≈1 new user/s per 30 VUs)
RUN_TIME="300s"           # 5 minutes per workload level
WARMUP_SLEEP=10           # seconds to wait after app start before testing
READINESS_TIMEOUT=60      # seconds to wait for app HTTP readiness

WORKLOADS=(500 750 1000 1250 1500 1750 2000)

CONFIGS=(
    "1vm_monolith"
    "1vm_frontend_colocated"
    "1vm_two_colocated"
    "1vm_distributed"
)

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; exit 1; }
section() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo -e "  $*"; echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# ── Helpers ────────────────────────────────────────────────────────────────────
wait_for_ready() {
    local url="$1"
    local timeout="$2"
    local elapsed=0
    info "Waiting for ${url} (timeout: ${timeout}s)..."
    while ! curl -sf "${url}" > /dev/null 2>&1; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$timeout" ]; then
            error "App did not become ready within ${timeout}s"
        fi
    done
    info "App is ready (${elapsed}s elapsed)"
}

kill_app() {
    local pid="$1"
    if kill -0 "$pid" 2>/dev/null; then
        info "Stopping app (PID ${pid})..."
        kill "$pid" 2>/dev/null || true
        sleep 3
        kill -9 "$pid" 2>/dev/null || true
    fi
}

# ── Preflight checks ───────────────────────────────────────────────────────────
[ -f "$BINARY" ]                  || error "Binary not found: ${BINARY}. Run 01_clone_build.sh first."
command -v weaver-kube > /dev/null || error "'weaver-kube' not in PATH. Run 00_install_deps.sh and source ~/.bashrc."
command -v locust   > /dev/null   || error "'locust' not in PATH. Activate the venv: source ~/ssp_venv/bin/activate"
command -v curl     > /dev/null   || error "'curl' not installed."
command -v minikube > /dev/null   || error "'minikube' not installed."
command -v kubectl  > /dev/null   || error "'kubectl' not installed."

mkdir -p "$RESULTS_DIR"
source "monitoring/lib_monitor.sh"

info "Checking Minikube status (Profile: ${MK_PROFILE})..."
# Start minikube with the isolated profile and virtualbox driver
if ! minikube start -p "$MK_PROFILE" --nodes 1 --driver=virtualbox --memory=4096 --cpus=2; then
    error "Minikube failed to start with profile ${MK_PROFILE}. Try: minikube delete -p ${MK_PROFILE}"
fi

# Point kubectl and docker to the new profile
minikube -p "$MK_PROFILE" profile "$MK_PROFILE"
eval $(minikube -p "$MK_PROFILE" docker-env)

# Clean up any residual deployments from previous runs/app names
info "Cleaning up old deployments..."
kubectl delete deploy,svc,hpa,pod -l serviceweaver/app=boutique --ignore-not-found=true
kubectl delete deploy,svc,hpa,pod -l serviceweaver/app=ob --ignore-not-found=true
sleep 5 # Give it a moment to finish deletion

# Ensure sysstat is inside the node
setup_minikube_nodes "$MK_PROFILE"

echo "[$(timestamp)] [1VM] ======== Starting 1-VM experiment suite ========" | tee -a "$LOG"

# ── Main experiment loop ───────────────────────────────────────────────────────
for CONFIG in "${CONFIGS[@]}"; do
    YAML_CONFIG="${CONFIGS_DIR}/${CONFIG}.yaml"
    [ -f "$YAML_CONFIG" ] || { warn "Config not found: ${YAML_CONFIG} — skipping"; continue; }

    section "CONFIG: ${CONFIG}"
    echo "[$(timestamp)] [1VM] Config=${CONFIG} START" | tee -a "$LOG"

    for VUS in "${WORKLOADS[@]}"; do
        SPAWN_RATE=$(( VUS / SPAWN_DIVISOR ))
        [ "$SPAWN_RATE" -lt 1 ] && SPAWN_RATE=1

        setup_run_dirs "$RESULTS_DIR" "$CONFIG" "$VUS"
        CSV_PREFIX="${LOCUST_DIR}/locust"

        info "▶  Config=${CONFIG} | VUs=${VUS} | Spawn rate=${SPAWN_RATE}/s | Duration=${RUN_TIME}"
        echo "[$(timestamp)] [1VM] Config=${CONFIG} VUs=${VUS} START" | tee -a "$LOG"

        # ── Start app via weaver-kube ──────────────────────────────────────────
        # Clean up any existing ob deployments before starting a new one
        kubectl delete deploy,svc,hpa,pod -l serviceweaver/app=ob --ignore-not-found=true
        sleep 5

        info "Generating K8s manifest for: ${YAML_CONFIG}"
        # deploy builds docker image and outputs path to generated yaml
        KUBE_YAML=$(weaver-kube deploy "$YAML_CONFIG" | tail -n 1)
        [ -f "$KUBE_YAML" ] || error "weaver-kube deploy failed to generate yaml"
        
        info "Applying generated K8s manifest: ${KUBE_YAML}"
        kubectl apply -f "$KUBE_YAML" | tee "${RUN_DIR}/kubectl_apply.log"

        info "Waiting for all pods to be Ready..."
        kubectl wait --for=condition=Ready pods --all --timeout=300s || warn "Some pods not ready!"
        
        # Find the service name (Service Weaver adds a deployment ID hash)
        SVC_NAME=$(kubectl get svc -l serviceweaver/app=ob -o jsonpath='{.items[0].metadata.name}')
        [ -n "$SVC_NAME" ] || error "Could not find Service Weaver service (label: serviceweaver/app=ob)"

        info "Resolving Minikube service URL for ${SVC_NAME}..."
        HOST=$(minikube service "${SVC_NAME}" --url -p "$MK_PROFILE" | head -n1)
        [ -n "$HOST" ] || error "Could not get Minikube service URL for ${SVC_NAME}"
        
        wait_for_ready "${HOST}" "$READINESS_TIMEOUT"
        info "Warming up for ${WARMUP_SLEEP}s..."
        sleep "$WARMUP_SLEEP"

        # ── Start System Monitoring (Node 1) ───────────────────────────────────
        start_k8s_monitoring "$SYSMET_DIR" "$MK_PROFILE"

        # ── Run Profiling & Locust ─────────────────────────────────────────────
        # Schedule pprof collection to run midway through the 300s test
        # e.g., wait 120s, profile 60s
        (
            sleep 120
            collect_pprof "${HOST#http://}" "$PPROF_DIR" 60
        ) &
        PPROF_SCHED_PID=$!

        # ── Run Locust ─────────────────────────────────────────────────────────
        info "Running Distributed Locust..."
        NUM_WORKERS=$(nproc 2>/dev/null || echo 4)
        info "Starting ${NUM_WORKERS} locust worker processes to avoid CPU bottlenecks..."

        WORKER_PIDS=()
        for i in $(seq 1 $NUM_WORKERS); do
            locust -f locustfile.py --worker > "${LOCUST_DIR}/worker_${i}.log" 2>&1 &
            WORKER_PIDS+=($!)
        done

        locust \
            -f locustfile.py \
            --headless \
            --master \
            --expect-workers "$NUM_WORKERS" \
            --host "$HOST" \
            -u "$VUS" \
            -r "$SPAWN_RATE" \
            --run-time "$RUN_TIME" \
            --csv "$CSV_PREFIX" \
            --csv-full-history \
            --only-summary \
            2>&1 | tee "${LOCUST_DIR}/locust.log"

        STATUS=$?
        
        # Cleanup worker processes after master exits
        for pid in "${WORKER_PIDS[@]}"; do
            kill "$pid" 2>/dev/null || true
        done
        wait "${WORKER_PIDS[@]}" 2>/dev/null || true
        
        wait $PPROF_SCHED_PID 2>/dev/null || true

        # ── Stop System Monitoring ─────────────────────────────────────────────
        stop_system_monitoring

        # ── Collect Prometheus ─────────────────────────────────────────────────
        collect_prometheus_snapshot "http://localhost:9090" "$PROM_DIR"

        # ── Write Metadata ─────────────────────────────────────────────────────
        write_run_metadata "$RUN_DIR" 1 "$CONFIG" "$VUS" 300

        if [ $STATUS -eq 0 ]; then
            info "✔  Locust run complete for Config=${CONFIG} VUs=${VUS}"
            echo "[$(timestamp)] [1VM] Config=${CONFIG} VUs=${VUS} SUCCESS" | tee -a "$LOG"
        else
            warn "✘  Locust exited with status ${STATUS} — results may be partial"
            echo "[$(timestamp)] [1VM] Config=${CONFIG} VUs=${VUS} PARTIAL (exit=${STATUS})" | tee -a "$LOG"
        fi

        # ── Stop app ───────────────────────────────────────────────────────────
        # (port-forward eliminated)
        
        info "Cleaning up K8s deployment..."
        kubectl delete -f "$KUBE_YAML" >/dev/null 2>&1 || true
        
        # Ensure pods are fully terminating before continuing
        sleep 5
    done

    echo "[$(timestamp)] [1VM] Config=${CONFIG} DONE" | tee -a "$LOG"
    info "All workload levels complete for config: ${CONFIG}"
    echo ""
done

# ── Summary ────────────────────────────────────────────────────────────────────
section "1-VM Experiments Complete"
echo "[$(timestamp)] [1VM] ======== All 1-VM experiments complete ========" | tee -a "$LOG"
info "Results saved to: ${RESULTS_DIR}/"
info ""
info "Next steps:"
info "  1. Run ./03_collect_results.sh   → generates results/summary.csv"
info "  2. Run python3 04_plot_results.py → generates plots/"
