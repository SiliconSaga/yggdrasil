# Thalamus Arc Dashboard — Design

**Status:** Draft, ready for plan
**Date:** 2026-05-07
**Owner:** Rasmus Praestholm
**Related:** [Realms and Hoards Design](2026-04-24-realms-and-hoards-design.md), [Scribe Role and Vault Templates](2026-05-01-scribe-role-and-vault-templates-design.md)

## Overview

Add a lightweight, cross-host visibility layer for in-flight work across multiple machines using the same yggdrasil workspace. The mechanism is a small `arcs:` list in each per-machine `<host>-thalamus.md` frontmatter, rendered as a single live table by Obsidian's Dataview plugin when the user opens the thalami hoard as a vault.

An *arc* is a discrete strand of work — typically finer-grained than a session (one session can spawn multiple arcs via tangents) but coarser than a single edit. Arcs carry status (`active` / `parked` / `closed` / `promoted`), a stable slug for cross-host stitching, and a one-line "next" pointer. The dashboard answers the question *"what was I working on, and where?"* without revealing any of the sensitive operational detail that lives in the body of each Thalamus file.

The pattern parallels Vörðu's split between dirty source (BDD scenarios in component repos) and clean projection (the roadmap dashboard). Here the dirty source is the full Thalamus body content; the clean projection is the frontmatter `arcs:` list. The renderer is Obsidian itself, so no new infrastructure is introduced.

## Goals

1. **Cross-host visibility** — at-a-glance view of active work across all machines using the workspace
2. **Sensitive content stays put** — only the frontmatter projection is dashboarded; bodies of Thalamus files are never exposed to a renderer
3. **Zero new infrastructure** — no CI, no Action, no Pages site, no daemon; Obsidian + Dataview only
4. **Convention over enforcement** — slug discipline and lifecycle transitions are conventions enforced by skill prose, not validation code
5. **Compose with existing GDD** — extend `gdd-orientation`, `gdd-flow`, and `gdd-housekeeping` rather than introducing a new skill
6. **Propose-not-act** — agent surfaces arc-shaped suggestions and confirms before mutating frontmatter, matching the cadence/staleness nudge pattern
7. **Thin schema, room to grow** — minimum viable fields in v1, with optional fields for the cases that already have known shape (`issue:`, `tags:`)

## Non-goals

The following are explicitly out of scope for v1:

- A push-event-built static dashboard (e.g., GitHub Action emitting HTML/JSON to a Pages site). Deferred until evidence shows Obsidian-only is insufficient.
- Cross-host arc registry, slug authority, or validation tooling. Convention plus grep is enough until evidence shows otherwise.
- Autonomous arc bookkeeping (agent creating/updating arcs without confirmation). The propose-not-act pattern is non-negotiable in v1.
- Compression-cycle counting, session counters, or any new instrumentation the agent must maintain. Elapsed-time signals from `started` and `last_touched` cover the same need.
- Migration tooling for existing arc-shaped notes already in Thalamus bodies. Manual one-time pass during initial rollout.
- Mobile-friendly bullet view in `dashboard.md`. Optional add-on noted in Future Work.

## Architecture

```text
hoards/thalami-<user>/
├── <host-a>-thalamus.md        # arcs: [...] in frontmatter (NEW)
├── <host-b>-thalamus.md        # arcs: [...] in frontmatter (NEW)
├── dashboard.md                # single Dataview query (NEW)
└── README.md                   # vault-opening note (UPDATE)
```

**Data flow (single direction, no daemons):**

1. Agent on a host proposes arc-shaped edits to that host's Thalamus frontmatter, following the propose-not-act pattern from existing GDD nudges.
2. User commits and pushes via the existing thalami cadence cycle (`ws commit` / `ws pull --rebase` / `ws push`).
3. Other hosts pull on their next session start (existing orientation behavior).
4. Obsidian, opened on any host with the hoard configured as a vault, runs the Dataview query in `dashboard.md` and renders the cross-host arc table live as files change.

The user keeps an Obsidian window parked in a visible spot on each machine for at-a-glance visibility. No round-trip to a remote service is required for any view.

## Schema

The arc list lives alongside existing frontmatter fields:

```yaml
---
last_session: 2026-05-07
last_audit: 2026-05-02
mode: flow
role: developer
staleness_days: 14
arcs:
  - id: thalamus-arc-dashboard
    name: Cross-host Thalamus dashboard
    status: active
    started: 2026-05-07
    last_touched: 2026-05-07
    next: "land schema, write skills, validate cross-host render"
    # optional:
    # issue: https://github.com/SiliconSaga/yggdrasil/issues/123
    # tags: [gdd, hoards]
---
```

**Field semantics:**

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | kebab-case slug, stable across hosts. Used for cross-host stitching by exact match. |
| `name` | yes | Short human-readable label. Free-form. |
| `status` | yes | One of `active` / `parked` / `closed` / `promoted`. |
| `started` | yes | ISO date the arc was opened on this host. Bound to *this host*, not the global arc — different hosts can have different `started` dates for the same `id`. |
| `last_touched` | yes | ISO date the arc most recently saw work on this host. Used by Dataview for sort and elapsed calculation. |
| `next` | yes | One-line pointer to the next concrete step. Should be safe to surface in a dashboard (no secrets, no sensitive specifics). |
| `issue` | no | URL of a GitHub/GitLab issue. Populated when `status` flips to `promoted`. |
| `tags` | no | YAML list of free-form labels for cross-arc grouping in Dataview queries. |

**Slug convention:** kebab-case, derived from the topic (e.g., `gh-pages-tutorial`, `thalamus-arc-dashboard`). Convention only — no validation code in v1.

**Status semantics:**

- **active** — agent is or recently was working on this; appears prominently
- **parked** — captured but not currently worked; surfaces alongside actives in the single-table view, sorted by status
- **closed** — finished naturally, no issue spawned; survives one housekeeping cycle, then prunable
- **promoted** — moved to a tracked issue; `issue:` URL set; survives one housekeeping cycle, then prunable

`templates/thalamus.md` gains a commented `arcs: []` placeholder so freshly scaffolded thalamus files inherit the schema.

## Skill integrations

No new skill is introduced. Three thin extensions to existing GDD skills carry the agent behavior.

### `gdd-orientation` — surface active arcs at session framing

Step 7 (Session Framing) gains an arc-surfacing pass after mode/role/concerns:

> *"Active arcs on this host: `thalamus-arc-dashboard` (started today, next: 'lock schema'). Picking up an existing one or starting fresh?"*

If the user's stated topic grep-matches a slug in any sibling thalamus file in the hoard, surface the cross-host pickup:

> *"Loki has an active arc `gh-pages-tutorial` from 2026-04-25. Picking it up here?"*

If the user agrees, the agent proposes adding the same slug to *this* host's thalamus when the first arc-shaped write happens. Cross-host stitching becomes a slug-discipline mechanic, not a coordination protocol.

### `gdd-flow` — tangent handling

When the agent detects a topic shift mid-session — user opens an unrelated thread, or an aside spawns its own brain-dump into Thalamus — propose:

> *"Looks like a tangent — want me to log it as a parked arc `<proposed-slug>`? You can come back to it later or promote it to an issue."*

If the session pivots wholesale to the tangent, propose flipping the new arc to `active` and the original arc to `parked` (a single combined edit if the user agrees).

### `gdd-housekeeping` — arc audit pass

During the existing audit cycle, walk the `arcs:` list:

- `active` arcs with `last_touched` more than ~30 days old → propose flip to `parked`
- `closed` or `promoted` arcs that survived a previous audit → propose pruning the entry
- Body content with no matching arc entry, or arc entries with no body content → flag the inconsistency for the human to resolve

All three nudges follow the existing propose-not-act pattern. None block the audit; all can be declined.

### `last_touched` bump

When the agent edits Thalamus body content tied to an arc, it offers to bump that arc's `last_touched` in the same edit. No autonomous bumping — keeps the arc list under explicit human control even for trivial-looking updates.

## Cross-host slug discipline

Two lightweight mechanisms keep slugs aligned across hosts:

1. **Pre-write slug check.** When the agent is about to propose a *new* arc entry, it greps sibling thalamus files in the active hoard for an existing slug that matches the topic. If found, it proposes reusing rather than creating a near-miss.
2. **Orientation surfacing.** When the user's session-opening message matches an existing sibling slug, orientation surfaces it as covered above.

**Failure mode:** the user manually picks a slug that drifts from another host's slug for the same topic. The dashboard then shows them as separate rows. Recovery is a manual rename across both files (find/replace) — cheap to fix, low frequency expected. Not worth tooling for v1.

There is no global registry, no slug authority, and no validation. Convention plus grep is the entire mechanism.

## Lifecycle and pruning

| Event | Frontmatter change | Body change | Trigger |
|-------|-------------------|-------------|---------|
| New arc | append entry, `status: active` | optional inline notes | agent proposes on session start / tangent / explicit ask |
| Park | `status: parked` | leave as-is | agent proposes on topic shift |
| Resume parked | `status: active`, bump `last_touched` | — | agent proposes on relevant-topic detection |
| Close | `status: closed` | optionally prune body notes | manual or agent-proposed at natural endpoint |
| Promote | `status: promoted`, set `issue:` URL | prune body content (now in issue) | manual after `ws issue` filing |
| Prune | remove entry from `arcs:` | remove residual body if any | housekeeping audit, only on `closed` or `promoted` arcs that already survived one prior audit |

**Two-cycle grace window.** Closed and promoted arcs survive their first housekeeping audit so the dashboard shows them as recently-closed records. They drop on the audit *after that*. Concretely: an arc closed on 2026-06-01 with audits on 2026-06-08 and 2026-06-22 prunes on 2026-06-22.

**Body-content discipline.** The existing Thalamus body structure (Observations / Concerns / Audit Log) stays exactly as-is. Arc-related notes can live anywhere in the body — there is no required link between an arc entry and a specific section. Frontmatter tracks state; body holds detail. If a body section gets pruned during housekeeping, the arc entry stays until its own pruning event.

## Dashboard query

`hoards/thalami-<user>/dashboard.md` ships a single Dataview query as the v1 view:

````markdown
# Thalami Arc Dashboard

```dataview
TABLE WITHOUT ID
  arc.id AS "Arc",
  arc.status AS "Status",
  arc.next AS "Next",
  file.name AS "Host",
  arc.last_touched AS "Touched",
  (date(today) - date(arc.started)).days AS "Days"
FROM "."
WHERE arcs
FLATTEN arcs AS arc
SORT arc.status ASC, arc.last_touched DESC
```
````

`FLATTEN arcs AS arc` explodes the per-host list so each row is one (host, arc) pair. Multiple hosts touching the same `id` produce multiple rows that sort adjacently under the status sort, naturally forming the cross-host view.

`Host` is derived from `file.name` (e.g., `Dionysus-thalamus`), so the host need not be duplicated inside each arc entry.

`Days` is elapsed-since-started, computed at render time. No separate session or compression counter is required.

The default `SORT arc.status ASC` puts `active` first by alphabetical luck, followed by `closed`, `parked`, `promoted`. If a custom order proves useful (e.g., active → parked → promoted → closed), Dataview supports an explicit `choice()` ladder. v1 ships alphabetical and revisits if it bothers anyone.

## Components and files touched

**Yggdrasil repo (this PR):**

- `templates/thalamus.md` — add commented `arcs: []` placeholder
- `templates/hoards/thalami/dashboard.md` — new file with the Dataview query
- `templates/hoards/thalami/README.md` — note about opening as Obsidian vault and installing Dataview
- `.agent/skills/gdd-orientation/SKILL.md` — arc surfacing in Step 7, sibling-slug grep
- `.agent/skills/gdd-flow/SKILL.md` — tangent handling
- `.agent/skills/gdd-housekeeping/SKILL.md` — arc audit pass and pruning rule
- `docs/gdd/hoards.md` — mention of the arc layer in the thalami section
- `docs/plans/2026-05-07-thalamus-arc-dashboard-design.md` — this file
- `docs/plans/2026-05-07-thalamus-arc-dashboard-plan.md` — implementation plan (next)

**Thalami hoard (separate commits, single main branch):**

- `dashboard.md` — Dataview query, copied from the template
- One commit each per host's `<host>-thalamus.md` frontmatter to add an initial `arcs:` list, derived by reading the existing body content on each file
- `README.md` — note about Dataview as the rendering mechanism

The thalami hoard work happens after the yggdrasil PR lands, so the template and skill prose are in place before the hoard receives its initial `arcs:` lists.

## Testing and validation

No new test infrastructure. Validation is a four-step manual pass:

1. **Schema renders single-host.** Add `arcs:` to `Dionysus-thalamus.md`, point Obsidian at `hoards/thalami-Cervator/` as a vault, install Dataview, confirm `dashboard.md` renders the table correctly.
2. **Schema renders cross-host.** Add `arcs:` to one other thalamus file (e.g., Loki via the prepared frontmatter additions), `ws push` from this host, `ws pull` on the other, confirm both rows appear and that any shared slug shows two adjacent rows.
3. **Skill prose validated by use.** The orientation, flow, and housekeeping extensions earn their keep through actual session use across a few weeks. No unit tests for prose. Observe friction points and adjust.
4. **Pruning verified once.** First housekeeping pass after rollout exercises the audit-and-prune flow on at least one closed or promoted arc to confirm the two-cycle grace window behaves as documented.

The existing `tests/ws-hoard-scan/` test directory does not need to grow — `arcs:` is invisible to the scanner; it only adds frontmatter content the scanner already ignores.

## Risks and open questions

**Slug drift across hosts.** Mitigated by orientation-time grep and pre-write check, but not eliminated. If drift becomes common, a `ws hoard arc <id>` lookup helper could be added in v2.

**Dashboard renderer lock-in.** Obsidian + Dataview is a specific stack. If the user later moves away from Obsidian, the schema survives (it is plain YAML frontmatter) but the dashboard query needs to be re-implemented. Acceptable trade-off given the zero-infrastructure goal.

**Sensitive content leakage via `next:`.** The `next:` field is the most likely place for accidental leakage of operational detail into the dashboard projection. Skill prose should remind the agent to keep `next:` short and non-sensitive. No technical enforcement.

**Tangent over-detection in flow mode.** The flow-mode tangent prompt could fire too often in genuinely free-flowing sessions. The propose-not-act pattern means each false positive is one declined nudge, but high frequency would still feel intrusive. Tune the trigger heuristics during the validation period.

**No mobile dashboard.** Obsidian mobile renders Dataview, but the user has not yet committed to mobile vault sync. View-from-phone is currently a non-goal; revisit if the obsidian-vault hoard validates the mobile path.

## Future work

- **Static-page renderer** — GitHub Action on push to the thalami repo emitting a small static HTML/JSON dashboard. Worth building only if Obsidian-only proves insufficient (e.g., user wants phone visibility, or to share with a collaborator).
- **`ws hoard arc <subcommand>`** — CLI helpers for arc operations (`add`, `park`, `close`, `promote`, `list`). Defer until skill-driven flows show enough friction to warrant codifying.
- **Mobile bullet view** — second Dataview block in `dashboard.md` showing only `active` arcs as a bullet list, optimized for narrow Obsidian-mobile screens.
- **Tag-based grouping queries** — once `tags:` see real use, additional Dataview blocks grouping by tag (`GROUP BY arc.tags`).
- **Vörðu integration** — if the BDD-roadmap dashboard ever grows a "personal work" lane, the same `arcs:` shape could feed it. Speculative.
- **Slug-rename helper** — `ws hoard arc rename <old> <new>` for cleaning up drift across hosts. Add when manual rename actually hurts.
