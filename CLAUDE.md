# Yggdrasil — Claude Code

**Read [`AGENTS.md`](AGENTS.md) first** — it contains shared workspace instructions
including **session startup** (GDD orientation), repo roles, skills, git workflow,
utility scripts, auth setup, and issue/PR conventions.

This file covers only Claude-specific overrides.

---

## Session Conventions

- **Start Claude from `yggdrasil/`** — this is the workspace root. All sessions
  should use it as the working directory. Avoid starting from `GitWS/` or
  component subdirectories.
- **Workspace CLI:** The `ws` CLI is the shared interface for both humans and
  AI agents. Always use `bash scripts/ws <cmd>` for workspace operations.
  Use `bash scripts/ws exec <component> <cmd>` to run commands in component
  directories — never manually `cd` to components.
  Available: `ws list`, `ws status`, `ws clone`, `ws pull`, `ws push`,
  `ws pr`, `ws issue`, `ws test`, `ws review`, `ws commit`, `ws log`, `ws clean`,
  `ws resolve`, `ws vscode`, `ws exec`, `ws help`.
- **Keep commands simple.** `gh`, `yq`, and Git Bash utilities are on PATH.
  Prefer `bash scripts/ws exec <comp> <cmd>` over manual `cd` + command.
- On first use of `ws` in a session, briefly note: "Using the workspace CLI
  (`scripts/ws`). Run `bash scripts/ws help` in your terminal for available
  commands. Add `export PATH="<yggdrasil>/scripts:$PATH"` to your shell
  profile for shorthand access."

## Workspace Structure

Yggdrasil is the workspace root. Component repos live in `components/` as
independent Git repos (gitignored from yggdrasil's history).

```
yggdrasil/
  ecosystem.yaml          # Central manifest — tiers, chart versions, values
  ecosystem.local.yaml    # Per-developer overrides (gitignored)
  components/
    nordri/               # Cloned via ws-clone.sh
    mimir/
    ...
  scripts/
    ws                    # Unified CLI — run `ws help` for subcommands
    ws-clone.sh           # Clone components from ecosystem.yaml
    ws-status.sh          # Git status across workspace
    ws-pull.sh            # Pull all cloned components
    ws-list.sh            # List components and local status
    ws-resolve.sh         # Generate ArgoCD Applications (Git vs chart)
    ws-vscode.sh          # Generate VS Code workspace file
```

Use `bash scripts/ws list` to see what's declared and what's checked out locally.


## Loading Skills

Use the `Skill` tool to load skills from `.agent/skills/<name>/SKILL.md`.

## Co-Authored-By Trailer

When committing, use this exact trailer format:

```
Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

Replace `<model>` with the model name (e.g. `Sonnet 4.6`, `Opus 4.6`).
