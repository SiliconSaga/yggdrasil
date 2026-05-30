---
name: kube-prometheus-stack
description: Use when configuring the kube-prometheus-stack helm chart — chart wiring + cross-namespace selectors, the `release:` label requirement on ServiceMonitor/PrometheusRule, `Recreate` strategy for single-replica RWO workloads, taming the noisy default `*Down` alerts on managed K8s (GKE/EKS/AKS) where the control plane is hidden, and the GKE dual-stack-cost recipe for fluent-bit↔plugin meta-chatter on `127.0.0.1:2021`. Defers to `grafana/skills` for PromQL/dashboarding/Loki/Tempo and `alertmanager-config` for native AM routing.
---

# kube-prometheus-stack

## Overview

`kube-prometheus-stack` (Prometheus Operator chart) is the canonical opinionated bundle for self-hosted Prometheus + AlertManager + Grafana on Kubernetes. Most of its gotchas are *integration* concerns: how the Operator selects your CRs (ServiceMonitor / PrometheusRule), what breaks on managed K8s where the control plane is hidden, and how to keep your observability stack from doubling your cloud-logging bill.

## When to Use

- Writing or debugging helm values for `prometheus-community/kube-prometheus-stack`.
- Authoring `ServiceMonitor` / `PodMonitor` / `PrometheusRule` CRs the Operator should pick up.
- Deploying on a managed cluster (GKE/EKS/AKS) and seeing constantly-firing default `*Down` alerts.
- Cloud Logging bill spiked after adding your own observability stack on GKE.

NOT for native AlertManager routing/templating — see `alertmanager-config`. NOT for PromQL / Grafana dashboards / Loki / Tempo content — adopt `grafana/skills`.

## Quick Reference

| Goal | Pattern | Gotcha |
|------|---------|--------|
| Operator picks up your CR | Label `ServiceMonitor`/`PrometheusRule` with `release: <chart-release-name>` | Default selector is `release=<release>`. **Missing this is the #1 silent-invisibility cause** — Prometheus doesn't scrape, rules don't fire, no error. |
| Pick up CRs from other namespaces | `prometheus.prometheusSpec.{serviceMonitor,podMonitor,rule,probe}SelectorNilUsesHelmValues: false` + `serviceMonitorNamespaceSelector: {}` (and the matching `*NamespaceSelector` fields) | Default is "same namespace as the Prometheus CR only." |
| Grafana admin password from Secret | `grafana.admin.existingSecret: <name>` + `passwordKey: password` | Legacy `grafana.adminPassword: <value>` works but bakes plaintext into helm values. Chart-version drift: `helm show values prometheus-community/kube-prometheus-stack` to confirm the current path. |
| Scrape interval | `30s` is production-safe | Matches the chart's own cadence and 5m alert windows. |
| `up == 0` `job` label | Operator-generated label is usually `<namespace>/<servicemonitor-name>` | If `up{job="…"} == 0` never matches, query bare `up{}` to see the actual label value. |

## Single-Replica RWO Workloads: `strategy: Recreate`

Any single-replica Deployment that mounts a `ReadWriteOnce` PVC (single-replica Loki, AlertManager with persistence, Grafana with a PVC, ntfy-style sidecar apps) **must** use `strategy: Recreate`. Default RollingUpdate deadlocks on the RWO volume:

- The new pod can't attach the PV the old pod still holds → `Multi-Attach error`.
- maxUnavailable rounds to 0 at 1 replica → the deployment controller refuses to scale old down → pod stuck `ContainerCreating` forever.
- On GKE PD-backed `standard-rwo`, the volume is genuinely single-attach.

`Recreate` kills the old pod first → volume detaches → new pod attaches cleanly. Brief downtime, deterministic.

**In-place migration trap:** SSA-patching an existing `RollingUpdate` Deployment to `Recreate` fails — the API forbids `spec.strategy.rollingUpdate` under `type: Recreate` and provider-kubernetes/SSA can't clear the defaulted field. Delete the live Deployment once so the controller recreates it cleanly from the manifest.

## Noisy Default Alerts on Managed K8s

`kube-prometheus-stack` bundles the upstream `kubernetes-mixin` rules, which assume self-managed control-plane components are scrape-exposed. On GKE/EKS/AKS the masters are hidden — targets are absent — `*Down` alerts fire forever:

- `KubeControllerManagerDown`, `KubeSchedulerDown` — components run on the managed master.
- `KubeProxyDown` — on GKE Dataplane V2 (Cilium) there's no kube-proxy at all.
- `etcd*Down` / `etcdInsufficientMembers` — etcd is master-side.
- `AlertmanagerClusterDown` — fires when AM is `replicas: 1` (rule expects a cluster).

`Watchdog` **always fires by design** — it's the heartbeat for dead-man's-switch integrations. Don't disable it. See `alertmanager-config` → "Watchdog canary."

**Tame at install** (best — both removes the rules AND stops the operator from creating the broken scrape jobs):

```yaml
defaultRules:
  rules:
    kubeControllerManager: false
    kubeSchedulerAlerts: false
    kubeProxy: false
    etcd: false
kubeControllerManager: { enabled: false }
kubeScheduler:         { enabled: false }
kubeProxy:             { enabled: false }
kubeEtcd:              { enabled: false }
```

Alternative — route the alertnames to `'null'` in AlertManager (clutters Prometheus's ALERTS table but suppresses notifications).

## Running on Managed K8s: Dual-Stack Cost Discipline

On managed K8s you have **two parallel log pipes** whether you want them or not:

1. Container stdout → node logging agent → **GCP Cloud Logging / CloudWatch / Azure Monitor** (always-on, charged per GiB).
2. Container stdout → **Promtail → Loki** (your stack, your cost).

You pay the cloud regardless. Discipline: drop the cloud-side ingestion for **your own observability stack's meta-chatter** — it adds no signal (you have it in Loki) but doubles ingest cost.

### Bucket vs sink (the common gcloud confusion)

`--restricted-fields` on a **bucket** is field-level *access control* (which fields can be returned during reads). It does NOT reduce ingestion or cost. Ingestion exclusions live on **sinks** — they drop matching logs before billing. Same filter logic, different verb.

### GKE: the fluent-bit ↔ plugin meta-chatter

The managed `fluentbit-gke` DaemonSet runs a main `fluentbit` container that POSTs every log batch over localhost to a `fluentbit-gke` sidecar plugin server on **`127.0.0.1:2021`** (plugin startup logs: `Starting Fluent Bit GKE plugin server with ... Port:2021`). Each successful POST emits a structured log:

```json
{"message": "127.0.0.1:2021, HTTP status=200", "plugin": "output:http:http.0"}
```

INFO severity, scales with cluster log throughput. `fluentbit-gke` is GKE-managed → unconfigurable → the only path is a Cloud Logging exclusion.

### The exclusion (apply once per project)

**Always verify the filter matches first** — pins down field/payload structure before you commit a no-op:

```bash
gcloud logging read \
  'logName="projects/YOUR_PROJECT_ID/logs/fluentbit" AND jsonPayload.message:"127.0.0.1:2021"' \
  --limit=1 --format=json
```

Then apply:

```bash
gcloud logging sinks update _Default \
  --project=YOUR_PROJECT_ID \
  --add-exclusion='name=fluentbit-localhost-2021-noise,description=Drop fluent-bit GKE-plugin forward chatter,filter=logName="projects/YOUR_PROJECT_ID/logs/fluentbit" AND jsonPayload.message:"127.0.0.1:2021"'
```

Confirm:

```bash
gcloud logging sinks describe _Default --format=yaml
# look for exclusions: -> your name + filter
```

Reversal:

```bash
gcloud logging sinks update _Default \
  --project=YOUR_PROJECT_ID \
  --remove-exclusions=fluentbit-localhost-2021-noise
```

**Filter-field gotcha:** fluent-bit-gke emits structured JSON, so the match is on `jsonPayload.message`, NOT `textPayload`. A filter like `textPayload:"HTTP status="` silently matches nothing — wrong field, no cost reduction.

**Pin the match string narrowly.** `"127.0.0.1:2021"` is the unique meta-chatter marker. Broad markers like `"HTTP status="` would catch unrelated workloads.

**gcloud version drift:** `gcloud logging exclusions create` (older project-level API) was removed in modern gcloud — `sinks update ... --add-exclusion` is the current form. If you're on an older SDK, the fallback is `gcloud logging exclusions create NAME --log-filter=... --description=...`.

**Bake into IaC** for fresh bootstraps: Terraform `google_logging_project_exclusion`, or Crossplane `provider-gcp` `LogExclusion`. Hand-applied exclusions don't survive a project recreate.

## Common Mistakes

- **Forgetting `release: <chart-release>` label** on a ServiceMonitor/PrometheusRule → Operator selector won't pick it up → silent invisibility.
- **`textPayload:` filter against JSON-payload logs** → exclusion silently matches nothing → no cost reduction. Verify the field with `gcloud logging read` first.
- **`--restricted-fields` on a bucket to reduce ingestion cost** → wrong knob (access control, not ingestion). Use sink exclusions.
- **Default `RollingUpdate` on single-replica RWO Deployments** → Multi-Attach deadlock. Use `Recreate`.
- **Leaving control-plane `*Down` alerts enabled on managed K8s** → pager noise / ALERTS-table pollution from alerts that physically cannot resolve. Disable in `defaultRules.rules.*` and `kubeXxx.enabled: false`.
- **`grafana.adminPassword:` in helm values** → plaintext secret in your IaC. Use `grafana.admin.existingSecret`.
- **Disabling `Watchdog`** → kills your dead-man's-switch signal. It's supposed to always fire — wire it to a heartbeat receiver (see `alertmanager-config`).

## Sources

- [kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) — `helm show values` for current paths
- [Prometheus Operator CRDs](https://prometheus-operator.dev/docs/)
- [Cloud Logging — Routing & exclusions](https://cloud.google.com/logging/docs/routing/overview#exclusions)
- For PromQL / dashboards / Loki / Tempo → adopt [grafana/skills](https://github.com/grafana/skills)
- For native AlertManager routing/templating → `alertmanager-config` skill
