#!/usr/bin/env bash
# Monit-managed port-forward: VictoriaTraces → localhost:10428
set -euo pipefail

export PATH="/Users/jeff/.local/share/mise/installs/kubectl/1.29.0:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/Users/jeff/.kube/config}"

if lsof -i ":10428" -P -sTCP:LISTEN >/dev/null 2>&1; then
  exit 0
fi

exec kubectl port-forward -n monitoring svc/traces-vt-single-server 10428:10428 \
  >/dev/null 2>&1
