# Claude Code hooks shipped with yggdrasil

This directory contains a hook script that fires during Claude Code sessions in this workspace. The main hook event fires automatically — no action needed once the workspace is cloned and Claude Code is started in it. It is registered in [`../settings.json`](../settings.json) under `hooks.PreToolUse` and is meant to make agent behavior more predictable and to teach safer command patterns by giving immediate corrective feedback.

**Codex uses a separate bridge, not this monolith.** The first focused Codex hook at [`.codex/hooks/gdd-k8s-hook.sh`](../../.codex/hooks/gdd-k8s-hook.sh) handles only the guarded-Kubernetes mentoring path and reuses `scripts/ws-k8s-guard.sh`; safe calls defer to normal Codex sandbox and approval routing. The [Codex project configuration](../../.codex/README.md) covers trust and troubleshooting. The [cross-harness design](../../docs/plans/2026-06-29-codex-k8s-hook-design.md) maps each remaining Claude hook piece to a Codex hook, rules or permission configuration, or a future platform-neutral policy engine.

**New here?** [`docs/gdd/agent-training.md`](../../docs/gdd/agent-training.md) is the user-friendly companion that covers why you'll see deny output early in a session, why the discipline doesn't double API cost, and how to handle the "this legit command got denied" case. This README is the technical spec — what each tier checks, the audit log format, registration, and troubleshooting.

## PreToolUse hook 

Fires before every Bash tool call. Five general decision tiers plus a Kubernetes write safety floor, then a passthrough:

1. **Deny shell composition** (`&&`, `||`, `;`, pipes, command substitution, redirects) with a corrective message that tells the agent how to retry. Trains the agent to use separate tool calls and native `ws` flags (`--limit`, `--compact`, `--output`) instead of shell composition.
2. **Deny raw `git commit` / `git push` / `gh pr create`** (and any other entry in the `[redirect-commands]` section of `hook-rules`) with a corrective message pointing at the right `ws` subcommand. A session-scoped bypass marker — written by `ws hook-bypass <slug>` after a human-approved ask prompt — overrides the deny for that slug. See [Redirect tier and bypass](#redirect-tier-and-bypass) below.
3. **Classify Kubernetes writes before scope and allowlist handling.** With no scope, a read passes onward and a write emits `ask`; a blanket local `Bash(kubectl:*)` allow therefore cannot suppress confirmation. With a scope, the existing redirect tier adds context and namespace enforcement. Common transparent forms such as `env KUBECONFIG=… kubectl`, `/usr/bin/kubectl`, `bash -x script.sh`, relative executable scripts, and literal `bash -c` kubectl calls are normalized before evaluation. A matching audited `k8s` bypass marker lifts both the unscoped write floor and raw-command redirect for that session, while an armed `ws k8s` wrapper remains scope-bounded.
4. **Ask** (force a permission prompt) for anything matching a glob in the `[ask-commands]` section of `hook-rules` (committed baseline) or `hook-rules.local` (per-machine). The hook emits `permissionDecision: "ask"`, which surfaces a human-facing prompt regardless of the session permission mode — including `acceptEdits` and `bypassPermissions`. The command is NOT blocked; once the human approves it runs normally. This tier exists specifically to intercept destructive commands like `rm -rf` and arbitrary-execution escape hatches like `ws exec` before they can auto-run silently.
5. **Allow** anything matching `permissions.allow` patterns in `.claude/settings.json` — the hook normalizes both the command and the pattern so bare `ws status` and verbose `bash scripts/ws status` both match a single pattern in either style.
6. **Allow** anything matching a glob in the `[allow-extras]` section of `hook-rules.local`. Per-machine personal extras for tools you trust on your laptop without committing them to the project config.
7. **Pass** everything else goes to default behavior based on other config.

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

**`[ask-commands]`** — glob patterns for destructive or arbitrary-execution Bash commands that should always produce a permission prompt, regardless of session mode. A match in either file triggers Tier 3 (ask) not a deny — the human approves and the command runs. `hook-rules.local` entries are additive-only: you can make more commands prompt, but you cannot remove a pattern committed in `hook-rules`. This is intentional — per-machine config can tighten the safety floor, never loosen it.

**`[adapter-redirect-commands]`** — Tier 3 patterns for raw test/lint/build runners. The hook resolves the component from `$cwd` and the active realm's adapter file; wired adapters get a deny-with-bypass, missing adapters get a one-line stderr nudge and fall through. See `[adapter-redirect-commands]` in `hook-rules` for the format.

**`[allow-extras]`** — personal Bash glob patterns auto-allowed on this machine without prompting (Tier 6). Only valid in `hook-rules.local`, never in the committed baseline. An entry here will not win over an "ask command" entry.

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
| `git-push` | `git push*` | `ws push <comp> [branch]` — picks the fork remote from `identity.forkRemote`, sets upstream on first push |
| `gh-pr-create` | `gh pr create*` | `ws cr <comp> <title> <bodyfile>` — bodyfile-driven, applies identity substitutions |

A deny here is a *training* signal, not a safety floor (that's Tier 4 ask). The hook trusts the workspace's own `ws` wrappers to do the right thing — attribution, remote selection, the right token. When a legitimate edge case exists (`ws` doesn't yet support what you need), the agent can request a bypass:

1. Agent hits the deny; corrective message names `ws hook-bypass <slug>` as the escape hatch.
2. Agent runs `ws hook-bypass <slug> --reason "<why>"`. The subcommand is on the ask-list, so the human gets a permission prompt — tailored to name the slug being bypassed and surface the `--reason`, so the human sees what they're approving rather than a generic "destructive command" line.
3. Human approves; the script writes `.tmp/hook-bypass/<slug>.bypass` keyed to the Claude Code session id (`$CLAUDE_CODE_SESSION_ID`).
4. Agent retries the raw command; the hook finds the marker, matches session_id, and emits an allow with audit `BYPASS-ALLOW [<slug>] reason="<text>" [PreToolUse]: <cmd>`.
5. The marker is honored for the rest of the session. Next session's `CLAUDE_CODE_SESSION_ID` differs, so the marker is stale; `ws clean` sweeps `.tmp/` whenever you want a clean slate.

The recurring-bypass pattern — same slug bypassed every session — is a signal that the corresponding `ws` subcommand needs to grow that capability. Periodic `grep BYPASS-ALLOW ~/.claude/hook-audit.log` surfaces it.

**Adding a new redirect.** Append a row to the `[redirect-commands]` section of `.claude/hooks/hook-rules`: `<slug> | <pattern> | <suggestion>`. The slug must match `^[a-z][a-z0-9-]*$` (start with a letter so the `ws hook-bypass [a-z]*` ask-pattern always catches a slug invocation). The pattern is a bash glob. The suggestion is free text (column 3, may contain pipes — parsing splits on the first two ` | ` only). The new slug is automatically bypassable via `ws hook-bypass <new-slug>`; no script change needed.

### PowerShell: blocked by default

The hook also registers on the `PowerShell` tool (see `settings.json`) and denies every invocation rather than porting the Bash tiers to PowerShell grammar. The rationale: the `ws` CLI + Bash tool are the sanctioned surface, agents observably drift into PowerShell once it starts "working," and a granular PowerShell tier would need its own grammar — PS 5.1 has no `&&`/`||`, so `;` is its *only* statement separator, and a naive port of the Tier 1 composition deny would make the tool unusable rather than safe.

Two exceptions:

- **Component kuttl test wrappers auto-allow.** kuttl ships no native Windows binary, so components wrap it in Docker via `test.ps1` (mimir, nidavellir). The allowed shapes are `./test.ps1 [args]` and `Set-Location <dir>; ./test.ps1 [args]` (also `cd`/`.\` forms), with both segments restricted to composition-free characters — no `;` chains beyond the single prefix, no `$()`/backticks/script blocks in the path or args. As everywhere else, the hook audits the invocation string only; what a committed script does internally is reviewed at the script's own PR, not at invocation time.
- **`ws hook-bypass powershell`** grants a session-scoped raw-PowerShell bypass through the same human-gated ask flow as the Tier 2/3 slugs (it's a built-in slug in `ws-hook-bypass.sh`, not a `hook-rules` row). The intended use is the rare case where PowerShell is genuinely the right tool — e.g. piping test payloads into *this hook* while debugging it, which Bash Tier 1 redirection rules block by design.

`WS_HOOK_DISABLE=1` disables this branch along with everything else.

## Optional: PermissionRequest hook

Power-user opt-in. Wires the same `gdd-permission-hook.sh` script to a second hook event — `PermissionRequest` — and broadens its matcher to also cover the `Edit` and `Write` tools. Net effect:

- **Scratch-dir writes stop prompting.** Edits and writes specifically under `.tmp/`, `.commits/`, `.crs/`, `.issues/`, and `.outputs/` (the "Workspace-local scratch" section of [`.gitignore`](../../.gitignore)) auto-allow. Useful when you're drafting commit bodies, CR templates, and capture files all day — those routine flows otherwise can generate a steady drip of approve prompts.
- **Bash allowlist matches double-cover at the prompt layer.** Anything your `settings.json` `allow` or `hook-rules.local` `[allow-extras]` would have allowed at `PreToolUse` also gets approved at `PermissionRequest`, which can help in some configurations — largely intended to let the GDD extensions be good citizens in otherwise constrained settings.

This isn't enabled by default because (a) `PermissionRequest` is a different threat-model surface than `PreToolUse` — auto-allowing writes into a directory list is a stronger trust grant than auto-allowing read-shaped Bash patterns, and (b) the value is mostly ergonomic, so it's better off opt-in than imposed. 

**Interaction with the redirect bypass.** When this optional hook is enabled, `.tmp/` is among the auto-allowed scratch dirs — so an agent could in principle write a bypass marker (`.tmp/hook-bypass/<slug>.bypass`) with the Write tool directly, skipping `ws hook-bypass` and therefore the ask-prompt. That sidesteps the human gate for the Tier 2 redirect deny. This is consistent with the redirect tier's stated threat model (agent *drift*, not an adversarial agent deliberately crafting marker files) — and an agent in `acceptEdits` can already write into `.tmp/` regardless of this hook — but operators who enable the PermissionRequest extension and want the bypass to remain strictly human-gated should be aware of it.

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
