---
name: alertmanager-config
description: Use when writing or debugging a native Prometheus AlertManager config — routing trees, the null-blackhole + Watchdog dead-man's-switch idiom, inhibit/silence rules, the `webhook_configs` body limitation (no headers, no body templating) and the bridge-vs-server-side-templating decision, severity→priority mapping, and amtool validation. Vanilla open-source AlertManager (Prometheus Operator / kube-prometheus-stack), NOT Grafana-managed alerting.
---

# alertmanager-config

## Overview

AlertManager config has a handful of well-known idioms (the `'null'` blackhole receiver, the Watchdog canary, inhibit rules) and one hard limitation: `webhook_configs` posts a fixed JSON envelope — you cannot set headers, rewrite the body, or template fields like `priority`. This skill covers the idioms, the limitation and its two workarounds, the Prometheus-Operator deployment loop, and the `amtool` toolbox.

## When to Use

- Writing or debugging an `alertmanager.yaml` for vanilla AM / Prometheus Operator / kube-prometheus-stack.
- Need to drop a subset of alerts silently (Watchdog, info-level, default-route flood control).
- Need to map severity to a downstream's notification priority (ntfy, custom pager, …).
- Validating routing or matchers before deploying.

NOT for Grafana-managed alerting (contact points, notification policies) — see Grafana's `alerting-irm` skill.

## Quick Reference

| Goal | Idiom | Caveat |
|------|-------|--------|
| Drop alerts silently | Receiver named `'null'` with **no notifier configs**; route to it | Quote `'null'` — bare `null` parses as YAML nil and the route ref no longer matches |
| Default-drop, send only matched | Root `receiver: 'null'` + child `routes:` per severity | Anything unmatched falls through to `'null'` (flood control) |
| Watchdog canary | k-p-stack ships a `Watchdog` alert that ALWAYS fires. Route it to a **dead-man's-switch** service (Dead Man's Snitch, Healthchecks.io) that alerts when the heartbeats stop. | Blackholing Watchdog destroys the pipeline-health signal |
| Suppress derived alerts | `inhibit_rules:` with `source_matchers`, `target_matchers`, `equal: [<shared-labels>]` | Inhibit is a *live* suppression — once source resolves, targets fire. Not a silence. |
| Per-route repeat | Set `repeat_interval` on the specific child route | Default is the root's `repeat_interval` (often 4h — too long for criticals) |
| Matchers vs match | Use modern `matchers: ['severity = "critical"']` | Legacy `match: {severity: critical}` is deprecated |

## The `webhook_configs` Body Limitation

Vanilla AM POSTs a fixed JSON envelope (`status`, `commonLabels`, `alerts[]`, `externalURL`, …). You CANNOT add headers, rewrite the body, or template `priority`/`title` fields. The `payload:` / `http_headers:` options you'll find in some examples are **Grafana-managed-alerting only**.

Two patterns to add custom fields like `priority` to the downstream payload — **pick by asking: does the downstream support payload templating?**

1. **Server-side templating on the receiver** (preferred when supported). The downstream renders the body from the AM payload. Example: ntfy's `--template-dir` + `?template=<name>` maps `severity`→priority and formats title/message server-side. No extra component to run.
2. **A small webhook bridge** (when the receiver can't template). A ~30-line Go/Python shim that AM POSTs to → rewrites body → re-POSTs to the real receiver. Off-the-shelf: `FXinnovation/alertmanager-webhook-template`, or hand-roll.

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
          - url: 'http://am-bridge.monitoring.svc:8080/hook'
            # OR, if the downstream supports server-side templating:
            # url: 'http://ntfy.ntfy.svc.cluster.local/<topic>?template=pager'
            send_resolved: true

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
