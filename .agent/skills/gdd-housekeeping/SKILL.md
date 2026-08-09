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
- During the Zen stance when deep work includes audit time

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
user to walk through it via the `gdd-permissions` skill before
applying the standard Promote/Keep/Prune trichotomy. Example:

> "This observation mentions a permission prompt for `xxd` you got
> last session. Want me to invoke `gdd-permissions` to think
> through whether it's worth allowlisting?"

After the skill completes, the housekeeping flow resumes:

- **Pattern added.** The decision is durably recorded across the
  paired artifacts `.claude/settings.json` (the rule itself) and
  `docs/gdd/permissions.md`'s Empirical matcher findings table (per
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
| Bug or feature idea | GitHub issue (use @gdd-github-issues) |
| User preference | `CLAUDE.md` or `AGENTS.md` update |
| Process improvement | Skill update or new skill |
| Safety concern (verified) | Trust rule in orientation skill or root instructions |

**Keep** — still relevant, not yet actionable. Leave it in place.

**Prune** — resolved, stale, or superseded. Remove from the file.

#### When you Promote, delete the original entry — don't leave a stub

Once an item lands in its canonical home (a doc, a skill update, an
issue, an instruction-file change), delete the Thalamus entry
entirely. **Don't replace it with a "promoted to X" pointer** — the
Audit Log entry (Step 4) already records that the promotion happened,
the canonical doc is the new source of truth, and git history
preserves the original phrasing. Three durable records is plenty; a
fourth in the Thalamus is clutter.

The same applies to `~~strikethrough~~` markers that linger
indefinitely. A short `~~item~~ DONE in PR #N` line is reasonable
*briefly* (across the next session or two while the PR settles),
but they should age out — pruned at the next housekeeping pass
once the PR has merged and the canonical doc is stable.

### Step 2.5: Walk the arcs list

If the active Thalamus has a non-empty `arcs:` list, walk it before
moving on:

- **Stale active arcs.** Any `active` arc whose `last_touched` is more
  than ~30 days old is a candidate to flip to `parked`. Propose the
  flip; let the human confirm or push back ("no, still active").
- **Closed/promoted arcs surviving previous audit.** Two-cycle grace
  window: arcs in `closed` or `promoted` status that already survived
  one prior audit are prunable. Check the Audit Log for prior mention
  of the slug; if present, propose removing the entry from `arcs:`.
- **Inconsistencies.** Body content describing work with no matching
  `arcs:` entry, or `arcs:` entries with no body context, should be
  flagged for the human. Don't auto-resolve — ambiguous cases are
  judgment calls.
- **Overgrown `next:` fields.** An arc's `next:` should stay under
  ~10-20 words so the ArcDashboard reads at a glance. Move extended
  context into a body section (the `Arc next-notes` pattern) and leave
  a one-liner pointing at it.

Beyond triage, the arcs walk also surfaces prioritization moves when arcs carry the optional `impact:` / `urgency:` / `project:` fields:

- **Act-order walk** (when `impact:` / `urgency:` are present). Read `impact:` (high/medium/low) and `urgency:` (asap/next/soon/later) across the current host's arcs and propose an act-order — high impact × `asap` first, then high × `next`, then medium × `asap`, and so on. Surface as a brief ranked list ("if you have an hour, look at X"). Propose-then-confirm; no automatic re-sort, no auto-write to `arcs:`. Arcs without either field set are skipped — the walk is opt-in per arc. Arc-level mirror of the scribe micro-ceremony.
- **Priority collapse** (arcs with a `project:` link). When an arc carries `impact:`, `urgency:`, and a `project:` field pointing at a vault project note, propose updating that project's lightweight `priority:` field to reflect the arc's richer two-dimensional read. Illustrative mapping: any × `asap`, or `high` × `next` → `high`; `high` × `soon`/`later`, or `medium` × `asap`/`next` → `medium`; otherwise → `low`. The collapse is **drift-tolerant** — no invariant, no mechanical sync. Propose only when the project note's current `priority:` looks out of step with the arc, only on the human's go-ahead. Cross-repo move (thalami hoard → vault hoard); the scribe skill picks up the same proposal from the project-note side (see @scribe).

When pruning, remove the entry from `arcs:` *and* note the slug in the
Audit Log entry (Step 4) so cross-host context survives even after the
arc itself is gone.

For arcs promoted to issues, the body content should already be
gone (it lives in the issue now); the `arcs:` entry survives one more
audit so the dashboard shows the recently-closed work, then prunes.

### Step 2.6: Drain the Intake

If the active thalami hoard has an `Intake.md` whose `## Items` section contains at least one bullet item (`- ...`) after ignoring HTML comments and blank lines, walk it with the human before Step 3. Each item is pre-arc GDD work the scribe bridge handed off — staging, not a tracker. For each item, propose one of:

- **Promote to an arc** — the item is real, scoped GDD work. Add an `arcs:` entry to the appropriate host's `*-thalamus.md` (usually this host; ask if another machine is the better home), then remove the item from `Intake.md`.
- **Fold into an existing arc** — the item is part of work already tracked. Note it on that arc's `next` or body context, then remove it from `Intake.md`.
- **Route without an arc** — the item is a one-off (a quick fix, a doc tweak) that does not justify an arc. Do it now or note it where it belongs, then remove it from `Intake.md`.
- **Leave** — not yet actionable; keep it in `Intake.md` for the next pass.

`Intake.md` is meant to stay short. If it keeps growing audit-over-audit, the GDD ceremony is not draining often enough — surface that to the human as a process observation.

### Step 2.7: Mine harvested sandbox notes, then delete them

If the active thalami hoard has a `sandboxes/` directory containing any files, each one is the harvested Thalamus of a sandboxed workspace — the notes its agent kept across sessions. Harvesting normally happens as part of recycling that sandbox, in which case the file is the only surviving copy; a harvest run on its own destroys nothing, so the sandbox may still be running with those notes intact. Check before assuming which case you are in.

Read each file with the human and treat its contents as ordinary audit input: an observation worth keeping moves to this host's `*-thalamus.md`, a concern is raised, a recurring friction feeds Step 3's pattern check. A tenant agent sees things the operator never does — which tools it could not use, what the person kept asking for, where it got stuck.

**Then delete the file** — once its observations are recorded and that sandbox has actually been recycled. Not archive, not leave for next time: at that point the notes are not memory any more, they are an inbox item, and an inbox that is never emptied stops being read. Anything worth keeping is in the host's Thalamus by then; anything not worth keeping was not worth carrying. If the sandbox is still running, leave the file — mining it early is fine, but deleting it is housekeeping for a tenant that has not finished.

Harvested files may also appear under the workspace `.tmp/sandbox-harvest/`, which is where harvesting falls back when no hoard is active. Same treatment — and `ws clean` sweeps that directory, so mine it before it is swept.

### Step 3: Check for Pattern Accumulation

After reviewing individual items, look across them:

- Do 2+ observations point to the same friction point or workaround?
- Is there a recurring concern about the same component or workflow?

If so, suggest consolidation — the cluster is likely a candidate for a
skill, `ws` subcommand, or instruction update. Cross-reference with the
@gdd-workflow-audit skill for patterns it might formalize.

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

Run `ws status` to see dirty state across all repos — there may be uncommitted drafts or stale edits worth addressing while you're in tidy-up mode.

Also suggest `ws clean` if `.commits/`, `.issues/`, `.crs/`, `.outputs/`, or `.tmp/` have accumulated many draft/scratch files — worth it once a directory has grown past a few dozen entries, since old drafts obscure current work and bloat grep results. Session identity files under `.tmp/gdd-agent-sessions/` are spared by default (wiping them would break a concurrent session's commit identity). During deliberate housekeeping you may additionally suggest `ws clean --sessions-all`, which clears ended sessions' identity files (the current session's is kept; plain `--sessions` is compatibility-only and prunes nothing) — but first confirm with the human that no other live sessions need them, and explain what it removes.

### Step 6.5: Review the PreToolUse hook audit log

`~/.claude/hook-audit.log` records every allow/deny decision the `gdd-permission-hook.sh` hook has made since the last cleanup. Worth a periodic skim during housekeeping — patterns that show up repeatedly tell you something about agent behavior or workspace configuration:

- **Recurring DENY entries for the same compound pattern** → the
  agent is reflexively reaching for shell composition. Check whether
  AGENTS.md or CLAUDE.md needs a more emphatic callout for the
  specific verb, or whether the ws CLI is missing a native flag the
  agent would prefer to use.
- **Recurring DENY entries from grep-with-`|`** → the agent isn't
  defaulting to the Grep tool. Cross-check the redirect message is
  reaching the agent; consider a Thalamus note if it persists.
- **Recurring ALLOW entries from the same extras-file pattern** →
  that pattern is earning its place; consider whether it belongs in
  the project's `.claude/settings.json` instead of a personal
  extras file (so all collaborators benefit).
- **No DENY entries since last review** → either the agent has
  learned, or sessions have been light. Compare against the human's
  recollection.

The hook log captures decisions the hook made; it does NOT capture
commands that went to passthrough and then prompted the user. The
companion data for "commands the user approved a lot through the
harness prompt" lives in `.claude/settings.local.json`'s
`permissions.allow` — every entry there is something the user
clicked "don't ask again" on at some point. Walk both during
housekeeping:

- **Recurring commands the user remembers approving** (or new
  entries in `.claude/settings.local.json`'s `permissions.allow`
  since the last audit) → propose a home for each one:

  > "`tree` was approved repeatedly last session. A general
  > assessment suggests it's safe to auto-allow on this machine —
  > want to add it to `hook-rules.local` so future sessions
  > skip the prompt?"

  Two possible homes once the human confirms:

  | Home | When | Trade-off |
  |---|---|---|
  | Project `.claude/settings.json` | The pattern is workspace-relevant and other contributors would benefit | Committed to the repo; visible in PR review |
  | `.claude/hooks/hook-rules.local` `[allow-extras]` (project-local) | A trusted command specific to this workspace but not policy-worthy | Per-machine; gitignored, not shared via git |
  | Leave in `.claude/settings.local.json` | The decision was correct as recorded (don't-ask-again at the harness level) | No change needed |

  For the doc-driven path (project `.claude/settings.json`), invoke
  the `gdd-permissions` skill for the full add-and-document
  flow. For the `hook-rules.local` path, copy
  `.claude/hooks/hook-rules.local.example` to `hook-rules.local`
  (if it doesn't exist) and append the bash glob pattern under the
  `[allow-extras]` section.

  Cross-reference: `ws audit-permissions` covers the opposite
  direction (patterns already in `permissions.allow` that look too
  broad and might be candidates for narrowing). The two tools meet
  in the middle: audit-permissions narrows what's there;
  housekeeping promotes what's missing.

A quick scan: `tail -100 ~/.claude/hook-audit.log` (the hook denies pipes, so reach for the Read tool instead if running through Claude). Truncate when reviewed: `truncate -s 0 ~/.claude/hook-audit.log`.

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
don't gate the push on anything beyond the rebase.

Same convention applies to other personal hoards (Obsidian vaults, scratch hoards). PRs are a component-and-realm pattern.

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
6. For arcs specifically: identify slugs that exist on multiple hosts
   and confirm they refer to the same work — if drift has happened (two
   slugs for the same topic), propose a rename so the dashboard
   collapses them into adjacent rows. Closed/promoted arcs on one host
   but still `active` on another are common during cross-host handoff;
   leave those alone unless the human confirms the work is done.

### Compare-only — no shared file in v1

V1 does not introduce a shared `common-thalamus.md`. If multi-thalami
review repeatedly promotes the same preference to every machine over many
audits, that's evidence to add a shared file in v2. Until then, the
N×duplication is acceptable cost for design simplicity.

## What Housekeeping Is NOT

- **Not a full retrospective** — it's lighter, more like tidying a desk
- **Not required before other work** — the staleness nudge is advisory
- **Not automated** — the human is always part of promote/prune decisions
- **Not a stance** — an activity that can happen under any stance (Zen may proactively suggest it)

## Relationship to Other Skills

- **@gdd-workflow-audit** — housekeeping may surface patterns that the auditor
  should formalize as scripts or `ws` subcommands
- **@gdd-github-issues** — promoted items that become issues use this
  skill for filing
- **@gdd-orientation** — housekeeping updates the frontmatter that orientation
  reads on next session startup. The two skills form a cycle: orientation
  reads → session produces observations → housekeeping reviews → orientation
  reads updated state
