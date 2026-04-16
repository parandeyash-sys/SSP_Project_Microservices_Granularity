#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="$(realpath "$(dirname "$0")")"
BIN_DIR="$(realpath "$CONFIG_DIR/../monitoring_bin")"

echo "Starting Node Exporter..."
"$BIN_DIR/node_exporter/node_exporter" --web.listen-address=:9100 > "$CONFIG_DIR/node_exporter.log" 2>&1 &
echo $! > "$CONFIG_DIR/node_exporter.pid"

echo "Starting Prometheus..."
"$BIN_DIR/prometheus/prometheus" \
    --config.file="$CONFIG_DIR/prometheus.yml" \
    --storage.tsdb.path="$BIN_DIR/prometheus_data" \
    --web.listen-address=:9090 \
    --log.level=warn > "$CONFIG_DIR/prometheus.log" 2>&1 &
echo $! > "$CONFIG_DIR/prometheus.pid"

echo "Prometheus: http://localhost:9090"
