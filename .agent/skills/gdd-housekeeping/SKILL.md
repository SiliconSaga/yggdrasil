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

**Per-item special case — permissions items.** If the item mentions
permissions, `.claude/settings.json`, a permission prompt the user
wants to follow up on, or "don't ask again" decisions, prompt the
user to walk through it via the `permissions-management` skill before
applying the standard Promote/Keep/Prune trichotomy. Example:

> "This observation mentions a permission prompt for `xxd` you got
> last session. Want me to invoke `permissions-management` to think
> through whether it's worth allowlisting?"

This routes permissions-related work through the dedicated skill
rather than handling it ad hoc during housekeeping. After the skill
completes, the housekeeping flow resumes:

- **Pattern added.** The decision is durably recorded across the
  paired artifacts `.claude/settings.json` (the rule itself) and
  `docs/gdd/permissions.md` § 4 (the empirical-findings table per
  the cross-reference rule). The original Thalamus item is typically
  Prune-able once both updates are in place.
- **Pattern declined.** No artifact captures a decline by default —
  `.claude/settings.json` only records accepted patterns. Before
  pruning the Thalamus item, write the decline outcome to the Audit
  Log (or a Concern, if it's safety-flavored) so the reasoning
  doesn't evaporate; otherwise the same prompt will surface again
  next session and re-litigate the same decision.

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

#### When you Promote, delete the original entry — don't leave a stub

Once an item lands in its canonical home (a doc, a skill update, an
issue, an instruction-file change), the corresponding Thalamus
entry should disappear entirely. **Don't replace the entry with a
"promoted to X" pointer** — that's graveyard noise, and the
Thalamus should be a current-working-brain rather than a history
of what used to be there. The Audit Log entry (Step 4) is what
records that the promotion happened; the canonical doc itself is
the new source of truth; git history preserves the original
phrasing for anyone archaeology-bound. Three durable records is
plenty; a fourth in the Thalamus is clutter.

The same applies to `~~strikethrough~~` markers that linger
indefinitely. A short `~~item~~ DONE in PR #N` line is reasonable
*briefly* (across the next session or two while the PR settles),
but they should age out — pruned at the next housekeeping pass
once the PR has merged and the canonical doc is stable.

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

### Thalami repos use direct push, not PR review

Unlike components and realms, thalami repos are stream-of-consciousness
personal notes — there's nothing for a bot to review usefully, and a
PR-and-review ceremony just adds friction to multi-machine sync. The
convention is: **commit and push directly to `main`** (after the
fetch+rebase cycle described in `gdd-orientation` Step 0a). Don't open
PRs against the thalami hoard, don't request CodeRabbit/Copilot review,
don't gate the push on anything beyond the rebase. The whole point of
the hoard is fast personal-state sync; ceremony defeats it.

Same convention applies to other personal hoards (Obsidian vaults,
scratch hoards). PRs are a component-and-realm pattern.

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
