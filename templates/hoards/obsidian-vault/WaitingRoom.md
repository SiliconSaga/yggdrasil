---
type: dashboard
tags: [dashboard, waiting]
---

# WaitingRoom

Projects parked in `waiting` status — blocked, scheduled, or pinged-but-unanswered.

`waiting` is off the decay path (blocked items aren't low-energy items), so this surface exists to keep them visible. The `scribe` skill surfaces items here that have been waiting longer than 30 days during ceremony and proposes a follow-up action or a status flip back to `active` / `next`.

```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  area AS "Area",
  (date(today) - file.mtime).days AS "Days waiting"
FROM "10_Projects"
WHERE status = "waiting"
SORT file.mtime ASC
```

See [[Status Schema]] for the full status enum and [[Ceremony Layers]] for how the `waiting` poke fits the review cadence.
