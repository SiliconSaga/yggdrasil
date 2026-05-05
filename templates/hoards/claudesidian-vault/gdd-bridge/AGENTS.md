# Agent Notes — Claudesidian Vault (GDD-bridged)

This vault was scaffolded via `ws hoard init claudesidian-vault` from
a GDD workspace. It can run standalone (just start `claude` here) or
be operated from the workspace root, where the `scribe-claudesidian`
skill provides equivalent functionality.

## Standalone use

Everything Claudesidian ships works as upstream intended — slash
commands like `/thinking-partner`, the `init-bootstrap` wizard,
MCP servers (if configured), and hooks. See `CLAUDE.md` (or
`CLAUDE-BOOTSTRAP.md` if you haven't run `/init-bootstrap` yet) for
the operational guide.

## Bridged use (from the GDD workspace)

When you operate this vault from a session rooted at the parent
GDD workspace:

- The `scribe` skill loads first (PARA, frontmatter, wikilinks)
- The `scribe-claudesidian` skill loads on top, reading this vault's
  `CLAUDE.md` (or `CLAUDE-BOOTSTRAP.md`) and surfacing the command
  manifest from `.claude/claude_config.json`
- You invoke commands in plain text: *"do a weekly synthesis"* →
  the agent reads `.claude/commands/weekly-synthesis.md` and follows
  it
- Hooks and MCP servers from `.claude/settings.json` and
  `.claude/mcp-servers/` are NOT activated in bridged use; they only
  fire when Claude Code is launched from this directory

## Which mode should I use?

- **Bridged (workspace-rooted):** when you also need the broader GDD
  context — multi-repo work, components, realm config
- **Standalone (this directory):** when you want pure Claudesidian
  ergonomics, especially the native slash-command palette and any
  configured hooks
