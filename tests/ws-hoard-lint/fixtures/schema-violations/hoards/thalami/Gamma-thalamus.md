---
last_session: 2026-08-27
arcs:
  - id: missing-several-keys
    status: active
    next: "No name, no started, no last_touched."
  - id: bogus-status
    name: Status the dashboard cannot render
    status: simmering
    started: 2026-08-01
    last_touched: 2026-08-27
    next: "Falls through every choice() branch and renders as the catch-all icon."
  - id: overgrown-next
    name: A next field that rotted into a status dump
    status: active
    started: 2026-08-01
    last_touched: 2026-08-27
    next: "This next field is far longer than the schema allows, because it stopped being a next step and became a running status report instead, which is exactly the drift the length check is meant to catch before the dashboard table becomes unreadable at a glance."
  - id: multiline-next
    name: A next field spanning lines
    status: parked
    started: 2026-08-01
    last_touched: 2026-08-27
    next: |
      First line of the next step.
      Second line, which the dashboard renders into one table cell.
---

# Thalamus

Body.
