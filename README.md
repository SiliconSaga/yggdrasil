# Yggdrasil

*The World Tree - The Mega-Workspace*

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