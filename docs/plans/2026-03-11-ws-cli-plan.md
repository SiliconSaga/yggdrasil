# Unified Workspace CLI (`ws`) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a unified `scripts/ws` CLI that wraps existing workspace scripts as subcommands, adds component-aware `exec` for cwd-independent command execution, and build a gdd-workflow-audit skill for detecting repeated patterns.

**Architecture:** Single bash dispatcher script (`scripts/ws`) that resolves ROOT_DIR from its own location, validates component names against `ecosystem.yaml`, and delegates to existing `ws-*.sh` scripts or executes commands in component directories via `cd` + `"$@"`.

**Tech Stack:** Bash 3.2+ (macOS compatible), yq v4, existing ws-*.sh scripts

**Spec:** `docs/plans/2026-03-11-ws-cli-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/ws` | Create | Unified CLI entry point — dispatch, validation, exec |
| `.gitattributes` | Modify | Add `scripts/ws text eol=lf` rule |
| `CLAUDE.md` | Modify | Add Workspace CLI instruction to Session Conventions |
| `docs/dev-setup.md` | Modify | Add ws CLI section for humans |
| `.agent/skills/gdd-workflow-audit/SKILL.md` | Create | Pattern detection skill |

---

## Chunk 1: The `ws` script — core dispatcher and exec

### Task 1: Create `scripts/ws` with help and version

**Files:**
- Create: `scripts/ws`

- [ ] **Step 1: Create the script with shebang, ROOT_DIR resolution, and help**

```bash
#!/usr/bin/env bash
# ws — Unified workspace CLI for yggdrasil
#
# Usage:
#   ws <command> [args...]
#   ws help
#
# Commands:
#   list              List ecosystem components
#   status [--verbose] Git status across workspace
#   clone [comp|--all] Clone components
#   pull [comp]       Pull all or one component
#   resolve           Generate ArgoCD Applications
#   vscode            Generate VS Code workspace file
#   push [comp] [branch] Push via HTTPS (sources .env)
#   issue <repo> <title> <label> <bodyfile> File GitHub issue
#   exec <comp> <cmd...> Run a command in a component directory
#   help              Show this help message
#
# For shorthand access, add to your shell profile:
#   export PATH="<yggdrasil>/scripts:$PATH"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

ws_help() {
    sed -n '/^# Usage:/,/^[^#]/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
}

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    help|--help|-h)
        ws_help
        ;;
    *)
        echo "ERROR: Unknown command '$COMMAND'. Run 'ws help' for usage." >&2
        exit 1
        ;;
esac
```

- [ ] **Step 2: Test the help output**

Run: `bash scripts/ws help`
Expected: Prints usage text listing all commands.

Run: `bash scripts/ws`
Expected: Same help output (default command).

Run: `bash scripts/ws nonsense`
Expected: `ERROR: Unknown command 'nonsense'. Run 'ws help' for usage.`

- [ ] **Step 3: Commit**

```bash
git add scripts/ws
git commit -m "feat(ws): add unified workspace CLI with help command"
```

---

### Task 2: Add passthrough subcommands (list, status, clone, pull, resolve, vscode)

**Files:**
- Modify: `scripts/ws`

- [ ] **Step 1: Add passthrough cases to the case statement**

Replace the `*)` catch-all section. Insert before it:

```bash
    list)
        bash "$SCRIPT_DIR/ws-list.sh" "$@"
        ;;
    status)
        bash "$SCRIPT_DIR/ws-status.sh" "$@"
        ;;
    clone)
        bash "$SCRIPT_DIR/ws-clone.sh" "$@"
        ;;
    pull)
        bash "$SCRIPT_DIR/ws-pull.sh" "$@"
        ;;
    resolve)
        bash "$SCRIPT_DIR/ws-resolve.sh" "$@"
        ;;
    vscode)
        bash "$SCRIPT_DIR/ws-vscode.sh" "$@"
        ;;
```

- [ ] **Step 2: Test passthrough commands**

Run: `bash scripts/ws list`
Expected: Same output as `bash scripts/ws-list.sh` — component table.

Run: `bash scripts/ws status`
Expected: Same output as `bash scripts/ws-status.sh` — git status per component.

- [ ] **Step 3: Commit**

```bash
git add scripts/ws
git commit -m "feat(ws): add passthrough subcommands for existing ws-* scripts"
```

---

### Task 3: Add component validation helper

**Files:**
- Modify: `scripts/ws`

- [ ] **Step 1: Add yq check and validation function after the variable declarations**

Insert after the `COMPONENTS_DIR=` line, before `ws_help()`:

```bash
# Validate a component name against ecosystem.yaml.
# Usage: ws_validate_component <name>
# Sets: COMPONENT_DIR to the resolved path
ws_validate_component() {
    local name="$1"

    # Allow "." and "root" as aliases for yggdrasil root
    if [[ "$name" == "." || "$name" == "root" ]]; then
        COMPONENT_DIR="$ROOT_DIR"
        return 0
    fi

    # Reject names that don't match safe pattern
    if ! echo "$name" | grep -qE '^[a-z][a-z0-9-]*$'; then
        echo "ERROR: Invalid component name '$name'. Must match [a-z][a-z0-9-]*." >&2
        exit 1
    fi

    # Check yq is available
    if ! command -v yq &>/dev/null; then
        echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
        exit 1
    fi

    # Check component exists in ecosystem.yaml
    local exists
    exists=$(yq ".components.$name // \"missing\"" "$ECOSYSTEM")
    if [[ "$exists" == "missing" ]]; then
        echo "ERROR: '$name' is not declared in ecosystem.yaml." >&2
        echo "  Run 'ws list' to see available components." >&2
        exit 1
    fi

    COMPONENT_DIR="$COMPONENTS_DIR/$name"

    # Check if cloned locally
    if [[ ! -d "$COMPONENT_DIR" ]]; then
        echo "ERROR: '$name' is not cloned locally." >&2
        echo "  Run 'ws clone $name' to clone it." >&2
        exit 1
    fi
}
```

- [ ] **Step 2: Test validation**

Run: `bash scripts/ws exec ymir echo hello`
Expected: Error (exec not wired yet), but this step just adds the helper.

Test the function directly:

Run: `bash -c 'source scripts/ws; ws_validate_component "ymir"'`

This won't work due to the `case` statement — skip this. Validation gets tested in Task 4.

- [ ] **Step 3: Commit**

```bash
git add scripts/ws
git commit -m "feat(ws): add component validation helper"
```

---

### Task 4: Add `exec` subcommand

**Files:**
- Modify: `scripts/ws`

- [ ] **Step 1: Add exec case to the case statement** (before the `*)` catch-all)

```bash
    exec)
        if [[ $# -lt 2 ]]; then
            echo "Usage: ws exec <component> <command...>" >&2
            exit 1
        fi
        local comp="$1"
        shift
        ws_validate_component "$comp"
        cd "$COMPONENT_DIR" && "$@"
        ;;
```

Note: `local` is not valid at the top level of a `case` in some Bash versions. Use a function instead. Replace the above with:

```bash
    exec)
        ws_exec "$@"
        ;;
```

And add this function after `ws_validate_component`:

```bash
ws_exec() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: ws exec <component> <command...>" >&2
        exit 1
    fi
    local comp="$1"
    shift
    ws_validate_component "$comp"
    cd "$COMPONENT_DIR" && "$@"
}
```

- [ ] **Step 2: Test exec with a real component**

Run: `bash scripts/ws exec ymir pwd`
Expected: Prints the absolute path to `components/ymir`.

Run: `bash scripts/ws exec ymir git log --oneline -3`
Expected: Last 3 ymir commits.

Run: `bash scripts/ws exec . pwd`
Expected: Prints the yggdrasil root path.

Run: `bash scripts/ws exec root pwd`
Expected: Same as `.` — yggdrasil root path.

- [ ] **Step 3: Test validation edge cases**

Run: `bash scripts/ws exec nonexistent echo hi`
Expected: `ERROR: 'nonexistent' is not declared in ecosystem.yaml.`

Run: `bash scripts/ws exec "foo;bar" echo hi`
Expected: `ERROR: Invalid component name 'foo;bar'. Must match [a-z][a-z0-9-]*.`

Run: `bash scripts/ws exec ymir`
Expected: `Usage: ws exec <component> <command...>`

- [ ] **Step 4: Commit**

```bash
git add scripts/ws
git commit -m "feat(ws): add exec subcommand for component-aware command execution"
```

---

### Task 5: Add `push` and `issue` subcommands

**Files:**
- Modify: `scripts/ws`

- [ ] **Step 1: Add push and issue functions and case entries**

Add functions:

```bash
ws_push() {
    local comp="${1:-.}"
    local branch="${2:-}"
    ws_validate_component "$comp"
    cd "$COMPONENT_DIR" && bash "$SCRIPT_DIR/git-push.sh" ${branch:+"$branch"}
}

ws_issue() {
    bash "$SCRIPT_DIR/gh-issue.sh" "$@"
}
```

Add case entries (before `*)`):

```bash
    push)
        ws_push "$@"
        ;;
    issue)
        ws_issue "$@"
        ;;
```

- [ ] **Step 2: Test push (dry run — just verify directory resolution)**

Run: `bash scripts/ws exec ymir git remote -v`
Expected: Shows ymir's remotes (verifies the component can be resolved).

Note: Don't actually push. The push command requires GH_TOKEN and network.
Just verify the dispatch works by checking `git-push.sh` can find the remote:

Run: `bash scripts/ws push ymir 2>&1 | head -3`
Expected: Either "Pushing ymir/main → siliconsaga (HTTPS)" or a GH_TOKEN error
(both confirm correct directory resolution and script invocation).

- [ ] **Step 3: Test issue (argument passthrough)**

Run: `bash scripts/ws issue 2>&1`
Expected: `Usage:` message from `gh-issue.sh`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ws
git commit -m "feat(ws): add push and issue subcommands"
```

---

### Task 6: Add `.gitattributes` entry and update CLAUDE.md

**Files:**
- Modify: `.gitattributes`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add line ending rule for `scripts/ws`**

Add to `.gitattributes`:

```
scripts/ws text eol=lf
```

- [ ] **Step 2: Update CLAUDE.md Session Conventions**

Replace the "Keep shell commands simple" bullet with:

```markdown
- **Workspace CLI:** Always use `bash scripts/ws <cmd>` for workspace
  operations. Use `bash scripts/ws exec <component> <cmd>` to run commands
  in component directories — never manually `cd` to components.
  Available: `ws list`, `ws status`, `ws clone`, `ws pull`, `ws push`,
  `ws issue`, `ws exec`, `ws help`.
```

Keep the existing "Keep shell commands simple" guidance but move it after the
new bullet, reworded:

```markdown
- **Keep commands simple.** `gh`, `yq`, and Git Bash utilities are on PATH.
  Prefer `bash scripts/ws exec <comp> <cmd>` over manual `cd` + command.
- On first use of `ws` in a session, briefly note: "Using the workspace CLI
  (`scripts/ws`). Run `ws help` in your terminal for available commands.
  Add `export PATH="<yggdrasil>/scripts:$PATH"` to your shell profile for
  shorthand access."
```

- [ ] **Step 3: Test that the ws script still works with LF endings**

Run: `bash scripts/ws help`
Expected: Help output (confirms LF endings work).

- [ ] **Step 4: Commit**

```bash
git add .gitattributes CLAUDE.md
git commit -m "chore: add ws to gitattributes, update CLAUDE.md with ws CLI instructions"
```

---

## Chunk 2: Documentation and gdd-workflow-audit skill

### Task 7: Add human documentation to dev-setup.md

**Files:**
- Modify: `docs/dev-setup.md` (create if not exists at yggdrasil level)

- [ ] **Step 1: Check if yggdrasil has a dev-setup.md**

Run: `ls docs/dev-setup.md 2>/dev/null || echo "not found"`

If not found, create `docs/dev-setup.md`. If found, append a section.

- [ ] **Step 2: Write the Workspace CLI section**

```markdown
## Workspace CLI (`ws`)

The `ws` script is a unified entry point for workspace operations. It wraps
the individual `ws-*.sh` scripts and adds component-aware command execution.

### Usage

```bash
# From anywhere (always works):
bash scripts/ws <command> [args...]

# With PATH setup (optional shorthand):
ws <command> [args...]
```

### Commands

| Command | Description |
|---|---|
| `ws list` | List all ecosystem components and local status |
| `ws status [--verbose]` | Git status across all cloned components |
| `ws clone <comp>\|--all` | Clone one or all components |
| `ws pull [comp]` | Pull latest for all or one component |
| `ws push [comp] [branch]` | Push via HTTPS (auto-sources .env) |
| `ws issue <repo> <title> <label> <body>` | File a GitHub issue |
| `ws resolve` | Generate ArgoCD Application manifests |
| `ws vscode` | Generate VS Code workspace file |
| `ws exec <comp> <cmd...>` | Run a command in a component directory |
| `ws help` | Show help |

### Examples

```bash
# Check what's available
bash scripts/ws list

# Run make test inside the ymir component
bash scripts/ws exec ymir make test

# Check git status of a specific component
bash scripts/ws exec ymir git status

# Push ymir to remote
bash scripts/ws push ymir

# Run a command in the yggdrasil root
bash scripts/ws exec . git log --oneline -5
```

### Optional: Add to PATH

For shorter commands in your terminal, add to your shell profile
(`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export PATH="/path/to/yggdrasil/scripts:$PATH"
```

Then you can use `ws` directly:

```bash
ws exec ymir make test
ws list
ws push ymir
```

- [ ] **Step 3: Commit**

```bash
git add docs/dev-setup.md
git commit -m "docs: add workspace CLI guide to dev-setup"
```

---

### Task 8: Create gdd-workflow-audit skill

**Files:**
- Create: `.agent/skills/gdd-workflow-audit/SKILL.md`

- [ ] **Step 1: Create the skill directory and file**

```markdown
---
name: gdd-workflow-audit
description: Use when you notice repeated manual workarounds (3+ instances), at session wrap-up, or when asked to check for workflow patterns
---

# Workflow Auditor

Detect repeated manual workarounds in a session and propose workspace utility
scripts or workflow improvements.

## When to Use

- **Self-trigger:** You notice 3+ instances of the same awkward pattern in a
  session (repeated `cd`, manual JSON formatting, same multi-step command
  sequence, retried commands with the same fix).
- **User-invoked:** User says "check for workflow patterns" or similar.
- **Session wrap-up:** When a session is ending, review the conversation for
  repeated patterns worth addressing.

## What to Analyze

Scan the current conversation for:

1. **Repeated `cd` or cwd workarounds** — switching directories manually,
   failed commands due to wrong cwd, `cd` + command sequences.
2. **Multi-step command sequences** — the same 2+ commands always run together
   as a logical unit.
3. **Manual formatting/transformation** — JSON reformatting, text extraction,
   output parsing done by hand.
4. **Error-recovery loops** — the same fix applied to the same error multiple
   times.
5. **Environment workarounds** — PATH exports, env var setup, tool version
   switches.
6. **Patterns across tool calls** — multiple tool invocations that achieve one
   logical operation.

## Output Format

For each detected pattern, report:

### Pattern: [short name]

- **Evidence:** List the 3+ instances (quote or summarize the commands/actions)
- **Proposed fix:** One of:
  - New `ws` subcommand (describe behavior)
  - New utility script (describe what it does)
  - CLAUDE.md instruction (draft the text)
  - Skill update (which skill, what change)
- **Effort:** trivial / small / medium
- **Recommendation:** implement now / file as issue / note for later

## Rules

- **Minimum evidence:** Do not propose a fix without at least 3 observed
  instances. Two might be coincidence; three is a pattern.
- **Propose, don't act:** Present findings to the user. Do not create scripts,
  modify CLAUDE.md, or file issues without approval.
- **Stay concrete:** Every proposal must reference specific commands or actions
  from the session. No speculative "we might need this someday."
- **Check existing tools first:** Before proposing a new script, verify that
  `ws` or an existing skill doesn't already handle it.

## Anti-Patterns to Watch For

These are especially high-value patterns to catch:

| Pattern | Likely Fix |
|---|---|
| `cd components/X && cmd` repeated | `ws exec X cmd` |
| Same git sequence across components | New `ws` subcommand |
| Manual JSON/YAML transformation | Utility script |
| Repeated PATH or env exports | CLAUDE.md instruction or ws-env |
| Same error fixed the same way 3+ times | CLAUDE.md note or pre-flight check |
```

- [ ] **Step 2: Verify skill is discoverable**

Run: `ls .agent/skills/gdd-workflow-audit/SKILL.md`
Expected: File exists.

- [ ] **Step 3: Commit**

```bash
git add .agent/skills/gdd-workflow-audit/SKILL.md
git commit -m "feat: add gdd-workflow-audit skill for detecting repeated patterns"
```

---

### Task 9: Final integration test

- [ ] **Step 1: Run the full ws subcommand suite**

```bash
bash scripts/ws help
bash scripts/ws list
bash scripts/ws status
bash scripts/ws exec ymir pwd
bash scripts/ws exec ymir git log --oneline -1
bash scripts/ws exec . pwd
bash scripts/ws exec root pwd
```

All should succeed.

- [ ] **Step 2: Test error cases**

```bash
bash scripts/ws exec nonexistent echo hi     # ERROR: not in ecosystem.yaml
bash scripts/ws exec "foo;bar" echo hi        # ERROR: invalid name
bash scripts/ws nonsense                      # ERROR: unknown command
bash scripts/ws exec ymir                     # Usage error
```

All should produce clear error messages.

- [ ] **Step 3: Verify no regressions in existing scripts**

```bash
bash scripts/ws-list.sh
bash scripts/ws-status.sh
```

Should produce identical output to `ws list` and `ws status`.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(ws): integration test fixes"
```

Only commit if changes were made. Skip if everything passed clean.
