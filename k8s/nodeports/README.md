# NodePort Services — Stable Host Ingress

Standalone `type: NodePort` Service objects that expose observability
backends on predictable localhost ports without requiring `kubectl
port-forward` processes.

## How it works

```
localhost:<hostPort> → k3d-observability-serverlb → node:<nodePort> → Service → pod
```

The host-port → node-port mapping lives in `cluster/k3d-config.yaml`
(applied at cluster create) or can be added live via:

```bash
k3d cluster edit observability --port-add <hostPort>:<nodePort>@loadbalancer
```

## Port map

| Backend          | Host port | NodePort | Pod port |
|------------------|----------:|---------:|---------:|
| VictoriaMetrics  | 8428      | 30428    | 8428     |
| VictoriaLogs     | 9428      | 30429    | 9428     |
| VictoriaTraces   | 10428     | 30430    | 10428    |
| Grafana          | 3000      | 30431    | 80       |
| OTLP gRPC        | 4317      | 30432    | 4317     |
| OTLP HTTP        | 4318      | 30433    | 4318     |
| vmalert          | 8880      | 30434    | 8080     |

## Why standalone Services?

VictoriaLogs and VictoriaTraces use StatefulSet headless services
(`clusterIP: None`) for pod DNS. Those can't be NodePort themselves.
Rather than fight the Helm chart, these extra Services sit alongside
the originals and target the same pods by label selector.

## Apply

```bash
kubectl apply -f k8s/nodeports/
```

## Why not `kubectl port-forward` via Monit?

Each port-forward was a separate long-lived kubectl process supervised
by Monit. When the k3d node hiccupped or the serverlb restarted, the
port-forward died; Monit restarted it; sometimes that got stuck.
Anchoring ingress at the k3d layer removes the moving parts.
