# Workspace CLI (`ws`) — Contributor Guide

How to add new subcommands, classify their permission level, and maintain
the security model.

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
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode` |
| **Side-effect** | User's choice (ask) | No | `push`, `pr`, `issue` |
| **Arbitrary execution** | Never (deny) | Yes | `exec` |

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
      "Bash(bash scripts/ws exec *)"
    ],
    "allow": [
      "Bash(bash scripts/ws mycommand)",
      "Bash(bash scripts/ws mycommand *)"
    ]
  }
}
```

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

### Why `exec` is permanently denied

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

## Finding Patterns Worth Scripting

Use the `workflow-auditor` skill (`.agent/skills/workflow-auditor/SKILL.md`)
to detect repeated manual workarounds that could become new subcommands.
The skill triggers on 3+ instances of the same awkward pattern in a session.

Common progression: manual workaround → noticed by auditor → proposed as
script → reviewed → added to `ws` → classified and permissioned.
