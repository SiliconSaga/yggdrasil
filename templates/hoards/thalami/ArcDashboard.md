# Thalami Arc Dashboard

Live cross-host view of in-flight work. Renders when this hoard is opened as an Obsidian vault with the Dataview plugin installed (see this hoard's `README.md` for one-time setup).

## Arcs

Each row is one (host, arc) pair. Arcs that span hosts share an `id` slug and appear as adjacent rows under the status sort.

```dataview
TABLE WITHOUT ID
  choice(arc.status = "active",
    choice((date(today) - date(arc.last_touched)).days <= 2, "🔥",
      choice((date(today) - date(arc.last_touched)).days <= 10, "🐢", "⚠️")),
  choice(arc.status = "parked",
    choice((date(today) - date(arc.last_touched)).days <= 5, "🚗",
      choice((date(today) - date(arc.last_touched)).days <= 10, "🕸️", "🧊")),
  choice(arc.status = "closed", "✅", "📦"))) AS "",
  arc.id AS "Arc",
  arc.status AS "Status",
  arc.next AS "Next",
  file.name AS "Host",
  (date(today) - date(arc.started)).days AS "Days"
FROM ""
WHERE arcs
FLATTEN arcs AS arc
SORT arc.status ASC, arc.last_touched DESC
```

## Diagnostics

<div style="display: flex; gap: 1.25rem; flex-wrap: wrap; align-items: flex-start;">

<div style="flex: 1 1 220px;">

**Tags (>1 arc)**

```dataview
TABLE WITHOUT ID
  tag AS "Tag",
  length(rows) AS "Arcs"
FROM ""
WHERE arcs
FLATTEN arcs AS arc
FLATTEN arc.tags AS tag
GROUP BY tag
WHERE length(rows) > 1
SORT length(rows) DESC
```

</div>

<div style="flex: 1 1 220px;">

**Vibe legend**

| Status   | Fresh        | Slowing       | Stale         |
|----------|--------------|---------------|---------------|
| active   | 🔥 (≤2d)     | 🐢 (≤10d)     | ⚠️ (>10d)     |
| parked   | 🚗 (≤5d)     | 🕸️ (≤10d)     | 🧊 (>10d)     |
| closed   | ✅           | ✅            | ✅            |
| promoted | 📦           | 📦            | 📦            |

</div>

<div style="flex: 1 1 220px;">

**Status count**

```dataview
TABLE WITHOUT ID
  s AS "Status",
  length(rows) AS "Count"
FROM ""
WHERE arcs
FLATTEN arcs AS arc
FLATTEN arc.status AS s
GROUP BY s
SORT length(rows) DESC
```

</div>

</div>

## Per-host

```dataview
TABLE WITHOUT ID
  file.name AS "Host",
  length(arcs) AS "Arcs"
FROM ""
WHERE arcs
SORT length(arcs) DESC
```

## Schema

Frontmatter shape per arc entry:

```yaml
arcs:
  - id: <kebab-case-slug>          # stable across hosts; same slug = same arc
    name: <short human label>
    status: active                 # active | parked | closed | promoted
    started: 2026-05-07
    last_touched: 2026-05-07
    next: "<one-line next step>"
    # optional:
    # issue: https://github.com/<org>/<repo>/issues/<n>
    # tags: [tag-a, tag-b]
```

See [the design doc](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/plans/2026-05-07-thalamus-arc-dashboard-design.md) for full lifecycle and skill-integration details.
