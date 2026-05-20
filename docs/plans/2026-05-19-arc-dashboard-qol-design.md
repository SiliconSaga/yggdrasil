# ArcDashboard QoL — Design (SP-A)

*Design doc — 2026-05-19. The first facet of the organization-stack model (see `2026-05-19-organization-stack-design.md`). Adds Impact + Urgency, completes the `review` status schema, and introduces a drift-tolerant arc → project `priority` collapse.*

## Problem

`ArcDashboard.md` currently shows arc lifecycle (`status:`) and staleness (`last_touched` → "Days"), but nothing about *importance* or *act-order*. With a dozen or more arcs in flight across hosts, "what should I work on next?" gets harder than it needs to. Three related gaps:

- **No Impact × Urgency read.** Lifecycle status is not priority — an `active` arc and a `parked` arc may both need attention soon, but the dashboard cannot say which.
- **The `review` status is unblessed.** It is used in arc frontmatter (introduced 2026-05-13 for the `hook-ask-tier` arc) but the schema comment in `ArcDashboard.md`, the `arcs:` comment in `templates/thalamus.md`, and the gdd-orientation / gdd-housekeeping skill prose still enumerate only `active|parked|closed|promoted`.
- **Arcs and Obsidian projects double-track priority.** A vault project note carries a single `priority:` field; an arc could now carry richer Impact + Urgency. When the two are linked, there is no rule for keeping the simpler field in step with the richer one.

This document fixes all three with the lightest schema and ceremony additions that do the job.

## The `review` status

Add `review` to the formal status enum everywhere it is enumerated. Logical ordering: `active | review | parked | closed | promoted` (review sits between active and closed in lifecycle terms — the work is built but waiting on third-party review).

Touchpoints:

- `templates/hoards/thalami/ArcDashboard.md` — Schema section comment
- `templates/thalamus.md` — `arcs:` frontmatter comment
- `.agent/skills/gdd-orientation/SKILL.md` — any prose listing statuses
- `.agent/skills/gdd-housekeeping/SKILL.md` — same
- ArcDashboard Dataview queries do not need updating — they already render any `status:` value without a hardcoded enum

## Impact and Urgency

Two new **optional** ordinal fields on each arc:

| Field | Values | Notes |
|-------|--------|-------|
| `impact` | `high` / `medium` / `low` | Light ordinal. Skip RICE-style numeric reach — Eisenhower-lite is the right size for a personal arc list. |
| `urgency` | `asap` / `next` / `soon` / `later` | Vocabulary deliberately echoes the PKM project-status tiers — the two systems feel coherent. No schema collision: they live on different artifacts. `asap` is for things suddenly needed right now. |

Both are optional. Arcs without values render blank in the new dashboard columns — no migration burden, no broken queries.

The two fields together are an **Eisenhower-lite** read (importance × urgency) — a separate axis from `status:` (lifecycle ≠ priority). They are not folded into `status:` and `status:` is not used as a priority proxy.

`deadline:` is a distinct, third thing — a discrete date for absolute-date-bound items ("ship before X"). Urgency is *relative ordering*; `deadline:` is *absolute date*. Both can coexist on an arc.

### Dashboard columns

The main `## Arcs` table in `ArcDashboard.md` gains two new columns positioned **immediately before** "Days":

```
| 🔥 / 🐢 / ⚠️ | Arc | Status | Next | Impact | Urgency | Host | Days |
```

Sort order unchanged (status ASC, last_touched DESC). The new columns are display-only — no auto-sort by Impact × Urgency. Sorting is left to the ceremony (see below) so the user keeps the "what should I look at?" decision in their head.

## The optional `project:` arc field

Add a third optional field that lets an arc point at an Obsidian project note in the active vault:

```yaml
arcs:
  - id: <slug>
    name: <label>
    status: active
    ...
    impact: high
    urgency: next
    project: "[[Garden Planning]]"   # optional; vault-project link
```

The value is a free-form string, conventionally a wikilink like `[[Project Note Name]]`. It is cross-repo (thalami hoard → vault hoard), so Dataview does not resolve it as a clickable link — it is documentary and ceremony-readable. No automated binding.

## The act-order ceremony

A new propose-then-confirm move belongs to `gdd-housekeeping` — the arc-level mirror of the PKM micro-ceremony ("what should I look at?"):

> **Walk the ArcDashboard.** Read `impact:` and `urgency:` across the current host's arcs. Propose an act-order: high-impact × asap first, then high × next, then medium × asap, etc. Surface as a single ranked list with a one-line "if you have an hour, look at X" recommendation. The human accepts or pushes back; no automatic re-sort, no auto-write.

This is the arc-level equivalent of the scribe micro-ceremony — same propose-then-confirm shape, same restraint (no auto-scoring). The dashboard is to the Thalamus what the project dashboard is to the vault.

Touchpoint: extend `.agent/skills/gdd-housekeeping/SKILL.md` Step 2.5 (the existing arcs-list walk) with the act-order subsection, or add a dedicated step. Step 2.5 already walks arcs for lifecycle reasons; folding the act-order proposal into the same walk avoids ceremony bloat.

## The priority collapse — drift-tolerant

When an arc with `impact:` and `urgency:` set also has a `project:` link, the vault project note's `priority:` field can be hand-set from the arc's two-dimensional read — a 2-D → 1-D collapse onto the lighter artifact.

**Drift is accepted.** No mechanical sync. No live binding. No invariant that `priority` matches Impact × Urgency at every moment. The collapse is *aspirational* — the same posture as the Thalamus itself, which drifts between housekeeping sweeps and gets reconciled there.

Two ceremony surfaces propose updates:

- **gdd-housekeeping** — during the act-order walk, when an arc has both `project:` and an `impact:`/`urgency:` read different from what the project's `priority:` currently shows, propose the update. Cross-repo move (thalami → vault), explicit confirmation.
- **scribe** — during any scribe ceremony, when a project note is touched and it has a linked arc with `impact:`/`urgency:`, propose updating `priority:` if it looks stale.

Neither side runs without the other's existence. If the vault is absent, the housekeeping side stays silent. If the arc is absent, the scribe side stays silent.

The Project Note template already carries a `priority:` field (high / medium / low) — no schema change there. The collapse maps:

| Arc Impact × Urgency | → Project `priority:` |
|---|---|
| any × asap, or high × next | `high` |
| high × soon / later; medium × asap / next | `medium` |
| medium × soon / later; low × any | `low` |

This mapping is illustrative for the agent's proposal, not a hard rule. The user can override on any proposal — the collapse is propose-then-confirm like every other ceremony move.

## What this does NOT do

- **No auto-sort.** The dashboard does not sort by Impact × Urgency. Display only; ranking belongs in the ceremony.
- **No mechanical sync.** The arc and the project `priority:` are linked by convention, not by tooling. Drift is fine.
- **No new dashboard visualizations.** No Eisenhower quadrant rendering, no impact-frequency histogram. The two columns are enough.
- **No backfill.** Existing arcs without `impact:` / `urgency:` render blank. No migration script.

## Touchpoints (consolidated)

- `templates/hoards/thalami/ArcDashboard.md` — Schema section (new fields + full status enum); main `## Arcs` query (two new columns)
- `templates/thalamus.md` — `arcs:` frontmatter comment documents the new optional fields and the full status enum
- `hoards/thalami-Cervator/ArcDashboard.md` — live copy mirrors the template
- `.agent/skills/gdd-orientation/SKILL.md` — any status-enum prose updated to include `review`
- `.agent/skills/gdd-housekeeping/SKILL.md` — Step 2.5 (or adjacent) gains the act-order walk + the priority-collapse proposal
- `.agent/skills/scribe/SKILL.md` — gains the project-note-side priority-collapse proposal

## Open questions

- **Vocabulary collision risk.** Urgency uses `next` / `soon` / `later` — the same words as PKM project-status tiers. That is deliberate (the two systems feel coherent), but it is also a footgun if a future contributor confuses them. Mitigation: the schema comments and skill prose name both contexts explicitly so the same word in different fields stays unambiguous.
- **Vault discovery for the priority-collapse.** The housekeeping side needs to find the active vault to update a project note. Today, scribe binds a vault per session; gdd-housekeeping does not. Likely fine to share the scribe skill's binding rules — defer to housekeeping skill implementation.
