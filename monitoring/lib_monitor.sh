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

# ── System metrics start/stop ─────────────────────────────────────────────────
# Usage: start_system_monitoring <sysmet_dir>
start_system_monitoring() {
    local dir="$1"
    _minfo "Starting system monitors → ${dir}/"

    # ── CPU per-core (mpstat 1) ───────────────────────────────────────────────
    if command -v mpstat &>/dev/null; then
        mpstat -P ALL 1 > "${dir}/mpstat_cpu_cores.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  mpstat PID=$!"
    else
        _mwarn "  mpstat not found — skipping (install sysstat)"
    fi

    # ── Overall CPU + load (sar -u 1) ────────────────────────────────────────
    if command -v sar &>/dev/null; then
        sar -u 1 > "${dir}/sar_cpu.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  sar -u PID=$!"

        sar -r 1 > "${dir}/sar_memory.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  sar -r PID=$!"

        sar -n DEV 1 > "${dir}/sar_network.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  sar -n DEV PID=$!"

        sar -q 1 > "${dir}/sar_loadavg.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  sar -q PID=$!"
    else
        _mwarn "  sar not found — skipping (install sysstat)"
    fi

    # ── Disk I/O (iostat -x 1) ────────────────────────────────────────────────
    if command -v iostat &>/dev/null; then
        iostat -x -t 1 > "${dir}/iostat_disk.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  iostat PID=$!"
    else
        _mwarn "  iostat not found — skipping"
    fi

    # ── Memory + swap (vmstat 1) ──────────────────────────────────────────────
    if command -v vmstat &>/dev/null; then
        vmstat 1 > "${dir}/vmstat.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  vmstat PID=$!"
    fi

    # ── Network socket stats (ss -s every 5s) ─────────────────────────────────
    if command -v ss &>/dev/null; then
        (
            while true; do
                echo "=== $(date '+%Y-%m-%dT%H:%M:%S') ===" >> "${dir}/ss_sockets.log"
                ss -s >> "${dir}/ss_sockets.log" 2>&1
                ss -tn state established >> "${dir}/ss_established.log" 2>&1
                sleep 5
            done
        ) &
        _MONITOR_PIDS+=($!)
        _minfo "  ss-loop PID=$!"
    elif command -v netstat &>/dev/null; then
        (
            while true; do
                echo "=== $(date '+%Y-%m-%dT%H:%M:%S') ===" >> "${dir}/netstat_an.log"
                netstat -an >> "${dir}/netstat_an.log" 2>&1
                sleep 5
            done
        ) &
        _MONITOR_PIDS+=($!)
        _minfo "  netstat-loop PID=$!"
    fi

    # ── Network bandwidth (iftop — writes to file if iface detected) ──────────
    if command -v iftop &>/dev/null; then
        # Detect primary non-loopback interface
        IFACE=$(ip route | awk '/default/ {print $5}' | head -1)
        if [ -n "$IFACE" ]; then
            # iftop requires root for full capture; use -i + text mode
            sudo iftop -t -s 5 -i "$IFACE" -o 5s > "${dir}/iftop_bandwidth.log" 2>&1 &
            _MONITOR_PIDS+=($!)
            _minfo "  iftop PID=$! (iface=${IFACE})"
        fi
    else
        _mwarn "  iftop not found — using nethogs alternative or skipping"
        # Fallback: /proc/net/dev sampling
        (
            while true; do
                echo "=== $(date '+%Y-%m-%dT%H:%M:%S') ===" >> "${dir}/proc_netdev.log"
                cat /proc/net/dev >> "${dir}/proc_netdev.log"
                sleep 1
            done
        ) &
        _MONITOR_PIDS+=($!)
        _minfo "  proc/net/dev sampler PID=$!"
    fi

    # ── Hardware context switches + interrupts (sar -I ALL 1) ─────────────────
    if command -v sar &>/dev/null; then
        sar -w 1 > "${dir}/sar_context_switches.log" 2>&1 &
        _MONITOR_PIDS+=($!)
        _minfo "  sar -w (ctx-switches) PID=$!"
    fi

    _minfo "System monitoring started. PIDs: ${_MONITOR_PIDS[*]:-none}"
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
