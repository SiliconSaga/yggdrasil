# Yggdrasil — Claude Code

**Read [`AGENTS.md`](AGENTS.md) first.** It carries the shared, agent-agnostic workspace instructions — session startup (GDD orientation), the `ws` CLI reflex contract, repo roles, skills, the git/commit workflow, auth, and issue/CR conventions. Run `ws orient` at session start for the live command/skill/realm inventory.

This file holds only what's specific to running GDD in **Claude Code**.

---

## Launching

Start Claude Code from the `yggdrasil/` root — not `GitWS/` or a component subdirectory. The orientation skill and the PreToolUse permission hook key off your working directory (e.g. resolving which component an adapter command applies to), so launching elsewhere skews that.

## Companion plugin

[Obra Superpowers](https://github.com/obra/superpowers) is the recommended companion — see [`AGENTS.md`](AGENTS.md) for what GDD uses it for and how it degrades without it. Install it in Claude Code with:

```text
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
/reload-plugins
```

This lives here rather than in `AGENTS.md` because the install path is agent-specific — Codex and other harnesses install the same plugin their own way. (Skill-loading conventions — Read tool for workspace `.agent/skills/`, the Skill tool for plugin `superpowers:*` skills — are covered in `AGENTS.md`.)
