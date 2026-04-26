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

### Step 6: Workspace Tidy

Run `ws status` to see dirty state across all repos — there may be
uncommitted drafts or stale edits worth addressing while you're in
tidy-up mode.

Also suggest `ws clean` if `.commits/`, `.issues/`, or `.crs/` have
accumulated many draft files. This is especially worth it when those
directories have grown past a few dozen entries — old drafts obscure
current work and bloat grep results.

### Step 7: Reflect on the Process

Ask the human:

> "Did the Thalamus capture useful things since last audit? Too much
> noise? Too little? Should we adjust what gets written?"

This is the self-improving loop — feedback here can result in:
- Immediate updates to the orientation skill's capture heuristics
- Template changes (adding or removing sections)
- Observations for the next cycle (if the change isn't clear yet)

## Multi-Thalami Review (when a thalami hoard is active)

If `hoards/thalami-<user>/` is the active hoard, housekeeping can audit
across every `<machine>-thalamus.md` file in the hoard. Use this to catch
preferences/observations that should be promoted across machines or
duplicates that should be merged.

### When to use multi-thalami mode

- The human asks to "review across machines" or similar
- Housekeeping on a single machine surfaces a preference that obviously
  applies everywhere ("user prefers terse responses") — pivot to
  multi-thalami to promote it
- Periodic: once or twice a year, even without a specific trigger

### Process

1. List every `<machine>-thalamus.md` file in the active hoard. Note the
   machine names.
2. For Preferences and Observations specifically, identify items that:
   - Appear on one machine but seem universal — candidates for promotion.
   - Appear on multiple machines with similar wording — candidates for
     dedup (consolidate to one canonical entry; keep machine-specific
     variations only if they're actually distinct).
3. Walk the candidates with the human, item by item. For each, decide:
   - Promote everywhere: add to every other machine file (with the
     human's blessing).
   - Keep machine-specific: leave it alone.
   - Dedup: pick the best phrasing, drop the others.
4. Update `last_audit` in each touched machine file.
5. Append the same audit-log entry to every reviewed
   `<machine>-thalamus.md` (not just the file the session started from).
   Listing the machines in that entry makes it clear at a glance which
   files were in scope this round.

### Compare-only — no shared file in v1

V1 does not introduce a shared `common-thalamus.md`. If multi-thalami
review repeatedly promotes the same preference to every machine over many
audits, that's evidence to add a shared file in v2. Until then, the
N×duplication is acceptable cost for design simplicity.

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
