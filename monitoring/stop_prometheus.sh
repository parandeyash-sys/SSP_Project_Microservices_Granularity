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
