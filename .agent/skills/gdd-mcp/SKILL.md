---
name: gdd-mcp
description: Use when an active realm declares `mcp.servers` and `.mcp.json` doesn't exist, when an MCP server prompts for authentication, when the user asks about MCP setup or usage, or when deciding how to call MCP tools (search-before-fetch, conservative page sizes).
---

# GDD MCP

Guidelines for AI agent behaviour around MCP servers in a GDD workspace.
This skill covers the GDD-side patterns (setup offer with Thalamus persistence, realm config integration, `ws mcp-setup` flow); realm-specific details (server list, caveats) are loaded from the file referenced by `mcp.doc` in the active realm's ecosystem config.

**Currently Claude-focused.** Concrete commands (`.mcp.json`, `/mcp`) below are Claude Code's. Codex, Gemini CLI, and other MCP-capable agents will follow the same `gdd-mcp` ↔ `gdd-mcp-<runner>` pair pattern as `gdd-bdd` ↔ `gdd-bdd-pytest` once their content lands.

## Setup (when .mcp.json is absent)

1. Check Thalamus Preferences for `mcp-setup: declined`. If found, skip silently.
2. Otherwise, check the merged ecosystem config for declared `mcp.servers`.
   If any are declared, offer once:

   > "This realm declares MCP servers. Run `bash scripts/ws mcp-setup` to configure
   > them for Claude Code — you'll then authenticate each via `/mcp` inside Claude Code.
   > Want me to run it now?"

3. If the user declines, write to Thalamus Preferences immediately:

   ```yaml
   - mcp-setup: declined YYYY-MM-DD — do not offer again this session or future sessions
   ```

## Authentication

MCP servers in this workspace use OAuth 2.0 (browser flow). When a server needs
authentication:

- Tell the user to run `/mcp` inside Claude Code and select the server — Claude
  Code handles the browser OAuth flow natively.
- **Do not call the `authenticate` MCP tool directly.** It returns a raw URL that
  wraps across lines, breaks command-click, and bypasses Claude Code's own OAuth
  handling. The `/mcp` command is always the right path.
- Auth tokens are managed by Claude Code — they do not belong in `.env`.

## Tool Calling Patterns

Follow the server's declared workflow hints (usually in the MCP system-reminder):

- **Search before fetch**: run a search tool first to locate the right resource,
  then fetch full content by ID or URL. Fetching blindly wastes tokens and may
  return the wrong page.
- **Start small**: use conservative `page_size` (1–5) and `max_snippet_size` values.
  Increase gradually if content is being truncated. Reduce if hitting token limits.
- **Paginate deliberately**: use the cursor from a response only when you have a
  specific reason to fetch the next page — don't paginate speculatively.

## Discovering What Is Configured

- `bash scripts/ws mcp-status` — lists servers in the current `.mcp.json`
- `bash scripts/ws mcp-setup --dry-run` — shows what would be generated from the
  active realm's `mcp.servers` declarations without writing anything

## Realm Details

Check the merged ecosystem config for `mcp.doc`. If set, read that file for
realm-specific server notes, access restrictions, and service caveats:

```bash
bash scripts/ws realm list   # active realm is prefixed with "* " and labelled "(active)"
```

Scripts can also call the `ws_detect_realm` shell function (sourced from
`scripts/ws-realm.sh`) for a deterministic single-line answer.

The doc file lives at `realms/<active-realm>/<mcp.doc value>` relative to
the workspace root. Read it with your Read tool.

## Session Logs (Claude Code)

Claude Code stores raw conversation JSONL logs at
`.claude/projects/{workspace-path}/`. Other MCP-capable agents (Gemini CLI,
Copilot CLI, etc.) use their own paths — consult their docs. These platform
logs are separate from Thalamus (curated shared thinking) and the AI memory
system (cross-session recall). Do not confuse them.

## Opting Out

If the user has set `gdd-mcp: skip` in Thalamus Preferences, do not load this
skill at future session starts and do not surface MCP-related prompts. Still load
on-demand if the user explicitly asks about MCP.
