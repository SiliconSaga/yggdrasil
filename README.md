# Yggdrasil

*The World Tree — GDD's Meta-Workspace*

> "An immense mythical tree that connects the nine worlds in Norse cosmology."

**Yggdrasil** is the meta-workspace where [Guardian Driven Development (GDD)](docs/gdd/index.md) lives. It isn't just a wrapper around the ecosystem's repos — it's the home of the methodology itself: the `ws` workspace CLI, the GDD skills, the shared-thinking Thalamus, the components/realms/hoards model, and the documentation, commit, and branch conventions that bind everything together. Components, realms, and hoards are what Yggdrasil *orchestrates*; GDD is what Yggdrasil *is*.

**Status: v1.0.0 — General Availability.** See the [release](https://github.com/SiliconSaga/yggdrasil/releases/tag/v1.0.0), the [CHANGELOG](CHANGELOG.md), and the [roadmap](docs/gdd/roadmap.md) for where it goes next.

**How you actually work here:** you direct an AI coding agent to get real work done in the ecosystem's components, and GDD is the methodology that keeps that work safe, attributable, and legible. The `ws` CLI and the git / commit / branch conventions are mostly **guardrails the agent operates within** — attribution, auth, safe git and review flows — rather than commands you run by hand. Day to day you mostly steer and review; the agent drives `ws`. New to the idea? Start with [Guardian Driven Development](docs/gdd/index.md).

## Start here

- **New here (human)?** [Getting Started](docs/getting-started/index.md) walks you from clone to a first live PR in about 15 minutes. For the ideas first: the [GDD index](docs/gdd/index.md) carries the methodology and the [features tour](docs/gdd/features.md) covers what's in the box.
- **Driving a session?** [`AGENTS.md`](AGENTS.md) is the operational guide — session startup, the `ws` CLI, skills, git workflow, auth. It's written *for agents* (terse and optimized for them, not prose for humans), but it's the reference when you need workspace mechanics.
- **The `ws` CLI** is the shared interface for both humans and agents. Run `bash scripts/ws help` (or `ws help` once `scripts/` is on your PATH).

## What lives here

- **`ecosystem.yaml`** — the manifest declaring components and their tiers, three-layer-merged with an active realm and a per-developer `ecosystem.local.yaml`.
- **`scripts/ws`** — the unified CLI: clone, status, commit, push, cr, review, test, plus realm / hoard / component management.
- **`.agent/skills/`** — agent-facing workspace skills (GDD orchestration, orientation, housekeeping, the documentation conventions, and more). These are operational guidance the agent reads directly, not human reading material — humans get the higher-level concepts from `docs/`. Some practice flows also lean on the optional [Obra Superpowers](https://github.com/obra/superpowers) plugin.
- **`docs/`** — ecosystem architecture, the GDD methodology, and design / plan docs. Component docs follow the **Component Documentation Convention** — a four-Shape graduation ladder, described human-side in [the organization stack](docs/gdd/organization-stack.md); the operational rules for agents writing docs live in the `gdd-doc-writing` skill.
- **Components / realms / hoards** — the things Yggdrasil orchestrates, cloned under `components/`, `realms/`, `hoards/` (all gitignored, independent Git repos). **Components** are the code repos you work on. A **realm** is a shared community-config layer: it declares which components exist and wires each one's test / lint / build commands (adapters), so a whole team gets the same setup by adopting one realm instead of configuring every repo by hand. **Hoards** are non-code collections (notes, vaults). A VS Code workspace file is generated on demand via `ws vscode`; it is not committed.

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
