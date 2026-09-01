---
last_session: 2026-08-23
arcs:
  - id: broken-scalar
    name: The real-world shape of this bug
    status: active
    started: 2026-08-01
    last_touched: 2026-08-23
    next: "Current status here. OLD NOTE: " and then prose continues past the closing quote."
  - id: collateral-damage
    name: A perfectly valid arc in the same file
    status: active
    started: 2026-08-02
    last_touched: 2026-08-23
    next: "This one is fine, and still vanishes from the dashboard."
---

# Thalamus

An unescaped `"` inside a double-quoted scalar closes it early, so the
whole document fails to parse and BOTH arcs above stop matching the
dashboard's `WHERE arcs`. Observed in the wild on 2026-08-24.
