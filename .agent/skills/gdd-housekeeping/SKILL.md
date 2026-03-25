---
name: gdd-housekeeping
description: >
  Audit and triage Thalamus.md content. Review observations and concerns
  with the human, promote actionable items to issues/skills/instructions,
  prune resolved items. Use when staleness threshold is reached, when the
  human requests housekeeping, or during dedicated tidy-up sessions.
---

# GDD Housekeeping

A collaborative audit process for the Thalamus shared thinking space.
The agent facilitates, but the human decides what to promote, keep, or prune.

## When to Use

- The orientation skill (@gdd-orientation) surfaced a staleness warning
- The human explicitly asks for housekeeping ("let's tidy up", "housekeeping")
- A dedicated short session for tidying up
- During Zen mode when deep work includes audit time

## The Housekeeping Process

### Step 1: Read Thalamus.md

Load the full file. Identify all items in the Observations and Concerns
sections. Count them and give the human a quick summary before diving in:

> "Thalamus has 5 observations and 2 concerns since the last audit on
> March 15th. Want to walk through them?"

### Step 2: Review Each Item with the Human

Present items one at a time or in small groups (related items together).
For each, offer three actions:

**Promote** — move to a permanent home:

| Item type | Destination |
|-----------|-------------|
| Recurring pattern or friction | Workflow-auditor candidate, new skill, or `ws` subcommand |
| Bug or feature idea | GitHub issue (use @creating-github-issues) |
| User preference | `CLAUDE.md` or `AGENTS.md` update |
| Process improvement | Skill update or new skill |
| Safety concern (verified) | Trust rule in orientation skill or root instructions |

**Keep** — still relevant, not yet actionable. Leave it in place.

**Prune** — resolved, stale, or superseded. Remove from the file.

### Step 3: Check for Pattern Accumulation

After reviewing individual items, look across them:

- Do 2+ observations point to the same friction point or workaround?
- Is there a recurring concern about the same component or workflow?

If so, suggest consolidation — the cluster is likely a candidate for a
skill, `ws` subcommand, or instruction update. Cross-reference with the
@workflow-auditor skill for patterns it might formalize.

### Step 4: Update the Audit Log

Append an entry to the Audit Log section:

```markdown
### 2026-03-22
- Promoted: "ws push friction" → GitHub issue #42; "prefer terse orientation" → CLAUDE.md
- Pruned: "autoboros AGENTS.md concern" (reviewed, benign)
- Kept: 3 items
- Notes: Capture quality good, but too many low-value observations about formatting
```

### Step 5: Update Frontmatter

Set `last_audit` to today's date in the YAML frontmatter.

### Step 6: Reflect on the Process

Ask the human:

> "Did the Thalamus capture useful things since last audit? Too much
> noise? Too little? Should we adjust what gets written?"

This is the self-improving loop — feedback here can result in:
- Immediate updates to the orientation skill's capture heuristics
- Template changes (adding or removing sections)
- Observations for the next cycle (if the change isn't clear yet)

## What Housekeeping Is NOT

- **Not a full retrospective** — it's lighter, more like tidying a desk
- **Not required before other work** — the staleness nudge is advisory
- **Not automated** — the human is always part of promote/prune decisions
- **Not a mode** — it's an activity that can happen in any mode (though Zen
  mode may proactively suggest it)

## Relationship to Other Skills

- **@workflow-auditor** — housekeeping may surface patterns that the auditor
  should formalize as scripts or `ws` subcommands
- **@creating-github-issues** — promoted items that become issues use this
  skill for filing
- **@gdd-orientation** — housekeeping updates the frontmatter that orientation
  reads on next session startup. The two skills form a cycle: orientation
  reads → session produces observations → housekeeping reviews → orientation
  reads updated state
