#!/usr/bin/env bash
set -euo pipefail

echo "This will delete the 'observability' k3d cluster and all data."
read -r -p "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

k3d cluster delete observability
echo "✓ Cluster deleted"

echo ""
echo "To remove /etc/hosts entries, delete the lines containing:"
echo "  grafana.local, vmui.local, vlui.local, vtui.local, alertmanager.local"
