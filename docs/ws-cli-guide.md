# Workspace CLI (`ws`) — Contributor Guide

How to add new subcommands, classify their permission level, and maintain
the security model.

## Purpose

While many utility frameworks exist to provide convenience for a human user, this setup is also meant to simplify commands in a flexible workspace _for AI agents_ resulting in clearer commands that can be auto-approved more meaningfully and safely.

Over time as more common patterns are detected they can result in new convenience scripts for better overall visibility and value in the utility framework. This is made available directly as an agent skill, auto-enabled at least for Claude.

## Architecture

`scripts/ws` is a bash dispatcher. Each subcommand either:
- **Delegates** to an existing `scripts/*.sh` script (e.g. `ws list` → `ws-list.sh`)
- **Wraps** a script with component-directory resolution (e.g. `ws push ymir` → `cd components/ymir && git-push.sh`)

The dispatcher handles argument parsing, component validation, and help text.
Existing scripts remain standalone and unchanged.

## Adding a New Subcommand

### 1. Write the script (or identify an existing one)

Follow the existing pattern:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
```

### 2. Add to the dispatcher

In `scripts/ws`, add three things:

**a) Help text** — add a `#` comment line in the header block (between
`# Commands:` and the blank line):

```bash
#   mycommand [args]  Description of what it does
```

**b) Case entry** — add before the `*)` catch-all:

```bash
    mycommand)
        bash "$SCRIPT_DIR/my-script.sh" "$@"
        ;;
```

Or if it needs component resolution:

```bash
    mycommand)
        ws_mycommand "$@"
        ;;
```

**c) Function** (if component-aware) — add with the other `ws_*` functions:

```bash
ws_mycommand() {
    local comp="${1:-.}"
    shift
    ws_validate_component "$comp"
    cd "$COMPONENT_DIR" && bash "$SCRIPT_DIR/my-script.sh" "$@"
}
```

### 3. Classify its permission level

Every subcommand falls into one of three tiers:

| Tier | Auto-approve? | Deny rule? | Examples |
|------|---------------|------------|----------|
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode`, `test`, `review` (listing/status), `log`, `clean`, `overlay list`, `overlay init`, `actions` |
| **Side-effect** | User's choice (ask) | No | `push`, `push --force`, `pr`, `issue`, `commit`, `review --resolve*` |
| **Arbitrary execution** | Always asks (deny) | Yes | `exec` |

**Safe:** Read-only or creates local files only. Add to the `allow` list in
`.claude/settings.json`.

**Side-effect:** Modifies external state (pushes code, creates issues/PRs,
sends messages). Prompts by default but users *can* whitelist for bulk
operations. Do NOT add a deny rule — let users decide.

**Arbitrary execution:** Takes user-provided commands and runs them. Must have
a deny rule in `.claude/settings.json`. Currently only `exec` is in this tier.

### 4. Update `.claude/settings.json`

```json
{
  "permissions": {
    "deny": [
      "Bash(bash scripts/ws exec *)",
      "Bash(bash scripts/ws exec * *)",
      "Bash(bash scripts/ws exec * * *)"
    ],
    "allow": [
      "Bash(bash scripts/ws mycommand)",
      "Bash(bash scripts/ws mycommand *)"
    ]
  }
}
```

> **Note:** Deny patterns shown above are truncated. The actual
> `.claude/settings.json` includes patterns for all supported arities
> (up to 7 wildcards). Always check the repo's committed file for the
> full set.

### 5. Update docs

- `scripts/ws` help text (already done in step 2a)
- `CLAUDE.md` — add to the Available commands list if it's a common command
- `docs/dev-setup.md` — add to the commands table
- This file — update the tier table above if adding a new tier

## Security Rules

These apply to all subcommands:

1. **Never `eval`** — use `"$@"` for command passthrough
2. **Validate component names** — use `ws_validate_component`, which checks
   the regex `^[a-z][a-z0-9-]*$` and verifies against `ecosystem.yaml`
3. **Quote everything** — `"$target"`, `"$@"`, `"$ROOT_DIR"`
4. **Don't source `.env` in the dispatcher** — only in scripts that need tokens
5. **Bash 3.2 compatible** — no associative arrays, no `${var,,}`, no `readarray`

### Why `exec` always requires human approval

`ws exec <comp> <cmd...>` runs **arbitrary commands**. If it were
auto-approvable, a compromised prompt or injected instruction could run
anything on the system. The deny rule in `.claude/settings.json` ensures
every `exec` invocation requires human approval, regardless of user settings.

### Component name validation

Component names pass through `yq` expressions (`.components.$name`). The
regex `^[a-z][a-z0-9-]*$` prevents:
- Path traversal (`../../etc`)
- Shell metacharacters (`;`, `|`, `$`, etc.)
- Newline injection (bash `=~` matches full string, not per-line)
- yq expression injection (no dots, brackets, etc.)

### Forking and renaming

The workspace name `yggdrasil` appears as a special case in `ws_validate_component`
(one string comparison) and throughout documentation. To fork and rename:

1. Change the `"yggdrasil"` check in `scripts/ws` → `ws_validate_component()`
2. Search docs for `yggdrasil` and update narrative references
3. Update the `siliconsaga` remote name and `SiliconSaga/` org prefix in
   `scripts/git-push.sh`, `scripts/git-pr.sh`, and `scripts/gh-issue.sh`
4. Update the domain in `ecosystem.yaml` (currently `cmdbee.org` via Nordri)
5. Update `.mcp.json` if you change component names that host MCP servers

The name is intentionally not stored in a variable — it's a single check in a
security-sensitive function, and indirection would add complexity for a one-time
operation.

## Local Permission Overrides for Bulk Operations

Side-effect commands (`push`, `pr`, `issue`, `commit`) prompt for approval by default.
For bulk operations (filing multiple issues, pushing several components),
you can auto-approve them in your local settings.

**Setup:** Copy the template and add bulk patterns:

```bash
cp .claude/settings.local.example.json .claude/settings.local.json
```

Then add the patterns you want to auto-approve. In Claude Code permission
rules, each `*` matches **one argument** (not multiple). So multi-argument
commands need one `*` per argument:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash scripts/ws push * *)",
      "Bash(bash scripts/ws pr * * *)",
      "Bash(bash scripts/ws issue * * * *)",
      "Bash(bash scripts/ws commit * *)",
      "Bash(bash scripts/ws commit * * *)"
    ]
  }
}
```

| Pattern | Matches | Example |
|---|---|---|
| `Bash(bash scripts/ws push *)` | Push with component only | `ws push ymir` |
| `Bash(bash scripts/ws push * *)` | Push with component + branch | `ws push ymir feat/foo` |
| `Bash(bash scripts/ws pr * * *)` | PR with component + title + bodyfile | `ws pr ymir "feat: add X" .prs/x.md` |
| `Bash(bash scripts/ws issue * * * *)` | Issue with all 4 args | `ws issue ymir "fix: Y" bug .issues/y.md` |
| `Bash(bash scripts/ws commit * *)` | Commit with message only | `ws commit ymir "fix: race"` |
| `Bash(bash scripts/ws commit * * *)` | Commit with message + bodyfile | `ws commit ymir "feat: X" .commits/x.md` |

**Note:** `ws exec` **always requires human approval** — the project-level
deny rule in `.claude/settings.json` cannot be overridden by local settings.
See "Why exec always requires human approval" above.

## Finding Patterns Worth Scripting

Use the `workflow-auditor` skill (`.agent/skills/workflow-auditor/SKILL.md`)
to detect repeated manual workarounds that could become new subcommands.
The skill triggers on 3+ instances of the same awkward pattern in a session.

Common progression: manual workaround → noticed by auditor → proposed as
script → reviewed → added to `ws` → classified and permissioned.
