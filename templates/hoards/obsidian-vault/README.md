# Plain Obsidian Vault

A vanilla Obsidian vault scaffolded by `ws hoard init obsidian-vault`,
ready to use as a personal hoard inside a GDD workspace.

## What's here

Folders follow the [PARA Method](https://fortelabs.com/blog/para/):

| Folder | Purpose |
|--------|---------|
| `00_Inbox/` | Temporary capture point. Process weekly. |
| `01_Projects/` | Time-bound initiatives with a clear completion criterion. |
| `02_Areas/` | Ongoing responsibilities without an end date. |
| `03_Resources/` | Reference material organized by topic. |
| `04_Archive/` | Completed or inactive items. |
| `05_Attachments/` | Images, PDFs, and other binary attachments. |
| `06_Metadata/Templates/` | Reusable note templates (daily, project, meeting, etc.). |

## Optional: install Obsidian

The vault is fully usable from Claude Code alone, but installing
[Obsidian](https://obsidian.md) gives you graph view, search, and
plugin support.

1. Download Obsidian from <https://obsidian.md>
2. Open Obsidian → "Open vault as folder"
3. Point it at this directory

The included `.obsidian/` config sets a few sensible defaults (new
notes go to `00_Inbox/`, attachments go to `05_Attachments/`,
shortest-form wikilinks). No community plugins are pre-installed —
add what you need.

## Working from GDD

When you operate this vault from a GDD-rooted Claude session:

- The `scribe` skill in the workspace knows this vault's conventions
- Say things like *"jot this in my inbox"* or *"start a daily note about
  X"* — the agent will create files following the templates here
- Use `ws hoard list` from the workspace root to see your hoards
- The vault is its own git repo; use `ws commit` and then `ws push`
  from the workspace root (run as separate commands)

You can also run Claude Code directly inside this vault — useful if you
want a standalone Obsidian session decoupled from the surrounding
workspace.

## Want richer Claude integration?

If you want Claude-Code-specific commands (`/thinking-partner`,
`/inbox-processor`, etc.) and the broader Claudesidian ecosystem,
consider the `claudesidian-vault` template instead:

```bash
ws hoard init claudesidian-vault <name>
```

It clones [Claudesidian](https://github.com/heyitsnoah/claudesidian)
(MIT, by Noah Brier / Alephic) on init and adds GDD bridge files. The
GDD `scribe-claudesidian` skill provides equivalent functionality from
the workspace root, so you can use it without `cd`-ing into the vault.
