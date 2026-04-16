#!/usr/bin/env bash
# =============================================================================
# 03_collect_results.sh — Parse Locust CSVs → results/summary.csv
# =============================================================================
# Walks results/{1vm,2vm}/<config>/<vus>/locust_stats.csv for every experiment
# and extracts the aggregated row (Name == "Aggregated") to produce a tidy CSV:
#
#   vm_count,config,vus,avg_ms,p95_ms,p99_ms,max_ms,rps,failure_rate
#
# Usage:
#   ./03_collect_results.sh
#
# Output:
#   results/summary.csv
# =============================================================================
set -euo pipefail

SUMMARY="results/summary.csv"
mkdir -p results

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

# ── Write header ──────────────────────────────────────────────────────────────
echo "vm_count,config,vus,avg_ms,p50_ms,p95_ms,p99_ms,max_ms,rps,failure_pct" > "$SUMMARY"
info "Writing summary to: ${SUMMARY}"

# ── Helper: extract aggregated row from a locust_stats.csv ───────────────────
# Locust stats CSV columns (default, Locust 2.x):
# Type,Name,Request Count,Failure Count,Median Response Time,Average Response Time,
# Min Response Time,Max Response Time,Average Content Size,Requests/s,Failures/s,
# 50%,66%,75%,80%,90%,95%,99%,99.9%,99.99%,100%
parse_stats_csv() {
    local csv_file="$1"
    local vm_count="$2"
    local config="$3"
    local vus="$4"

    if [ ! -f "$csv_file" ]; then
        echo "  [SKIP] Missing: ${csv_file}" >&2
        return
    fi

    # Use Python for reliable CSV parsing — handles Locust's quoting
    python3 - <<PYEOF
import csv, sys

with open("${csv_file}") as f:
    reader = csv.DictReader(f)
    for row in reader:
        name = row.get("Name", "").strip()
        if name == "Aggregated":
            # Pull the fields we need — handle both old/new Locust column names
            avg   = row.get("Average Response Time", row.get("Average", "0")).strip()
            p50   = row.get("50%", "0").strip()
            p95   = row.get("95%", "0").strip()
            p99   = row.get("99%", "0").strip()
            mx    = row.get("Max Response Time", row.get("Max", "0")).strip()
            rps   = row.get("Requests/s", "0").strip()
            fails = row.get("Failure Count", "0").strip()
            reqs  = row.get("Request Count", "1").strip()

            # Failure percentage
            try:
                fail_pct = round(int(fails) / max(int(reqs), 1) * 100, 2)
            except:
                fail_pct = 0.0

            print(f"${vm_count},${config},${vus},{avg},{p50},{p95},{p99},{mx},{rps},{fail_pct}")
            sys.exit(0)

print(f"${vm_count},${config},${vus},N/A,N/A,N/A,N/A,N/A,N/A,N/A", file=sys.stderr)
PYEOF
}

FOUND=0

for VM_COUNT in 1 2; do
    VM_DIR="results/${VM_COUNT}vm"
    [ -d "$VM_DIR" ] || { info "No results at ${VM_DIR} — skipping"; continue; }

    for CONFIG_DIR in "${VM_DIR}"/*/; do
        CONFIG=$(basename "$CONFIG_DIR")

        for VUS_DIR in "${CONFIG_DIR}"*/; do
            VUS=$(basename "$VUS_DIR")
            STATS_CSV="${VUS_DIR}locust_stats.csv"

            ROW=$(parse_stats_csv "$STATS_CSV" "$VM_COUNT" "$CONFIG" "$VUS" 2>/dev/null || true)
            if [ -n "$ROW" ]; then
                echo "$ROW" >> "$SUMMARY"
                FOUND=$((FOUND + 1))
            fi
        done
    done
done

echo ""
info "Done. ${FOUND} data rows written to ${SUMMARY}"
info ""
info "Preview:"
head -5 "$SUMMARY"
info ""
info "Next: python3 04_plot_results.py"
