# Claude Code hooks shipped with yggdrasil

This directory contains a hook script that fires during Claude Code sessions in this workspace. The main hook event fires automatically — no action needed once the workspace is cloned and Claude Code is started in it. It is registered in [`../settings.json`](../settings.json) under `hooks.PreToolUse` and is meant to make agent behavior more predictable and to teach safer command patterns by giving immediate corrective feedback.

**New here?** [`docs/gdd/agent-training.md`](../../docs/gdd/agent-training.md) is the user-friendly companion that covers why you'll see deny output early in a session, why the discipline doesn't double API cost, and how to handle the "this legit command got denied" case. This README is the technical spec — what each tier checks, the audit log format, registration, and troubleshooting.

## PreToolUse hook 

Fires before every Bash tool call. Five decision tiers, then a passthrough:

1. **Deny shell composition** (`&&`, `||`, `;`, pipes, command substitution, redirects) with a corrective message that tells the agent how to retry. Trains the agent to use separate tool calls and native `ws` flags (`--limit`, `--compact`, `--output`) instead of shell composition.
2. **Deny raw `git commit` / `git push` / `gh pr create`** (and any other entry in the `[redirect-commands]` section of `hook-rules`) with a corrective message pointing at the right `ws` subcommand. A session-scoped bypass marker — written by `ws hook-bypass <slug>` after a human-approved ask prompt — overrides the deny for that slug. See [Redirect tier and bypass](#redirect-tier-and-bypass) below.
3. **Ask** (force a permission prompt) for anything matching a glob in the `[ask-commands]` section of `hook-rules` (committed baseline) or `hook-rules.local` (per-machine). The hook emits `permissionDecision: "ask"`, which surfaces a human-facing prompt regardless of the session permission mode — including `acceptEdits` and `bypassPermissions`. The command is NOT blocked; once the human approves it runs normally. This tier exists specifically to intercept destructive commands like `rm -rf` on some directory within the workspace that `acceptEdits` would otherwise auto-approve silently (to perhaps some surprise! But mass file deletion *could* be considered an "edit" technically).
4. **Allow** anything matching `permissions.allow` patterns in `.claude/settings.json` — the hook normalizes both the command and the pattern so bare `ws status` and verbose `bash scripts/ws status` both match a single pattern in either style.
5. **Allow** anything matching a glob in the `[allow-extras]` section of `hook-rules.local`. Per-machine personal extras for tools you trust on your laptop without committing them to the project config.
6. **Pass** everything else goes to default behavior based on other config.

Logs allow/deny/ask decisions to `~/.claude/hook-audit.log` with timestamps so you can review what the hook is doing. Passthroughs are not logged.

The tool-permission hook also understands the `PermissionRequest` event and the `Edit` / `Write` tools — those code paths are dormant under the default registration and activate only when you wire them up. See [Optional: PermissionRequest hook](#optional-permissionrequest-hook) below.

### Rules configuration

Two files drive the hook's allow/ask/deny decisions beyond the committed `settings.json`:

| File | Tracked in git? | Purpose |
|---|---|---|
| `.claude/hooks/hook-rules` | **Yes** | Committed baseline — transparent project policy for `[scratch-dirs]` and `[ask-commands]` |
| `.claude/hooks/hook-rules.local` | **No** (gitignored) | Per-machine overrides — copy from `hook-rules.local.example` |

The format is flat sectioned text: `[section]` headers, one entry per line, `#` comments, blank lines ignored.

#### Sections

**`[scratch-dirs]`** — workspace-relative paths under which Edit/Write tool calls auto-allow. Keeps in lockstep with the "Workspace-local scratch" section of [`.gitignore`](../../.gitignore). Entries in `hook-rules.local` add to the baseline; they never replace it.

**`[ask-commands]`** — glob patterns for destructive Bash commands that should always produce a permission prompt, regardless of session mode. A match in either file triggers Tier 2 (ask) not a deny — the human approves and the command runs. `hook-rules.local` entries are additive-only: you can make more commands prompt, but you cannot remove a pattern committed in `hook-rules`. This is intentional — per-machine config can tighten the safety floor, never loosen it.

**`[allow-extras]`** — personal Bash glob patterns auto-allowed on this machine without prompting (Tier 4). Only valid in `hook-rules.local`, never in the committed baseline. An entry here will not win over an "ask command" entry.

### Setting up per-machine overrides

```bash
cp .claude/hooks/hook-rules.local.example .claude/hooks/hook-rules.local
```

Then edit `hook-rules.local`. The example file is annotated with common entries.

**Important:** the safety reasoning of every `[allow-extras]` pattern depends on the hook's Tier 1 still being active. Removing the hook OR disabling Tier 1 would change the calculus of every entry. Treat changes to `hook-rules.local` with care.

### Redirect tier and bypass

The Tier 2 redirect-deny channels three raw commands toward the workspace's `ws` wrappers:

| Slug | Pattern | Use this instead |
|---|---|---|
| `git-commit` | `git commit*` | `ws commit <comp> <bodyfile>` — bodyfile-driven, attaches the Co-Authored-By trailer |
| `git-push` | `git push*` | `ws push <comp> [branch]` — picks the fork remote from `identity.forkOrg`, sets upstream on first push |
| `gh-pr-create` | `gh pr create*` | `ws cr <comp> <title> <bodyfile>` — bodyfile-driven, applies identity substitutions |

A deny here is a *training* signal, not a safety floor (that's Tier 3 ask). The hook trusts the workspace's own `ws` wrappers to do the right thing — attribution, remote selection, token coverage. When a legitimate edge case exists (`ws` doesn't yet support what you need), the agent can request a bypass:

1. Agent hits the deny; corrective message names `ws hook-bypass <slug>` as the escape hatch.
2. Agent runs `ws hook-bypass <slug> --reason "<why>"`. The subcommand is on the ask-list, so the human gets a permission prompt.
3. Human approves; the script writes `.tmp/hook-bypass/<slug>.bypass` keyed to `$CLAUDE_SESSION_ID`.
4. Agent retries the raw command; the hook finds the marker, matches session_id, and emits an allow with audit `BYPASS-ALLOW [<slug>] reason="<text>": <cmd>`.
5. The marker is honored for the rest of the session. Next session's `CLAUDE_SESSION_ID` differs, so the marker is stale; `ws clean` sweeps `.tmp/` whenever you want a clean slate.

The recurring-bypass pattern — same slug bypassed every session — is a signal that the corresponding `ws` subcommand needs to grow that capability. Periodic `grep BYPASS-ALLOW ~/.claude/hook-audit.log` surfaces it.

**Adding a new redirect.** Append a row to the `[redirect-commands]` section of `.claude/hooks/hook-rules`: `<slug> | <pattern> | <suggestion>`. The slug must match `^[a-z0-9-]+$`. The pattern is a bash glob. The suggestion is free text (column 3, may contain pipes — parsing splits on the first two ` | ` only). The new slug is automatically bypassable via `ws hook-bypass <new-slug>`; no script change needed.

## Optional: PermissionRequest hook

Power-user opt-in. Wires the same `gdd-permission-hook.sh` script to a second hook event — `PermissionRequest` — and broadens its matcher to also cover the `Edit` and `Write` tools. Net effect:

- **Scratch-dir writes stop prompting.** Edits and writes specifically under `.tmp/`, `.commits/`, `.crs/`, `.issues/`, and `.outputs/` (the "Workspace-local scratch" section of [`.gitignore`](../../.gitignore)) auto-allow. Useful when you're drafting commit bodies, CR templates, and capture files all day — those routine flows otherwise can generate a steady drip of approve prompts.
- **Bash allowlist matches double-cover at the prompt layer.** Anything your `settings.json` `allow` or `hook-rules.local` `[allow-extras]` would have allowed at `PreToolUse` also gets approved at `PermissionRequest`, which can help in some configurations — largely intended to let the GDD extensions be good citizens in otherwise constrained settings.

This isn't enabled by default because (a) `PermissionRequest` is a different threat-model surface than `PreToolUse` — auto-allowing writes into a directory list is a stronger trust grant than auto-allowing read-shaped Bash patterns, and (b) the value is mostly ergonomic, so it's better off opt-in than imposed. 

It still includes the sometimes more severe blocks that GDD implements to teach the agent not to let commands be chained at all, favoring deterministic scripts and temporary files that are more auditable than massive commands dumping to a simple point-in-time approve prompt.

### Enabling

Add this block to your `.claude/settings.local.json` (per-user, gitignored) alongside any existing `permissions` / `enabledMcpjsonServers` entries:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gdd-permission-hook.sh\""
          }
        ]
      }
    ]
  }
}
```

You may also want a `hook-rules.local` of your own (copy from `hook-rules.local.example`) — the PermissionRequest hook reads the same rules files the PreToolUse hook does.

### Verifying it's live

Ask your agent to run any safe scratch-dir write and check `~/.claude/hook-audit.log`. A scratch-dir hit logs as e.g. `ALLOW [PreToolUse] (scratch-dir: .tmp/): Write .../marker.txt` — the `[PreToolUse]` / `[PermissionRequest]` tag in the entry tells you which event fired.

### Adding more scratch dirs

The dir list lives in the `[scratch-dirs]` section of `.claude/hooks/hook-rules` (committed baseline) and optionally `hook-rules.local` (per-machine additions). Keep it in lockstep with the "Workspace-local scratch" section of [`.gitignore`](../../.gitignore) — anything gitignored as scratch should be safe to auto-allow, and vice versa. Additions to the committed `hook-rules` belong in the same PR that adds the directory to `.gitignore`.

## Disabling the hook

If a single session needs the hook off, set `WS_HOOK_DISABLE=1` in your shell, `.env`, or shell profile. The hook reads the variable on every invocation and exits as a passthrough when it's set.

```bash
export WS_HOOK_DISABLE=1
```

This bypass is per-user / per-machine and doesn't require editing the committed `settings.json`. To re-enable later, unset the variable.

## What if a Bash call stalls?

Earlier versions of this hook had an infinite-loop bug on Windows-style paths (the upward-walk for `.claude/settings.json` didn't terminate when `dirname` started returning `.` repeatedly). The current script has a `prev == dir` guard that ensures the loop exits at the filesystem root regardless of platform. Both `tests/hook/gdd-permission-hook.bats` and `tests/ws-smoke/read-only.bats` include timeout assertions that fail loudly if a regression introduces a hang.

If you encounter a stall anyway:

1. Set `WS_HOOK_DISABLE=1` to unblock yourself
2. Capture the audit log around the stall (`~/.claude/hook-audit.log`) and file a yggdrasil issue
3. As a workaround until fixed, remove the `hooks` block from your local `.claude/settings.local.json` (overrides the committed `settings.json` for your machine)

## Audit log

`~/.claude/hook-audit.log` records every allow/deny with a timestamp and the reason (which tier / which pattern fired). Worth a periodic skim — anything you didn't expect to be auto-approved is a pattern to narrow; anything you keep getting prompted for despite expecting auto-approval is a missing entry to add.

The log is append-only and per-user. The hook doesn't rotate it; if it grows, `truncate -s 0 ~/.claude/hook-audit.log` resets it.
