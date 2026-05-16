# Claude Code hooks shipped with yggdrasil

This directory contains hook scripts that fire during Claude Code sessions in this workspace. They run automatically — no action needed once the workspace is cloned and Claude Code is started in it.

The hooks are registered in [`../settings.json`](../settings.json) under `hooks.PreToolUse`. They're meant to make agent behavior more predictable and to teach safer command patterns by giving immediate corrective feedback.

**New here?** [`docs/gdd/agent-training.md`](../../docs/gdd/agent-training.md) is the user-friendly companion that covers why you'll see deny output early in a session, why the discipline doesn't double API cost, and how to handle the "this legit command got denied" case. This README is the technical spec — what each tier checks, the audit log format, registration, and troubleshooting.

## Shipped hooks

### `gdd-allowlist-bridge.sh` (PreToolUse on Bash, by default)

Fires before every Bash tool call. Three tiers of decision:

1. **Deny shell composition** (`&&`, `||`, `;`, pipes, command substitution, redirects) with a corrective message that tells the agent how to retry. Trains the agent to use separate tool calls and native `ws` flags (`--limit`, `--compact`, `--output`) instead of shell composition.
2. **Allow** anything matching `permissions.allow` patterns in `.claude/settings.json` — the hook normalizes both the command and the pattern so bare `ws status` and verbose `bash scripts/ws status` both match a single pattern in either style.
3. **Allow** anything matching a `safe-bash-extras` file (project or user — see below). Per-machine personal extras for tools you trust on your laptop without committing them to the project config.

Logs allow/deny decisions to `~/.claude/hook-audit.log` with timestamps so you can review what the hook is doing. Passthroughs are not logged.

The script itself also understands the `PermissionRequest` event and the `Edit` / `Write` tools — those code paths are dormant under the default registration and activate only when you wire them up. See [Optional: PermissionRequest extension](#optional-permissionrequest-extension) below.

## Adding a safe command (per-machine extras)

You can declare additional commands as auto-allowed without editing the committed `settings.json`. Two locations, both optional:

| Path | Scope | Tracked in git? |
|---|---|---|
| `<project>/.claude/hooks/safe-bash-extras` | This project, this machine | **No** (gitignored) |
| `~/.claude/hooks/safe-bash-extras` | All projects, this machine | (Your user dir, not in any repo) |

The hook reads both if present. To set up the project-level one, copy [`safe-bash-extras.example`](safe-bash-extras.example) to `safe-bash-extras` (drop the `.example` suffix) in this same directory and edit. The example file documents the format with annotated entries.

**Important:** the safety reasoning of every pattern below depends on the hook's Tier 1 still being active. Removing the hook OR disabling Tier 1 would change the calculus of every entry. Treat changes to the extras file with the same care as changes to a sudoers config.

## Optional: PermissionRequest extension

Power-user opt-in. Wires the same `gdd-allowlist-bridge.sh` script to a second hook event — `PermissionRequest` — and broadens its matcher to also cover the `Edit` and `Write` tools. Net effect:

- **Scratch-dir writes stop prompting.** Edits and writes under `.tmp/`, `.commits/`, `.crs/`, `.issues/`, and `.outputs/` (the "Workspace-local scratch" section of [`.gitignore`](../../.gitignore)) auto-allow. Useful when you're drafting commit bodies, CR templates, and capture files all day — those routine flows otherwise can generate a steady drip of approve prompts.
- **Bash allowlist matches double-cover at the prompt layer.** Anything your settings.json `allow` or `safe-bash-extras` would have allowed at `PreToolUse` also gets approved at `PermissionRequest`, which can help in some configurations - largely intended to let the GDD extensions be good citizens in otherwise constrained settings.

This isn't enabled by default because (a) `PermissionRequest` is a different threat-model surface than `PreToolUse` — auto-allowing writes into a directory list is a stronger trust grant than auto-allowing read-shaped Bash patterns, and (b) the value is mostly ergonomic, so it's better off opt-in than imposed. 

It still includes the *extra* and sometimes more severe blocks that GDD implements to teach the agent not to let commands be chained at all, favoring deterministic scripts and temporary files that are more auditable than massive commands dumping to a simple point-in-time approve prompt.

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
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gdd-allowlist-bridge.sh\""
          }
        ]
      }
    ]
  }
}
```

You may also want a `safe-bash-extras` of your own (copy from `safe-bash-extras.example`) — the PermissionRequest hook reads the same extras file the PreToolUse hook does. Changes take effect on the next session (or sometimes mid-session — Claude Code may reload settings.json on edit).

### Verifying it's live

Ask your agent to run any safe scratch-dir write and check `~/.claude/hook-audit.log`. A scratch-dir hit logs as e.g. `ALLOW [PreToolUse] (scratch-dir: .tmp/): Write .../marker.txt` — the `[PreToolUse]` / `[PermissionRequest]` tag in the entry tells you which event fired.

### Adding more scratch dirs

The dir list is hardcoded in `gdd-allowlist-bridge.sh`'s tool-routing block. Keep it in lockstep with the "Workspace-local scratch" section of [`.gitignore`](../../.gitignore) — anything gitignored as scratch should be safe to auto-allow, and vice versa.

## Disabling the hook

If a session needs the hook off (corporate scanner says no, you want Claude's default flow, the hook is misbehaving and you need to work around it), set `WS_HOOK_DISABLE=1` in your shell, `.env`, or shell profile. The hook reads the variable on every invocation and exits as a passthrough when it's set.

```bash
export WS_HOOK_DISABLE=1
```

This bypass is per-user / per-machine and doesn't require editing the committed `settings.json`. To re-enable later, unset the variable.

## What if a Bash call stalls?

Earlier versions of this hook had an infinite-loop bug on Windows-style paths (the upward-walk for `.claude/settings.json` didn't terminate when `dirname` started returning `.` repeatedly). The current script has a `prev == dir` guard that ensures the loop exits at the filesystem root regardless of platform. Both `tests/hook/allowlist-bridge.bats` and `tests/ws-smoke/read-only.bats` include timeout assertions that fail loudly if a regression introduces a hang.

If you encounter a stall anyway:

1. Set `WS_HOOK_DISABLE=1` to unblock yourself
2. Capture the audit log around the stall (`~/.claude/hook-audit.log`) and file a yggdrasil issue
3. As a workaround until fixed, remove the `hooks` block from your local `.claude/settings.local.json` (overrides the committed `settings.json` for your machine)

## Audit log

`~/.claude/hook-audit.log` records every allow/deny with a timestamp and the reason (which tier / which pattern fired). Worth a periodic skim — anything you didn't expect to be auto-approved is a pattern to narrow; anything you keep getting prompted for despite expecting auto-approval is a missing entry to add.

The log is append-only and per-user. The hook doesn't rotate it; if it grows, `truncate -s 0 ~/.claude/hook-audit.log` resets it.
