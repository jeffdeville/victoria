#!/usr/bin/env bash
# Expose observability services on localhost for local tooling (MCP servers, CLIs, etc.)
# Run this in a terminal while you're working; Ctrl-C kills all forwards.

set -euo pipefail

NAMESPACE="monitoring"

echo "Starting port-forwards (Ctrl-C to stop all)..."
echo "  VictoriaMetrics → http://localhost:8428"
echo "  VictoriaLogs    → http://localhost:9428"
echo "  VictoriaTraces  → http://localhost:10428"
echo "  Grafana         → http://localhost:3000"
echo "  OTEL Collector  → grpc://localhost:4317  http://localhost:4318"

kubectl port-forward svc/vmsingle-vm-victoria-metrics-k8s-stack 8428 -n "$NAMESPACE" &
kubectl port-forward svc/logs-victoria-logs-single-server       9428 -n "$NAMESPACE" &
kubectl port-forward svc/traces-vt-single-server               10428 -n "$NAMESPACE" &
kubectl port-forward svc/vm-grafana                             3000:80 -n "$NAMESPACE" &
kubectl port-forward svc/otel-opentelemetry-collector           4317 4318 -n "$NAMESPACE" &

wait
