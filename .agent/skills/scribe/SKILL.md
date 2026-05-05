---
name: scribe
description: >
  Obsidian vault conventions: PARA, frontmatter, daily notes, wikilinks,
  inbox capture loop. Auto-loaded for `role: scribe`. Other roles can
  dip in on keyword detection — vault, note, journal, inbox, daily note,
  obsidian, PARA, wikilink, frontmatter, capture, jot, weekly review,
  thinking partner, weekly synthesis, research assistant — when the
  phrase implies capture intent, not bare keyword matches.
---

# Scribe Skill

Operates against Obsidian-style vaults stored as hoards under
`hoards/<name>/`. Vendor-flavor agnostic — handles plain Obsidian
vaults directly. If a vault is detected as Claudesidian-flavored,
hands off to `scribe-claudesidian` for extension behavior.

## When to Load

- **Path A — `role: scribe` in Thalamus frontmatter** — orientation
  loads this skill automatically per the standard role-default flow
- **Path B — orientation discovers a vault, role is null** — orientation
  surfaces the vault and offers scribe role; if the user accepts, this
  skill loads
- **Path C — mid-session keyword dip-in** — user says something matching
  capture intent (*"jot this in my inbox"*, *"add a daily note"*,
  *"capture this idea"*) while in another role; load this skill ad-hoc
  and perform the requested action without formally swapping role
- **Path D — explicit user ask** — *"scribe role for this session"* or
  *"scribe on borgr"*

## Vault Discovery and Binding

Run `ws hoard scan --flavor vault` and parse the YAML inventory. The
`vault` meta-flavor matches any hoard whose recorded flavors include
`obsidian` or `claudesidian` — a single query covers both plain
Obsidian vaults and Claudesidian variants, including Claudesidian
vaults that haven't been opened in Obsidian on this machine yet.

Apply binding rules:

| Match count | Action |
|-------------|--------|
| 0 | Tell the user no vault-flavored hoards exist. Offer `ws hoard init obsidian-vault` or `ws hoard init claudesidian-vault`. Exit binding flow if declined. |
| 1 | Auto-bind to the single match. In-memory pin for the session. |
| >1 | Check Thalamus frontmatter for `active_vault: <name>`. If set and matches a scanned hoard, use it silently. Otherwise ask the user which vault for this session. |

After binding, re-check the bound hoard's flavor list (from the same
`ws hoard scan` output). If it contains `claudesidian`, also load
`.agent/skills/scribe-claudesidian/SKILL.md` to layer on the extension
behavior.

The pin is **session-local, in-memory**. Don't write the binding to
Thalamus unless the user explicitly says *"make it permanent"* — in
which case set `active_vault: <name>` in frontmatter.

## PARA Conventions

Folder roles in a vault scaffolded by GDD's templates (`obsidian-vault`
or `claudesidian-vault` after `/init-bootstrap`):

| Folder | Role |
|--------|------|
| `00_Inbox/` | Temporary capture point. Process weekly to <20 items. |
| `01_Projects/` | Time-bound initiatives with a clear completion criterion. Each project lives in its own subfolder. |
| `02_Areas/` | Ongoing responsibilities without an end date. |
| `03_Resources/` | Reference material organized by topic. |
| `04_Archive/` | Completed projects and inactive notes. Move whole project folders here when done. |
| `05_Attachments/` | Binary attachments (images, PDFs). |
| `06_Metadata/Templates/` | Reusable note templates. |

When creating notes:
- New captures default to `00_Inbox/`
- Move to PARA folders when processing (capture → process → organize)
- Keep folder depth shallow — projects get one subfolder, not nested trees

## Frontmatter Habits

Every new note opens with YAML frontmatter:

```yaml
---
created: YYYY-MM-DD
tags: [...]
status: active   # or 'unprocessed' for inbox captures, 'archived' for done items
---
```

Substitute the actual date — the templates in `06_Metadata/Templates/`
use Obsidian's `{{date:YYYY-MM-DD}}` syntax that gets replaced when
inserted via Obsidian's Templates plugin. When creating notes via
Claude (not Obsidian's UI), substitute the literal date.

## Wikilinks and Embeds

| Syntax | Result |
|--------|--------|
| `[[Note Name]]` | Link to another note in the vault |
| `[[Note Name\|Display Text]]` | Wikilink with custom display text |
| `![[Note Name]]` | Embed (transclude) another note's content |
| `![[image.png]]` | Embed an image |
| `[[Note Name#Heading]]` | Link to a specific heading |

Prefer wikilinks over markdown links inside the vault — they survive
note renames and Obsidian auto-updates them.

## Daily Notes

Naming pattern: `YYYY-MM-DD - Topic.md`. Lives in `01_Projects/Daily/`
or `02_Areas/Journal/` — your call, but pick one and be consistent.

When the user says *"start a daily note"* or *"jot something for today"*,
use the `06_Metadata/Templates/daily-note.md` shape if it exists,
otherwise create with this minimal frontmatter:

```yaml
---
created: YYYY-MM-DD
tags: [daily]
status: active
---

# YYYY-MM-DD — <Topic>

## Today

## Captures

## Links

```

## Inbox Processing

The capture-process-organize loop:

1. **Capture** — anything new lands in `00_Inbox/` with `status: unprocessed`
2. **Process** — weekly (or on demand), go through inbox items:
   - Delete only when clearly safe (obvious noise, duplicates, expired
     captures); when in doubt, move to `04_Archive/<topic>/` instead.
     **Never auto-delete user content silently** — uncertain items
     always go to Archive, not the trash.
   - Move project material to `01_Projects/<name>/`
   - Move ongoing-responsibility notes to `02_Areas/<area>/`
   - Move reference material to `03_Resources/<topic>/`
   - Update each moved note's frontmatter (`status: active`, add tags)
   - Update wikilinks if names change
3. **Organize** — keep `00_Inbox/` under 20 items; if it's growing,
   processing cadence is too slow

## Claudesidian Extension Hand-off

After binding to a vault, check if `claudesidian` appears in its flavor
list (from `ws hoard scan` output). If yes, also load
`.agent/skills/scribe-claudesidian/SKILL.md`. That skill layers
plain-text invocation of Claudesidian commands (`/thinking-partner`,
`/inbox-processor`, `/weekly-synthesis`, etc.) on top of the core PARA
behavior in this skill.

## Keyword Calibration

Trigger keywords advertised in this skill's frontmatter description
include `note`, `journal`, `inbox`, `capture`, `jot`, etc. — but
those words appear in many non-vault contexts.

**Trigger this skill only on phrases implying capture intent:**

| Trigger | Don't trigger |
|---------|---------------|
| *"jot this in my inbox"* | *"note that this fails on Windows"* |
| *"capture this idea"* | *"capture group in the regex"* |
| *"add a daily note about X"* | *"daily standups are at 10"* |
| *"start a meeting note"* | *"meeting notes from 2025 are gone"* |
| *"do a weekly synthesis"* (Claudesidian) | *"weekly all-hands"* |

The distinction is **capture intent** — the user wants to record
something into a vault — versus **incidental keyword match** — the
word appeared but the user is talking about something unrelated. When
in doubt, ask: *"sounds like you want to capture this — should I add
it to your vault inbox?"* before loading the skill and binding to a
vault.

## Multi-vault Edge Case

If Path C (keyword dip-in) triggers in a workspace with multiple
vault-flavored hoards and no `active_vault:` is set, the binding
sub-flow asks the user which vault — mid-conversation. The pin sticks
for the rest of the session, so it's a one-time prompt. Users who
frequently dip into capture from multi-vault workspaces should set
`active_vault:` in Thalamus frontmatter once to skip the question.

## What This Skill Does NOT Do

- Set `role: scribe` in Thalamus permanently — only the user can do
  that
- Auto-commit the vault — vault hoards are independent git repos;
  the user commits when they want
- Modify `00–06` numbered folder names — those are PARA structural
  invariants
- Force any specific filename pattern beyond the daily-note convention
