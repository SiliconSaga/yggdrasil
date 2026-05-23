# Yggdrasil

*The World Tree — GDD's Meta-Workspace*

> "An immense mythical tree that connects the nine worlds in Norse cosmology."

**Yggdrasil** is the meta-workspace where [Guardian Driven Development (GDD)](docs/gdd/index.md) lives. It isn't just a wrapper around the ecosystem's repos — it's the home of the methodology itself: the `ws` workspace CLI, the GDD skills, the shared-thinking Thalamus, the components/realms/hoards model, and the documentation, commit, and branch conventions that bind everything together. Components, realms, and hoards are what Yggdrasil *orchestrates*; GDD is what Yggdrasil *is*.

## Start here

- **[`AGENTS.md`](AGENTS.md)** — the canonical workspace guide for humans and AI agents: session startup, the `ws` CLI, skills, git workflow, auth, conventions. Read this first.
- **[`docs/gdd/`](docs/gdd/index.md)** — the methodology: roles and modes, the Thalamus, trust & safety, permissions, and the agent-training companion to the PreToolUse hook.
- **The `ws` CLI** — the shared interface for both humans and agents. Run `bash scripts/ws help` (or `ws help` once `scripts/` is on your PATH).

## What lives here

- **`ecosystem.yaml`** — the manifest declaring components and their tiers, three-layer-merged with an active realm and a per-developer `ecosystem.local.yaml`.
- **`scripts/ws`** — the unified CLI: clone, status, commit, push, cr, review, test, plus realm / hoard / component management.
- **`.agent/skills/`** — workspace skills (GDD orchestration, orientation, housekeeping, the documentation conventions, and more). They are plain-markdown files read directly; some practice flows also lean on the optional [Obra Superpowers](https://github.com/obra/superpowers) plugin.
- **`docs/`** — ecosystem architecture, the GDD methodology, and design / plan docs. Documentation follows the **Component Documentation Convention** — a four-Shape graduation ladder (loose root Markdown → structured `/docs` → themed site → custom) defined in the [`writing-yggdrasil-docs`](.agent/skills/writing-yggdrasil-docs/SKILL.md) skill.
- **Components / realms / hoards** — cloned under `components/`, `realms/`, `hoards/` (all gitignored, independent Git repos). A VS Code workspace file is generated on demand via `ws vscode`; it is not committed.

## AI usage

This ecosystem is built with heavy AI assistance (Claude Code, among others). General agent instructions live in [`AGENTS.md`](AGENTS.md); agent-specific files like `CLAUDE.md` point at it to avoid duplication. Custom skills go under `.agent/skills/`.

### Claude Code skills

* https://code.claude.com/docs/en/skills — skills overview and what ships bundled
* https://github.com/anthropics/skills — Anthropic's official skill set
  * `/plugin marketplace add anthropics/skills`, then `/plugin install example-skills@anthropic-agent-skills`
* https://github.com/obra/superpowers — Obra Superpowers, a well-regarded additional set
  * `/plugin marketplace add obra/superpowers-marketplace`, then `/plugin install superpowers@superpowers-marketplace`
* Restart Claude or run `/reload-plugins` after installing.

### The PreToolUse hook

This repo ships a Claude Code PreToolUse hook (`.claude/hooks/gdd-permission-hook.sh`) that channels agent Bash calls toward the `ws` CLI and away from opaque shell composition. Corrective "deny" messages early in a session are the hook teaching conventions, not errors. Full details live in [`.claude/hooks/README.md`](.claude/hooks/README.md) (the technical spec) and [`docs/gdd/agent-training.md`](docs/gdd/agent-training.md) (why it exists, in plain terms). Opt out for a session with `WS_HOOK_DISABLE=1`.
