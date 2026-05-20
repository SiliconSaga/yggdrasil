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
  choice(arc.status = "review",
    choice((date(today) - date(arc.last_touched)).days <= 10, "👀", "😪"),
  choice(arc.status = "closed", "✅", "📦")))) AS "",
  arc.id AS "Arc",
  arc.status AS "Status",
  arc.next AS "Next",
  arc.impact AS "Impact",
  arc.urgency AS "Urgency",
  regexreplace(file.name, "-thalamus$", "") AS "Host",
  (date(today) - date(arc.started)).days AS "Days"
FROM ""
WHERE arcs
FLATTEN arcs AS arc
SORT arc.status ASC, arc.last_touched DESC
```

## Vibe legend & count

```dataview
TABLE WITHOUT ID
  length(rows) AS "Count",
  s AS "Status",
  choice(s = "active", "🔥 (≤2d)",
    choice(s = "parked", "🚗 (≤5d)",
      choice(s = "review", "👀 (≤10d)",
        choice(s = "closed", "✅", "📦")))) AS "Fresh",
  choice(s = "active", "🐢 (≤10d)",
    choice(s = "parked", "🕸️ (≤10d)",
      choice(s = "review", "😪 (>10d)",
        "Audited"))) AS "Slowing",
  choice(s = "active", "⚠️ (>10d)",
    choice(s = "parked", "🧊 (>10d)",
      choice(s = "review", "😪 (chase!)",
        "Pruned"))) AS "Stale"
FROM ""
WHERE arcs
FLATTEN arcs AS arc
FLATTEN arc.status AS s
GROUP BY s
SORT s ASC
```

The Slowing and Stale columns for `closed` / `promoted` are lifecycle markers, not icons — terminal-state arcs survive one housekeeping audit (Slowing = "Audited") then prune on the next (Stale = "Pruned"). `review` arcs (PR open, awaiting third-party review) sit outside the decay model; they shift from 👀 (≤10 days) to 😪 (>10 days) — the drowsier eyes are a poke to chase the review, not a decay signal.

## Tags and hosts

```dataviewjs
const counts = {};
for (const p of dv.pages('""').where(p => p.arcs)) {
  for (const arc of p.arcs) {
    if (!arc.tags) continue;
    for (const tag of arc.tags) {
      counts[tag] = (counts[tag] || 0) + 1;
    }
  }
}
const out = Object.entries(counts)
  .filter(([, n]) => n > 1)
  .sort((a, b) => b[1] - a[1])
  .map(([tag, n]) => `**${tag}** (${n})`);
dv.paragraph(out.length ? out.join(" · ") : "_none_");
```

```dataviewjs
const hosts = dv.pages('""')
  .where(p => p.arcs && p.arcs.length > 0)
  .sort(p => p.arcs.length, "desc")
  .map(p => `**${p.file.name}** (${p.arcs.length})`);
dv.paragraph(hosts.length ? hosts.join(" · ") : "_no arcs yet_");
```

## Schema

Frontmatter shape per arc entry:

```yaml
arcs:
  - id: <kebab-case-slug>          # stable across hosts; same slug = same arc
    name: <short human label>
    status: active                 # active | review | parked | closed | promoted
    started: 2026-05-07
    last_touched: 2026-05-07
    next: "<one-line next step>"
    # optional:
    # issue: https://github.com/<org>/<repo>/issues/<n>
    # impact: high | medium | low          # Eisenhower-lite priority axis
    # urgency: asap | next | soon | later  # paired with impact for the act-order ceremony
    # project: "[[Vault Project Name]]"    # cross-repo link to an Obsidian vault project note
    # tags: [tag-a, tag-b]
```

See [the design doc](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/plans/2026-05-07-thalamus-arc-dashboard-design.md) for full lifecycle and skill-integration details.
