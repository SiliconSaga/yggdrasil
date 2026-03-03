# Yggdrasil — Claude Code

**Read [`AGENTS.md`](AGENTS.md) first** — it contains all shared workspace instructions:
repo roles, skills, git workflow, utility scripts, auth setup, and issue/PR conventions.

This file covers only Claude-specific overrides.

---

## Loading Skills

Use the `Skill` tool to load skills from `.agent/skills/<name>/SKILL.md`.

## Co-Authored-By Trailer

When committing, use this exact trailer format:

```
Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

Replace `<model>` with the model name (e.g. `Sonnet 4.6`, `Opus 4.6`).
