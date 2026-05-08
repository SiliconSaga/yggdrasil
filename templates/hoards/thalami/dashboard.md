# Thalami Arc Dashboard

Live cross-host view of in-flight work. Renders when this hoard is opened as an Obsidian vault with the Dataview plugin installed.

Each row is one (host, arc) pair. Arcs that span hosts share an `id` slug and appear as adjacent rows under the status sort.

```dataview
TABLE WITHOUT ID
  choice(arc.status = "active",
    choice((date(today) - date(arc.last_touched)).days <= 2, "🔥",
      choice((date(today) - date(arc.last_touched)).days <= 14, "🌱", "⚠️")),
  choice(arc.status = "parked",
    choice((date(today) - date(arc.last_touched)).days <= 2, "🚗",
      choice((date(today) - date(arc.last_touched)).days <= 14, "🧊", "🪦")),
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

**Vibe legend:** active = 🔥 (≤2d) / 🌱 (≤14d) / ⚠️ (stale, audit candidate). parked = 🚗 (warm) / 🧊 (cool) / 🪦 (cold). closed = ✅. promoted = 📦.

## How to view

1. Open this folder as a vault in Obsidian (`File → Open vault → this folder`).
2. Install the **Dataview** community plugin (`Settings → Community plugins → Browse → "Dataview"`).
3. **Recommended:** disable Obsidian's "Readable line length" cap so the table uses the full window width. `Settings → Editor → Readable line length` (toggle off). This vault is single-purpose (thalamus files + dashboard) so the prose-readability cap isn't useful here.
4. Open this file. The query block above renders as a live table.

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
