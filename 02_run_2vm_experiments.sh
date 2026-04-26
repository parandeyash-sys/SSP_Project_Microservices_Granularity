#!/usr/bin/env bash
# =============================================================================
# 02_run_2vm_experiments.sh — Run all 4 × 2-VM configuration experiments
# =============================================================================
# Uses Minikube with 2 nodes to simulate a multi-VM environment.
# Inject nodeAffinity to pin specific components to specific nodes.
# =============================================================================
set -euo pipefail

export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# ── Configuration ──────────────────────────────────────────────────────────────
BOUTIQUE_DIR="onlineboutique"
BINARY="${BOUTIQUE_DIR}/boutique"
CONFIGS_DIR="configs"
RESULTS_DIR="results/2vm"
LOG="experiment.log"
MK_PROFILE="ssp-study"   # Use isolated profile to avoid driver conflicts
HOST="http://localhost:8080"
APP_PORT=8080
SPAWN_DIVISOR=30
RUN_TIME="300s"
WARMUP_SLEEP=15
READINESS_TIMEOUT=600

WORKLOADS=(500 750 1000 1250 1500 1750 2000)

CONFIGS=(
    "2vm_frontend_colocated"
    "2vm_frontend_distributed"
    "2vm_colocated_colocated"
    "2vm_distributed_distributed"
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
    local url="$1" timeout="$2" elapsed=0
    info "Waiting for ${url} (timeout: ${timeout}s)..."
    while ! curl -s --max-time 1 "${url}" > /dev/null 2>&1; do
        sleep 3; elapsed=$((elapsed + 3))
        [ "$elapsed" -ge "$timeout" ] && {
            warn "App not responding at ${url} after ${elapsed}s. Pod status:"
            kubectl get pods -o wide 2>&1 | head -20
            error "App did not become ready within ${timeout}s"
        }
    done
    info "App is ready (${elapsed}s)"
}

kill_app() {
    local pid="$1"
    if kill -0 "$pid" 2>/dev/null; then
        info "Stopping port-forward (PID ${pid})..."
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
    fi
}

# ── Preflight checks ───────────────────────────────────────────────────────────
[ -f "$BINARY" ]                  || error "Binary not found. Run 01_clone_build.sh."
command -v weaver-kube > /dev/null || error "'weaver-kube' not in PATH."
command -v minikube > /dev/null   || error "'minikube' not installed."
command -v kubectl  > /dev/null   || error "'kubectl' not installed."

mkdir -p "$RESULTS_DIR"
source "monitoring/lib_monitor.sh"

info "Checking Minikube status (Profile: ${MK_PROFILE})..."
if ! minikube start -p "$MK_PROFILE" --driver=virtualbox --nodes=2; then
    error "Minikube failed to start with profile ${MK_PROFILE}. Try: minikube delete -p ${MK_PROFILE}"
fi

# Point kubectl and docker to the new profile
minikube -p "$MK_PROFILE" profile "$MK_PROFILE"
# Note: docker-env is incompatible with multi-node clusters
# eval $(minikube -p "$MK_PROFILE" docker-env)

# Clean up any residual deployments from previous runs/app names
info "Cleaning up old deployments..."
kubectl delete deploy,svc,hpa,pod -l serviceweaver/app=boutique --ignore-not-found=true
kubectl delete deploy,svc,hpa,pod -l serviceweaver/app=ob --ignore-not-found=true
sleep 5 # Give it a moment to finish deletion

# Ensure sysstat in both nodes
setup_minikube_nodes "$MK_PROFILE" "${MK_PROFILE}-m02"

echo "[$(timestamp)] [2VM] ======== Starting 2-VM experiment suite ========" | tee -a "$LOG"

# ── Main experiment loop ───────────────────────────────────────────────────────
for CONFIG in "${CONFIGS[@]}"; do
    YAML_CONFIG="${CONFIGS_DIR}/${CONFIG}.yaml"
    [ -f "$YAML_CONFIG" ] || { warn "Config not found: ${YAML_CONFIG} — skipping"; continue; }

    section "CONFIG: ${CONFIG}"
    echo "[$(timestamp)] [2VM] Config=${CONFIG} START" | tee -a "$LOG"

    # Define node mapping based on config
    case "$CONFIG" in
        "2vm_frontend_colocated")
            NODE1="fe,weaver-main"
            NODE2="be"
            ;;
        "2vm_frontend_distributed")
            NODE1="fe,weaver-main"
            # Distributed components in their own short-named groups
            NODE2="ad,cs,co,cu,em,pa,pc,rc,sh"
            ;;
        "2vm_colocated_colocated")
            NODE1="g1,weaver-main"
            NODE2="g2"
            ;;
        "2vm_distributed_distributed")
            NODE1="fe,em,pa,rc,sh,weaver-main"
            NODE2="ad,cs,co,cu,pc"
            ;;
    esac

    for VUS in "${WORKLOADS[@]}"; do
        SPAWN_RATE=$(( VUS / SPAWN_DIVISOR ))
        [ "$SPAWN_RATE" -lt 1 ] && SPAWN_RATE=1

        setup_run_dirs "$RESULTS_DIR" "$CONFIG" "$VUS"
        CSV_PREFIX="${LOCUST_DIR}/locust"

        info "▶  Config=${CONFIG} | VUs=${VUS} | Spawn=${SPAWN_RATE}/s | Duration=${RUN_TIME}"
        echo "[$(timestamp)] [2VM] Config=${CONFIG} VUs=${VUS} START" | tee -a "$LOG"

        # ── Start app via weaver-kube ──────────────────────────────────────────
        info "Generating K8s manifest for: ${YAML_CONFIG}"
        RAW_KUBE_YAML=$(weaver-kube deploy "$YAML_CONFIG" | tail -n 1)
        [ -f "$RAW_KUBE_YAML" ] || error "weaver-kube deploy failed"

        # For multi-node Minikube, change imagePullPolicy to Never to use local images
        info "Setting imagePullPolicy to Never for all nodes..."
        sed -i 's/imagePullPolicy: IfNotPresent/imagePullPolicy: Never/g' "$RAW_KUBE_YAML"

        # Extract image name and load it on all nodes using minikube image load
        IMAGE_NAME=$(grep "image: ob:" "$RAW_KUBE_YAML" | head -1 | sed 's/.*image: \(ob:[^ ]*\).*/\1/')
        if [ -n "$IMAGE_NAME" ]; then
            info "Loading Docker image ${IMAGE_NAME} onto all Minikube nodes..."
            minikube -p "$MK_PROFILE" image load "$IMAGE_NAME" || warn "Failed to load image ${IMAGE_NAME}"
            info "Image ${IMAGE_NAME} is now available on all nodes"
        fi

        INJECTED_YAML="${RUN_DIR}/weaver_kube_injected.yaml"
        info "Injecting nodeAffinity (Node1=${NODE1}, Node2=${NODE2})..."
        python3 scripts/inject_nodes.py "$RAW_KUBE_YAML" "$INJECTED_YAML" "$NODE1" "$NODE2" "$MK_PROFILE" "${MK_PROFILE}-m02"

        info "Applying manifest: ${INJECTED_YAML}"
        kubectl apply -f "$INJECTED_YAML" | tee "${RUN_DIR}/kubectl_apply.log"

        info "Waiting for all pods to be Ready..."
        if ! kubectl wait --for=condition=Ready pods --all --timeout=300s; then
            warn "Some pods not ready! Checking status..."
            kubectl get pods -o wide
        fi

        # Find the service name (Service Weaver adds a deployment ID hash)
        SVC_NAME=$(kubectl get svc -l serviceweaver/app=ob -o jsonpath='{.items[0].metadata.name}')
        [ -n "$SVC_NAME" ] || error "Could not find Service Weaver service (label: serviceweaver/app=ob)"

        info "Resolving Minikube service URL for ${SVC_NAME}..."
        HOST=$(minikube service "${SVC_NAME}" --url -p "$MK_PROFILE" | head -n1)
        [ -n "$HOST" ] || error "Could not get Minikube service URL for ${SVC_NAME}"

        wait_for_ready "${HOST}" "$READINESS_TIMEOUT"
        info "Warming up for ${WARMUP_SLEEP}s..."
        sleep "$WARMUP_SLEEP"

        # ── Start System Monitoring (Both Nodes) ───────────────────────────────
        start_k8s_monitoring "$SYSMET_DIR" "$MK_PROFILE"
        start_k8s_monitoring "$SYSMET_DIR" "${MK_PROFILE}-m02"

        # ── Run Profiling & Locust ─────────────────────────────────────────────
        (
            sleep 120
            collect_pprof "${HOST#http://}" "$PPROF_DIR" 60
        ) &
        PPROF_SCHED_PID=$!

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
        write_run_metadata "$RUN_DIR" 2 "$CONFIG" "$VUS" 300

        if [ $STATUS -eq 0 ]; then
            info "✔  Complete: Config=${CONFIG} VUs=${VUS}"
            echo "[$(timestamp)] [2VM] Config=${CONFIG} VUs=${VUS} SUCCESS" | tee -a "$LOG"
        else
            warn "✘  Partial result (exit=${STATUS})"
            echo "[$(timestamp)] [2VM] Config=${CONFIG} VUs=${VUS} PARTIAL (exit=${STATUS})" | tee -a "$LOG"
        fi

        # (port-forward eliminated)
        info "Cleaning up K8s deployment..."
        kubectl delete -f "$INJECTED_YAML" >/dev/null 2>&1 || true
        sleep 10  # Wait for pods to terminate
    done

    echo "[$(timestamp)] [2VM] Config=${CONFIG} DONE" | tee -a "$LOG"
    info "All workload levels complete for config: ${CONFIG}"
    echo ""
done

section "2-VM Experiments Complete"
echo "[$(timestamp)] [2VM] ======== All 2-VM experiments complete ========" | tee -a "$LOG"
info "Results saved to: ${RESULTS_DIR}/"
