# Yggdrasil — Claude Code

**Read [`AGENTS.md`](AGENTS.md) first** — it contains all shared workspace instructions:
repo roles, skills, git workflow, utility scripts, auth setup, and issue/PR conventions.

This file covers only Claude-specific overrides.

---

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
    ws-clone.sh           # Clone components from ecosystem.yaml
    ws-status.sh          # Git status across workspace
    ws-pull.sh            # Pull all cloned components
    ws-list.sh            # List components and local status
    ws-resolve.sh         # Generate ArgoCD Applications (Git vs chart)
    ws-vscode.sh          # Generate VS Code workspace file
```

Use `scripts/ws-list.sh` to see what's declared and what's checked out locally.

## Loading Skills

Use the `Skill` tool to load skills from `.agent/skills/<name>/SKILL.md`.

## Co-Authored-By Trailer

When committing, use this exact trailer format:

```
Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

Replace `<model>` with the model name (e.g. `Sonnet 4.6`, `Opus 4.6`).
