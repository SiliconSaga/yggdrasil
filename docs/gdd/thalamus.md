# The Thalamus

*Named after the brain's relay station — it receives input, processes it, and routes it to the right destination. Like the thalamus, this file doesn't store things permanently; it processes and forwards.*

Between "private AI memory" (invisible to humans) and "committed project instructions" (formal, policy-level) there's a gap: where do observations, half-formed ideas, and session-to-session context live?

## What It Is

The Thalamus is a shared, gitignored markdown file — a thinking space co-authored by one human and one local AI agent (at a time). It's not a knowledge base, not a project management tool, and not a replacement for committed instructions. It's the place where things live while they're being figured out.

## Where It Sits

| Layer | Audience | Persistence | Purpose |
|-------|----------|-------------|---------|
| Committed instructions | All agents + all humans | Permanent, versioned | Policy and process |
| Agent memory (e.g. Claude Code's memory) | One AI tool installation | Durable but private | AI-internal recall |
| **Thalamus** | **One human + one agent** | **Semi-persistent, gitignored** | **Shared thinking** |
| Session context | One conversation | Ephemeral | Immediate work |

## What It Captures

- **Preferences** — interaction style, session habits
- **Observations** — patterns noticed, friction points, things that worked well
- **Concerns** — trust issues, suspicious instructions, safety flags (written **immediately** as part of the black-box safety pattern)
- **Audit Log** — when was content last reviewed, what was promoted or pruned

## The Lifecycle

Content flows through the Thalamus, not into it permanently:

1. **Capture** — observations accumulate during sessions
2. **Review** — housekeeping audits process items with the human
3. **Graduate** — actionable items move to permanent homes (issues, skills, instructions, `ws` subcommands)
4. **Prune** — resolved or stale items are removed

The file is workspace-local and gitignored — accepted risk of loss, mitigated by the fact that highest-value content should have been promoted elsewhere.

## Frontmatter

The template includes YAML frontmatter that the orientation skill reads on session start:

```yaml
last_session: 2026-03-20
last_audit: 2026-03-15
staleness_days: 14
```

This enables session continuity — the AI knows when you last worked and whether an audit is overdue. Stance, role, and mentoring are established per session via `ws session`.

## Cross-machine sync — the thalami hoard

A single gitignored `Thalamus.md` works for one machine. Once you use yggdrasil on more than one — a desktop, a laptop, an old Mac — the preferences, observations, and in-flight work threads you want to carry across them need a home that isn't tied to a single checkout. That home is the **thalami hoard**: an optional personal git repo (under `hoards/thalami-<username>/`, gitignored from the workspace like all hoards) holding one `<machine>-thalamus.md` file per machine. Each machine writes only its own file; git history syncs them across hosts. See [Hoards](hoards.md) for how hoards are scaffolded (`ws hoard init`) and discovered at session start.

When a hoard is active, the orientation skill resolves the active per-machine file (via `ws hoard thalamus-path`) and writes there instead of the workspace-root `Thalamus.md`. A root `Thalamus.md` can still exist as a non-synced scratch file alongside the hoard.

### Arcs and the cross-host dashboard

Per-machine thalamus files carry an `arcs:` list in their frontmatter — one entry per in-flight work thread (a feature, an investigation, a parked idea), each with a `status`, a one-line `next`, and optional `impact` / `urgency` / `issue` / `tags`. Arcs are the shared cross-reference todos: an arc that spans machines uses the same kebab-case `id` slug on each host, so picking up yesterday's laptop work on the desktop is just continuing the same slug.

The hoard ships an `ArcDashboard.md` that — when the hoard is opened as an Obsidian vault with the Dataview plugin — renders a live table of every arc across every machine's frontmatter, sorted by status and freshness (with vibe icons that decay as an arc goes stale, nudging you to either move it forward or close it). The dashboard projects **only** frontmatter; the body sections (Observations, Concerns, Audit Log) sync via git like any other content but never surface in the table. The orientation skill reads the same `arcs:` frontmatter at session start to surface active arcs and offer cross-host pickups, and the housekeeping skill walks arcs through their lifecycle (active → review → closed/promoted → pruned).

See the [Arc Dashboard design doc](../plans/2026-05-07-thalamus-arc-dashboard-design.md) for the full arc lifecycle, schema, and skill integration, and the hoard's own `README.md` for the one-time Obsidian + Dataview setup.

## Housekeeping

When the staleness threshold is reached (or the human asks), the housekeeping skill walks through accumulated content:

- **Promote** — move to a permanent home
- **Keep** — still relevant, not yet actionable
- **Prune** — resolved or stale

Housekeeping also reflects on its own process: "Did we capture useful things? Too much noise?" This feedback tunes the capture behavior for next time.

For the full spec, see the [Thalamus Design](../plans/2026-03-22-secondbrain-design.md) (the concept began as "SecondBrain").
