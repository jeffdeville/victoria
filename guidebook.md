# Instrumentation Guidebook

How to connect a project deployed into the observability cluster.

## Overview

Each project lives in its own Kubernetes namespace. Telemetry flows like this:

```
your app (OTEL SDK)
    ↓ OTLP/gRPC or HTTP
OpenTelemetry Collector  (otel-opentelemetry-collector.monitoring.svc.cluster.local)
    ↓ enriches with k8s.namespace.name → project label
    ├── VictoriaMetrics  (metrics)
    ├── VictoriaLogs     (logs)
    └── VictoriaTraces   (traces)
```

The collector automatically adds a `project` label/attribute to all telemetry by reading the Kubernetes namespace of the sending pod. You do not need to set this yourself.

---

## Step 1: Create a namespace for the project

```bash
kubectl create namespace my-project
```

That's the only infrastructure step. Everything else is in your app.

---

## Step 2: Point the OTEL SDK at the collector

### Collector endpoints

| Protocol | Address |
|----------|---------|
| gRPC (preferred) | `otel-opentelemetry-collector.monitoring.svc.cluster.local:4317` |
| HTTP | `otel-opentelemetry-collector.monitoring.svc.cluster.local:4318` |

These are plain HTTP (no TLS) — they're internal cluster traffic.

### Environment variables (works for most SDKs)

Set these in your pod spec or deployment:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-opentelemetry-collector.monitoring.svc.cluster.local:4317"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "grpc"
  - name: OTEL_SERVICE_NAME
    value: "my-service-name"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=local"
```

`OTEL_SERVICE_NAME` is what appears in trace timelines, log searches, and metric labels. Use a consistent name across deploys.

---

## Step 3: SDK setup by language

### Elixir / Phoenix

Add to `mix.exs`:
```elixir
{:opentelemetry, "~> 1.4"},
{:opentelemetry_exporter, "~> 1.8"},
{:opentelemetry_phoenix, "~> 1.2"},
{:opentelemetry_ecto, "~> 1.2"},    # if using Ecto
{:opentelemetry_logger_metadata, "~> 0.1"},  # structured logs
```

`config/runtime.exs`:
```elixir
config :opentelemetry,
  resource: [
    service: [
      name: System.get_env("OTEL_SERVICE_NAME", "my-app"),
      version: System.get_env("APP_VERSION", "dev")
    ]
  ]

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: System.get_env(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://otel-opentelemetry-collector.monitoring.svc.cluster.local:4317"
  )
```

`application.ex`:
```elixir
OpentelemetryPhoenix.setup()
OpentelemetryEcto.setup([:my_app, :repo])
```

Logs: Phoenix already logs structured data. To forward logs through OTLP, use `opentelemetry_logger_metadata` + a log exporter, or ship stdout logs via a sidecar (see Log shipping section below).

### Go

```bash
go get go.opentelemetry.io/otel \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc \
       go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc \
       go.opentelemetry.io/otel/sdk/trace \
       go.opentelemetry.io/otel/sdk/metric
```

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func setupOtel(ctx context.Context) (func(), error) {
    res := resource.NewWithAttributes(
        semconv.SchemaURL,
        semconv.ServiceName("my-service"),
        semconv.ServiceVersion("1.0.0"),
    )

    // Traces
    traceExp, _ := otlptracegrpc.New(ctx,
        otlptracegrpc.WithInsecure(),
        otlptracegrpc.WithEndpoint("otel-opentelemetry-collector.monitoring.svc.cluster.local:4317"),
    )
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(traceExp),
        sdktrace.WithResource(res),
    )
    otel.SetTracerProvider(tp)

    // Metrics
    metricExp, _ := otlpmetricgrpc.New(ctx,
        otlpmetricgrpc.WithInsecure(),
        otlpmetricgrpc.WithEndpoint("otel-opentelemetry-collector.monitoring.svc.cluster.local:4317"),
    )
    mp := sdkmetric.NewMeterProvider(
        sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp)),
        sdkmetric.WithResource(res),
    )
    otel.SetMeterProvider(mp)

    return func() { tp.Shutdown(ctx); mp.Shutdown(ctx) }, nil
}
```

### Node.js / TypeScript

```bash
npm install @opentelemetry/sdk-node \
            @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-trace-otlp-grpc \
            @opentelemetry/exporter-metrics-otlp-grpc
```

`instrumentation.ts` (loaded before your app):
```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-opentelemetry-collector.monitoring.svc.cluster.local:4317',
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: 'http://otel-opentelemetry-collector.monitoring.svc.cluster.local:4317',
    }),
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

`package.json`:
```json
{
  "scripts": {
    "start": "node -r ./instrumentation.js dist/index.js"
  }
}
```

### Python

```bash
pip install opentelemetry-sdk \
            opentelemetry-exporter-otlp-proto-grpc \
            opentelemetry-instrumentation-fastapi \  # or flask, django, etc.
            opentelemetry-instrumentation-requests
```

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource

ENDPOINT = "otel-opentelemetry-collector.monitoring.svc.cluster.local:4317"

resource = Resource.create({"service.name": "my-service"})

# Traces
tracer_provider = TracerProvider(resource=resource)
tracer_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT, insecure=True))
)
trace.set_tracer_provider(tracer_provider)

# Metrics
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=ENDPOINT, insecure=True)
)
meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(meter_provider)
```

---

## Step 4: Log shipping

OTLP log export is the cleanest path if your SDK supports it. For frameworks that don't, ship stdout/stderr via a Vector sidecar.

### Option A: OTLP logs (SDK-native, preferred)

Add the OTLP log exporter alongside traces and metrics. Example for Python:

```python
from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter

logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter(endpoint=ENDPOINT, insecure=True))
)
set_logger_provider(logger_provider)

# Bridge Python logging to OTEL
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)
```

### Option B: Vector sidecar (stdout → VictoriaLogs)

Add to your pod spec when OTLP log export isn't available:

```yaml
# In your Deployment spec.template.spec:
volumes:
  - name: varlog
    emptyDir: {}

containers:
  - name: my-app
    # ... your app container
    volumeMounts:
      - name: varlog
        mountPath: /var/log/app

  - name: log-shipper
    image: timberio/vector:0.41.0-alpine
    args: ["--config", "/etc/vector/vector.yaml"]
    volumeMounts:
      - name: varlog
        mountPath: /var/log/app
    env:
      - name: K8S_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: K8S_POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
    volumeMounts:
      - name: vector-config
        mountPath: /etc/vector

  - name: vector-config
    configMap:
      name: vector-config
```

`vector-config` ConfigMap:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vector-config
data:
  vector.yaml: |
    sources:
      app_logs:
        type: file
        include: ["/var/log/app/*.log"]

    transforms:
      add_metadata:
        type: remap
        inputs: [app_logs]
        source: |
          .project = get_env_var!("K8S_NAMESPACE")
          .pod = get_env_var!("K8S_POD_NAME")

    sinks:
      victoria_logs:
        type: elasticsearch
        inputs: [add_metadata]
        endpoints: ["http://logs-victoria-logs-single-server.monitoring.svc.cluster.local:9428/insert/elasticsearch/"]
        mode: bulk
        bulk:
          index: "logs"
```

---

## Step 5: Querying your project's data

After deploying, filter all UIs to your project namespace.

### Grafana → Explore

**Metrics** (VictoriaMetrics datasource):
```
{project="my-project", __name__=~".*"}
```
or for a specific metric:
```
http_requests_total{project="my-project", service_name="my-service"}
```

**Logs** (VictoriaLogs datasource):
```
project: my-project AND level: error
```
or with stream filter:
```
{project="my-project"} | json | level = "error"
```

**Traces** (VictoriaTraces datasource):
- Search by service name or use the TraceQL query:
```
{ resource.project = "my-project" }
```
- Or filter by `resource.service.name = "my-service"`

### Native UIs

- **VictoriaMetrics**: http://vmui.obsrv.clny.dev — enter MetricsQL directly
- **VictoriaLogs**: http://logs.obsrv.clny.dev — LogsQL query interface
- **VictoriaTraces**: http://traces.obsrv.clny.dev — Jaeger-compatible UI

---

## Step 6: Adding alerts

Create a `VMRule` in your project's namespace:

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: my-project-alerts
  namespace: my-project
spec:
  groups:
    - name: my-project
      interval: 1m
      rules:
        - alert: HighErrorRate
          expr: |
            rate(http_requests_total{project="my-project", status=~"5.."}[5m])
            /
            rate(http_requests_total{project="my-project"}[5m]) > 0.05
          for: 5m
          labels:
            severity: warning
            project: my-project
          annotations:
            summary: "High error rate in {{ $labels.service_name }}"
            description: "Error rate is {{ $value | humanizePercentage }}"

        - alert: ServiceDown
          expr: up{project="my-project"} == 0
          for: 2m
          labels:
            severity: critical
            project: my-project
```

Apply it:
```bash
kubectl apply -f alerts.yaml
```

VMAlert picks it up automatically — no restart needed. View firing alerts at http://alertmanager.obsrv.clny.dev.

---

## Checklist

- [ ] Namespace created: `kubectl create namespace my-project`
- [ ] `OTEL_EXPORTER_OTLP_ENDPOINT` set to the collector gRPC address
- [ ] `OTEL_SERVICE_NAME` set to a consistent service name
- [ ] Traces instrumented (auto-instrumentation or manual spans)
- [ ] Metrics instrumented (process metrics auto-collected; add custom counters/histograms as needed)
- [ ] Logs shipping (OTLP or Vector sidecar)
- [ ] Verified data appears in Grafana: filter by `project="my-project"`
- [ ] Alerts defined as `VMRule` in project namespace

---

## Common issues

**No data appearing**: Check that your pod's service account has no network policies blocking egress to port 4317 in the `monitoring` namespace. In k3d the default allows all, so this is usually only an issue if you've added network policies.

**`k8s.namespace.name` not being set**: The collector's `k8sattributes` processor looks up the sending pod's IP in the Kubernetes API. This requires the pod to be sending from its actual pod IP (not NATed). This works by default in k3d.

**Metrics not visible in VMSingle**: VictoriaMetrics ignores OTLP metrics with no data points. Ensure your SDK is actually recording values before export, not just creating instruments.

**Traces showing but no logs correlated**: Ensure your log exporter is propagating the `trace_id` field. With `LoggingInstrumentor` in Python or `opentelemetry_logger_metadata` in Elixir, this is automatic when a span is active.
