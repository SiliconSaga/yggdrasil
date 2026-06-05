# MCP Setup

[Model Context Protocol](https://modelcontextprotocol.io) servers extend
agent sessions with additional tools and data sources. The yggdrasil
workspace declares MCP servers in the active realm's `ecosystem.yaml`,
and `ws mcp-setup` generates the `.mcp.json` Claude Code reads at
startup.

---

## Declaring servers in the realm

Add an `mcp` block to the realm's `ecosystem.yaml`:

```yaml
mcp:
  doc: docs/mcp-servers.md   # optional pointer to per-server URLs/notes
  servers:
    sentry:
      url: https://mcp.sentry.dev/mcp
      transport: http
    linear:
      url: https://mcp.linear.app/mcp
      transport: http
```

Each server entry must declare:

- **`url`** — the MCP server endpoint
- **`transport`** — the transport type (`http` is typical for MaaS-style
  remote servers)

Both are required; `ws mcp-setup` errors if either is missing rather
than writing a `.mcp.json` Claude Code would reject.

The optional `mcp.doc` field points at a realm-side reference doc
(server descriptions, who owns each, auth caveats). The setup command
prints the resolved path so users can find it.

---

## The `ws mcp-setup` and `ws mcp-status` commands

```bash
ws mcp-setup              # generate .mcp.json from realm mcp.servers
ws mcp-setup --dry-run    # preview without touching .mcp.json
ws mcp-status             # show currently configured servers
```

`ws mcp-setup` reads the merged ecosystem config (upstream + realm +
local), builds `.mcp.json` at the workspace root, and prints the
resulting server map. The write is atomic — the file is staged to a
sibling temp file and `mv`d into place, so an interrupted run never
leaves a truncated `.mcp.json`.

`ws mcp-status` reads the existing `.mcp.json` and lists each server's
name and URL. Useful to confirm a regeneration produced what you
expected, or to check what an existing checkout is currently wired up
for.

---

## Authenticating

After `.mcp.json` exists, **restart Claude Code** so it picks up the
new server list, then run `/mcp` inside the session to authenticate
each server. Claude Code handles the browser OAuth flow — don't
paste auth URLs manually.

Cursor users: MaaS servers must be added to `~/.cursor/mcp.json`
manually; the workspace's `.mcp.json` is Claude Code-shaped.

---

## See also

- [`ws help mcp-setup`](ws-cli-guide.md) — CLI flags and behavior
- [Ecosystem Architecture](ecosystem-architecture.md) — the
  three-layer config merge `ws mcp-setup` reads from
- [Realms](gdd/realms.md) — where the `mcp.servers` declaration lives
- [`gdd-mcp` skill](gdd/skills-reference.md#workspace-operations) —
  agent conventions around calling MCP tools and surfacing setup nudges
