# Hook Ask-Tier and Rules File — Design

**Status:** Draft, awaiting review
**Date:** 2026-05-17
**Owner:** Rasmus Praestholm
**Related:**

- `.claude/hooks/gdd-allowlist-bridge.sh` and `.claude/hooks/README.md` — the hook this design extends
- [`docs/gdd/agent-training.md`](../gdd/agent-training.md) — the user-facing companion to the hook
- PR #61 / #62 — prior hook work (registration, PermissionRequest event, scratch-dir Edit/Write)

## Overview

The PreToolUse hook `gdd-allowlist-bridge.sh` today does two things: it **denies** shell composition (`&&`, `|`, `;`, redirects, …) and it **allows** commands matching `.claude/settings.json` or `safe-bash-extras`. It has no guard against individually destructive *single* commands.

An investigation on 2026-05-16 confirmed the gap: in `acceptEdits` permission mode, the harness auto-approves Bash file-mutations — including `rm -rf` — on workspace paths with no prompt. The hook is not at fault: it correctly passes through (verified with `WS_HOOK_DEBUG=1` passthrough logging — every `rm -rf` test logged `[PreToolUse] PASSTHROUGH`). The harness's own `acceptEdits` logic classifies a Bash file-mutation on a workspace path as an auto-acceptable "edit". The hook's deny logic only polices command *composition*, never command *danger*.

This design adds a third decision behavior to the hook — **`ask`** — and externalizes the hook's configuration:

1. A new **ask-tier**: commands matching a configurable "scary command" list cause the hook to emit `permissionDecision: "ask"`, which forces a permission prompt regardless of mode (`acceptEdits` included) **without hard-blocking** — the agent can still run the command once the human approves. `ask` is the right tool because destructive commands are *sometimes legitimate* (bulk temp-cache delete); `deny` would block them outright.
2. A single, transparent, layered **rules file**: the hook's previously hardcoded scratch-dir list and the `safe-bash-extras` allowlist move into a committed `hook-rules` baseline plus an optional per-machine `hook-rules.local` override.

## Goals

1. **Ask-tier** — force a prompt for destructive commands in *any* permission mode; never silently auto-run them.
2. **Transparency** — the hook's behavior (which dirs are scratch, which commands are scary) is legible in one committed file, not buried in the script.
3. **Layered config** — committed baseline + optional per-machine override, mirroring the repo's existing `ecosystem.yaml` → `ecosystem.local.yaml` pattern.
4. **Consolidation** — fold the `safe-bash-extras` allowlist into the new config so there is one per-machine file, not two.
5. **No new dependency** — flat sectioned text parsed by pure bash; the hook must not gain a `yq` dependency on top of `jq`.
6. **Clean tier numbering** — the new tier makes the hook's tiers 1-2-3-4, renumbered everywhere they're documented.
7. **Symlink caution** — `rm` ask-prompts carry a reminder that a path could be a symlink reaching outside the workspace.
8. **Two-layer testing** — bats for the deterministic decision logic; a new interactive acceptance script for what bats cannot verify (the prompt the human actually sees).

## Non-goals

Explicitly out of scope for this design:

- **Session-toggle / bypass marker** — deferred (YAGNI). `ask` already lets the human approve each prompt, and Claude Code's own prompt offers a "don't ask again" choice giving per-session suppression natively. Recorded in the Thalamus; revisit only if repeated ask-prompts prove genuinely annoying.
- **Bash symlink resolution** — the hook will *not* parse paths out of Bash command strings to resolve symlinks (fragile, the same per-segment parsing Tier 1 deliberately refuses). Replaced by a caution line in the `rm` ask-prompt text. A real Bash symlink-resolution pass remains a possible separate follow-on.
- **PermissionRequest event** — not registered in this workspace; its code paths stay dormant and untouched.
- **A `[defaults]` config section** — with the session-toggle deferred, there is nothing for it to hold in v1.
- **User-level (`~/.claude/`) hook config** — the workspace directive is "everything hook-related in the workspace". Both config files live under `.claude/hooks/`.
- **Per-ask-pattern custom messages** — v1 uses one generic ask message plus an `rm`-family symlink addendum. Per-pattern messages are a possible future refinement.
- **Renaming the hook script** — `gdd-allowlist-bridge.sh` keeps its name despite the broadened role; renaming touches the settings.json registration, README, and tests for no functional gain.

## Architecture — decision flow

The hook remains a PreToolUse hook on the Bash tool. The decision tiers, **renumbered**:

```text
  Tier 1 — DENY    shell composition (&&, ||, ;, |, $(), `…`, redirects, &)
                   — unchanged
  Tier 2 — ASK     command matches an [ask-commands] glob   ← NEW
                   → emit permissionDecision: "ask"
  Tier 3 — ALLOW   command matches a Bash(...) pattern in .claude/settings.json
                   — was Tier 2
  Tier 4 — ALLOW   command matches an [allow-extras] glob in hook-rules.local
                   — was Tier 3 (the retired safe-bash-extras)
  Default — PASSTHROUGH   exit 0, no JSON; harness decides
```

**Ordering rationale — ask before allow.** A Tier 2 ask-match forces a prompt even when a Tier 3/4 allow rule would otherwise pass the command silently. The ask-list is a safety *floor*: if `rm -rf*` is on the ask-list, it prompts even if some machine also has `rm -rf*` in its allowlist. Danger outranks convenience. (The alternative — ask after allow — would let an explicit allowlist entry silently win; rejected.)

Tier 1 still precedes Tier 2: `rm -rf x && something` denies for the `&&` (composition is never merely "ask"-worthy — it's opaque to audit), it does not ask.

## Components

### The config files

| File | Tracked | Role |
|------|---------|------|
| `.claude/hooks/hook-rules` | committed | Active baseline — `[scratch-dirs]`, `[ask-commands]` |
| `.claude/hooks/hook-rules.local` | gitignored | Optional per-machine override + `[allow-extras]` |
| `.claude/hooks/hook-rules.local.example` | committed | Template the user copies to `hook-rules.local` |

`safe-bash-extras` and `safe-bash-extras.example` are **retired** — their content and role migrate into `[allow-extras]` (see Migration).

### File format — flat sectioned text

```text
# Comments start with '#'. Blank lines ignored. Section headers in
# [brackets]. One entry per line within a section.

[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/

[ask-commands]
rm -rf*
rm -fr*
rm -r *
git reset --hard*
git clean -f*
git clean -d*
find * -delete*
```

- Parsed by the hook's existing pure-bash line-loop (the one that reads `safe-bash-extras` today). **No `yq`/`jq` dependency added.**
- Trailing-CR tolerant (CRLF-committed files), same as the current `safe-bash-extras` parsing.
- Entries in `[scratch-dirs]` are workspace-relative path prefixes; entries in `[ask-commands]` and `[allow-extras]` are bash-glob patterns matched against the full command string (same matching the hook already uses for `safe-bash-extras`).
- An entry before any `[section]` header is a file error — the hook logs a warning to the audit log and skips the malformed file (degrade to the baseline, never crash).

### `hook-rules` — committed baseline

Holds `[scratch-dirs]` (migrated verbatim from the hook's current hardcoded list, which already mirrors `.gitignore`'s scratch section) and `[ask-commands]` (the destructive-command list). This file is the single transparent source of truth for "what the hook treats specially" — its primary value is *visibility*, readable without opening the 600-line script.

### `hook-rules.local` — per-machine override

Optional, gitignored. May contain:
- `[scratch-dirs]` — entries here are **added** to the baseline (a machine can mark an extra dir as scratch).
- `[ask-commands]` — entries here are **added** to the baseline. **Additive-only**: there is no removal syntax. A per-machine file cannot delete a committed ask-command — that would silently weaken the safety floor with no reset. (Adding is always safe: more confirmation, never less.)
- `[allow-extras]` — the migrated `safe-bash-extras` role: personal allow-patterns (e.g. `ls *`) the user trusts on this machine. Consumed by Tier 4.

The realistic use is a power user uncommenting a few `[allow-extras]` entries they're tired of approving — not heavy reconfiguration. Scratch-dirs and ask-commands are expected to be rarely touched; they live in config for *legibility*, not because frequent editing is anticipated.

### Merge semantics

The hook reads `hook-rules`, then `hook-rules.local` if present:
- `[scratch-dirs]`: union of baseline + local.
- `[ask-commands]`: union of baseline + local (additive-only — no removal).
- `[allow-extras]`: from `hook-rules.local` only (baseline has no such section — personal trust is never committed policy).

### The ask-tier (`ask()` helper)

A new `ask()` decision helper joins `allow()` and `deny()`:
- Emits `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"<text>"}}`.
- Logs an `ASK [<event>] (<reason>): <cmd>` line to the audit log, consistent with the existing `ALLOW`/`DENY` entries.
- For the PermissionRequest event the dormant code path uses that event's decision shape (parity with how `allow()`/`deny()` already branch on `$event`).

After Tier 1, the hook glob-matches the command against the merged `[ask-commands]`. On a match it calls `ask()`.

**Reason text:** a generic line — *"This command is on the GDD hook's ask-list — destructive or hard to undo. Confirm before proceeding."* — plus, when the command's first word is an `rm` variant, a brief appended caution: *"Caution: symlinks here could delete outside the workspace."* No path resolution is performed; the caution is unconditional for `rm`-family matches.

### Scratch-dir consumption

The Edit/Write branch currently tests against a hardcoded `for prefix in ".tmp/" ".commits/" …`. It instead reads the merged `[scratch-dirs]`. Behavior is identical when the config matches today's hardcoded list; the config simply makes the list visible and overridable.

### Tier renumbering

The hook's header comment block and every inline `Tier N` reference update to the 1-2-3-4 scheme above. The `.claude/hooks/README.md` tier descriptions update to match.

## Migration

1. Move the commented example patterns from `safe-bash-extras.example` (`ls *`, `mkdir *`, `touch *`, the niche utilities) into the `[allow-extras]` section of `hook-rules.local.example`.
2. If a live `safe-bash-extras` exists in the working tree, its active patterns are migrated into the developer's `hook-rules.local` `[allow-extras]` as part of rollout (documented in the README; the live file is per-machine so this is a local step, not a repo change).
3. Delete `safe-bash-extras` and `safe-bash-extras.example` from the repo.
4. `.gitignore`: add `/.claude/hooks/hook-rules.local`, remove the `safe-bash-extras` entry.
## Documentation updates

The ask-tier is a new behavior and the renumbered tiers invalidate existing tier descriptions. The hook's documentation set is GDD's written account of the agent-human permission workflow, so it is updated as part of this work — it must not drift from the hook:

- **`.claude/hooks/README.md`** — the hook's technical spec. Renumbered tiers; the new ask-tier; the `hook-rules` / `hook-rules.local` / `.example` config; drop the retired `safe-bash-extras` section.
- **`docs/gdd/permissions.md`** — add `ask` as a third hook decision alongside allow / deny, and note it forces a prompt regardless of permission mode.
- **`docs/gdd/agent-training.md`** — the user-facing hook companion. Explain that destructive commands now always prompt (the ask-tier), why, and that the prompt is a deliberate agent-human confirmation checkpoint, not a failure.
- **`docs/gdd/trust-and-safety.md`** — record the ask-tier as the destructive-command safety floor and note the `acceptEdits` auto-approve gap it closes.
- **`docs/gdd/roles-and-modes.md`** — accuracy review: `acceptEdits` no longer silently runs destructive Bash, since the ask-tier intercepts first.

The implementation plan specifies the exact per-file edits after reading each.

## Testing

### bats — deterministic decision logic

Extends `tests/hook/` (the hook already has bats coverage). The hook is invoked with a synthetic stdin payload; assertions are on the emitted JSON and the audit-log line. New cases:

- An `[ask-commands]` match emits `permissionDecision: "ask"`.
- Tier 1 precedence: `rm -rf x && y` denies (composition) — it does not ask.
- Tier 2 precedence: an ask-match emits `ask` even when the same command also matches a Tier 3/4 allow pattern.
- Rules-file parsing: sections, comments, blank lines, CRLF tolerance; a malformed file (entry before any section header) degrades gracefully and logs a warning.
- Merge: a `hook-rules.local` `[ask-commands]` entry is added to the baseline set.
- Additive-only: a `hook-rules.local` file cannot remove a baseline ask-command (there is no removal syntax — a test confirms a baseline entry still asks regardless of `.local` content).
- `[scratch-dirs]` is read from config (Edit/Write auto-allow still works when the config lists the dir).
- `rm`-family ask reason text contains the symlink caution; non-`rm` ask reason does not.

### Interactive acceptance script — what bats cannot do

bats verifies the hook's *output*; it cannot verify the *prompt the human sees*. A new `tests/hook/interactive-acceptance.md` is a scripted "actor's script" the agent walks through live with the human:

- The agent announces the batch up front: the commands it will run and the prompt shape expected for each (`ask` with symlink caution / `ask` plain / composition `deny` / no prompt).
- The agent runs each command in sequence.
- The human confirms each prompt matched the announced shape, or flags a mismatch.

A representative sequence (the doc carries the full version):

1. `rm -rf .tmp/acceptance-probe` — expect an `ask` prompt **with** the symlink caution.
2. `git reset --hard` *(in a throwaway repo)* — expect an `ask` prompt **without** the symlink caution.
3. `ls -la` — expect **no** prompt (Tier 4 `[allow-extras]`, if enabled) or a normal prompt.
4. `echo hi && echo bye` — expect a composition **deny**, not an ask.
5. `rm -rf .tmp/acceptance-probe-2` with `acceptEdits` mode on — expect the `ask` prompt to **still** appear (the core regression check — the original bug).

The script is run on request; whether it is wired into `ws test` as an interactive mode is left to the implementation plan as an optional nicety.

## Implementation outline (for the follow-on plan)

Branch `feat/hook-ask-tier` is created off `main`; the `WS_HOOK_DEBUG` opt-in passthrough logging is already committed there (`ea794ae`). Remaining work, roughly ordered:

1. Create `.claude/hooks/hook-rules` (baseline `[scratch-dirs]` + `[ask-commands]`).
2. Create `.claude/hooks/hook-rules.local.example` (all three sections, `[allow-extras]` carrying the migrated commented examples).
3. `.gitignore` — add `hook-rules.local`, remove `safe-bash-extras`.
4. Rewrite the hook: config parsing + merge; `ask()` helper; Tier 2 ask-tier; tier renumbering; scratch-dirs from config; retire the `safe-bash-extras` read in favour of `[allow-extras]`.
5. Delete `safe-bash-extras` + `safe-bash-extras.example`.
6. bats tests per above.
7. `tests/hook/interactive-acceptance.md`.
8. Documentation updates — `.claude/hooks/README.md`, `docs/gdd/permissions.md`, `docs/gdd/agent-training.md`, `docs/gdd/trust-and-safety.md`, plus a `docs/gdd/roles-and-modes.md` accuracy check (see Documentation updates).
9. Run bats; then the interactive acceptance script with the user as the final gate.

## Success criteria

- `rm -rf` on a workspace path produces a permission prompt **even in `acceptEdits` mode** (the original bug, fixed).
- A destructive command can still be run — the prompt is `ask`, not `deny` — so a legitimate bulk delete needs one approval, not a workaround.
- bats suite green, including the additive-only and tier-precedence cases.
- The interactive acceptance script's prompts appear exactly as announced.
- `hook-rules` makes the hook's scratch-dir and ask-command behavior readable without opening the script.
