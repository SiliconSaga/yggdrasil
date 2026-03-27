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
  `ws resolve`, `ws vscode`, `ws exec`, `ws overlay`, `ws actions`, `ws help`.
- **Keep commands simple.** `gh`, `yq`, and Git Bash utilities are on PATH.
  Prefer `bash scripts/ws exec <comp> <cmd>` over manual `cd` + command.
- On first use of `ws` in a session, briefly note: "Using the workspace CLI
  (`scripts/ws`). Run `bash scripts/ws help` in your terminal for available
  commands. Add `export PATH="<yggdrasil>/scripts:$PATH"` to your shell
  profile for shorthand access."

## Workspace Structure

Yggdrasil is the workspace root. Component repos live in `components/` and
community overlays in `overlays/` — both gitignored, independent Git repos.

```
yggdrasil/
  ecosystem.yaml          # Upstream defaults (generic, no components)
  ecosystem.local.yaml    # Per-developer overrides (gitignored)
  components/
    nordri/               # Cloned via ws clone
    mimir/
    ...
  overlays/
    overlay-yggdrasil-live/    # Community config (components, identity, adapters)
    overlay-yggdrasil-template/ # Tutorial overlay
  scripts/
    ws                    # Unified CLI — run `ws help` for subcommands
    ws-lib.sh             # Shared functions (overlay detection, config merge)
    ws-clone.sh           # Clone components from merged ecosystem config
    ws-status.sh          # Git status across workspace
    ws-pull.sh            # Pull all cloned components
    ws-list.sh            # List components and local status
    ws-resolve.sh         # Generate ArgoCD Applications (Git vs chart)
    ws-vscode.sh          # Generate VS Code workspace file
```

Config is three-layer merged: `ecosystem.yaml` → overlay → `ecosystem.local.yaml`.
Use `bash scripts/ws list` to see what's declared and what's checked out locally.


## Loading Skills

Use the `Skill` tool to load skills from `.agent/skills/<name>/SKILL.md`.

## Committing

**Always use `ws commit`** — never raw `git add` / `git commit`. The `ws commit`
command handles file staging (via bodyfile `add:` frontmatter) and appends the
Co-Authored-By trailer automatically. Write a bodyfile to `.commits/` and use:

```bash
bash scripts/ws commit <component> .commits/<name>.md
```

The Co-Authored-By trailer format (handled by `ws commit`):

```
Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

Replace `<model>` with the model name (e.g. `Sonnet 4.6`, `Opus 4.6`).
