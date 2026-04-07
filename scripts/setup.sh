#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"
CLUSTER_CONFIG="../cluster/k3d-config.yaml"
HELM_DIR="../helm"

# ── Prerequisites ──────────────────────────────────────────────────────────────
check_prerequisites() {
  local missing=()
  for cmd in k3d kubectl helm docker; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}"
    echo ""
    echo "Install with:"
    echo "  brew install k3d kubectl helm"
    echo "  # Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi
  if ! docker info &>/dev/null; then
    echo "ERROR: Docker is not running. Start Docker Desktop first."
    exit 1
  fi
  echo "✓ Prerequisites satisfied"
}

# ── Cluster ────────────────────────────────────────────────────────────────────
create_cluster() {
  if k3d cluster list | grep -q "^observability"; then
    echo "✓ Cluster 'observability' already exists, skipping creation"
    k3d kubeconfig merge observability --kubeconfig-merge-default
    return
  fi
  echo "Creating k3d cluster 'observability'..."
  k3d cluster create --config "$CLUSTER_CONFIG"
  echo "✓ Cluster created"
}

# ── Helm repos ─────────────────────────────────────────────────────────────────
add_helm_repos() {
  helm repo add vm https://victoriametrics.github.io/helm-charts/ 2>/dev/null || true
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
  helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
  helm repo update
  echo "✓ Helm repos updated"
}

# ── Namespace ──────────────────────────────────────────────────────────────────
create_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo "✓ Namespace '$NAMESPACE' ready"
}

# ── cert-manager ───────────────────────────────────────────────────────────────
# Required by the VictoriaMetrics operator for webhook TLS
install_cert_manager() {
  echo "Installing cert-manager..."
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --wait \
    --timeout 5m
  echo "✓ cert-manager ready"
}

# ── VictoriaMetrics operator (must be ready before CRDs are applied) ───────────
install_operator() {
  echo "Installing victoria-metrics-operator..."
  helm upgrade --install vm-operator vm/victoria-metrics-operator \
    --namespace "$NAMESPACE" \
    --wait \
    --timeout 5m
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=victoria-metrics-operator \
    -n "$NAMESPACE" \
    --timeout=120s
  echo "✓ Operator ready"
}

# ── VictoriaMetrics stack ──────────────────────────────────────────────────────
install_metrics() {
  echo "Installing victoria-metrics-k8s-stack..."
  helm upgrade --install vm vm/victoria-metrics-k8s-stack \
    --namespace "$NAMESPACE" \
    --values "$HELM_DIR/metrics-values.yaml" \
    --wait \
    --timeout 10m
  echo "✓ VictoriaMetrics stack ready"
}

# ── VictoriaLogs ───────────────────────────────────────────────────────────────
install_logs() {
  echo "Installing victoria-logs-single..."
  helm upgrade --install logs vm/victoria-logs-single \
    --namespace "$NAMESPACE" \
    --values "$HELM_DIR/logs-values.yaml" \
    --wait \
    --timeout 5m
  echo "✓ VictoriaLogs ready"
}

# ── VictoriaTraces ─────────────────────────────────────────────────────────────
install_traces() {
  echo "Installing victoria-traces-single..."
  helm upgrade --install traces vm/victoria-traces-single \
    --namespace "$NAMESPACE" \
    --values "$HELM_DIR/traces-values.yaml" \
    --wait \
    --timeout 5m
  echo "✓ VictoriaTraces ready"
}

# ── OpenTelemetry Collector ────────────────────────────────────────────────────
install_collector() {
  echo "Installing opentelemetry-collector..."
  helm upgrade --install otel open-telemetry/opentelemetry-collector \
    --namespace "$NAMESPACE" \
    --values "$HELM_DIR/collector-values.yaml" \
    --wait \
    --timeout 5m
  echo "✓ OpenTelemetry Collector ready"
}

# ── /etc/hosts entries ─────────────────────────────────────────────────────────
print_hosts_instructions() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Add these entries to /etc/hosts (requires sudo):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Run this command:"
  echo ""
  echo '  sudo bash -c '"'"'cat >> /etc/hosts << EOF'"'"
  echo "  127.0.0.1  grafana.local"
  echo "  127.0.0.1  vmui.local"
  echo "  127.0.0.1  vlui.local"
  echo "  127.0.0.1  vtui.local"
  echo "  127.0.0.1  alertmanager.local"
  echo "EOF"
  echo ""
}

# ── Service name verification ──────────────────────────────────────────────────
print_service_names() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Deployed services in namespace '$NAMESPACE':"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  kubectl get svc -n "$NAMESPACE" --no-headers \
    | awk '{print "  " $1 " → " $5}' \
    | sort
  echo ""
  echo "If the VMSingle service name differs from 'vmsingle-victoria-metrics',"
  echo "update the endpoint in helm/collector-values.yaml and re-run:"
  echo "  helm upgrade otel-collector open-telemetry/opentelemetry-collector \\"
  echo "    --namespace $NAMESPACE --values helm/collector-values.yaml"
  echo ""
}

# ── Access summary ─────────────────────────────────────────────────────────────
print_access() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Access"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Grafana          http://grafana.local:8088      admin/admin"
  echo "  VictoriaMetrics  http://vmui.local:8088/vmui"
  echo "  Alertmanager     http://alertmanager.local:8088"
  echo ""
  echo "Native UIs (port-forward as needed):"
  echo "  kubectl port-forward svc/logs-victoria-logs-single-server 9428 -n monitoring"
  echo "  kubectl port-forward svc/traces-vt-single-server 10428 -n monitoring"
  echo "  Then open http://localhost:9428  or  http://localhost:10428"
  echo ""
  echo "From project namespaces, send OTLP to:"
  echo "  gRPC:  otel-opentelemetry-collector.monitoring.svc.cluster.local:4317"
  echo "  HTTP:  otel-opentelemetry-collector.monitoring.svc.cluster.local:4318"
  echo ""
  echo "Filter by project in queries:"
  echo "  Metrics:  {project=\"your-namespace\"}"
  echo "  Logs:     {project=\"your-namespace\"} | ..."
  echo "  Traces:   resource.project = \"your-namespace\""
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo "=== VictoriaMetrics Observability Stack Setup ==="
  echo ""

  check_prerequisites
  create_cluster
  add_helm_repos
  create_namespace
  install_cert_manager
  install_operator
  install_metrics
  install_logs
  install_traces
  install_collector

  echo ""
  echo "=== Setup complete ==="
  echo ""
  print_service_names
  print_hosts_instructions
  print_access
}

main "$@"
