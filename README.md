# Yggdrasil

*The World Tree — The Meta-Workspace*

> "An immense mythical tree that connects the nine worlds in Norse cosmology."

**Yggdrasil** is the **Root Workspace** / wrapper for the entire ecosystem. It holds the VS Code workspace file, the high-level "Project Constellation" map, workflow strategies that bind the other projects together, and so on

## AI Usage

This ecosystem is largely made possible by extensive AI usage, such as with Claude Code or Google's Antigravity. General AI instructions can be found in `agents.md` in this project, which can be pointed at by other agent-specific files like `CLAUDE.md` to avoid duplication. Only put agent-specific instructions in named agent files.

Agent skills can be installed in various ways and custom ones added at `.agent/skills`

### Claude Code

* https://code.claude.com/docs/en/skills - read about skills in general and which are bundled
* https://github.com/anthropics/skills - an additional set of official skills by Anthropic
  * Install with `/plugin marketplace add anthropics/skills`
  * Then `/plugin install example-skills@anthropic-agent-skills`
* https://github.com/obra/superpowers - Obra Superpowers is a well-reputed set of additional skills
  * Install with `/plugin marketplace add obra/superpowers-marketplace`
  * Then `/plugin install superpowers@superpowers-marketplace`
* Restart Claude or run `/reload-plugins` after

#### Shipped Claude Code hook

This repo ships a PreToolUse hook at `.claude/hooks/gdd-permission-hook.sh` (registered in `.claude/settings.json`). When a Claude Code session is started in this workspace, the hook fires on every Bash tool call the agent attempts and:

* **Rejects shell composition** (`&&`, `||`, `;`, pipes, redirects, command substitution) with a corrective message telling the agent to use separate tool calls or native `ws` flags. Keeps commands single-purpose and easier for newer users to follow.
* **Auto-allows** anything matching the project's `permissions.allow` patterns or per-machine allow patterns in `.claude/hooks/hook-rules.local`.

If the hook ever stalls a session, or you'd just rather have Claude's default permission flow, you can opt out by exporting `WS_HOOK_DISABLE=1`. Full operational details, including how to add safe-command patterns of your own, live in [`.claude/hooks/README.md`](./.claude/hooks/README.md).