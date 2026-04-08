#!/usr/bin/env bash
# Exit 0 if k3d agent node is Ready, 1 otherwise.
# Used by monit to trigger a docker restart when the node goes NotReady.
set -euo pipefail

export PATH="/Users/jeff/.local/share/mise/installs/kubectl/1.29.0:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/Users/jeff/.kube/config}"

STATUS=$(kubectl get node k3d-observability-agent-0 --no-headers 2>/dev/null | awk '{print $2}')

if [[ "$STATUS" == "Ready" ]]; then
  exit 0
else
  exit 1
fi
