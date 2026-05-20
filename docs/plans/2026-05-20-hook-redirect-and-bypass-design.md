# Hook Redirect-to-`ws` and Session-Scoped Bypass — Design

**Status:** Draft, awaiting review
**Date:** 2026-05-20
**Owner:** Rasmus Praestholm
**Related:**

- `.claude/hooks/gdd-permission-hook.sh` and `.claude/hooks/README.md` — the hook this design extends
- [`docs/plans/2026-05-17-hook-ask-tier-design.md`](2026-05-17-hook-ask-tier-design.md) — the prior hook design, which deferred the bypass mechanism as YAGNI
- [`docs/gdd/agent-training.md`](../gdd/agent-training.md) — the user-facing companion to the hook
- Thalamus `hook-v2-extensions` arc — the parked arc this work picks up; the deep pair is two of six grouped ideas

## Overview

The PreToolUse hook today denies shell composition (Tier 1) and asks before destructive single commands (Tier 2, added in the ask-tier work). It does not address a different drift pattern: agents reaching for raw `git commit` / `git push` / `gh pr create` when the workspace's `ws` wrappers are the right tool. The wrappers handle attribution (Co-Authored-By), bodyfile-driven flows, fork-remote selection, identity substitutions, and token coverage — discipline that AGENTS.md documents but training-data reflex drifts away from.

This design adds a **redirect deny** tier that catches three raw commands and points the agent at the corresponding `ws` subcommand. Because legitimate edge cases exist (a `ws` subcommand may not yet support a needed feature), the redirect ships paired with a **session-scoped bypass mechanism**: a `ws hook-bypass <slug>` subcommand that writes a marker file the hook honors for the current session only. The bypass subcommand itself is on the ask-list, so creating a bypass always force-prompts the human — the security gate is the existing ask-tier, no env vars or HMACs added.

## Goals

1. **Redirect deny** — three named raw commands deny with a corrective message that names the right `ws` subcommand.
2. **Per-command bypass** — when the redirect blocks a legitimate use, the agent can request a session-scoped bypass; the human approves once and the rest of the session runs through.
3. **Severe guardrails against drift** — bypass is scoped to a specific slug (never blanket), creation is force-prompted (never silent), markers expire with the session, and audit logging makes reuse patterns visible.
4. **No new dependency** — flat-text config in the existing `hook-rules` file; the `ws` subcommand uses the existing dispatcher.
5. **Clean tier numbering** — five whole-numbered tiers, every documentation reference updated.
6. **Composability with prior work** — the redirect tier sits between the existing composition deny and ask tiers; no other tier behavior changes.
7. **YAGNI for the broader hook-v2 arc** — design only the deep pair (redirect + bypass). The other four ideas in the `hook-v2-extensions` arc (PowerShell coverage, hard-wrap rejection, `ws exec` narrowing, `--ff-only` nudge) are out of scope for this round.

## Non-goals

- **General named-bypass mechanism.** The bypass slug allowlist is implicit — anything declared in `[redirect-commands]` is bypassable, nothing else is. A separate `[bypass-slugs]` section is not designed. If a second deny tier later wants the same escape hatch, the refactor to extract bypass-slug declaration is mechanical and small.
- **Extending the redirect to additional commands in v1.** Only `git commit`, `git push`, `gh pr create`. The Thalamus `hook-v2-extensions` notes list more candidates (`gh api graphql` for review threads, `git status` for cross-workspace awareness, etc.); they are explicitly deferred so the deny-with-bypass loop can be proven on a small set first.
- **Housekeeping integration.** `ws clean` purges `.tmp/` and the audit log records every `BYPASS-ALLOW` entry — a periodic `grep BYPASS-ALLOW ~/.claude/hook-audit.log` is the mini-retro. No new housekeeping-skill step is added in v1.
- **Cross-session bypass persistence.** Markers are session-scoped by `CLAUDE_SESSION_ID`. A "remember this bypass for this user" persistent allowlist is not part of v1; if usage shows the same slug being bypassed every session, the right fix is to extend the `ws` subcommand, not to make the bypass durable.
- **Concurrent-session isolation.** Two Claude sessions writing to the same `.tmp/hook-bypass/<slug>.bypass` will overwrite each other's marker (last-writer-wins). Documented limitation; rare in practice; future iteration can use per-session filenames if needed.

## Architecture — decision flow

The hook remains a PreToolUse hook on the Bash tool. Five tiers, **renumbered** to all whole numbers:

```text
Tier 1 — DENY    composition (&&, ||, ;, |, $(), `…`, redirects, &, FD merges)   [unchanged]
Tier 2 — DENY    command matches [redirect-commands] pattern,                    [NEW]
                 UNLESS a bypass marker for the matching slug exists with
                 the current CLAUDE_SESSION_ID → fall through to ALLOW with
                 audit `BYPASS-ALLOW [<slug>] reason="<text>": <cmd>`
Tier 3 — ASK     command matches [ask-commands] pattern                          [was Tier 2]
Tier 4 — ALLOW   command matches a Bash(...) pattern in .claude/settings.json    [was Tier 3]
Tier 5 — ALLOW   command matches [allow-extras] in hook-rules.local              [was Tier 4]
Default — PASSTHROUGH   exit 0, no JSON; harness decides
```

**Ordering rationale.** Tier 2 sits after composition deny (composition is structurally hostile — no bypass for it) and before the ask-tier (the redirect is a stronger "use the right tool" signal than ask's "this is destructive — please confirm"). The bypass sub-check sits inside Tier 2: a marker overrides the redirect deny only for its declared slug, never for composition (Tier 1) and never for ask-list commands (Tier 3 still fires regardless of marker state).

A bypass for `git-commit` does not cascade to `git push` or `gh pr create` — each slug is isolated. A `git commit -m "x" && git push` still denies at Tier 1 (composition) regardless of any marker — the bypass mechanism never weakens the composition guard.

## Components

### `hook-rules` — new `[redirect-commands]` section

Three columns separated by ` | ` (pipe with surrounding spaces). The pipe character is safe as a separator because Tier 1 already blocks `|` from agent commands, so a stray pipe in an agent invocation can never collide with a pattern column.

```text
[redirect-commands]
git-commit   | git commit*    | Use `ws commit <comp> <bodyfile>` — handles Co-Authored-By trailer + bodyfile-driven staging. See `ws help commit`. If `ws commit` doesn't fit (rare), run `ws hook-bypass git-commit` to request a session-scoped bypass.
git-push     | git push*      | Use `ws push <comp> [branch]` — handles fork-remote selection from identity.forkOrg and sets upstream on first push. `ws hook-bypass git-push` for a session-scoped bypass.
gh-pr-create | gh pr create*  | Use `ws cr <comp> <title> <bodyfile>` — bodyfile-driven, applies identity substitutions, picks the right token + remote. `ws hook-bypass gh-pr-create` for a session-scoped bypass.
```

- **Column 1 (slug)** — single kebab-case word, validated against `^[a-z0-9-]+$`. Doubles as the bypass-marker filename stem and as the `ws hook-bypass` argument. No whitespace allowed.
- **Column 2 (pattern)** — bash glob matched against the full command string after the existing `normalize_for_match` transform. Same matching semantics as `[ask-commands]` and `[allow-extras]`.
- **Column 3 (suggestion)** — free-text deny message emitted as `permissionDecisionReason`. Conventionally names the `ws` equivalent and points at `ws hook-bypass <slug>` as the escape hatch.

**Parsing rule.** Each line is split into three fields on the first two ` | ` occurrences. Any further pipes belong to the suggestion text (column 3) and are preserved verbatim. This lets suggestion text include a literal pipe if needed without escaping.

The slug allowlist for `ws hook-bypass` is implicit — it is exactly the set of slugs declared in `[redirect-commands]`. There is no separate `[bypass-slugs]` section in v1.

### `ws hook-bypass <slug> [--reason "<text>"]`

New subcommand at `scripts/ws-hook-bypass.sh`, dispatched via `scripts/ws`. Behavior:

1. Parses `hook-rules` to enumerate the slugs declared in `[redirect-commands]`. Uses the same flat-text parser the hook itself uses (a small shared bash helper is the cleanest factoring — extracted during implementation). Validates `<slug>` against that list. Unknown slug → exit 1 with a message listing the known slugs.
2. Reads `$CLAUDE_SESSION_ID` from env. Absent → exit 1 with "no Claude Code session detected — this command only makes sense inside an active Claude Code session." Prevents the human from running it standalone (which would write a marker that never matches anything).
3. Creates `.tmp/hook-bypass/` with `mkdir -p` if absent.
4. Writes `.tmp/hook-bypass/<slug>.bypass` with YAML-ish frontmatter:

```yaml
session_id: 7f8e9d8a-4c2b-...
slug: git-commit
created_at: 2026-05-20T15:42:11Z
reason: ws commit doesn't support amend yet
```

5. Echoes a one-line confirmation to stdout for the agent's transcript: `bypass marker written: .tmp/hook-bypass/git-commit.bypass (session 7f8e9d...)`.

The subcommand pattern `ws hook-bypass *` is added to the committed `[ask-commands]` baseline in `hook-rules`. That makes every invocation force-prompt the human regardless of session mode (`acceptEdits` included) — the security gate is the existing Tier 3 ask mechanism, no new permission machinery is added.

### Hook bypass-check logic — inside Tier 2

Pseudo-code for the new Tier 2 evaluation:

```text
for entry in parsed [redirect-commands]:
    slug, pattern, suggestion = entry
    if cmd matches pattern:
        marker_path = "$project_dir/.tmp/hook-bypass/$slug.bypass"
        if marker_path exists:
            marker_session_id = parse(marker_path).session_id
            marker_reason = parse(marker_path).reason  # may be empty
            if marker_session_id == current_session_id:
                log: BYPASS-ALLOW [$slug] reason="$marker_reason": $cmd
                allow()
                return
        log: DENY [$slug]: $cmd
        deny(suggestion)
        return
```

The marker parse is a small bash function — three `grep`-free reads via pure parameter expansion or a tiny `awk` (consistent with the hook's "no new dependency beyond jq" stance). Field-by-field tolerant of missing keys: `session_id` absent → treat as session-unidentified (no match → deny); `reason` absent → empty string.

### `ws clean` — no change needed

`ws clean` already purges `.tmp/` along with the other workspace scratch directories. Markers under `.tmp/hook-bypass/` are swept naturally. The hook's bypass-check ignores stale markers (different session_id) silently, so no cleanup is strictly required for correctness — only for housekeeping hygiene.

### Audit log — new `BYPASS-ALLOW` entry kind

The audit log gains a fourth entry kind alongside `ALLOW`, `DENY`, and `ASK`:

```text
[2026-05-20 15:42:33] BYPASS-ALLOW [git-commit] reason="ws commit doesn't support amend yet" [PreToolUse]: git commit --amend -m "fix typo"
```

The `reason=""` field is always emitted (empty string when `--reason` was omitted) so log-parsers can rely on a stable shape. `grep BYPASS-ALLOW ~/.claude/hook-audit.log` is the mini-retro mechanism: recurring slugs are the signal that the corresponding `ws` subcommand needs extending.

## Data flow

### Happy path — agent reaches for `git commit`, corrects to `ws commit`

1. Agent: `git commit -m "fix bug"` via Bash tool.
2. Harness sends PreToolUse payload to hook (`tool_input.command = "git commit -m \"fix bug\""`, `session_id = "abc123"`).
3. Hook → Tier 1 composition checks pass (no `&&`/`|`/etc).
4. Hook → Tier 2 walks `[redirect-commands]`, matches `git commit*` → slug `git-commit`.
5. Hook checks `.tmp/hook-bypass/git-commit.bypass` — not present.
6. Hook emits `permissionDecision: "deny"` with the suggestion-text as `permissionDecisionReason`. Agent sees the corrective message.
7. Agent corrects to `ws commit <comp> .commits/<name>.md`. Allowed via existing Tier 4 (settings.json `Bash(ws commit *)` pattern). Done.

### Bypass path — agent needs raw `git commit` (legitimate edge case)

1. Steps 1-6 as above — agent hits the deny.
2. Agent recognizes the corrective message offers `ws hook-bypass git-commit` and decides to request it.
3. Agent: `ws hook-bypass git-commit --reason "amend last commit; ws commit doesn't support amend yet"` via Bash tool.
4. Hook → Tier 1 pass; Tier 2 walks `[redirect-commands]` — `ws hook-bypass git-commit ...` doesn't match any redirect pattern. Falls through.
5. Hook → Tier 3 walks `[ask-commands]` — matches `ws hook-bypass *`. Emits `permissionDecision: "ask"`. Human gets prompt.
6. Human approves → command runs. `ws-hook-bypass.sh` validates slug, reads `$CLAUDE_SESSION_ID`, writes `.tmp/hook-bypass/git-commit.bypass` with frontmatter.
7. Agent retries: `git commit --amend -m "..."`.
8. Hook → Tier 2 matches `git-commit` → checks marker → session_id matches → ALLOW with audit `BYPASS-ALLOW [git-commit] reason="amend last commit...": git commit --amend...`.
9. Subsequent `git commit` calls in this session also bypass.
10. Next session: `CLAUDE_SESSION_ID` differs → marker is stale → re-deny on first `git commit`. `ws clean` (or any `.tmp/` purge) sweeps it.

### Session-id source

Claude Code sets `CLAUDE_SESSION_ID` in the harness env (visible to the hook script as `$CLAUDE_SESSION_ID`, and to `ws hook-bypass` since `ws` runs inside the same env). The hook also reads `session_id` from the JSON payload on stdin (already parsed at line 132 of the current script — used by `audit_log` context but not currently surfaced for tier logic). The two sources should agree; mismatch falls back to the stdin value (closer to the truth of what the hook actually saw on this invocation).

## Error handling

| Failure mode | Behavior |
|---|---|
| Malformed `[redirect-commands]` entry (wrong column count, bad slug chars, empty slug) | Log `WARNING (hook-rules: malformed [redirect-commands] entry, line skipped): <file>:<lineno>` to audit; skip the entry; continue. Other entries still parse. |
| Unknown slug passed to `ws hook-bypass` | Exit 1 with a message listing the known slugs from `[redirect-commands]`. No marker file written. |
| Missing `$CLAUDE_SESSION_ID` in `ws hook-bypass` | Exit 1 with "no Claude Code session detected — this command only makes sense inside an active Claude Code session." |
| Marker file corrupted (missing `session_id`, unparseable frontmatter) | Treat as stale (no match) — deny as usual. Log warning to audit. The corrupted file stays until `ws clean`. |
| Marker file `session_id` mismatch | Silently ignored on that decision (same as "not present"). Not deleted — could be a sibling session running concurrently. |
| Hook stdin payload missing `session_id` | Falls back to `$CLAUDE_SESSION_ID`. If both absent: no markers can match — falls back to denying as usual. Bats test asserts no crash. |
| Pattern collision between a redirect pattern and `ws hook-bypass <slug>` | Bats invariant test: parse `[redirect-commands]`, synthesize `ws hook-bypass <each-slug>` invocations, assert none match any redirect pattern. Fails the test if a future entry accidentally collides. |
| `.tmp/hook-bypass/` directory missing | `ws hook-bypass` creates it with `mkdir -p`. Hook treats missing-dir as no-marker (deny). |
| Concurrent Claude sessions writing the same `.tmp/hook-bypass/<slug>.bypass` | Last-writer-wins. Documented as a known limitation; rare in practice; second session can re-issue its own bypass. |

## Testing

### Bats — deterministic decision logic

Extends `tests/hook/gdd-permission-hook.bats`. New cases:

- `git commit -m "x"` payload → emits `permissionDecision: "deny"` with `permissionDecisionReason` containing "Use `ws commit`".
- `git push origin main` → deny with "Use `ws push`".
- `gh pr create --title x --body y` → deny with "Use `ws cr`".
- Composition wins over redirect: `git commit -m "x" && git push` → Tier 1 deny (composition reason), not Tier 2 redirect reason.
- Bypass marker present + matching session_id → ALLOW; audit line is `BYPASS-ALLOW [git-commit] reason="...": <cmd>`.
- Bypass marker present + mismatched session_id → DENY (same as no marker).
- Bypass marker with empty `reason` field → ALLOW with `reason=""` in audit.
- Slug isolation: a `git-commit` bypass marker does NOT bypass a `git push` deny.
- Tier 1 invariant: bypass marker does NOT bypass composition deny (`git commit -m x && y` denies regardless of marker).
- Tier 3 invariant: bypass marker does NOT bypass ask-list (`rm -rf .git` still asks, even with any marker present).
- `[redirect-commands]` malformed entry (2 columns instead of 3, bad slug chars `git_commit`, empty slug): logs warning, skips entry, other entries still parse. Hook does not crash.
- `ws hook-bypass git-commit` invocation passes Tier 2 (no pattern collision) and hits Tier 3 ask.
- Pattern-collision invariant: parse `[redirect-commands]`, synthesize `ws hook-bypass <each-slug>` calls, confirm none match any redirect pattern.

### Bats — `ws hook-bypass` subcommand

New `tests/ws-cli/hook-bypass.bats`:

- Valid slug + `$CLAUDE_SESSION_ID` set → writes `.tmp/hook-bypass/<slug>.bypass` with correct frontmatter (session_id, slug, created_at, reason).
- `--reason "..."` captured into frontmatter; absent reason → `reason: ""`.
- Unknown slug → exit 1; stderr lists known slugs.
- Missing `$CLAUDE_SESSION_ID` → exit 1.
- `.tmp/hook-bypass/` auto-created if absent.
- Re-running same slug overwrites the marker with the new session_id / timestamp / reason.

### Interactive acceptance script

New `tests/hook/interactive-redirect-acceptance.md`, following the pattern of the existing `interactive-acceptance.md` from the ask-tier work. The actor's script walks the human through:

1. Agent announces: "I'll run `git commit -m test` — expect a Tier 2 deny pointing at `ws commit`."
2. Agent runs it; human confirms the deny message names `ws commit` and `ws hook-bypass git-commit`.
3. Agent: "Now `ws hook-bypass git-commit --reason \"acceptance test\"` — expect an ask prompt."
4. Human approves; confirms the prompt is the Tier 3 ask, not a silent run.
5. Agent: "Retrying `git commit -m test` in a throwaway repo — expect ALLOW with audit `BYPASS-ALLOW [git-commit] reason=\"acceptance test\"`."
6. Agent runs it; human confirms no prompt and checks the audit log line.
7. Agent: "Now `gh pr create --title test --body test` — expect deny (different slug, marker is for git-commit only)."
8. Agent runs it; human confirms deny.
9. Agent: "Wrapping up — `ws clean` to sweep the marker."

### Test runner integration

The bats files run via `ws test yggdrasil` (the existing bats-core vendored runner). The interactive script is invoked on demand by the agent during a real session — not in CI — matching the convention from the prior ask-tier acceptance script.

## Documentation updates

The redirect tier is new behavior and the renumbered tiers invalidate every existing tier reference. The hook's documentation set must move with the implementation:

- **`.claude/hooks/README.md`** — the hook's technical spec. Renumbered tiers; the new redirect-commands section; the bypass mechanism (file format, session_id binding, `ws hook-bypass` flow); audit-log `BYPASS-ALLOW` entry kind.
- **`docs/gdd/permissions.md`** — add the redirect tier and the bypass mechanism alongside existing allow/deny/ask documentation.
- **`docs/gdd/agent-training.md`** — the user-facing hook companion. Explain that raw `git commit` / `git push` / `gh pr create` now deny with corrective messages, why the redirect exists, and how the bypass loop works (deny → `ws hook-bypass` → ask prompt → retry).
- **`docs/gdd/trust-and-safety.md`** — record the redirect tier as a training-aid layer (not a safety floor like the ask-tier; the threat model is agent drift, not adversarial commands) and document the bypass mechanism's security boundary (the `ws hook-bypass *` ask-list entry IS the gate).
- **`AGENTS.md`** — small mention in the "ws-first reflex check" section pointing at the hook as the enforcement layer for the table's "Use this instead" column. One line; the table already documents the right wrappers.

The implementation plan specifies exact per-file edits after reading each.

## Implementation outline (for the follow-on plan)

Rough order, finalized in the implementation plan:

1. Extend `_parse_rules_file` in `gdd-permission-hook.sh` to recognize `[redirect-commands]` with three pipe-separated columns; validate slug format; log warnings for malformed entries.
2. Add Tier 2 redirect-deny evaluation between the current composition deny and ask-list loops; include the bypass-marker check inside Tier 2.
3. Add the `BYPASS-ALLOW` audit-log helper (parallel to `allow`/`deny`/`ask`).
4. Renumber tier comments / inline `Tier N` references throughout the hook script.
5. Add the v1 `[redirect-commands]` entries to `hook-rules` and the `ws hook-bypass *` entry to the baseline `[ask-commands]`.
6. Write `scripts/ws-hook-bypass.sh` with slug validation, session_id check, marker writing.
7. Wire the subcommand into `scripts/ws` dispatcher and `ws help`.
8. Bats coverage per the testing section.
9. Documentation updates per the documentation section.
10. Interactive acceptance script (`tests/hook/interactive-redirect-acceptance.md`).
11. Run bats; then the interactive acceptance script with the user as the final gate.

## Success criteria

- Raw `git commit` / `git push` / `gh pr create` produce a permission deny with a corrective message naming the `ws` equivalent and the bypass command.
- `ws hook-bypass <slug>` always force-prompts the human via the ask-tier; no env-var ceremony required.
- A granted bypass allows subsequent matching commands for the rest of the session, then expires automatically when `CLAUDE_SESSION_ID` changes or `.tmp/` is swept.
- Bypass for one slug does not extend to other slugs; bypass never overrides composition deny or ask-tier.
- Audit log records every `BYPASS-ALLOW` with slug + reason; `grep BYPASS-ALLOW ~/.claude/hook-audit.log` surfaces recurring patterns as signal to extend the corresponding `ws` subcommand.
- Bats suite green, including tier-precedence, slug-isolation, and pattern-collision invariants.
- The interactive acceptance script's prompts and audit lines appear exactly as announced.
- Renumbered tiers are reflected consistently across `gdd-permission-hook.sh`, `.claude/hooks/README.md`, and the four `docs/gdd/*` files listed above.
