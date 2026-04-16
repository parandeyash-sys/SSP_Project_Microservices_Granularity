#!/usr/bin/env bash
# =============================================================================
# 05_setup_prometheus.sh — Install & configure Prometheus + Node Exporter
# =============================================================================
set -euo pipefail

PROM_VERSION="2.51.2"
NODE_EXP_VERSION="1.8.1"
BASE_DIR=$(realpath "$(dirname "$0")")
INSTALL_DIR="${BASE_DIR}/monitoring_bin"
PROM_DIR="${INSTALL_DIR}/prometheus"
NODE_EXP_DIR="${INSTALL_DIR}/node_exporter"
CONFIG_DIR="${BASE_DIR}/monitoring"
LOG="${BASE_DIR}/experiment.log"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(timestamp)] [SETUP] Prometheus + Node Exporter setup" | tee -a "$LOG"

# Clean start
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# ── 1. Prometheus ──────────────────────────────────────────────────────────────
PROM_TAR="prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TAR}"

if [ -x "${PROM_DIR}/prometheus" ]; then
    info "Prometheus already installed at ${PROM_DIR}"
else
    info "Downloading & installing Prometheus ${PROM_VERSION}..."
    TDIR=$(mktemp -d)
    wget -q "$PROM_URL" -O "${TDIR}/${PROM_TAR}"
    mkdir -p "$PROM_DIR"
    tar -xzf "${TDIR}/${PROM_TAR}" -C "$PROM_DIR" --strip-components=1
    rm -rf "$TDIR"
    info "Prometheus installed."
fi

# ── 2. Node Exporter ──────────────────────────────────────────────────────────
NODE_TAR="node_exporter-${NODE_EXP_VERSION}.linux-amd64.tar.gz"
NODE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXP_VERSION}/${NODE_TAR}"

if [ -x "${NODE_EXP_DIR}/node_exporter" ]; then
    info "Node Exporter already installed at ${NODE_EXP_DIR}"
else
    info "Downloading & installing Node Exporter ${NODE_EXP_VERSION}..."
    TDIR=$(mktemp -d)
    wget -q "$NODE_URL" -O "${TDIR}/${NODE_TAR}"
    mkdir -p "$NODE_EXP_DIR"
    tar -xzf "${TDIR}/${NODE_TAR}" -C "$NODE_EXP_DIR" --strip-components=1
    rm -rf "$TDIR"
    info "Node Exporter installed."
fi

# ── 3. Prometheus config ──────────────────────────────────────────────────────
cat > "${CONFIG_DIR}/prometheus.yml" <<YAML
global:
  scrape_interval:     5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'boutique_app'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
YAML

info "Config written: ${CONFIG_DIR}/prometheus.yml"

# ── 4. Start/Stop helpers ─────────────────────────────────────────────────────
PROM_DATA="${INSTALL_DIR}/prometheus_data"
mkdir -p "$PROM_DATA"

cat > "${CONFIG_DIR}/start_prometheus.sh" <<BASH
#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="\$(realpath "\$(dirname "\$0")")"
BIN_DIR="\$(realpath "\$CONFIG_DIR/../monitoring_bin")"

echo "Starting Node Exporter..."
"\$BIN_DIR/node_exporter/node_exporter" --web.listen-address=:9100 > "\$CONFIG_DIR/node_exporter.log" 2>&1 &
echo \$! > "\$CONFIG_DIR/node_exporter.pid"

echo "Starting Prometheus..."
"\$BIN_DIR/prometheus/prometheus" \\
    --config.file="\$CONFIG_DIR/prometheus.yml" \\
    --storage.tsdb.path="\$BIN_DIR/prometheus_data" \\
    --web.listen-address=:9090 \\
    --log.level=warn > "\$CONFIG_DIR/prometheus.log" 2>&1 &
echo \$! > "\$CONFIG_DIR/prometheus.pid"

echo "Prometheus: http://localhost:9090"
BASH
chmod +x "${CONFIG_DIR}/start_prometheus.sh"

cat > "${CONFIG_DIR}/stop_prometheus.sh" <<'BASH'
#!/usr/bin/env bash
CONFIG_DIR="$(realpath "$(dirname "$0")")"
for svc in prometheus node_exporter; do
    pidfile="$CONFIG_DIR/${svc}.pid"
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile")
        kill "$pid" 2>/dev/null && echo "Stopped $svc" || echo "$svc not running"
        rm -f "$pidfile"
    fi
done
BASH
chmod +x "${CONFIG_DIR}/stop_prometheus.sh"

info "Setup complete. Start with: ./monitoring/start_prometheus.sh"
