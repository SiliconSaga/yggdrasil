---
name: gdd-permissions
description: >
  Use when adding or editing permission patterns, considering a "don't
  ask again" offer at a permission prompt, explaining the permission
  system to a user, or reviewing .claude/settings.json changes during
  code review. Operational companion to docs/gdd/permissions.md.
---

# GDD Permissions

Operational guidance for working with `.claude/settings.json` allowlist
and deny rules. The reference content (how the system works, the
two-layer defense model, the empirical matcher findings) lives in
`docs/gdd/permissions.md`. This skill is what to *do* with that
knowledge.

## When to Use

Invoke this skill when:

- About to **add or edit** a pattern in `.claude/settings.json` — sister
  to `fewer-permission-prompts` (which does the bulk-from-transcripts
  case); this skill handles per-pattern safety analysis.
- At a **permission prompt** that's offering a "don't ask again" choice
  with a wide pattern — judgment guidance below.
- A **user asks** how the permission system works, or what a specific
  pattern means.
- **Reviewing `.claude/settings.json` changes** during code review.

For the bulk case (scanning recent transcripts and proposing many
patterns at once), invoke `fewer-permission-prompts` instead.

## Pattern-form decision tree

The full decision tree is in `docs/gdd/permissions.md`, the
**When to widen vs narrow patterns** section. Read that for the full
reasoning before adding any non-trivial pattern.

Operational shortcuts when you've already read the doc:

- **Already auto-allowed by Claude Code?** Don't add — redundant.
- **Subcommand has no mutating flag-form?** Prefix wildcard is fine.
- **Subcommand has mutating flag-forms?** Pin to the exact safe form.
- **Wrapping an interpreter or task runner** (`bash`, `python`,
  `node`, `make`, `npm run`, `gh api`, etc.)? **Never widen.**
- **Writes to a shared system** (push, deploy, publish, send)?
  Don't allowlist at all — side-effect-tier per
  `docs/ws-cli-guide.md`.

When in doubt, narrower wins.

## "Don't ask again" judgment guidance

Claude Code prompts on unmatched commands. The prompt offers a
"don't ask again" with a suggested pattern (often wide). Decision
criteria for whether to accept:

| Offered pattern | Read-only command? | Pattern admits non-read-only forms? | Decision |
|-----------------|--------------------|-------------------------------------|----------|
| Wide (`Bash(xxd*)`, `Bash(python *)`) | Doesn't matter | Yes — wildcards admit anything | **Decline.** Suggest a narrower pattern manually if it's worth allowlisting at all. |
| Exact form (`Bash(git -C . status --porcelain)`) | Yes | No — pinned to one specific safe form | **Accept** — equivalent to adding the pattern via this skill anyway. |
| Prefix on a non-mutating subcommand (`Bash(git -C * show *)`) | Yes | No — subcommand is read-only | **Accept**, but verify the subcommand has no mutating flag-forms first (decision tree #2). |
| Anything wrapping `bash`, `python`, `node`, `make`, etc. | Doesn't matter | Yes — any of these is arbitrary code execution | **Always decline.** |

When declining, take a moment to either suggest a narrower pattern
inline (using this skill's decision tree), capture a Thalamus
observation about the prompt for later batch review, or just let the
user decide.

## Scope-narrowing checklist

Before committing any new pattern:

- [ ] Could this pattern match a mutating subcommand? (Re-read the
  command's `--help` and look for any flag that writes/deletes/sends.)
- [ ] Does the wildcard admit shell metacharacters that change the
  command's semantics? (Almost never; the matcher rejects substitution
  and validates compound commands per-segment, but corner cases exist.)
- [ ] Is there an existing auto-allowed form that covers this without
  a custom pattern? (See `docs/gdd/permissions.md`, the
  **When to widen vs narrow patterns** section.)
- [ ] Does the pattern align with the **When to widen vs narrow
  patterns** section of `docs/gdd/permissions.md`? If you're departing
  from the doc's guidance, document the reason in the commit body.

## Known-safe allowance candidates (per-system, human-approved)

A few patterns are safe by *nature* but look broad to pattern-shape analysis — they trip the `ws audit-permissions` watchlist even though the underlying command cannot mutate anything. Agents should know these exist as legitimate candidates **before** any workspace has activated them, and may offer one when the relevant prompt friction comes up — but activation is always the human's call, per system, never preemptive.

Current catalog (one entry; grow it as cases earn their way in):

| Pattern | Why it looks dangerous | Why it's actually safe | Caveat for the human |
|---|---|---|---|
| `Bash(bash -n:*)` | Glob-matches the `Bash(bash *)` watchlist entry ("wildcards out the hook") | `bash -n` parses a script and exits — it **never executes** anything | Only the `-n` form is safe; approving this pattern auto-approves syntax checks, nothing else. Verify the pattern pins `-n` immediately after `bash`. |

Activation procedure (both steps need explicit human approval):

1. Add the pattern to `.claude/settings.local.json` `permissions.allow` — per-system judgment, never the committed `settings.json`.
2. Acknowledge it in `.claude/hooks/hook-rules.local` under `[audit-acknowledged]` (exact entry string), so `ws audit-permissions` reports it as `acknowledged: true` instead of a standing finding. The audit keeps printing it for transparency; it just stops counting toward the exit code.

When offering one of these, give the human the full picture: what the pattern auto-approves, why it's safe by nature, and that declining just means an occasional prompt. If the human declines, drop it — don't re-offer in the same session.

## Cross-reference rule

When you modify `.claude/settings.json`'s `permissions.allow` (or
`permissions.deny`):

1. **Add the pattern.**
2. **Add empirical test cases to the `docs/gdd/permissions.md`
   Empirical matcher findings table.**
   Minimum: one positive case (matches → allowed) and one negative
   case (close-but-not-quite → prompts).
3. **Commit both files together.** A commit that touches the allowlist
   without updating the doc is review-blocking.

The doc and the config are paired artifacts. Drift gives false
confidence — humans and agents both trust the doc.

## Pointers

- `fewer-permission-prompts` — Claude Code-native skill for the
  bulk-from-transcripts case (sister to this one).
- `docs/gdd/permissions.md` — full reference content; consult for
  matcher details, pattern shapes, and the empirical findings table.
- Issue #46 — automated regression testing of allowlist patterns
  (future arc; not in v1's scope).

## Future scope

Cross-framework porting (mapping Claude Code's allowlist semantics to
Codex / Gemini / Cursor / etc.) is a known future direction. Not
covered by v1 of this skill — when picking it up, design as its own
arc.
