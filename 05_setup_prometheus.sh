#!/usr/bin/env bash
# =============================================================================
# 05_setup_prometheus.sh — Install & configure Prometheus + Node Exporter
#                          for the granularity study
# =============================================================================
# What this does:
#   1. Downloads Prometheus 2.51 (no Docker required)
#   2. Downloads Node Exporter 1.8 for host-level metrics
#   3. Writes prometheus.yml that scrapes:
#      - node_exporter (host metrics)
#      - Online Boutique app (if it exposes /metrics)
#      - itself
#   4. Creates systemd-style start/stop helpers
#
# Run once before experiments:   ./05_setup_prometheus.sh
# Start Prometheus:               ./monitoring/start_prometheus.sh
# Stop Prometheus:                ./monitoring/stop_prometheus.sh
# =============================================================================
set -euo pipefail

PROM_VERSION="2.51.2"
NODE_EXP_VERSION="1.8.1"
INSTALL_DIR="$HOME/ssp_monitoring"
PROM_DIR="${INSTALL_DIR}/prometheus"
NODE_EXP_DIR="${INSTALL_DIR}/node_exporter"
CONFIG_DIR="monitoring"
LOG="experiment.log"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(timestamp)] [SETUP] Prometheus + Node Exporter setup" | tee -a "$LOG"

mkdir -p "$INSTALL_DIR" "$PROM_DIR" "$NODE_EXP_DIR" "$CONFIG_DIR"

# ── 1. Prometheus ──────────────────────────────────────────────────────────────
PROM_TAR="prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TAR}"

if [ -f "${PROM_DIR}/prometheus" ]; then
    info "Prometheus already downloaded at ${PROM_DIR}"
else
    info "Downloading Prometheus ${PROM_VERSION}..."
    wget -q "$PROM_URL" -O "/tmp/${PROM_TAR}"
    tar -xzf "/tmp/${PROM_TAR}" -C "$INSTALL_DIR" --strip-components=1 \
        --wildcards "*/prometheus" "*/promtool" "*/console_libraries" "*/consoles" || \
    tar -xzf "/tmp/${PROM_TAR}" -C "$PROM_DIR" --strip-components=1
    cp /tmp/prometheus-*/prometheus "$PROM_DIR/" 2>/dev/null || true
    # Try again extracting to its own dir
    mkdir -p "${PROM_DIR}"
    tar -xzf "/tmp/${PROM_TAR}" -C "${PROM_DIR}" --strip-components=1 2>/dev/null || {
        # Single binary extraction fallback
        cd /tmp && tar -xzf "${PROM_TAR}"
        cp "/tmp/prometheus-${PROM_VERSION}.linux-amd64/prometheus" "${PROM_DIR}/"
        cp "/tmp/prometheus-${PROM_VERSION}.linux-amd64/promtool"   "${PROM_DIR}/"
        cd - > /dev/null
    }
    rm -f "/tmp/${PROM_TAR}"
    info "Prometheus installed at ${PROM_DIR}"
fi

# ── 2. Node Exporter ──────────────────────────────────────────────────────────
NODE_TAR="node_exporter-${NODE_EXP_VERSION}.linux-amd64.tar.gz"
NODE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXP_VERSION}/${NODE_TAR}"

if [ -f "${NODE_EXP_DIR}/node_exporter" ]; then
    info "Node Exporter already downloaded at ${NODE_EXP_DIR}"
else
    info "Downloading Node Exporter ${NODE_EXP_VERSION}..."
    wget -q "$NODE_URL" -O "/tmp/${NODE_TAR}"
    mkdir -p "${NODE_EXP_DIR}"
    tar -xzf "/tmp/${NODE_TAR}" -C "${NODE_EXP_DIR}" --strip-components=1 2>/dev/null || {
        cd /tmp && tar -xzf "${NODE_TAR}"
        cp "/tmp/node_exporter-${NODE_EXP_VERSION}.linux-amd64/node_exporter" "${NODE_EXP_DIR}/"
        cd - > /dev/null
    }
    rm -f "/tmp/${NODE_TAR}"
    info "Node Exporter installed at ${NODE_EXP_DIR}"
fi

# ── 3. Prometheus config ──────────────────────────────────────────────────────
cat > "${CONFIG_DIR}/prometheus.yml" <<'YAML'
# =============================================================================
# prometheus.yml — SSP Granularity Study
# =============================================================================
global:
  scrape_interval:     5s   # High frequency for experiment windows
  evaluation_interval: 5s

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter — host-level CPU, memory, disk, network
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # Online Boutique app — Service Weaver exposes metrics at /metrics
  - job_name: 'boutique_app'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
    scrape_timeout: 5s

  # Second VM node exporter (uncomment and replace IP for 2-VM experiments)
  # - job_name: 'node_exporter_vm2'
  #   static_configs:
  #     - targets: ['<VM2_IP>:9100']
YAML

info "Prometheus config written → ${CONFIG_DIR}/prometheus.yml"

# ── 4. Start/Stop helpers ─────────────────────────────────────────────────────
PROM_DATA="${INSTALL_DIR}/prometheus_data"
mkdir -p "$PROM_DATA"

cat > "${CONFIG_DIR}/start_prometheus.sh" <<BASH
#!/usr/bin/env bash
# Start Prometheus + Node Exporter for SSP study
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR}"
CONFIG_DIR="$(pwd)/monitoring"

echo "[START] Node Exporter..."
"\${INSTALL_DIR}/node_exporter/node_exporter" \\
    --web.listen-address=:9100 \\
    > "\${CONFIG_DIR}/node_exporter.log" 2>&1 &
echo \$! > "\${CONFIG_DIR}/node_exporter.pid"
echo "  Node Exporter PID=\$(cat \${CONFIG_DIR}/node_exporter.pid) → :9100"

echo "[START] Prometheus..."
"\${INSTALL_DIR}/prometheus/prometheus" \\
    --config.file="\${CONFIG_DIR}/prometheus.yml" \\
    --storage.tsdb.path="${PROM_DATA}" \\
    --storage.tsdb.retention.time=7d \\
    --web.listen-address=:9090 \\
    --log.level=warn \\
    > "\${CONFIG_DIR}/prometheus.log" 2>&1 &
echo \$! > "\${CONFIG_DIR}/prometheus.pid"
echo "  Prometheus PID=\$(cat \${CONFIG_DIR}/prometheus.pid) → :9090"
echo ""
echo "Prometheus UI: http://localhost:9090"
echo "Node Exporter: http://localhost:9100/metrics"
BASH
chmod +x "${CONFIG_DIR}/start_prometheus.sh"

cat > "${CONFIG_DIR}/stop_prometheus.sh" <<'BASH'
#!/usr/bin/env bash
# Stop Prometheus + Node Exporter
for svc in prometheus node_exporter; do
    pidfile="monitoring/${svc}.pid"
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile")
        kill "$pid" 2>/dev/null && echo "Stopped ${svc} (PID ${pid})" || echo "${svc} already stopped"
        rm -f "$pidfile"
    fi
done
BASH
chmod +x "${CONFIG_DIR}/stop_prometheus.sh"

# ── 5. Grafana install note ───────────────────────────────────────────────────
cat > "${CONFIG_DIR}/grafana_setup_notes.md" <<'MD'
# Grafana Setup (Optional)

## Install
```bash
sudo apt-get install -y apt-transport-https software-properties-common
wget -qO - https://apt.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update && sudo apt-get install grafana
sudo systemctl enable --now grafana-server
```

## Access
http://localhost:3000  (admin / admin)

## Data Source
Add → Prometheus → URL: http://localhost:9090

## Recommended Dashboards (import by ID)
- **Node Exporter Full**: 1860
- **Go Runtime Metrics**: 13240
- **HTTP Overview**:       9614

## Snapshot Export
In Grafana: Dashboard → Share → Snapshot → Save to server
Or use the API:
```bash
curl -s http://admin:admin@localhost:3000/api/snapshots \
  -H 'Content-Type: application/json' \
  -d @<dashboard_json>
```
MD

echo "[$(timestamp)] [SETUP] Prometheus setup complete" | tee -a "$LOG"
echo ""
info "Setup complete!"
info "  Start observability:  ./monitoring/start_prometheus.sh"
info "  Prometheus UI:         http://localhost:9090"
info "  Grafana notes:         monitoring/grafana_setup_notes.md"
