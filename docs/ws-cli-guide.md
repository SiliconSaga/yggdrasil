# Workspace CLI (`ws`) — Contributor Guide

How to add new subcommands, classify their permission level, and maintain the security model.

## Purpose

While many utility frameworks exist to provide convenience for a human user, this setup is also meant to simplify commands in a flexible workspace _for AI agents_ resulting in clearer commands that can be auto-approved more meaningfully and safely.

Over time as more common patterns are detected they can result in new convenience scripts for better overall visibility and value in the utility framework. This is made available directly as an agent skill, auto-enabled at least for Claude.

## Architecture

`scripts/ws` is a bash dispatcher. Each subcommand either:
- **Delegates** to an existing `scripts/*.sh` script (e.g. `ws list` → `ws-list.sh`)
- **Wraps** a script with component-directory resolution (e.g. `ws push mimir` → `cd components/mimir && git-push.sh`)

The dispatcher handles argument parsing, component validation, and help text. Existing scripts remain standalone and unchanged.

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

**a) Help text** — add a `#` comment line in the header block (between `# Commands:` and the blank line):

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
    ws_resolve_target "$comp"
    cd "$COMPONENT_DIR" && bash "$SCRIPT_DIR/my-script.sh" "$@"
}
```

### 3. Classify its permission level

Every subcommand falls into one of three tiers:

| Tier | Auto-approve? | Committed prompt rule? | Representative examples |
|------|---------------|------------|----------|
| **Auto-approved wrapper** | Yes (allow) | No | `orient`, `status`, `clone`, `test`, `lint`, `commit`, `log`, `preflight` |
| **Side-effect** | User's choice (ask) | No | `push`, `cr`, `issue`, `review reply/resolve`, `realm <url>`, `hoard <url>` |
| **Arbitrary execution** | Always asks | Yes (`hook-rules` ask-list) | `exec` |

**Auto-approved wrapper:** Read-only, wrapper-bounded local actions, or trusted adapter dispatches. Add to the `allow` list in `.claude/settings.json`.

**Side-effect:** Modifies shared state or adopts external repositories. Prompts by default but users *can* whitelist common bulk operations. Do NOT add a deny rule — let users decide.

**Arbitrary execution:** Takes user-provided commands and runs them. Must have an ask-list entry in `.claude/hooks/hook-rules` and must not be allowlisted. Currently only `exec` is in this tier.

### 4. Update permission policy

For auto-approved wrapper commands, add the narrowest useful pattern to `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash scripts/ws mycommand)",
      "Bash(bash scripts/ws mycommand *)"
    ]
  }
}
```

For arbitrary-execution commands, add the normalized `ws` form to `.claude/hooks/hook-rules` under `[ask-commands]` instead. The hook normalizes `bash scripts/ws <subcommand>` to `ws <subcommand>` before matching, so a single bare `ws ...` pattern covers both invocation styles:

```text
[ask-commands]
ws exec *
```

### 5. Update docs

- `scripts/ws` help text (already done in step 2a)
- `CLAUDE.md` — no command list to maintain (it points at `ws help` / `ws orient`); touch only if the command changes a documented convention
- `docs/workspace-setup.md` — only if the command changes setup/PATH guidance (no per-command table to maintain anymore — it points at `ws help` / `ws orient`)
- This file — update the tier table above if adding a new tier

## Security Rules

These apply to all subcommands:

1. **Never `eval`** — use `"$@"` for command passthrough
2. **Validate target names** — use `ws_resolve_target`, which resolves realm/hoard directory names and checks component names against a strict regex plus the merged `ecosystem.yaml` (see Component name validation below)
3. **Quote everything** — `"$target"`, `"$@"`, `"$ROOT_DIR"`
4. **Treat `.env` as high-trust process state** — the dispatcher sources the root `.env` so provider tokens are available to subcommands; keep token-bearing commands narrow, and keep arbitrary execution (`ws exec`) ask-gated because child commands inherit that environment
5. **Bash 4+ is the floor** — `mapfile` and `${var,,}` are used (git-push.sh, git-cr.sh, git-issue.sh, ws). Git Bash on Windows and Linux distros qualify; macOS's system bash 3.2 does not — `brew install bash` (the `ws preflight` hint covers this). Defensive 3.2-safe idioms (e.g. `${arr[@]+"${arr[@]}"}` for empty arrays) are still used in hook and test-critical scripts so failures surface as preflight hints rather than crashes.

### Why `exec` always requires human approval

`ws exec <comp> <cmd...>` runs **arbitrary commands**. If it were auto-approvable, a compromised prompt or injected instruction could run anything on the system. The committed ask-list entry in `.claude/hooks/hook-rules` ensures every `exec` invocation requires human approval before it can run.

Recurring `ws exec` shapes should not become muscle memory. If a command is common enough to want auto-approval, promote it into an adapter-backed `ws test` / `ws lint` / `ws build` type path, a focused `ws` subcommand, or a reviewed component-local script invoked by a narrower wrapper.

### Component name validation

Component names pass through `yq` expressions via bracket-quoted lookups (`.components["$name"]`). The regex `^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$` allows dotted names (e.g. `movingblocks.github.com`) while preventing:
- Path traversal (no slashes; `..` is impossible because every dot must be followed by a letter)
- Shell metacharacters (`;`, `|`, `$`, etc.)
- Newline injection (bash `=~` matches full string, not per-line)
- yq expression injection (no quotes or brackets can appear in a name, so the bracket-quoted lookup can't be escaped)

### Forking and renaming

The workspace name `yggdrasil` appears as a special case in `ws_resolve_target` (one string comparison) and throughout documentation. To fork and rename:

1. Change the `"yggdrasil"` check in `scripts/ws` → `ws_resolve_target()`
2. Search docs for `yggdrasil` and update narrative references
3. Update remote names and org prefixes in `scripts/git-push.sh` and `scripts/git-cr.sh` to match your fork's remote naming
4. Update the domain in `ecosystem.yaml`
5. Update `.mcp.json` if you change component names that host MCP servers

The name is intentionally not stored in a variable — it's a single check in a security-sensitive function, and indirection would add complexity for a one-time operation.

#### Reserved component names

The following names are reserved and cannot be used as component names:

| Name | Reserved in | Reason |
|---|---|---|
| `yggdrasil` | `ws_resolve_target`, `ws-review.sh` | Refers to the workspace root itself |
| `help` | `ws-review.sh` | Subcommand keyword — `ws review help` shows usage |

If you add new subcommand keywords to any `ws-*.sh` script, guard them before the component name validation block (see the `help` check in `ws-review.sh` as a pattern).

## Local Permission Overrides for Bulk Operations

Side-effect commands (`push`, `cr`, `issue`) prompt for approval by default. (`ws commit` is **allowlisted by default** — see [ws commit](#ws-commit) below — so it needs no local override.) For bulk operations (filing multiple issues, pushing several components), you can auto-approve the rest in your local settings.

**Setup:** Create `.claude/settings.local.json` (gitignored) and add the patterns you want to auto-approve. Current GDD hook matching no longer requires one `*` per argument; a tail wildcard can cover the remaining normalized command string. Keep these patterns scoped to side-effect commands you intentionally want to bulk-approve:

```json
{
  "permissions": {
    "allow": [
      "Bash(ws push *)",
      "Bash(ws cr *)",
      "Bash(ws issue *)"
    ]
  }
}
```

| Pattern | Matches | Example |
|---|---|---|
| `Bash(ws push *)` | Push with component or component + branch | `ws push mimir feat/foo` |
| `Bash(ws cr *)` | CR creation with title and bodyfile, including rare remote overrides | `ws cr mimir --remote siliconsaga "feat: add X" .crs/x.md` |
| `Bash(ws issue *)` | Issue creation with title, label, and bodyfile | `ws issue mimir "fix: Y" bug .issues/y.md` |

Use the bare `ws ...` form for normal GDD sessions. Add parallel `Bash(bash scripts/ws ...)` patterns only if you intentionally want native Claude Code permission matching to work when the GDD hook is absent or disabled; with the hook active, wrapper-form commands normalize to `ws ...` before matching.

For CRs, `identity.forkRemote` remains the default fork/head remote. Use `ws cr <comp> --remote <remote> ...` or `GIT_CR_REMOTE=<remote> ws cr <comp> ...` only for the rare case where a local checkout has an alternate fork/project remote you want to target for this one review request.

**Note:** `ws exec` **always requires human approval** — the committed ask-list entry in `.claude/hooks/hook-rules` runs before local allow patterns, so it cannot be silently auto-approved by `.claude/settings.local.json`. See "Why exec always requires human approval" above.

## ws orient

`ws orient` is the L1 layer of the progressive-disclosure surface (L0 is `AGENTS.md`, L2 is per-subcommand `ws <cmd> --help`). It prints a deterministic discovery menu:

- **Subcommand survey** — every dispatched subcommand with its `# ws:use-when …` docstring, built dynamically by scanning the dispatcher in `scripts/ws`.
- **Active realm** — the `ecosystem.local.yaml`-selected realm (community realms activate only via the explicit `ws realm use` trust step; without a selector only the bundled `realm-template` is implied), with a pointer at its `AGENTS.md` guide.
- **Per-component adapter wiring** — for each cloned component with a realm-side adapter file, the wired verbs (`ws test`, `ws lint`, `ws build`) and the **resolved command** each dispatches (`runs: ./gradlew test`). Components without an adapter file are suppressed so the section stays signal-rich.
- **Skill index** — workspace skills (`/.agent/skills/`) and active-realm skills (`realms/<r>/.agent/skills/`), parsed from each SKILL.md frontmatter.

The output stays cheap even with dozens of skills — frontmatter-only parsing on SKILL.md bodies, single-line per row. Read-only; no flags yet. Run at session start, after compaction, or whenever you're unsure what's available.

A post-dispatch stderr footer on every other `ws` subcommand keeps `ws orient` discoverable mid-session. Suppressed for `orient` itself, `--help` variants, and under bats. Opt out with `WS_FOOTER_DISABLE=1`.

## ws commit

`ws commit <component> <bodyfile>` is the bodyfile-driven commit wrapper (staging declared in the bodyfile's `add:` frontmatter, no separate `git add`). It appends a `Co-Authored-By` trailer automatically. Run `ws commit --help` for the full bodyfile and flag reference; the attribution behavior is documented here.

### Identity (the Co-Authored-By trailer)

The trailer credits the *agent* that made the commit, and it resolves **per session**, not from static config. First match wins:

1. `--human` — commit with **no trailer** (a human committing; e.g. a retry with an edited bodyfile).
2. `--co-author-file <name>` — read the identity from `.tmp/gdd-agent-sessions/<name>.env`. This is how a **sub-agent** attributes its own commits (see below).
3. The **session identity file** `.tmp/gdd-agent-sessions/<session-id>.env`, established at `ws orient` (or `ws whoami --set`). This is the main-agent path; if a session id resolves but the file is missing, that's a **hard error** (re-establish — never a silent mis-attribution).
4. **Nothing resolves** (no `--human`, no `--co-author-file`, no session id) — **hard error** guiding the caller: an agent must establish its identity; a human committing manually must pass `--human`.

There is **no silent no-trailer fallback**: an agent always has a session id (so it lands on rung 3 and can never quietly skip attribution), and a no-session caller must mark itself with `--human` rather than be guessed at. The environment is never consulted for identity. The resolved value must include an email in angle brackets (e.g. `Codex GPT-5 <noreply@openai.com>`), only feeds the trailer string, and is newline-sanitized — never evaluated as a command. Run `ws whoami` to see who the current session commits as.

### Establishing identity

A main agent sets its session identity at orientation with the split name + bare-email form (no angle brackets, so it passes the permission hook):

```bash
ws whoami --set "Claude Opus 4.8" noreply@anthropic.com
```

A human in their own terminal can use the bracketed form instead: `ws whoami --set "Name <email>"`.

### Sub-agent attribution

A sub-agent shares its parent's session id, so it must not write the parent's identity file. Instead it writes its own — `.tmp/gdd-agent-sessions/<parent-session-id>--<label>.env` (one line: `GDD_CO_AUTHOR=Claude <model> <noreply@anthropic.com>`, via the Write tool — `.tmp/` is a scratch dir, so the write auto-allows) — and names it at commit time:

```bash
ws commit --co-author-file <parent-session-id>--<label> <comp> <bodyfile>
```

The flag value is a bare name (no angle brackets), so it passes the hook and needs no special allowlist entry — `ws commit --co-author-file …` matches the existing `ws commit:*` allow.

## ws component init

Scaffolds a new component into `components/<name>/` from a template shipped at `templates/components/<flavor>/`.

Usage:

```bash
ws component init <flavor> [name] [template-args]
ws component list
```

Behavior:

1. Validates the flavor exists. Errors with the available-flavors list if not.
2. Resolves the component name. Required; prompted on a tty if omitted.
3. Pre-flight checks: `components/<name>/` doesn't exist, `<name>` isn't already in `ecosystem.local.yaml`. Warns + confirms if `<name>` shadows a realm-catalog entry.
4. Copies the template directory into `components/<name>/`.
5. `git init -b main`, initial commit using the user's git config — `git config user.name` for the author name (fallback to `identity.human_account`) and `git config user.email` for the email (fallback to `<human_account>@local`).
6. Adds an entry to `ecosystem.local.yaml` under `components.<name>.repo` (matches the field `ws-clone.sh` reads). The URL is inferred from `identity.human_account` and the component name, in canonical `https://github.com/<user>/<name>.git` form.
7. Prints educational output explaining the local-first → upstream-when-ready flow plus a flavor-appropriate `gh repo create` suggestion.

`ecosystem.local.yaml` is the per-developer (gitignored) layer of the three-layer merge. The new component is immediately usable from this workspace; when ready to share with the community, move the entry into the realm's `ecosystem.yaml` with realm-appropriate fields (tier, chartVersion, etc.) and push the realm.

Currently shipped flavors:

- `gh-pages` — tutorial-friendly GitHub Pages site, bare markdown + default GitHub Jekyll theme. Comprehensive README walks the user through the edit → PR → bot-review → merge → see-it-live demo loop.

Per-flavor flag handling is hardcoded in `scripts/ws-component.sh` for v1.

## Finding Patterns Worth Scripting

Use the `gdd-workflow-audit` skill (`.agent/skills/gdd-workflow-audit/SKILL.md`) to detect repeated manual workarounds that could become new subcommands. The skill triggers on 3+ instances of the same awkward pattern in a session.

Common progression: manual workaround → noticed by auditor → proposed as script → reviewed → added to `ws` → classified and permissioned.
