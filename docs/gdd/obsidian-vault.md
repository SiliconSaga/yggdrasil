# Obsidian vault hoard

The `obsidian-vault` template is the primary PKM-flavored hoard. Init creates a PARA-laid-out Obsidian vault with a small curated plugin set installed and pre-configured for daily-note capture, project tracking, and dashboard-driven review. This is paired with the "Scribe" skill and role available for your GDD agent.

## Init

Scaffold a new vault as a hoard:

```bash
ws hoard init obsidian-vault --name <your-vault-name>
```

What this does for you:

1. Copies the template content (PARA folders, base templates, `Dashboard.md`, `README.md`, `00_Inbox/Welcome.md`) into `hoards/<your-vault-name>/`
2. Fetches seven Obsidian community plugins from their GitHub releases at pinned versions and installs them under `.obsidian/plugins/`
3. Seeds each plugin's `data.json` with sane defaults aligned to PARA layout — Templater folder mappings, Periodic Notes wiring for daily/weekly/monthly, Linter rules, etc.
4. Disables the core daily-notes plugin (Periodic Notes supersedes it) and removes its now-redundant config file
5. Initializes a git repo and creates the initial commit

The first time you open the vault in Obsidian, you'll be prompted to trust the community plugins. Once trusted (and after one Obsidian restart to settle plugin-load timing), the full setup is live.

`00_Inbox/Welcome.md` walks first-time users through the Obsidian-side setup steps (binding a daily-note hotkey, finding the Calendar view, etc.) — process and archive when done.

## What's installed

Seven community plugins, all auto-installed on init and pinned to known-working versions:

| Plugin | Why |
|--------|-----|
| **Templater** | Folder→template auto-apply on file creation; scripted dates and titles via `<% tp.* %>`. Powers the magic where creating a note in `10_Projects/` auto-applies Project Note. |
| **Periodic Notes** | Daily / weekly / monthly notes from templates. Replaces the core daily-notes plugin (which is disabled). |
| **Calendar** | Sidebar calendar widget; clicking a date opens-or-creates that day's daily note. Defers configuration to Periodic Notes when both are active. |
| **Linter** | Auto-format on save — keeps frontmatter, headings, and spacing consistent so the vault stays machine-readable. |
| **Filename Heading Sync** | Keeps each note's filename and `# H1` in lockstep. Templates folder + `README.md` are excluded. |
| **Dataview** | Query engine for live tables and dashboards. Powers `Dashboard.md`. |
| **Tasks** | `- [ ]` query engine; supports due dates, recurring, filters. |

Plugin code (`main.js`, `styles.css`) is *committed by default* in fresh hoards so all devices — including Android via the Obsidian Git plugin, which has no `ws hoard upgrade` — get the JS via `git pull`. `manifest.json` and `data.json` are also tracked. The vault's `.gitignore` documents the opt-in path back to a minimal repo (gitignore the JS, refetch via `ws hoard upgrade` on desktop only); pick whichever fits your sync model. The single always-ignored exception is `.obsidian/plugins/obsidian-git/` — its `data.json` holds the auth Personal Access Token for mobile sync and must not enter git history.

## PARA conventions

Folder roles, applied by both the human and the `scribe` skill:

| Folder | Role |
|--------|------|
| `00_Inbox/` | Capture point. Daily / weekly / monthly notes land here. Process weekly to under 20 items. |
| `10_Projects/` | Time-bound initiatives with a clear completion criterion. Each project gets its own subfolder. Templater auto-applies Project Note here. |
| `20_Areas/` | Ongoing responsibilities without an end date. Templater auto-applies Area Note here. |
| `30_Resources/` | Reference material organized by topic. Includes `Clippings/` for web captures. |
| `40_Archive/` | Completed projects and inactive notes. |
| `50_Attachments/` | Binary attachments (images, PDFs). |
| `60_Metadata/Templates/` | Reusable note templates. |

The capture-process-organize loop lives in the `scribe` skill, which the agent loads when you say things like *"jot this in my inbox"* or *"process my inbox"*.

## Templates and syntax

Some templates ship in `60_Metadata/Templates/`. Two different substitution syntaxes are in play depending on which plugin owns each template:

| Template | Plugin | Syntax |
|----------|--------|--------|
| `Daily Note.md` | Periodic Notes | `{{date:YYYY-MM-DD}}` (core Templates) |
| `Weekly Review.md` | Periodic Notes | `{{date:fmt}}` + Templater JS (`<%* ... _%>`) for week-range computation |
| `Monthly Review.md` | Periodic Notes | Same as Weekly — Templater JS for month-range |
| `Project Note.md` | Templater (folder template) | `<% tp.date.now() %>`, `<% tp.file.title %>` |
| `Area Note.md` | Templater (folder template) | Same |
| `Inbox Capture.md` | Templater (manual insert) | Same |
| `Meeting Note.md` | Templater (manual insert) | Same |
| `Clipping.md` | Templater (manual insert) | Same |

**The two-syntax rule of thumb:** `{{...}}` for templates that Periodic Notes / core Templates plugin own; `<% ... %>` for templates that Templater owns. Mixing within a single template breaks YAML — putting `{{date:fmt}}` in a Templater-owned template produces invalid frontmatter (the curly braces parse as a YAML flow mapping).

When the `scribe` skill creates notes via Claude (not via Obsidian's UI), it substitutes literal dates — neither plugin runs from outside Obsidian.

## Daily / weekly / monthly cadence

Periodic Notes handles file creation for all three time scales. Each scale has a configured folder, format, and template — all written into `.obsidian/plugins/periodic-notes/data.json` by the upgrade phase.

| Scale | Filename format | Folder | Template |
|-------|-----------------|--------|----------|
| Daily | `YYYY-MM-DD` | `00_Inbox/` | `Daily Note` |
| Weekly | `gggg-[W]ww` | `00_Inbox/` | `Weekly Review` |
| Monthly | `YYYY-MM` | `00_Inbox/` | `Monthly Review` |

Quarterly and yearly are not configured — write those freeform when the moment arrives.

The recommended cadence:

- **Daily** — capture in the morning, review in the evening. The `scribe` skill builds out a richer review structure (Accomplished / Progress / Insights / Blocked / Tomorrow's Focus / Open Loops) when you say *"do a daily review"*.
- **Weekly** — synthesis at week's end. Template includes a Tasks query that auto-fills "what got done this week", a Project Review checklist, and "3 big rocks" for next week. The `scribe` skill's *"do a weekly synthesis"* workflow surfaces themes and connections across the week's notes.
- **Monthly** — themes that span weekly reviews. The Monthly Review template ships with a "first-time? customize this" prompt since monthly cadence varies a lot by user.

## Dashboard.md

A Dataview-driven dashboard ships at the vault root. It surfaces:

- Overdue active projects (Dataview query against `10_Projects/`)
- Tasks due today or before today
- Priority-tagged tasks
- Inbox items needing organization
- Project tasks grouped by folder

Pin it as a tab somewhere stable so a glance gives you the day's reality. Pairs naturally with the Calendar view — typical layout is Calendar above Dashboard in the same pane group, both pinned.

To customize: edit the queries in `Dashboard.md`. Dataview and Tasks both have rich query languages — see [Dataview docs](https://blacksmithgu.github.io/obsidian-dataview/) and [Tasks docs](https://publish.obsidian.md/tasks/).

## Web clipping

The Obsidian Web Clipper is a *browser* extension, not an Obsidian plugin. The vault ships with a `30_Resources/Clippings/` folder and a `Clipping.md` template, but you install the extension separately.

Conventions:

- Extension destination folder: `30_Resources/Clippings/`
- Configure highlights to *replace* page content (not append) so clippings aren't full-page noise

Browser links in the `Welcome.md` first-time setup section.

## Filename and folder conventions

Cross-platform safe (Windows / Mac / Linux):

- **Folders:** numbered + Title Case, no spaces (`00_Inbox`, `60_Metadata`)
- **Subfolders:** Title Case, single word or hyphenated (`Templates`, `Reference`)
- **Note filenames:** Title Case with spaces (`Daily Note.md`, `Project Note.md`)
- **Daily notes:** `YYYY-MM-DD.md` (rename to `YYYY-MM-DD - Topic.md` after the fact if useful)

**Hard rule for cross-platform:** never two paths differing only in case. Mac / Windows are case-insensitive by default, so collisions on commit are silent disasters when teammates are on Linux or APFS-case-sensitive volumes. The `Filename Heading Sync` plugin's `ignoreRegex` is configured to skip the Templates folder and `README.md` so the H1-vs-filename rules don't disrupt those.

## Refresh / upgrade

`ws hoard upgrade <vault-name>` allows you to re-baseline the hoard against the template, for instance if new plugin versions have been pinned:

```bash
ws hoard upgrade <your-vault-name>
```

Run it any time you want to re-sync the vault to the template's current state — typically after pulling a yggdrasil update that bumps plugin pins. By default new vaults commit plugin code, so a fresh `git clone` of an existing vault arrives plugin-code-included and Obsidian works without `ws hoard upgrade` needing to run first; upgrade is for *intentional* re-baselines.

What upgrade does:

- Re-downloads each plugin's `main.js` / `styles.css` from its pinned GitHub release
- Re-seeds each plugin's `data.json` from the template
- Disables the core daily-notes plugin (in case it's been re-enabled)
- Refreshes the auto-managed "Installed plugins" table in `README.md` between sentinel markers — versions track upgrade.yaml, descriptions track upgrade.yaml. Edits outside the marker block are preserved.

Upgrade is idempotent — safe to run repeatedly.

### Bumping pins

Plugin pins live in `templates/hoards/obsidian-vault/.upgrade/upgrade.yaml`. To bump:

1. Edit the `pin:` field for the relevant plugin
2. `ws hoard upgrade <vault-name>` — re-fetches at the new tag
3. Plugin code is replaced; `data.json` is *also* re-overwritten (V1 limitation — see [#58](https://github.com/SiliconSaga/yggdrasil/issues/58) for the JSON-merge followup that will preserve user customizations)

If you've customized a plugin's `data.json` (e.g. added Templater folder mappings, modified Linter rules), back it up before upgrading until #58 lands.

## Mobile sync (Android)

The vault syncs to Android via the [Obsidian Git community plugin](https://github.com/Vinzent03/obsidian-git) — runs inside Obsidian, no separate app or terminal needed. Workflow: **pull on session start, edit in Obsidian, commit + push when done.**

### Why git, not Obsidian Sync

Obsidian Sync (first-party paid service) works fine but creates a parallel sync layer alongside git, which gets awkward when you want git to be the source of truth across multiple computers. Git-based sync via Obsidian Git keeps a single source of truth for free and integrates naturally with the workspace's existing `ws push` / `ws pull` flow on desktop.

### Plugin-code-in-git policy

Default for new vaults: plugin code (`main.js`, `styles.css`) is **committed**. Mobile has no `ws hoard upgrade`, so the only way phones get plugin JS is via `git pull`. The trade-off (~1.5MB repo bloat) is fine for personal use. Documented in the vault's `.gitignore` with the opt-in path back to a minimal repo if anyone ever wants it.

**Exception:** `.obsidian/plugins/obsidian-git/` is *always* gitignored. Its `data.json` stores the auth Personal Access Token; committing it would leak your token into git history.

### Setup walkthrough

Lives in the vault's `00_Inbox/Welcome.md` under the "Mobile setup (Android)" section — eight steps covering PAT generation, the install-twice dance (throwaway vault → install plugin to get the Clone command → clone real vault → re-install plugin in cloned vault since its folder is gitignored → reconfigure auth → test round-trip), and ongoing pull/push commands. The walkthrough exists in Welcome rather than this doc page so it travels with each vault to whatever device opens it first.

### community-plugins.json side effect

When you enable obsidian-git on the phone, Obsidian writes `"obsidian-git"` to `.obsidian/community-plugins.json` and that change propagates to desktops on the next push. Desktops then see an entry for a plugin whose code isn't there. Modern Obsidian usually skips it silently; in some versions you may see a one-time "couldn't load" notice — dismiss it.

If the notice persists or you'd rather not see it at all, the cleanest workaround is a **per-clone gitignore on phone only**: edit `.git/info/exclude` inside the *phone's* cloned repo (this file is local-only, never committed) and add:

```gitignore
.obsidian/community-plugins.json
```

Phone's community-plugins.json (with obsidian-git) stays local. Desktops keep their version (without it). Trade-off: if you ever install a regular plugin on phone and want it on desktop too, you'd need to manually update the desktop side once.

### Two-paths reminder for plugin updates

Phone-side mobile workflow puts in-app plugin updates (via Obsidian's Community plugins page) into the same git timeline as everything else. If you click "Update" on Templater on phone, it commits the new `main.js` + new `manifest.json` to git, and on next pull desktops get the updated plugin too.

This means the two upgrade paths can fight: in-app updates push fresher versions, then `ws hoard upgrade` would clobber them back to the template's pinned set. **Don't routinely run `ws hoard upgrade`** on a vault you've been actively maintaining via in-app updates. Run it for fresh init, intentional re-baselining, or after bumping pins in `templates/hoards/obsidian-vault/.upgrade/upgrade.yaml`.

## Related skills and docs

- [`scribe` skill](../../.agent/skills/scribe/SKILL.md) — vault conventions, capture-process-organize, daily review, weekly synthesis, de-AI-ifying text
- [`writing-yggdrasil-docs` skill](../../.agent/skills/writing-yggdrasil-docs/SKILL.md) — line-wrapping convention applies to vault content too
- [Hoards overview](hoards.md) — the hoard concept across all flavors
