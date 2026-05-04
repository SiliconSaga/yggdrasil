---
name: scribe-claudesidian
description: >
  Extension to the scribe skill for Claudesidian-flavored vaults.
  Reads the vault's CLAUDE.md (or CLAUDE-BOOTSTRAP.md fallback),
  surfaces the command manifest from .claude/claude_config.json, and
  lets the user invoke Claudesidian commands like /thinking-partner
  or /weekly-synthesis in plain text. Auto-loaded by scribe when the
  bound vault has the `claudesidian` flavor.
---

# Scribe Claudesidian Extension Skill

Layers Claudesidian-specific behavior on top of the core `scribe`
skill's PARA / frontmatter / wikilink content. Used when a bound vault
has the `claudesidian` flavor (per `ws hoard scan`).

## Loads `scribe` First

This skill is an extension, not a replacement. The scribe skill must
be loaded first — its content covers vault discovery, PARA conventions,
frontmatter habits, daily notes, and the inbox-processing loop.

If for any reason this skill is invoked without scribe loaded, load
scribe first via `Read .agent/skills/scribe/SKILL.md`, then continue
here.

## Read the Vault's CLAUDE.md

On activation, read the bound vault's instruction file:

1. **Prefer `<vault>/CLAUDE.md`** — if it exists, read it. After upstream
   `/init-bootstrap` runs, this file contains personalized vault
   conventions (writing style, primary uses, custom context, tools
   configured).
2. **Fall back to `<vault>/CLAUDE-BOOTSTRAP.md`** — if `CLAUDE.md` is
   absent or its content looks generic (no name, no custom context,
   matches the upstream template verbatim), read `CLAUDE-BOOTSTRAP.md`
   instead. The bootstrap file ships with the upstream Claudesidian
   repo and provides the core PARA / vault-handling guidance.

Either path works. The fallback just means less personalized context —
nothing important breaks.

## Surface the Command Manifest

The canonical source of truth is the `.claude/commands/` directory —
each command is a Markdown file (e.g. `thinking-partner.md`,
`weekly-synthesis.md`) with YAML frontmatter declaring the command's
description, allowed tools, model, and arguments. Enumerate commands
by globbing `<vault>/.claude/commands/*.md` and stripping the `.md`
extension from each filename.

If `<vault>/.claude/claude_config.json` is also present (some
post-`/init-bootstrap` Claudesidian installs ship a manifest at this
path; fresh upstream clones may not), parse it for richer metadata —
shortcuts, descriptions, and any non-default `file` mappings:

```json
{
  "commands": {
    "thinking-partner": { "description": "...", "file": "commands/thinking-partner.md" },
    "inbox-processor":  { "description": "...", "file": "commands/inbox-processor.md" },
    "weekly-synthesis": { "description": "...", "file": "commands/weekly-synthesis.md" },
    ...
  },
  "shortcuts": {
    "tp": "thinking-partner",
    ...
  }
}
```

When the manifest is present, prefer its `file` field for resolving
the command's instruction file path — that lets vaults override the
default `commands/<cmd>.md` layout. When it's absent, fall back to
the implicit `commands/<cmd>.md` convention.

On first activation in a session, surface the inventory once briefly.
Build the command list from the directory glob (or the manifest if
present, since it can carry shortcuts not visible from filenames).
Sort alphabetically and render comma-separated:

> "Claudesidian-flavored vault detected. Commands available: <list
> each command name from the manifest, sorted, comma-separated>.
> Invoke any in plain text — e.g. *'do a weekly synthesis'* — and
> I'll follow the matching instruction file."

If `.claude/claude_config.json` is missing (older Claudesidian or
manually trimmed), fall back to enumerating `.claude/commands/*.md`
files directly and report just the filename stems.

## Plain-Text Invocation Pattern

When the user references a Claudesidian command in plain text:

1. Match the request against the command names from the manifest.
   Match leniently — *"do a weekly synthesis"*, *"weekly synthesis"*,
   *"run the weekly synthesis command"* all map to `weekly-synthesis`.
   Shortcuts (e.g. `tp` → `thinking-partner`) also count.
2. Resolve the command's `file` from `<vault>/.claude/claude_config.json`
   (falling back to `<vault>/.claude/commands/<cmd>.md` only if the
   manifest is absent or the command isn't listed there). The manifest
   may map a command to a different `file` path than the conventional
   `commands/<cmd>.md`, so trust the manifest when present.
3. Cite the resolved file path so the user can see what was loaded:
   *"Following `<vault>/<resolved-file-path>`..."*
4. Follow the instructions in the file verbatim, treating them as
   authoritative for that command's behavior

If multiple commands could match, ask the user which one they meant
rather than guessing.

## Skill Manifest

Read `<vault>/.claude/skills/` to enumerate available Claudesidian
skills (each is a directory with a `SKILL.md`). Common ones include
`obsidian-markdown`, `obsidian-bases`, `git-worktrees`, `json-canvas`,
`skill-creator`, `systematic-debugging`.

**Lazy-load these skills.** Don't read them all on activation — the
inventory list is enough. Read individual `SKILL.md` files only when
the user's request makes them relevant:

- User mentions "wikilinks" or "callouts" → read
  `<vault>/.claude/skills/obsidian-markdown/SKILL.md`
- User mentions "Obsidian Bases" → read
  `<vault>/.claude/skills/obsidian-bases/SKILL.md`
- User asks for canvas / `.canvas` files → read
  `<vault>/.claude/skills/json-canvas/SKILL.md`

## What This Skill Does NOT Do

The following are intentionally NOT adopted from upstream Claudesidian:

- **`.claude/settings.json` hooks** — the SessionStart welcome banner
  and the `skill-discovery.sh` UserPromptSubmit hook are replaced by
  this skill's once-on-activation manifest surfacing
- **`CLAUDE-BOOTSTRAP.md` as primary** — only used as a fallback when
  `CLAUDE.md` is absent or generic
- **MCP server registration** — the upstream Gemini Vision MCP isn't
  auto-wired. If the user wants it, they explicitly add it to
  yggdrasil's `.mcp.json` (handled separately, out of scope for this
  skill)
- **`pnpm` / `npm` install** — Claudesidian's helper scripts and
  attachment management need a Node toolchain. If the user wants them,
  they run `pnpm install` themselves inside the vault. The bridge skill
  doesn't gate on it.
- **`/upgrade` command bookkeeping** — Claudesidian's self-upgrade
  command is for users running it standalone. From the bridge, treat
  the vault as upstream-managed; if it needs refreshing, that's a user
  decision.

## Composition with `scribe`

In normal flow:

1. User triggers vault binding (any of paths A–D from the scribe skill)
2. Scribe skill calls `ws hoard scan --flavor vault`
3. The bound vault's flavor list contains `claudesidian` → scribe
   instructs the agent to also load this skill
4. This skill reads `<vault>/CLAUDE.md` and surfaces the command
   manifest
5. Subsequent vault interactions use scribe's PARA/frontmatter
   conventions PLUS this skill's command-invocation behavior

For plain Obsidian vaults without `.claude/`, this skill is never
loaded; scribe's vanilla content is sufficient.
