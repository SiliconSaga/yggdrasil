---
created: 2026-05-15
type: resource
tags: [pkm, methodology, schema]
status: active
---

# Status Schema

The five-tier status enum carried in every project note's `status:` frontmatter, plus the two terminal states `done` and `cancelled`.

| Status | Meaning | Folder |
|---|---|---|
| `active` | Currently moving; work touched recently | `10_Projects/` |
| `next` | Top-of-mind, picking up next | `10_Projects/` |
| `soon` | Committed, queued behind `next` | `10_Projects/` |
| `waiting` | Blocked or future-scheduled (not lack of energy) | `10_Projects/` |
| `someday` | Wishful, no commitment | `40_Archive/Backlog/` |
| `done` | Finished successfully | `40_Archive/Projects/` |
| `cancelled` | Abandoned deliberately | `40_Archive/Projects/` |

## Decay

When a project goes untouched for long enough, the agent proposes a status flip (and a move when the new status implies a different folder). You confirm; nothing drifts silently.

| Transition | Threshold |
|---|---|
| `active` → `next` | 14 days untouched |
| `next` → `soon` | 28 days untouched |
| `soon` → `someday` | 42 days untouched (+ move to `40_Archive/Backlog/`) |
| `someday` → archive-propose | 84 days untouched (full archive after you confirm) |
| `waiting` → poke | 30 days untouched ("still waiting on X?" — no status change proposed) |

`waiting` is intentionally **not** on the decay path. Blocked is categorically different from low-energy. The agent surfaces stale waiting items periodically; you decide what to do with them.

## Why five tiers

Binary `active` / `archive` forces a project to be either a current commitment or dead. Most projects are neither — they have momentum that ebbs. The intermediate tiers (`next`, `soon`, `someday`) let a project lose energy gracefully without a binary "you failed" signal, and let the agent propose realistic drift instead of demanding you defend every stalled item. `waiting` is separated out because a blocked project shouldn't decay — it's parked for a reason, not for lack of will.

`done` and `cancelled` are folder destinations (`40_Archive/Projects/`), not active-query statuses — moving the file is the canonical "this is finished" signal.

## `#someday` tasks vs the `someday` status

The `someday` above is a **project** status — a whole project note parked in `40_Archive/Backlog/`. An individual loose **task** can also be deferred without becoming a project: tag it `#someday` alongside its area tag (`#area/<slug>`), and it surfaces in that area note's `## Someday` section while staying off the global Dashboard. Rule of thumb: project status for whole initiatives, the `#someday` task tag for one-off "maybe later" actions.
