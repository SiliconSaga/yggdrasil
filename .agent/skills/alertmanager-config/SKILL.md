---
name: alertmanager-config
description: Use when writing or debugging a native Prometheus AlertManager config — routing trees, the null-blackhole + Watchdog dead-man's-switch idiom, inhibit/silence rules, webhook payload/header customization (`webhook_configs[].payload`, `http_config.http_headers`) and the native-vs-server-side-vs-bridge templating decision, severity→priority mapping, and amtool validation. Vanilla open-source AlertManager (Prometheus Operator / kube-prometheus-stack), NOT Grafana-managed alerting.
---

# alertmanager-config

## Overview

AlertManager config has a handful of well-known idioms (the `'null'` blackhole receiver, the Watchdog canary, inhibit rules) plus one common confusion: `webhook_configs` *does* support templating the JSON body (`payload:`) and adding custom HTTP headers (`http_config.http_headers:`) — many older blog posts/stackoverflow answers claim otherwise. This skill covers the idioms, the native-vs-server-side-vs-bridge templating choice for shaping downstream payloads, the Prometheus-Operator deployment loop, and the `amtool` toolbox.

## When to Use

- Writing or debugging an `alertmanager.yaml` for vanilla AM / Prometheus Operator / kube-prometheus-stack.
- Need to drop a subset of alerts silently (Watchdog, info-level, default-route flood control).
- Need to map severity to a downstream's notification priority (ntfy, custom pager, …).
- Validating routing or matchers before deploying.

NOT for Grafana-managed alerting (contact points, notification policies) — that's a different config model entirely.

## Quick Reference

| Goal | Idiom | Caveat |
|------|-------|--------|
| Drop alerts silently | Receiver named `'null'` with **no notifier configs**; route to it | Quote `'null'` — bare `null` parses as YAML nil and the route ref no longer matches |
| Default-drop, send only matched | Root `receiver: 'null'` + child `routes:` per severity | Anything unmatched falls through to `'null'` (flood control) |
| Watchdog canary | k-p-stack ships a `Watchdog` alert that ALWAYS fires. Route it to a **dead-man's-switch** service (Dead Man's Snitch, Healthchecks.io) that alerts when the heartbeats stop. | Blackholing Watchdog destroys the pipeline-health signal |
| Suppress derived alerts | `inhibit_rules:` with `source_matchers`, `target_matchers`, `equal: [<shared-labels>]` | Inhibit is a *live* suppression — once source resolves, targets fire. Not a silence. |
| Per-route repeat | Set `repeat_interval` on the specific child route | Default is the root's `repeat_interval` (often 4h — too long for criticals) |
| Matchers vs match | Use modern `matchers: ['severity = "critical"']` | Legacy `match: {severity: critical}` is deprecated |

## Customizing `webhook_configs` Body and Headers

Vanilla AM POSTs a fixed JSON envelope by default (`status`, `commonLabels`, `alerts[]`, `externalURL`, …), but `webhook_configs` *does* support customization — the old "you can't template the body or set headers" claim is out of date:

- **`payload:`** — a templated JSON payload that overrides the default envelope. Rendered with AM's Go templates (`{{ range .Alerts }}`, `{{ .Labels.severity }}`, etc.). Useful for mapping `severity`→`priority` or matching a specific downstream schema.
- **`http_config.http_headers:`** — arbitrary headers (auth tokens, `X-Priority`, content negotiation). Headers AM sets itself (`Content-Type`) can't be overridden.

Three patterns to shape the downstream payload — pick by where templating lives:

1. **Native `payload` + `http_headers` on `webhook_configs`** (preferred for most cases). One config file, no extra runtime, full access to AM's template namespace. Use when the transformation is expressible in Go templates over the alert data.
2. **Server-side templating on the receiver** (when the receiver already has a richer template system). Example: ntfy's `--template-dir` + `?template=<name>` formats title/message/priority server-side; AM just posts its default envelope. Useful if you want to reuse the receiver's templates from other sources too.
3. **A small webhook bridge** (rare — only when the transformation needs logic neither AM templates nor the receiver can express: external lookups, fan-out to multiple downstreams, schema diffing). A ~30-line Go/Python shim. Off-the-shelf: `FXinnovation/alertmanager-webhook-template`, or hand-roll. Adds an extra component to operate; avoid unless you actually need it.

## `amtool` Toolbox

```bash
# 1. Pre-deploy config validation (CI gate).
amtool check-config alertmanager.yaml

# 2. Test the routing tree against a labeled alert (no firing required).
amtool config routes test --config.file=alertmanager.yaml \
  severity=critical alertname=ClusterDown
# → prints which receiver(s) would fire.

# 3. Show the routing tree of a LIVE AlertManager.
amtool config routes --alertmanager.url=http://localhost:9093

# 4. Query active alerts on a live AM (useful for verifying inhibit/silence).
amtool alert query --alertmanager.url=http://localhost:9093 severity=critical
```

`amtool` ships in the same release tarball as AlertManager and is available inside the AM container.

## Verifying the Live Config (Operator-Deployed)

You do **NOT** edit `alertmanager.yaml` on the pod. The Prometheus Operator renders the config from a Secret (kube-prometheus-stack: `alertmanager.config` helm values → secret → CRD-mounted into the pod) and reloads AM via `POST /-/reload` on change. Editing the file in-pod gets overwritten on next reconcile.

Confirm a new config landed by reading the live config back:

```bash
kubectl -n monitoring exec <am-pod> -c alertmanager -- \
  wget -qO- http://localhost:9093/api/v2/status | jq -r '.config.original'
```

Diff against your source. Matching = loaded; mismatch = the Operator's reload hasn't propagated yet (give it ~30s; check `prometheus-operator` logs).

## Common Mistakes

- **Bare `null` receiver.** `receiver: null` parses as YAML nil; the route's reference no longer matches any receiver and AM rejects the config. Always quote `'null'`.
- **Blackholing Watchdog.** Kills your dead-man's-switch. Route Watchdog to an external service that pages when heartbeats stop arriving.
- **Default `repeat_interval` on criticals.** Root is often 4h. Override on the critical child route (e.g. 1h) so re-pages match urgency.
- **Mismatched `equal:` labels in inhibit.** If source and target don't both carry every label listed in `equal:`, inhibit silently no-ops. Verify with `amtool alert query`.
- **Treating inhibit as a silence.** Inhibit only applies while the source is firing. Once the source resolves, all target alerts fire. For long-term suppression use `mute_time_intervals:` or AM silences.
- **Editing `alertmanager.yaml` on the pod.** Operator overwrites on next reload. Edit the source (helm values / `AlertmanagerConfig` CRD / Secret).

## Implementation Sketch (kube-prometheus-stack helm values)

```yaml
alertmanager:
  config:
    route:
      receiver: 'null'
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - matchers: ['severity = "critical"']
          receiver: pager
          repeat_interval: 1h          # override — criticals re-page fast
        - matchers: ['severity = "warning"']
          receiver: email
        - matchers: ['alertname = "Watchdog"']
          receiver: watchdog-dms       # external dead-man's-switch — don't blackhole

    receivers:
      - name: 'null'                   # quote — bare null = YAML nil

      - name: pager
        webhook_configs:
          # Option 1 (native): templated payload + custom headers, no extra runtime.
          - url: 'http://ntfy.ntfy.svc.cluster.local/<topic>'
            send_resolved: true
            http_config:
              http_headers:
                X-Priority: high
                X-Tags: warning,rotating_light
            payload: |
              {
                "alerts": [{{ range $i, $a := .Alerts }}{{ if $i }},{{ end }}
                  {"title":"{{ $a.Labels.alertname }}","msg":"{{ $a.Annotations.description }}"}
                {{ end }}]
              }
          # Option 2 (server-side template on receiver):
          # - url: 'http://ntfy.ntfy.svc.cluster.local/<topic>?template=pager'
          # Option 3 (webhook bridge — only if neither side can express the shape):
          # - url: 'http://am-bridge.monitoring.svc:8080/hook'

      - name: email
        email_configs:
          - to: 'team@example.com'
            send_resolved: true

      - name: watchdog-dms
        webhook_configs:
          - url: 'https://nosnch.in/<token>'
            send_resolved: false

    inhibit_rules:
      - source_matchers: ['severity = "critical"', 'alertname = "ClusterDown"']
        target_matchers: ['severity = "warning"']
        equal: ['cluster']
```

## Sources

- [AlertManager Configuration Reference](https://prometheus.io/docs/alerting/latest/configuration/)
- [amtool — Prometheus AlertManager](https://github.com/prometheus/alertmanager#examples)
- [kube-prometheus-stack chart values](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Operator CRDs](https://prometheus-operator.dev/docs/)
