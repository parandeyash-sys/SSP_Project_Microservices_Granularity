#!/usr/bin/env bash
# =============================================================================
# monitoring/lib_monitor.sh — Shared monitoring functions
# Source this file from experiment runners:
#   source monitoring/lib_monitor.sh
# =============================================================================

# ── Guard against double-sourcing ─────────────────────────────────────────────
[[ -n "${_LIB_MONITOR_LOADED:-}" ]] && return 0
_LIB_MONITOR_LOADED=1

# ── Global PID tracking arrays ────────────────────────────────────────────────
declare -a _MONITOR_PIDS=()  # All background monitor PIDs for this run
declare -a _PPROF_PIDS=()    # pprof collector PIDs

# ── Colour helpers (only define if not already set) ───────────────────────────
_GREEN='\033[0;32m'; _YELLOW='\033[1;33m'; _CYAN='\033[0;36m'; _NC='\033[0m'
_minfo()  { echo -e "${_GREEN}[MONITOR]${_NC}  $*"; }
_mwarn()  { echo -e "${_YELLOW}[MONITOR]${_NC}  $*"; }\

# ── Directory builder ─────────────────────────────────────────────────────────
# Usage: setup_run_dirs <base_results_dir> <config> <vus>
# Sets globals: RUN_DIR, SYSMET_DIR, PPROF_DIR, PROM_DIR, LOCUST_DIR
setup_run_dirs() {
    local base_dir="$1" config="$2" vus="$3"
    export RUN_DIR="${base_dir}/${config}/${vus}"
    export SYSMET_DIR="${RUN_DIR}/system-metrics"
    export PPROF_DIR="${RUN_DIR}/pprof"
    export PROM_DIR="${RUN_DIR}/prometheus"
    export LOCUST_DIR="${RUN_DIR}/locust"
    mkdir -p "$SYSMET_DIR" "$PPROF_DIR" "$PROM_DIR" "$LOCUST_DIR"
    _minfo "Output dirs ready under: ${RUN_DIR}/"
}

# ── Minikube Node Setup ────────────────────────────────────────────────────────
# Usage: setup_minikube_nodes [node1] [node2]
setup_minikube_nodes() {
    local profile="${MK_PROFILE:-minikube}"
    for node in "$@"; do
        _minfo "Checking sysstat on node: ${node} (Profile: ${profile})..."
        if minikube -p "$profile" ssh -n "$node" "command -v sar" >/dev/null 2>&1; then
            _minfo "  sysstat already installed on ${node}"
        else
            _minfo "  Installing sysstat on ${node} (minikube ssh)..."
            minikube -p "$profile" ssh -n "$node" "sudo apt-get update -qq && sudo apt-get install -y -qq sysstat" || _mwarn "  Failed to install sysstat on ${node}"
        fi
    done
}

# ── System metrics start/stop (Remote via Minikube) ───────────────────────────
# Usage: start_k8s_monitoring <sysmet_dir> <node_name>
start_k8s_monitoring() {
    local dir="$1"
    local node="$2"
    local profile="${MK_PROFILE:-minikube}"
    _minfo "Starting system monitors on node [${node}] (Profile: ${profile}) → ${dir}/"

    # We use 'minikube ssh' to run the monitors in the background inside the VM
    # and redirect output back to the host.
    
    # ── CPU per-core (mpstat 1) ───────────────────────────────────────────────
    minikube -p "$profile" ssh -n "$node" "mpstat -P ALL 1" > "${dir}/mpstat_cpu_${node}.log" 2>&1 &
    _MONITOR_PIDS+=($!)

    # ── Overall CPU + load (sar -u 1) ────────────────────────────────────────
    minikube -p "$profile" ssh -n "$node" "sar -u 1" > "${dir}/sar_cpu_${node}.log" 2>&1 &
    _MONITOR_PIDS+=($!)

    minikube -p "$profile" ssh -n "$node" "sar -r 1" > "${dir}/sar_memory_${node}.log" 2>&1 &
    _MONITOR_PIDS+=($!)

    minikube -p "$profile" ssh -n "$node" "sar -n DEV 1" > "${dir}/sar_network_${node}.log" 2>&1 &
    _MONITOR_PIDS+=($!)

    # ── Disk I/O (iostat -x 1) ────────────────────────────────────────────────
    minikube -p "$profile" ssh -n "$node" "iostat -x -t 1" > "${dir}/iostat_disk_${node}.log" 2>&1 &
    _MONITOR_PIDS+=($!)

    # ── Memory + swap (vmstat 1) ──────────────────────────────────────────────
    minikube -p "$profile" ssh -n "$node" "vmstat 1" > "${dir}/vmstat_${node}.log" 2>&1 &
    _MONITOR_PIDS+=($!)

    _minfo "  Monitoring PIDs for ${node}: ${_MONITOR_PIDS[*]: -6}"
}

# ── Old local system metrics start/stop (deprecated for K8s) ──────────────────
# Keeping legacy local monitoring for host-level context if desired.
start_local_monitoring() {
    local dir="$1"
    _minfo "Starting LOCAL host monitors → ${dir}/"
    # ... (same as original start_system_monitoring)
}


# Usage: stop_system_monitoring
stop_system_monitoring() {
    _minfo "Stopping ${#_MONITOR_PIDS[@]} system monitor process(es)..."
    for pid in "${_MONITOR_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in "${_MONITOR_PIDS[@]}"; do
        kill -9 "$pid" 2>/dev/null || true
    done
    _MONITOR_PIDS=()
    _minfo "System monitoring stopped."
}

# ── pprof collection ──────────────────────────────────────────────────────────
# Usage: collect_pprof <app_host_port> <pprof_dir> [duration_sec]
# Collects CPU, heap, goroutine, and blocking profiles in background.
collect_pprof() {
    local host="$1"
    local dir="$2"
    local duration="${3:-30}"   # seconds of CPU profiling window
    local base_url="http://${host}/debug/pprof"

    _minfo "Collecting pprof profiles from ${base_url} → ${dir}/"

    # ── CPU profile (blocking call, duration seconds) ─────────────────────────
    (
        curl -sf --max-time $(( duration + 10 )) \
            "${base_url}/profile?seconds=${duration}" \
            -o "${dir}/cpu.prof" 2>"${dir}/cpu_prof.err" \
        && _minfo "  pprof cpu.prof done" \
        || _mwarn "  pprof CPU profile failed (is /debug/pprof enabled?)"
    ) &
    _PPROF_PIDS+=($!)

    # ── Heap profile ──────────────────────────────────────────────────────────
    (
        curl -sf --max-time 30 \
            "${base_url}/heap?gc=1" \
            -o "${dir}/heap.prof" 2>"${dir}/heap_prof.err" \
        && _minfo "  pprof heap.prof done" \
        || _mwarn "  pprof heap profile failed"
    ) &
    _PPROF_PIDS+=($!)

    # ── Goroutine profile ─────────────────────────────────────────────────────
    (
        curl -sf --max-time 30 \
            "${base_url}/goroutine?debug=1" \
            -o "${dir}/goroutine.prof" 2>"${dir}/goroutine_prof.err" \
        && _minfo "  pprof goroutine.prof done" \
        || _mwarn "  pprof goroutine profile failed"
    ) &
    _PPROF_PIDS+=($!)

    # ── Blocking profile ──────────────────────────────────────────────────────
    (
        curl -sf --max-time 30 \
            "${base_url}/block?debug=1" \
            -o "${dir}/block.prof" 2>"${dir}/block_prof.err" \
        && _minfo "  pprof block.prof done" \
        || _mwarn "  pprof block profile failed"
    ) &
    _PPROF_PIDS+=($!)

    # ── Mutex profile ─────────────────────────────────────────────────────────
    (
        curl -sf --max-time 30 \
            "${base_url}/mutex?debug=1" \
            -o "${dir}/mutex.prof" 2>"${dir}/mutex_prof.err" \
        && _minfo "  pprof mutex.prof done" \
        || _mwarn "  pprof mutex profile failed"
    ) &
    _PPROF_PIDS+=($!)

    # ── Thread create profile ─────────────────────────────────────────────────
    (
        curl -sf --max-time 30 \
            "${base_url}/threadcreate" \
            -o "${dir}/threadcreate.prof" 2>/dev/null
    ) &
    _PPROF_PIDS+=($!)

    _minfo "pprof collectors running. Waiting for completion..."
    wait "${_PPROF_PIDS[@]}" 2>/dev/null || true
    _PPROF_PIDS=()

    # Write a summary of collected file sizes
    ls -lh "${dir}/"*.prof 2>/dev/null >> "${dir}/pprof_manifest.txt" || true
    _minfo "pprof collection complete."
}

# ── Prometheus snapshot ───────────────────────────────────────────────────────
# Usage: collect_prometheus_snapshot <prometheus_url> <prom_dir>
collect_prometheus_snapshot() {
    local prom_url="${1:-http://localhost:9090}"
    local dir="$2"
    local ts
    ts=$(date '+%Y%m%dT%H%M%S')

    _minfo "Collecting Prometheus snapshot from ${prom_url} → ${dir}/"

    # ── Targets health ────────────────────────────────────────────────────────
    curl -sf --max-time 10 "${prom_url}/api/v1/targets" \
        -o "${dir}/targets_${ts}.json" 2>/dev/null || _mwarn "  targets endpoint unreachable"

    # ── Key metrics via instant query ─────────────────────────────────────────
    local QUERIES=(
        "up"
        "rate(http_requests_total[1m])"
        "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))"
        "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))"
        "process_resident_memory_bytes"
        "go_goroutines"
        "go_gc_duration_seconds"
        "node_cpu_seconds_total"
        "node_memory_MemAvailable_bytes"
        "rate(node_network_receive_bytes_total[1m])"
        "rate(node_network_transmit_bytes_total[1m])"
    )

    for query in "${QUERIES[@]}"; do
        local safe_name
        safe_name=$(echo "$query" | tr -cs '[:alnum:]_' '_' | head -c 60)
        curl -sf --max-time 10 \
            "${prom_url}/api/v1/query" \
            --data-urlencode "query=${query}" \
            -o "${dir}/metric_${safe_name}_${ts}.json" 2>/dev/null \
        || _mwarn "  Query failed: ${query}"
    done

    # ── Range data for last 6 minutes at 15s resolution ──────────────────────
    local end_ts
    end_ts=$(date +%s)
    local start_ts=$(( end_ts - 360 ))

    curl -sf --max-time 30 \
        "${prom_url}/api/v1/query_range" \
        --data-urlencode "query=rate(http_requests_total[1m])" \
        --data-urlencode "start=${start_ts}" \
        --data-urlencode "end=${end_ts}" \
        --data-urlencode "step=15" \
        -o "${dir}/rps_range_${ts}.json" 2>/dev/null || true

    curl -sf --max-time 30 \
        "${prom_url}/api/v1/query_range" \
        --data-urlencode "query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))" \
        --data-urlencode "start=${start_ts}" \
        --data-urlencode "end=${end_ts}" \
        --data-urlencode "step=15" \
        -o "${dir}/p95_range_${ts}.json" 2>/dev/null || true

    _minfo "Prometheus snapshot done."
}

# ── Write run metadata ────────────────────────────────────────────────────────
write_run_metadata() {
    local dir="$1" vm_count="$2" config="$3" vus="$4" run_time="$5"
    cat > "${dir}/run_metadata.json" <<JSON
{
  "vm_count": ${vm_count},
  "config": "${config}",
  "vus": ${vus},
  "run_time_seconds": ${run_time},
  "start_ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "cpu_model": "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs || echo unknown)",
  "cpu_cores": $(nproc),
  "mem_total_kb": $(grep MemTotal /proc/meminfo | awk '{print $2}')
}
JSON
    _minfo "Run metadata written → ${dir}/run_metadata.json"
}
