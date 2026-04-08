#!/usr/bin/env bash
# Apply Grafana provisioning configmaps (datasources + dashboards).
# The Grafana sidecar watches for these and hot-reloads — no pod restart needed.
# Run this after cluster create or whenever provisioning files change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROV="$SCRIPT_DIR/../helm/provisioning"

echo "Applying Grafana provisioning configmaps..."
kubectl apply -f "$PROV/datasources.yaml"
kubectl apply -f "$PROV/dashboard-overview.yaml"
kubectl apply -f "$PROV/dashboard-logs.yaml"
kubectl apply -f "$PROV/dashboard-traces.yaml"
echo "✓ Done — sidecar will reload within ~30s"
