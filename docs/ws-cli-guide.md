# Workspace CLI (`ws`) — Contributor Guide

How to add new subcommands, classify their permission level, and maintain
the security model.

## Purpose

While many utility frameworks exist to provide convenience for a human user, this setup is also meant to simplify commands in a flexible workspace _for AI agents_ resulting in clearer commands that can be auto-approved more meaningfully and safely.

Over time as more common patterns are detected they can result in new convenience scripts for better overall visibility and value in the utility framework. This is made available directly as an agent skill, auto-enabled at least for Claude.

## Architecture

`scripts/ws` is a bash dispatcher. Each subcommand either:
- **Delegates** to an existing `scripts/*.sh` script (e.g. `ws list` → `ws-list.sh`)
- **Wraps** a script with component-directory resolution (e.g. `ws push mimir` → `cd components/mimir && git-push.sh`)

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
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode`, `test`, `review` (listing/status), `log`, `clean`, `realm list`, `realm init`, `hoard list`, `hoard init`, `hoard init <template>`, `hoard init <template> <args>`, `component list`, `component init <flavor>`, `component init <flavor> <name>`, `actions` |
| **Side-effect** | User's choice (ask) | No | `push`, `push --force`, `pr`, `issue`, `commit`, `review --resolve*`, `realm <url>`, `hoard <url>` (URL clones touch arbitrary external git URLs) |
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
3. Update remote names and org prefixes in `scripts/git-push.sh` and
   `scripts/git-cr.sh` to match your fork's remote naming
4. Update the domain in `ecosystem.yaml`
5. Update `.mcp.json` if you change component names that host MCP servers

The name is intentionally not stored in a variable — it's a single check in a
security-sensitive function, and indirection would add complexity for a one-time
operation.

#### Reserved component names

The following names are reserved and cannot be used as component names:

| Name | Reserved in | Reason |
|---|---|---|
| `yggdrasil` | `ws_validate_component`, `ws-review.sh` | Refers to the workspace root itself |
| `help` | `ws-review.sh` | Subcommand keyword — `ws review help` shows usage |

If you add new subcommand keywords to any `ws-*.sh` script, guard them before
the component name validation block (see the `help` check in `ws-review.sh` as
a pattern).

## Local Permission Overrides for Bulk Operations

Side-effect commands (`push`, `cr`, `issue`) prompt for approval by default. (`ws commit` is **allowlisted by default** — see [ws commit](#ws-commit) below — so it needs no local override.) For bulk operations (filing multiple issues, pushing several components), you can auto-approve the rest in your local settings.

**Setup:** Create `.claude/settings.local.json` (gitignored) and add the
patterns you want to auto-approve. In Claude Code permission
rules, each `*` matches **one argument** (not multiple). So multi-argument
commands need one `*` per argument:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash scripts/ws push * *)",
      "Bash(bash scripts/ws cr * * *)",
      "Bash(bash scripts/ws issue * * * *)"
    ]
  }
}
```

| Pattern | Matches | Example |
|---|---|---|
| `Bash(bash scripts/ws push *)` | Push with component only | `ws push mimir` |
| `Bash(bash scripts/ws push * *)` | Push with component + branch | `ws push mimir feat/foo` |
| `Bash(bash scripts/ws cr * * *)` | CR with component + title + bodyfile | `ws cr mimir "feat: add X" .crs/x.md` |
| `Bash(bash scripts/ws issue * * * *)` | Issue with all 4 args | `ws issue mimir "fix: Y" bug .issues/y.md` |

**Note:** `ws exec` **always requires human approval** — the project-level
deny rule in `.claude/settings.json` cannot be overridden by local settings.
See "Why exec always requires human approval" above.

## ws commit

`ws commit <component> <bodyfile>` is the bodyfile-driven commit wrapper (staging declared in the bodyfile's `add:` frontmatter, no separate `git add`). It appends a `Co-Authored-By` trailer automatically. Run `ws commit --help` for the full bodyfile and flag reference; the attribution behavior is documented here.

### Model attribution

The `Co-Authored-By` trailer name resolves as:

1. `identity.co_authored_by` from the merged ecosystem config, **if set** — a realm or local override can pin a fixed attribution string.
2. Otherwise `"Claude $CLAUDE_MODEL"`.

`CLAUDE_MODEL` is auto-sourced from `.env` at the workspace root. The shipped default (see `.env.example`) is:

```bash
export CLAUDE_MODEL="${CLAUDE_MODEL:-Opus 4.8}"
```

Keep `.env` current with the model the workspace primarily commits as, rather than prepending `CLAUDE_MODEL` on every commit. If `.env` is absent, `ws-commit.sh` falls back to a hardcoded default (also `Opus 4.8`). The resolved value only feeds the trailer string and is newline-sanitized — it is never evaluated as a command.

### Sub-agent override rule

A sub-agent running on a **non-default** model (e.g. Sonnet while the workspace default is Opus) should prepend the model **inline** for that one commit:

```bash
CLAUDE_MODEL="Sonnet 4.6" ws commit <comp> <bodyfile>
```

Inline is the correct mechanism for sub-agents. Do **not** rewrite the shared `.env` to change attribution for a single commit — parallel sub-agents rewriting the same file would race. The inline prefix is allowlisted (`Bash(CLAUDE_MODEL=* ws commit:*)`); see [the bounded `CLAUDE_MODEL=` prefix in the permissions reference](gdd/permissions.md#bounded-claude_model-attribution-prefix) for why this specific prefix auto-approves while arbitrary env prefixes do not.

## ws component init

Scaffolds a new component into `components/<name>/` from a template
shipped at `templates/components/<flavor>/`.

Usage:

```bash
ws component init <flavor> [name] [template-args]
ws component list
```

Behavior:

1. Validates the flavor exists. Errors with the available-flavors list
   if not.
2. Resolves the component name. Required; prompted on a tty if omitted.
3. Pre-flight checks: `components/<name>/` doesn't exist, `<name>`
   isn't already in `ecosystem.local.yaml`. Warns + confirms if `<name>`
   shadows a realm-catalog entry.
4. Copies the template directory into `components/<name>/`.
5. `git init -b main`, initial commit using the user's git config —
   `git config user.name` for the author name (fallback to
   `identity.human_account`) and `git config user.email` for the email
   (fallback to `<human_account>@local`).
6. Adds an entry to `ecosystem.local.yaml` under `components.<name>.repo`
   (matches the field `ws-clone.sh` reads). The URL is inferred from
   `identity.human_account` and the component name, in canonical
   `https://github.com/<user>/<name>.git` form.
7. Prints educational output explaining the local-first → upstream-when-
   ready flow plus a flavor-appropriate `gh repo create` suggestion.

`ecosystem.local.yaml` is the per-developer (gitignored) layer of the
three-layer merge. The new component is immediately usable from this
workspace; when ready to share with the community, move the entry into
the realm's `ecosystem.yaml` with realm-appropriate fields (tier,
chartVersion, etc.) and push the realm.

Currently shipped flavors:

- `gh-pages` — tutorial-friendly GitHub Pages site, bare markdown +
  default GitHub Jekyll theme. Comprehensive README walks the user
  through the edit → PR → bot-review → merge → see-it-live demo loop.

Per-flavor flag handling is hardcoded in `scripts/ws-component.sh`
for v1.

## Finding Patterns Worth Scripting

Use the `gdd-workflow-audit` skill (`.agent/skills/gdd-workflow-audit/SKILL.md`)
to detect repeated manual workarounds that could become new subcommands.
The skill triggers on 3+ instances of the same awkward pattern in a session.

Common progression: manual workaround → noticed by auditor → proposed as
script → reviewed → added to `ws` → classified and permissioned.
