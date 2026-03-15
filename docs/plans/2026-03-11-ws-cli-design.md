# Unified Workspace CLI (`ws`) — Design Spec

**Date:** 2026-03-11
**Status:** Draft
**Scope:** Yggdrasil workspace tooling

---

## Problem

AI agents and human developers both struggle with directory context in the
yggdrasil multi-repo workspace. Agents lose cwd between shell invocations.
Humans must remember paths. Existing `ws-*.sh` scripts work well individually
but lack a unified entry point.

Additionally, repeated manual workarounds (cwd switching, multi-step command
sequences, manual formatting) accumulate across sessions with no mechanism to
detect and address them.

## Solution

Two deliverables:

1. **`scripts/ws`** — A unified CLI entry point that dispatches subcommands and
   provides component-aware command execution.
2. **`.agent/skills/workflow-auditor/SKILL.md`** — A skill for detecting
   repeated workflow patterns and proposing utility scripts.

---

## Part 1: The `ws` CLI

### Architecture

A single `scripts/ws` bash script that:
- Dispatches to existing `ws-*.sh` scripts as subcommands
- Adds `exec` for running arbitrary commands in component directories
- Validates input to prevent injection
- Works on macOS (Bash 3.2), Linux, and Windows (Git Bash)

```
scripts/
  ws                  # Entry point (no .sh extension)
  ws-clone.sh         # Existing (unchanged, called by ws)
  ws-list.sh          # Existing (unchanged)
  ws-status.sh        # Existing (unchanged)
  ws-pull.sh          # Existing (unchanged)
  ws-resolve.sh       # Existing (unchanged)
  ws-vscode.sh        # Existing (unchanged)
  git-push.sh         # Existing (unchanged)
  gh-issue.sh         # Existing (unchanged)
```

### Subcommands

| Command | Maps to | Description |
|---|---|---|
| `ws list` | `ws-list.sh` | List ecosystem components |
| `ws status [--verbose]` | `ws-status.sh` | Git status across workspace |
| `ws clone [comp]` | `ws-clone.sh` | Clone components |
| `ws pull` | `ws-pull.sh` | Pull all components |
| `ws resolve` | `ws-resolve.sh` | Generate ArgoCD apps |
| `ws vscode` | `ws-vscode.sh` | Generate VS Code workspace |
| `ws push [comp] [branch]` | `git-push.sh` (in component dir) | Push component or yggdrasil |
| `ws issue <repo> <title> <label> <bodyfile>` | `gh-issue.sh` | File GitHub issue |
| `ws exec <comp> <cmd...>` | `cd components/<comp> && cmd` | Run command in component dir |
| `ws help` | (built-in) | Show available subcommands |

### The `exec` subcommand

Resolves the component directory from `ecosystem.yaml` and runs the command
there. This is the primary solution for cwd drift.

```bash
# Agent usage (always works, no setup):
bash scripts/ws exec ymir make test
bash scripts/ws exec ymir git status
bash scripts/ws exec ymir uv run python -m ymir_gateway

# Human usage (after adding scripts/ to PATH):
ws exec ymir make test
```

Special component names:
- `.` or `root` — run in yggdrasil root directory

Validation:
- Component name must match a key in `ecosystem.yaml`
- Component must be cloned locally (directory exists)
- Error message suggests `ws clone <comp>` if not found

### Dispatch mechanism

All subcommands that target a component directory (`exec`, `push`) resolve
the path first, then `cd` into it before calling the underlying script or
command:

```bash
target="$COMPONENTS_DIR/$component"
cd "$target" && "$@"           # for exec
cd "$target" && bash "$SCRIPT_DIR/git-push.sh" "$branch"  # for push
```

This is necessary because `git-push.sh` runs `git rev-parse` and
`git remote get-url` against cwd. The dispatcher handles the `cd`; existing
scripts remain unchanged.

Note: Shell operators (`&&`, `|`, `;`) in `ws exec` arguments apply at the
outer shell level, not inside the component directory. To chain commands
inside the component, use: `bash scripts/ws exec ymir bash -c "cmd1 && cmd2"`.

### The `push` subcommand

Convenience wrapper around `git-push.sh` with component awareness:

```bash
# Push ymir (resolves dir, sources .env, uses HTTPS):
bash scripts/ws push ymir

# Push yggdrasil itself:
bash scripts/ws push .

# Push specific branch:
bash scripts/ws push ymir feat/my-feature
```

### Security

The `ws` script handles untrusted input (component names, commands). Rules:

1. **Whitelist component names** — validate against `ecosystem.yaml` keys.
   Reject anything that doesn't match `^[a-z][a-z0-9-]*$`.
2. **Never `eval`** — use `"$@"` for command passthrough, preserving argument
   boundaries. Shell metacharacters in arguments are not re-interpreted.
3. **Don't source `.env` in the dispatcher** — only individual scripts
   (`git-push.sh`, `gh-issue.sh`) source tokens when they need them.
4. **Quote everything** — `"$target"`, `"$@"`, `"$ROOT_DIR"`.
5. **Check dependencies early** — the dispatcher validates `yq` is available
   before attempting component name resolution.

```bash
# DANGEROUS — never do this:
eval "cd $target && $cmd"

# SAFE — argument boundaries preserved:
cd "$target" && "$@"
```

### Cross-platform compatibility

- **Bash 3.2 compatible** — no associative arrays, no `${var,,}`,
  no `readarray`/`mapfile`, no `|&`
- **Path resolution** via `cd/pwd` pattern (not `readlink -f` or `realpath`)
- **Forward slashes only** — already standard in the workspace
- **`.gitattributes`** entry: `scripts/ws text eol=lf` (no extension, needs explicit rule)
- **`#!/usr/bin/env bash`** shebang for portability

### CLAUDE.md integration

Add to Session Conventions in `yggdrasil/CLAUDE.md`:

```markdown
- **Workspace CLI:** Always use `bash scripts/ws <cmd>` for workspace
  operations. Use `bash scripts/ws exec <component> <cmd>` to run commands
  in component directories — never manually `cd` to components.
  Available: `ws list`, `ws status`, `ws clone`, `ws pull`, `ws push`,
  `ws issue`, `ws exec`, `ws help`.
```

On first use of `ws` in a session, briefly note:

> "Using the workspace CLI (`scripts/ws`). Run `ws help` in your terminal
> for available commands. To use shorthand, add
> `export PATH="<yggdrasil>/scripts:$PATH"` to your shell profile."

### Human documentation

Add a section to `docs/dev-setup.md` covering:
- What `ws` does and all subcommands
- Optional PATH setup for shell profile
- Examples for common operations

---

## Part 2: Workflow Auditor Skill

### Location

`.agent/skills/workflow-auditor/SKILL.md`

### Purpose

Detect repeated manual workarounds in a session and propose workspace utility
scripts or workflow improvements.

### Trigger conditions

- **Self-trigger:** When the agent notices 3+ instances of the same awkward
  pattern in a session (repeated `cd`, manual JSON formatting, same multi-step
  command sequence, retried commands with the same fix)
- **User-invoked:** `/workflow-auditor` or "check for workflow patterns"
- **Session wrap-up:** When a session is ending, review the conversation for
  repeated patterns worth addressing

### What it analyzes

- Commands run in the session (especially repeated `cd`, multi-step sequences)
- Manual formatting or transformation that could be scripted
- Error-recovery patterns (same fix applied multiple times)
- Commands that needed workarounds for cwd, PATH, or environment issues
- Patterns that span multiple tool calls achieving one logical operation

### Output format

For each detected pattern:

1. **Pattern name** — short description (e.g. "repeated cwd switching to ymir")
2. **Evidence** — the 3+ instances observed
3. **Proposed fix** — a new `ws` subcommand, script, or CLAUDE.md instruction
4. **Effort** — trivial / small / medium
5. **Recommendation** — implement now, file as issue, or note for later

### What it does NOT do

- Does not auto-create scripts (proposes them, human decides)
- Does not modify CLAUDE.md or other config directly
- Does not analyze other sessions' transcripts (only current context)
- Does not propose changes without evidence (minimum 3 instances)

### Future extension

When tooling exists to read session logs, the skill could operate in "audit
mode" — scanning multiple past sessions for cross-session patterns. For now,
it works within the current conversation context only.

---

## Design decisions

| Decision | Choice | Rationale |
|---|---|---|
| Single `ws` vs separate scripts | Unified `ws` with subcommands | Discoverable, shorter commands, one thing to learn |
| `ws` file extension | No `.sh` extension | Cleaner invocation: `ws help` not `ws.sh help` |
| Existing scripts | Keep unchanged, called internally | No breakage, incremental adoption |
| exec safety | `"$@"` passthrough, never `eval` | Prevents command injection |
| Component validation | Whitelist from `ecosystem.yaml` | Prevents path traversal |
| Bash version target | 3.2+ | macOS ships with 3.2 |
| Agent invocation | `bash scripts/ws <cmd>` always | No PATH dependency, works without setup |
| Human invocation | Optional PATH addition | Opt-in convenience, documented in dev-setup |
| Pattern detection | Skill, not always-on | Avoids noise, invoked when relevant |
