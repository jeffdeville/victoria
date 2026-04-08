#!/usr/bin/env bash
# Monit-managed port-forward: Grafana → localhost:3000
# Matches pattern of colony/bin/start-otel-port-forward
set -euo pipefail

export PATH="/Users/jeff/.local/share/mise/installs/kubectl/1.29.0:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/Users/jeff/.kube/config}"

if lsof -i ":3000" -P -sTCP:LISTEN >/dev/null 2>&1; then
  exit 0
fi

exec kubectl port-forward -n monitoring svc/vm-grafana 3000:80 \
  >/dev/null 2>&1
