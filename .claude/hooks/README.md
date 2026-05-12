# Claude Code hooks shipped with yggdrasil

This directory contains hook scripts that fire during Claude Code sessions in this workspace. They run automatically — no action needed once the workspace is cloned and Claude Code is started in it.

The hooks are registered in [`../settings.json`](../settings.json) under `hooks.PreToolUse`. They're meant to make agent behavior more predictable and to teach safer command patterns by giving immediate corrective feedback.

## Shipped hooks

### `gdd-allowlist-bridge.sh` (PreToolUse on Bash)

Fires before every Bash tool call. Three tiers of decision:

1. **Deny shell composition** (`&&`, `||`, `;`, pipes, command substitution, redirects) with a corrective message that tells the agent how to retry. Trains the agent to use separate tool calls and native `ws` flags (`--limit`, `--compact`, `--output`) instead of shell composition.
2. **Allow** anything matching `permissions.allow` patterns in `.claude/settings.json` — the hook normalizes both the command and the pattern so bare `ws status` and verbose `bash scripts/ws status` both match a single pattern in either style.
3. **Allow** anything matching a `safe-bash-extras` file (project or user — see below). Per-machine personal extras for tools you trust on your laptop without committing them to the project config.

Logs allow/deny decisions to `~/.claude/hook-audit.log` with timestamps so you can review what the hook is doing. Passthroughs are not logged.

## Adding a safe command (per-machine extras)

You can declare additional commands as auto-allowed without editing the committed `settings.json`. Two locations, both optional:

| Path | Scope | Tracked in git? |
|---|---|---|
| `<project>/.claude/hooks/safe-bash-extras` | This project, this machine | **No** (gitignored) |
| `~/.claude/hooks/safe-bash-extras` | All projects, this machine | (Your user dir, not in any repo) |

The hook reads both if present. To set up the project-level one, copy [`safe-bash-extras.example`](safe-bash-extras.example) to `safe-bash-extras` (drop the `.example` suffix) in this same directory and edit. The example file documents the format with annotated entries.

**Important:** the safety reasoning of every pattern below depends on the hook's Tier 1 still being active. Removing the hook OR disabling Tier 1 would change the calculus of every entry. Treat changes to the extras file with the same care as changes to a sudoers config.

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
