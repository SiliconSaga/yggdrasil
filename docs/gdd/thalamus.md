# The Thalamus

*Named after the brain's relay station — it receives input, processes it, and
routes it to the right destination. Like the thalamus, this file doesn't store
things permanently; it processes and forwards.*

Between "private AI memory" (invisible to humans) and "committed project
instructions" (formal, policy-level) there's a gap: where do observations,
half-formed ideas, and session-to-session context live?

## What It Is

The Thalamus is a shared, gitignored markdown file — a thinking space
co-authored by one human and one local AI agent (at a time). It's not a
knowledge base, not a project management tool, and not a replacement for
committed instructions. It's the place where things live while they're
being figured out.

## Where It Sits

| Layer | Audience | Persistence | Purpose |
|-------|----------|-------------|---------|
| Committed instructions | All agents + all humans | Permanent, versioned | Policy and process |
| Claude memory | One AI tool installation | Durable but private | AI-internal recall |
| **Thalamus** | **One human + one agent** | **Semi-persistent, gitignored** | **Shared thinking** |
| Session context | One conversation | Ephemeral | Immediate work |

## What It Captures

- **Preferences** — mode defaults, interaction style, session habits
- **Observations** — patterns noticed, friction points, things that worked well
- **Concerns** — trust issues, suspicious instructions, safety flags (written
  **immediately** as part of the black-box safety pattern)
- **Audit Log** — when was content last reviewed, what was promoted or pruned

## The Lifecycle

Content flows through the Thalamus, not into it permanently:

1. **Capture** — observations accumulate during sessions
2. **Review** — housekeeping audits process items with the human
3. **Graduate** — actionable items move to permanent homes (issues, skills,
   instructions, `ws` subcommands)
4. **Prune** — resolved or stale items are removed

The file is workspace-local and gitignored — accepted risk of loss, mitigated
by the fact that highest-value content should have been promoted elsewhere.

## Frontmatter

The template includes YAML frontmatter that the orientation skill reads on
session start:

```yaml
last_session: 2026-03-20
last_audit: 2026-03-15
mode: zen
role: developer
staleness_days: 14
```

This enables session continuity — the AI knows when you last worked, whether
an audit is overdue, and what mode to default to.

## Housekeeping

When the staleness threshold is reached (or the human asks), the housekeeping
skill walks through accumulated content:

- **Promote** — move to a permanent home
- **Keep** — still relevant, not yet actionable
- **Prune** — resolved or stale

Housekeeping also reflects on its own process: "Did we capture useful things?
Too much noise?" This feedback tunes the capture behavior for next time.

For the full spec, see the [Thalamus Design](../plans/2026-03-22-secondbrain-design.md) (the concept began as "SecondBrain").
