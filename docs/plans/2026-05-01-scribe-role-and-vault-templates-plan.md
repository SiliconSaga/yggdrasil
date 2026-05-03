# Scribe Role and Vault Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the design in `docs/plans/2026-05-01-scribe-role-and-vault-templates-design.md`: a new `scribe` role with two layered skills (`scribe`, `scribe-claudesidian`), a deterministic `ws hoard scan` subcommand, two new hoard templates (`obsidian-vault` vendored, `claudesidian-vault` thin wrapper), and minimal AGENTS.md / orientation-skill wiring.

**Architecture:** Five sequential phases — scanner first (skills depend on it), then templates (independent of skills), then skills (consume scanner), then wiring (small additions to AGENTS.md / orientation / role list / thalamus template), then end-to-end verification. Each phase ends in a single `ws commit` so intermediate states are landing-ready and the history reads as logical units of work.

**Tech Stack:** Bash (ws CLI), `yq` v4 (Mike Farah, used for `template.yaml` parsing), `git` (clone-on-init), markdown documentation.

---

## Conventions for executing this plan

- The repo lives at `/Users/cervator/dev/git_ws/yggdrasil` on this machine. Adjust absolute paths if running on Windows or another machine.
- The user has `<workspace>/scripts/` on PATH so `ws <cmd>` works as a bare command. **Don't prepend `bash scripts/ws`** in commit messages or smoke-test commands; in code blocks here we use the bare form.
- Always commit via `ws commit yggdrasil <bodyfile>` — never raw `git add` / `git commit`. Bodyfiles live in `.commits/<name>.md` (gitignored). The format is in `templates/commit.md`.
- Don't chain `ws commit && ws push` — run separately so each can be reviewed and approved independently.
- Stay on branch `hodgepodge` (or create a fresh `feat/scribe-role` topic branch — the user's call) for the duration. The design spec is in `docs/plans/2026-05-01-scribe-role-and-vault-templates-design.md` and gets committed alongside Phase A.
- yggdrasil has no shell-test framework. Verification is `bash -n` syntax checks + runtime smoke tests against the existing `hoards/` directory (which already has known content: `borgr` = obsidian+claudesidian, `nonclaudesidian` = obsidian, `thalami-Cervator` = thalami).
- Skill markdown files don't have automated tests; verification is by reading the file and confirming structure matches the spec.

---

## Files Changed Overview

### Phase A — Scanner

- **Modify** `scripts/ws-hoard.sh` — add `ws_classify_hoard()` helper, `ws_hoard_scan()` subcommand, dispatch entry, help-text entry (~80 lines added)

### Phase B — Templates

- **Create** `templates/hoards/obsidian-vault/` directory tree (~15 small files)
- **Create** `templates/hoards/claudesidian-vault/` directory (4 files: `template.yaml`, `README.md`, `gdd-bridge/AGENTS.md`, `gdd-bridge/README.md`)
- **Modify** `scripts/ws-hoard.sh` — extend `ws_hoard_init()` to detect `template.yaml` and run the clone-on-init flow (~50 lines added)

### Phase C — Skills

- **Create** `.agent/skills/scribe/SKILL.md` (~150 lines)
- **Create** `.agent/skills/scribe-claudesidian/SKILL.md` (~100 lines)

### Phase D — Wiring

- **Modify** `.agent/skills/gdd-orientation/SKILL.md` — add vault-scan step in Step 6 (~15 lines added)
- **Modify** `.agent/skills/gdd/SKILL.md` — add `scribe` to role list (~5 lines added)
- **Modify** `AGENTS.md` — two new skill table rows + hoards section line (~5 lines added)
- **Modify** `templates/thalamus.md` — document optional `active_vault:` frontmatter (~3 lines added)

### Phase E — Verification

- No new files. End-to-end smoke test, then commit the full feature branch.

---

# Phase A — Scanner

Lands `ws hoard scan` end-to-end against the existing `hoards/` directory. Skills in Phase C will consume its YAML output.

### Task A1: Add `ws_classify_hoard()` and `ws_hoard_scan()` to `ws-hoard.sh`

**Files:**
- Modify: `/Users/cervator/dev/git_ws/yggdrasil/scripts/ws-hoard.sh`

- [ ] **Step 1: Establish the smoke-test scenario**

The existing `hoards/` directory has three known fixtures we'll use as the synthetic test:

```
hoards/borgr              → obsidian + claudesidian
hoards/nonclaudesidian    → obsidian
hoards/thalami-Cervator   → thalami
```

After implementation, `ws hoard scan` should emit exactly three records with those flavor lists.

- [ ] **Step 2: Run the not-yet-implemented command, verify it fails**

```bash
ws hoard scan
```

Expected: `Usage: ws hoard <subcommand>` help dump or "Unknown subcommand" — `scan` doesn't exist yet.

- [ ] **Step 3: Add the classifier helper before `ws_hoard_help()`**

Insert this block just before the `ws_hoard_help()` definition (around line 143 in current `ws-hoard.sh`). Keep the surrounding code unchanged:

```bash
# Classify a hoard directory by flavor.
# Echoes a comma-separated list of flavors, or empty if none.
# Argument is the hoard directory path. Flavors stack — a hoard can be
# both `obsidian` and `claudesidian`.
#
# Detection rules:
#   thalami      — directory name matches `thalami-*`
#   obsidian     — has a `.obsidian/` subdirectory
#   claudesidian — has `.obsidian/` AND `.claude/` AND a top-level
#                  CLAUDE.md whose first 30 lines reference Claudesidian
#                  or PARA conventions (multi-signal — avoids
#                  false-positives on unrelated `.claude/` directories)
ws_classify_hoard() {
    local hoard_path="$1"
    local hoard_name
    hoard_name="$(basename "$hoard_path")"
    local flavors=()

    # thalami: name pattern (matches existing ws_detect_thalami_hoard convention)
    if [[ "$hoard_name" == thalami-* ]]; then
        flavors+=("thalami")
    fi

    # obsidian: .obsidian/ directory present
    if [[ -d "$hoard_path/.obsidian" ]]; then
        flavors+=("obsidian")
    fi

    # claudesidian: obsidian + .claude/ + signature in CLAUDE.md
    if [[ -d "$hoard_path/.obsidian" ]] && \
       [[ -d "$hoard_path/.claude" ]] && \
       [[ -f "$hoard_path/CLAUDE.md" ]]; then
        # Multi-signal: read first 30 lines, look for either
        # "Claudesidian" (the kit's name) or "PARA Method" (its
        # organizational scheme) — case-insensitive.
        if head -n 30 "$hoard_path/CLAUDE.md" 2>/dev/null | \
           grep -qiE 'claudesidian|PARA Method'; then
            flavors+=("claudesidian")
        fi
    fi

    if [[ ${#flavors[@]} -eq 0 ]]; then
        echo ""
    else
        local IFS=,
        echo "${flavors[*]}"
    fi
}
```

- [ ] **Step 4: Add the `ws_hoard_scan()` function**

Append this immediately after `ws_classify_hoard()`. It iterates `$HOARDS_DIR`, applies the classifier, and emits YAML:

```bash
# Iterate hoards/ and emit a YAML inventory with flavor classification.
# Optional flags:
#   --flavor <name>   Only emit hoards containing the named flavor
#   --names-only      Emit just hoard names (one per line) — for shell pipelines
ws_hoard_scan() {
    local filter_flavor=""
    local names_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --flavor)
                if [[ -z "${2:-}" ]]; then
                    echo "ERROR: --flavor requires a value" >&2
                    return 2
                fi
                filter_flavor="$2"
                shift 2
                ;;
            --names-only)
                names_only=true
                shift
                ;;
            -h|--help)
                echo "Usage: ws hoard scan [--flavor <name>] [--names-only]" >&2
                echo "" >&2
                echo "Emit a YAML inventory of hoards/ classified by flavor." >&2
                echo "" >&2
                echo "Flavors detected:" >&2
                echo "  thalami       — directory name matches thalami-*" >&2
                echo "  obsidian      — contains .obsidian/" >&2
                echo "  claudesidian  — contains .obsidian/ + .claude/ + Claudesidian-signed CLAUDE.md" >&2
                return 0
                ;;
            *)
                echo "ERROR: Unknown flag: $1" >&2
                return 2
                ;;
        esac
    done

    [[ -d "$HOARDS_DIR" ]] || return 0

    local d hoard_name flavors_csv
    for d in "$HOARDS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        hoard_name="$(basename "$d")"
        flavors_csv="$(ws_classify_hoard "$d")"

        # Apply --flavor filter
        if [[ -n "$filter_flavor" ]]; then
            local found=false
            local IFS=,
            for f in $flavors_csv; do
                if [[ "$f" == "$filter_flavor" ]]; then
                    found=true
                    break
                fi
            done
            $found || continue
        fi

        if $names_only; then
            echo "$hoard_name"
        else
            echo "- name: $hoard_name"
            # Strip trailing slash from path for cleanliness
            echo "  path: ${d%/}"
            if [[ -z "$flavors_csv" ]]; then
                echo "  flavors: []"
            else
                # Convert "a,b" → "[a, b]" for inline YAML list form
                local yaml_list="${flavors_csv//,/, }"
                echo "  flavors: [$yaml_list]"
            fi
        fi
    done
}
```

- [ ] **Step 5: Wire `scan` into the dispatcher**

In the `case "$SUBCMD" in` block at the bottom of the file (around line 571), add a `scan)` clause. The full updated block:

```bash
case "$SUBCMD" in
    ""|--help|-h)
        ws_hoard_help
        ;;
    init)
        ws_hoard_init "$@"
        ;;
    list)
        ws_hoard_list
        ;;
    scan)
        ws_hoard_scan "$@"
        ;;
    cadence)
        ws_hoard_cadence
        ;;
    thalamus-path)
        ws_resolve_thalamus_path
        ;;
    *)
        ws_hoard_clone_url "$SUBCMD" "$@"
        ;;
esac
```

- [ ] **Step 6: Add `scan` to `ws_hoard_help()` output**

In `ws_hoard_help()` (around line 143), insert the `scan` line just below `list`:

```bash
    echo "  scan [--flavor <name>] [--names-only]" >&2
    echo "                           Emit a YAML inventory of hoards classified by" >&2
    echo "                           flavor (thalami / obsidian / claudesidian)" >&2
```

- [ ] **Step 7: Run `bash -n` syntax check**

```bash
bash -n /Users/cervator/dev/git_ws/yggdrasil/scripts/ws-hoard.sh
```

Expected: no output (clean syntax). Any error → fix and re-run.

- [ ] **Step 8: Run the full scan and verify the output matches expectations**

```bash
ws hoard scan
```

Expected output (order may vary depending on filesystem enumeration):

```yaml
- name: borgr
  path: /Users/cervator/dev/git_ws/yggdrasil/hoards/borgr
  flavors: [obsidian, claudesidian]
- name: nonclaudesidian
  path: /Users/cervator/dev/git_ws/yggdrasil/hoards/nonclaudesidian
  flavors: [obsidian]
- name: thalami-Cervator
  path: /Users/cervator/dev/git_ws/yggdrasil/hoards/thalami-Cervator
  flavors: [thalami]
```

If any record is wrong, recheck the classifier rules (especially the multi-signal claudesidian detection — verify `borgr/CLAUDE.md` has "Claudesidian" or "PARA" in its first 30 lines).

- [ ] **Step 9: Verify `--flavor` filter**

```bash
ws hoard scan --flavor obsidian
```

Expected: two records (`borgr`, `nonclaudesidian`). `thalami-Cervator` filtered out.

```bash
ws hoard scan --flavor claudesidian
```

Expected: one record (`borgr`).

```bash
ws hoard scan --flavor thalami
```

Expected: one record (`thalami-Cervator`).

- [ ] **Step 10: Verify `--names-only` flag**

```bash
ws hoard scan --names-only
```

Expected: three lines, each a bare hoard name (`borgr`, `nonclaudesidian`, `thalami-Cervator`).

```bash
ws hoard scan --flavor obsidian --names-only
```

Expected: two lines (`borgr`, `nonclaudesidian`).

- [ ] **Step 11: Verify error handling**

```bash
ws hoard scan --flavor
```

Expected: stderr `ERROR: --flavor requires a value`, exit 2.

```bash
ws hoard scan --bogus
```

Expected: stderr `ERROR: Unknown flag: --bogus`, exit 2.

- [ ] **Step 12: Write the commit bodyfile**

Create `/Users/cervator/dev/git_ws/yggdrasil/.commits/phase-a-scan.md`:

```markdown
---
message: |
  feat(ws-hoard): add scan subcommand for vault classification

  Iterates hoards/ and emits a YAML inventory tagging each with one or
  more flavors (thalami, obsidian, claudesidian). Multi-signal detection
  for claudesidian (.obsidian + .claude + signed CLAUDE.md) avoids
  false-positives on unrelated .claude/ dirs.

  Used by the new scribe skill for deterministic vault discovery.
  Companion to the design + plan committed separately on this branch.
add:
  - scripts/ws-hoard.sh
---
```

- [ ] **Step 13: Commit Phase A**

```bash
ws commit yggdrasil .commits/phase-a-scan.md
```

Verify the commit lands cleanly and includes the spec + plan files.

---

# Phase B — Templates

Adds `templates/hoards/obsidian-vault/` (vendored, vanilla) and `templates/hoards/claudesidian-vault/` (thin wrapper that clones upstream on init), plus extends `ws hoard init` to detect `template.yaml` and follow the clone-on-init flow.

### Task B1: Build `templates/hoards/obsidian-vault/` directory structure

**Files:**
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.gitignore`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.obsidian/app.json`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.obsidian/appearance.json`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.obsidian/core-plugins.json`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/01_Projects/README.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/02_Areas/README.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/03_Resources/README.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/04_Archive/README.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/05_Attachments/.gitkeep`

- [ ] **Step 1: Verify the parent directory exists**

```bash
ls /Users/cervator/dev/git_ws/yggdrasil/templates/hoards/
```

Expected: `basic` and `thalami` directories already exist.

- [ ] **Step 2: Create the `.gitignore`**

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.gitignore`:

```
# Obsidian local state — not vault content
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.trash/

# Common OS / editor cruft
.DS_Store
Thumbs.db
*.swp
```

- [ ] **Step 3: Create minimal `.obsidian/` config files**

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.obsidian/app.json`:

```json
{
  "promptDelete": true,
  "alwaysUpdateLinks": true,
  "newFileLocation": "folder",
  "newFileFolderPath": "00_Inbox",
  "useMarkdownLinks": false,
  "newLinkFormat": "shortest",
  "attachmentFolderPath": "05_Attachments"
}
```

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.obsidian/appearance.json`:

```json
{
  "theme": "obsidian",
  "baseFontSize": 16
}
```

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/.obsidian/core-plugins.json`:

```json
[
  "file-explorer",
  "global-search",
  "switcher",
  "graph",
  "backlink",
  "outgoing-link",
  "tag-pane",
  "page-preview",
  "daily-notes",
  "templates",
  "command-palette",
  "markdown-importer",
  "outline",
  "word-count",
  "file-recovery"
]
```

(No community plugins. User installs what they want.)

- [ ] **Step 4: Create the per-folder README files**

Each PARA folder gets a one-line description so the empty folders survive git and explain themselves to anyone browsing.

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/01_Projects/README.md`:

```markdown
# 01_Projects

Time-bound initiatives with a clear completion criterion. Each project
lives in its own subfolder. When complete, move the folder to `04_Archive/`.
```

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/02_Areas/README.md`:

```markdown
# 02_Areas

Ongoing responsibilities without an end date — health, finances, work,
relationships. Notes here are maintained over time, not completed.
```

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/03_Resources/README.md`:

```markdown
# 03_Resources

Reference material organized by topic — research notes, articles, snippets.
Not tied to any specific project.
```

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/04_Archive/README.md`:

```markdown
# 04_Archive

Completed projects and inactive notes. Preserved for reference but no
longer actively maintained.
```

- [ ] **Step 5: Create the attachments placeholder**

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/05_Attachments/.gitkeep` (empty file). Keeps the folder tracked even when empty.

- [ ] **Step 6: Verify directory structure**

```bash
find /Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault -type f | sort
```

Expected: 9 files at this point (`.gitignore`, three `.obsidian/*.json`, four folder READMEs, one `.gitkeep`). Welcome.md, Templates, and the top-level README come in next tasks.

### Task B2: Add `obsidian-vault` content (Welcome.md, Templates/, top-level README)

**Files:**
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/00_Inbox/Welcome.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/06_Metadata/Templates/daily-note.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/06_Metadata/Templates/project-note.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/06_Metadata/Templates/meeting-note.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/06_Metadata/Templates/inbox-capture.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/06_Metadata/Templates/weekly-review.md`

- [ ] **Step 1: Create `00_Inbox/Welcome.md`**

Write `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/00_Inbox/Welcome.md`:

```markdown
---
created: {{date:YYYY-MM-DD}}
tags: [welcome]
status: active
---

# Welcome to your vault

This is a plain Obsidian vault scaffolded by GDD using the
`obsidian-vault` template.

## Getting started

The folders use the [PARA Method](https://fortelabs.com/blog/para/):

- [[01_Projects/README|Projects]] — time-bound initiatives
- [[02_Areas/README|Areas]] — ongoing responsibilities
- [[03_Resources/README|Resources]] — reference material
- [[04_Archive/README|Archive]] — completed or inactive

New captures go in `00_Inbox/`. Process them weekly, moving each note
into its proper PARA folder or deleting it.

## Templates

`06_Metadata/Templates/` has starter notes for daily, project, meeting,
inbox-capture, and weekly-review patterns. Obsidian's built-in Templates
plugin can insert them via the Command Palette.

## Working from GDD

If you're using this from a GDD workspace, the `scribe` skill handles
PARA conventions, frontmatter habits, and capture-process-organize
workflows automatically. Just say things like *"jot this in my inbox"*
or *"start a daily note"* and the workspace agent will follow this
vault's conventions.

You can also run Claude Code directly inside this vault — useful if you
want to operate the vault standalone without the surrounding GDD
workspace context.
```

- [ ] **Step 2: Create `06_Metadata/Templates/daily-note.md`**

Write the file:

```markdown
---
created: {{date:YYYY-MM-DD}}
tags: [daily]
status: active
---

# {{date:YYYY-MM-DD}} — Daily Note

## Today

## Captures

## Links

```

- [ ] **Step 3: Create `06_Metadata/Templates/project-note.md`**

Write the file:

```markdown
---
created: {{date:YYYY-MM-DD}}
tags: [project]
status: active
deadline:
---

# {{title}}

## Goal

What does done look like?

## Scope

What's in, what's out.

## Deliverable

The single artifact this project produces.

## Research

## Drafts

## Output

## Links

```

- [ ] **Step 4: Create `06_Metadata/Templates/meeting-note.md`**

Write the file:

```markdown
---
created: {{date:YYYY-MM-DD}}
tags: [meeting]
status: active
attendees: []
---

# Meeting — {{title}} — {{date:YYYY-MM-DD}}

## Agenda

## Discussion

## Decisions

## Action items

- [ ] 

## Links

```

- [ ] **Step 5: Create `06_Metadata/Templates/inbox-capture.md`**

Write the file:

```markdown
---
created: {{date:YYYY-MM-DD}}
tags: [inbox]
status: unprocessed
---

# {{title}}

```

- [ ] **Step 6: Create `06_Metadata/Templates/weekly-review.md`**

Write the file:

```markdown
---
created: {{date:YYYY-MM-DD}}
tags: [weekly-review]
status: active
---

# Weekly Review — week of {{date:YYYY-MM-DD}}

## Inbox processed

How many items, where they went.

## Active projects

What progressed, what stalled.

## Areas check

Any area need attention?

## Resources captured

What new material is worth keeping.

## Archive candidates

What can move to `04_Archive/`.

## Next week

```

- [ ] **Step 7: Verify Templates folder structure**

```bash
ls /Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/06_Metadata/Templates/
```

Expected: 5 files (`daily-note.md`, `inbox-capture.md`, `meeting-note.md`, `project-note.md`, `weekly-review.md`).

### Task B3: Add `obsidian-vault/README.md`

**Files:**
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault/README.md`

- [ ] **Step 1: Write the README**

Write the file:

```markdown
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
- The vault is its own git repo; commit and push it like any other repo

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
```

- [ ] **Step 2: Verify the obsidian-vault template is complete**

```bash
find /Users/cervator/dev/git_ws/yggdrasil/templates/hoards/obsidian-vault -type f | sort
```

Expected file list (15 files):

```
.../obsidian-vault/.gitignore
.../obsidian-vault/.obsidian/app.json
.../obsidian-vault/.obsidian/appearance.json
.../obsidian-vault/.obsidian/core-plugins.json
.../obsidian-vault/00_Inbox/Welcome.md
.../obsidian-vault/01_Projects/README.md
.../obsidian-vault/02_Areas/README.md
.../obsidian-vault/03_Resources/README.md
.../obsidian-vault/04_Archive/README.md
.../obsidian-vault/05_Attachments/.gitkeep
.../obsidian-vault/06_Metadata/Templates/daily-note.md
.../obsidian-vault/06_Metadata/Templates/inbox-capture.md
.../obsidian-vault/06_Metadata/Templates/meeting-note.md
.../obsidian-vault/06_Metadata/Templates/project-note.md
.../obsidian-vault/06_Metadata/Templates/weekly-review.md
.../obsidian-vault/README.md
```

### Task B4: Build `templates/hoards/claudesidian-vault/` thin wrapper

**Files:**
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/claudesidian-vault/template.yaml`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/claudesidian-vault/README.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/claudesidian-vault/gdd-bridge/AGENTS.md`
- Create: `/Users/cervator/dev/git_ws/yggdrasil/templates/hoards/claudesidian-vault/gdd-bridge/README.md`

- [ ] **Step 1: Write `template.yaml`**

Write the file:

```yaml
# Claudesidian wrapper template
#
# This template doesn't vendor upstream files — it clones Claudesidian
# from GitHub at init time. The clone-on-init flow is implemented in
# scripts/ws-hoard.sh's ws_hoard_init() function (Task B5).

# Upstream source. Required.
upstream: https://github.com/heyitsnoah/claudesidian

# Pinned commit or tag. Re-vendor by bumping this when upstream releases
# a version worth picking up. Empty string = follow default branch.
pin: ""

# Fallback URL if upstream clone fails (e.g. GitHub outage, repo moved).
# Currently a placeholder — the SiliconSaga fork doesn't yet exist.
# Populate when the fork is created.
fallback: ""

# Post-clone steps applied in order:
#   strip_git    — rm -rf .git so ws hoard init can re-init the clone
#                  as the user's own repo
#   apply_bridge — copy gdd-bridge/* into the cloned vault
post_clone:
  - strip_git
  - apply_bridge
```

- [ ] **Step 2: Write `README.md`**

Write the file:

```markdown
# Claudesidian Vault (GDD Wrapper)

A thin wrapper around [Claudesidian](https://github.com/heyitsnoah/claudesidian)
— Noah Brier and Alephic's Claude-Code-friendly Obsidian starter kit
(MIT licensed). When you run `ws hoard init claudesidian-vault <name>`,
GDD clones the upstream repo into `hoards/<name>/`, strips its `.git`
directory, and overlays a small `gdd-bridge/` set of files that wire
the vault into the surrounding workspace.

## Attribution

- **Upstream:** <https://github.com/heyitsnoah/claudesidian>
- **License:** MIT (see `LICENSE` in the cloned vault)
- **Built by:** Noah Brier — see <https://every.to/podcast/how-to-use-claude-code-as-a-thinking-partner>
- **Maintained by:** [Alephic](https://alephic.com)

This template is a pointer, not a fork. The full Claudesidian
experience and any updates to it come from upstream.

## What `ws hoard init claudesidian-vault` does

1. Clones the upstream repo into `hoards/<name>/`
2. Removes the cloned `.git/` directory so the hoard can be re-init'd
   as your own repo (per existing `ws hoard init` convention)
3. Copies files from this template's `gdd-bridge/` into the new vault
   (currently `AGENTS.md` and a small `README.md` explaining the bridge)
4. Initializes a fresh git repo for the hoard
5. Prints the optional `/init-bootstrap` tip below

## Optional: run the Claudesidian onboarding once

The bridge GDD provides covers core Claudesidian conventions out of
the box, but Claudesidian's upstream `/init-bootstrap` command builds
a personalized `CLAUDE.md` (writing style, custom context, optionally
pulled from public profiles). If you want that, do it once standalone:

```bash
cd hoards/<your-vault-name>
claude
/init-bootstrap
```

Then exit and resume in your usual GDD-rooted Claude session — the
`scribe-claudesidian` skill picks up the personalized `CLAUDE.md`
automatically.

Skip this if you're happy with the generic Claudesidian conventions;
nothing important breaks. Even without `/init-bootstrap`, the
`CLAUDE-BOOTSTRAP.md` shipped by upstream provides the core PARA and
vault-handling guidance that `scribe-claudesidian` reads as a fallback.

## Optional: install Obsidian

The vault works fine from Claude Code alone, but
[Obsidian](https://obsidian.md) provides graph view, search, plugin
ecosystem, and the visual interface most Obsidian workflows assume.
Open the cloned vault folder as an Obsidian vault.

## Working from GDD vs. running Claude inside the hoard

This template's main purpose is letting you operate the vault from a
single Claude session rooted at your yggdrasil workspace, instead of
having to `cd` into the vault and start a new session there. The
`scribe-claudesidian` skill (in
`.agent/skills/scribe-claudesidian/SKILL.md`) provides equivalent
plain-text invocation of Claudesidian commands like
`/thinking-partner` and `/weekly-synthesis` from the workspace root.

If you prefer the standalone Claudesidian experience — slash-command
auto-completion, hooks, MCP servers wired up natively — just `cd` into
the hoard and run `claude` there. Both modes coexist; `gdd-bridge/`
files don't interfere with standalone use.
```

- [ ] **Step 3: Write `gdd-bridge/AGENTS.md`**

This file lands inside the cloned vault. It tells any agent operating
*from inside* the hoard that the parent workspace provides a richer
context, while keeping the standalone experience functional.

Write the file:

```markdown
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
yggdrasil workspace:

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
```

- [ ] **Step 4: Write `gdd-bridge/README.md`**

Write the file:

```markdown
# `gdd-bridge/` — Why this directory is here

This is a small overlay of files that GDD adds to a freshly cloned
Claudesidian vault. They land in the vault root after the clone:

- `AGENTS.md` — explains the bridged-vs-standalone distinction to
  any agent operating from inside the vault
- `README.md` (this file) — explains why `gdd-bridge/` exists, kept
  for human navigation

Nothing here modifies upstream Claudesidian files. If you ever
re-vendor by re-cloning upstream, the bridge files will be re-applied
automatically by `ws hoard init`.
```

- [ ] **Step 5: Verify the claudesidian-vault template structure**

```bash
find /Users/cervator/dev/git_ws/yggdrasil/templates/hoards/claudesidian-vault -type f | sort
```

Expected (4 files):

```
.../claudesidian-vault/README.md
.../claudesidian-vault/gdd-bridge/AGENTS.md
.../claudesidian-vault/gdd-bridge/README.md
.../claudesidian-vault/template.yaml
```

### Task B5: Extend `ws_hoard_init()` to handle `template.yaml`

**Files:**
- Modify: `/Users/cervator/dev/git_ws/yggdrasil/scripts/ws-hoard.sh`

- [ ] **Step 1: Identify the insertion points**

Read the existing `ws_hoard_init()` function (around lines 304–466). The plan inserts a new helper before it and a detection branch inside it just before the `cp -R "$template_dir" "$target"` line (around line 422).

- [ ] **Step 2: Add the `ws_hoard_init_from_yaml()` helper**

Insert this just before `ws_hoard_init()`:

```bash
# Init a hoard from a template that uses `template.yaml` for clone-on-init
# semantics (instead of the standard cp -R). Returns 0 on success, 1 if
# the template doesn't have a template.yaml (caller should fall back to
# the standard flow), or exits non-zero on actual failure.
#
# Args:
#   $1 — template directory (e.g. templates/hoards/claudesidian-vault)
#   $2 — target hoard directory (e.g. hoards/my-vault)
ws_hoard_init_from_yaml() {
    local template_dir="$1"
    local target="$2"
    local manifest="$template_dir/template.yaml"

    [[ -f "$manifest" ]] || return 1   # Not a yaml-driven template

    local upstream pin fallback
    upstream="$(yq '.upstream // ""' "$manifest" 2>/dev/null)"
    pin="$(yq '.pin // ""' "$manifest" 2>/dev/null)"
    fallback="$(yq '.fallback // ""' "$manifest" 2>/dev/null)"

    [[ "$upstream" == "null" ]] && upstream=""
    [[ "$pin" == "null" ]] && pin=""
    [[ "$fallback" == "null" ]] && fallback=""

    if [[ -z "$upstream" ]]; then
        echo "ERROR: $manifest is missing the 'upstream' field." >&2
        exit 1
    fi

    echo "Cloning $upstream into $target..."
    if ! git clone "$upstream" "$target" 2>/dev/null; then
        if [[ -n "$fallback" ]]; then
            echo "  Upstream clone failed; trying fallback: $fallback" >&2
            if ! git clone "$fallback" "$target"; then
                echo "ERROR: both upstream and fallback clones failed." >&2
                exit 1
            fi
        else
            echo "ERROR: upstream clone failed and no fallback configured." >&2
            echo "  Check network access or update the manifest:" >&2
            echo "    $manifest" >&2
            exit 1
        fi
    fi

    # Honor the pin if set
    if [[ -n "$pin" ]]; then
        (cd "$target" && git checkout -q "$pin") || {
            echo "WARNING: failed to check out pin '$pin'; staying on default branch." >&2
        }
    fi

    # Strip cloned .git so the upcoming git init in ws_hoard_init() can
    # re-init this as the user's own repo (matches the standard flow's
    # post-condition).
    rm -rf "$target/.git"

    # Apply gdd-bridge/* if present (overlay into vault root)
    if [[ -d "$template_dir/gdd-bridge" ]]; then
        # cp -R the gdd-bridge contents (not the directory itself) into target
        cp -R "$template_dir/gdd-bridge/." "$target/"
        echo "Applied gdd-bridge overlay."
    fi

    # Print optional /init-bootstrap tip if the cloned vault advertises one
    # in its README. We grep loosely so this works for any future template
    # that wants to surface a similar tip.
    local clone_readme="$target/README.md"
    if [[ -f "$clone_readme" ]] && grep -qiE 'init-bootstrap|bootstrap wizard' "$clone_readme" 2>/dev/null; then
        echo ""
        echo "Tip: this vault has an optional onboarding wizard. To run it:"
        echo "  cd $target"
        echo "  claude"
        echo "  /init-bootstrap"
        echo ""
    fi

    return 0
}
```

- [ ] **Step 3: Branch in `ws_hoard_init()` to call the YAML helper when present**

Find the existing line in `ws_hoard_init()` that does the standard copy:

```bash
    # Copy template directory
    mkdir -p "$HOARDS_DIR"
    cp -R "$template_dir" "$target"
```

Replace those three lines with:

```bash
    # Copy template directory — UNLESS this is a yaml-driven template,
    # in which case follow the clone-on-init flow instead.
    mkdir -p "$HOARDS_DIR"
    if ws_hoard_init_from_yaml "$template_dir" "$target"; then
        : # YAML-driven flow handled the clone + post-clone steps
    else
        # Standard flow: copy template files verbatim
        cp -R "$template_dir" "$target"
    fi
```

The exit code from `ws_hoard_init_from_yaml` distinguishes "not a yaml template, go fall back" (1) from "yaml flow ran successfully" (0). On actual failure, the helper exits the script directly.

- [ ] **Step 4: Update the templates list in help text**

In `ws_hoard_help()` (around line 151), update the line listing available templates:

Existing:
```bash
    echo "                           Available templates: thalami, basic" >&2
```

Replace with:
```bash
    echo "                           Available templates: thalami, basic, obsidian-vault, claudesidian-vault" >&2
```

- [ ] **Step 5: Run `bash -n` syntax check**

```bash
bash -n /Users/cervator/dev/git_ws/yggdrasil/scripts/ws-hoard.sh
```

Expected: clean (no output).

- [ ] **Step 6: Smoke test — init the obsidian-vault template**

```bash
cd /tmp
rm -rf test-yggdrasil-init
mkdir test-yggdrasil-init && cd test-yggdrasil-init
mkdir -p hoards
HOARDS_DIR=$PWD/hoards ROOT_DIR=/Users/cervator/dev/git_ws/yggdrasil \
    ws hoard init obsidian-vault --name test-vault
```

(Note: this assumes `identity.human_account` is resolvable from the workspace's `ecosystem.local.yaml`. If it errors with "identity.human_account is not set", set it temporarily or run from the actual workspace.)

Expected:
- `/tmp/test-yggdrasil-init/hoards/test-vault/` is created
- Contains the 15 files from Task B3
- Has its own `.git/` (re-init'd by the standard flow's git init step)

```bash
ls /tmp/test-yggdrasil-init/hoards/test-vault/
```

Expected: `00_Inbox  01_Projects  02_Areas  03_Resources  04_Archive  05_Attachments  06_Metadata  README.md` (.gitignore + .obsidian/ also present but may not show with default `ls`).

- [ ] **Step 7: Smoke test — init the claudesidian-vault template (network required)**

This requires network access to clone the upstream repo. If the test machine is offline, skip and verify visually.

```bash
cd /tmp/test-yggdrasil-init
HOARDS_DIR=$PWD/hoards ROOT_DIR=/Users/cervator/dev/git_ws/yggdrasil \
    ws hoard init claudesidian-vault --name test-claudesidian
```

Expected output includes:
```
Cloning https://github.com/heyitsnoah/claudesidian into ...
Applied gdd-bridge overlay.
Tip: this vault has an optional onboarding wizard...
```

Then:
```bash
ls /tmp/test-yggdrasil-init/hoards/test-claudesidian/
```

Expected: contents of upstream Claudesidian (CLAUDE-BOOTSTRAP.md, README.md, 00_Inbox/, etc.) PLUS `AGENTS.md` from `gdd-bridge/`.

```bash
test -d /tmp/test-yggdrasil-init/hoards/test-claudesidian/.git && echo "FAIL: .git not stripped"
test -f /tmp/test-yggdrasil-init/hoards/test-claudesidian/AGENTS.md || echo "FAIL: gdd-bridge AGENTS.md not applied"
```

Expected: no FAIL output. (The standard flow re-inits its own .git after the helper returns; that's correct.)

- [ ] **Step 8: Clean up smoke-test fixtures**

```bash
rm -rf /tmp/test-yggdrasil-init
```

- [ ] **Step 9: Write the commit bodyfile**

Create `/Users/cervator/dev/git_ws/yggdrasil/.commits/phase-b-templates.md`:

```markdown
---
message: |
  feat(hoards): add obsidian-vault and claudesidian-vault templates

  obsidian-vault is a vendored vanilla Obsidian vault with PARA layout
  (00-06), minimal .obsidian/ config, and starter templates for daily
  notes, projects, meetings, weekly review, and inbox capture.

  claudesidian-vault is a thin wrapper that clones upstream Claudesidian
  on init and overlays a small gdd-bridge/ folder. ws_hoard_init now
  detects template.yaml and follows the clone-on-init flow when present.

  Per design in docs/plans/2026-05-01-scribe-role-and-vault-templates-design.md.
add:
  - templates/hoards/obsidian-vault/
  - templates/hoards/claudesidian-vault/
  - scripts/ws-hoard.sh
---
```

- [ ] **Step 10: Commit Phase B**

```bash
ws commit yggdrasil .commits/phase-b-templates.md
```

---

# Phase C — Skills

The two new skill files. Each is plain markdown — verification is by reading and confirming structure matches the spec.

### Task C1: Create `.agent/skills/scribe/SKILL.md`

**Files:**
- Create: `/Users/cervator/dev/git_ws/yggdrasil/.agent/skills/scribe/SKILL.md`

- [ ] **Step 1: Write the skill file**

```markdown
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
  surfaces the vault and offers scribe role; if user accepts, this skill
  loads
- **Path C — mid-session keyword dip-in** — user says something matching
  capture intent (*"jot this in my inbox"*, *"add a daily note"*,
  *"capture this idea"*) while in another role; load this skill ad-hoc
  and perform the requested action without formally swapping role
- **Path D — explicit user ask** — *"scribe role for this session"* or
  *"scribe on borgr"*

## Vault Discovery and Binding

Run `ws hoard scan --flavor vault` and parse the YAML inventory.
Then apply binding rules:

| Match count | Action |
|-------------|--------|
| 0 | Tell the user no obsidian-flavored hoards exist. Offer `ws hoard init obsidian-vault` or `ws hoard init claudesidian-vault`. Exit binding flow if declined. |
| 1 | Auto-bind to the single match. In-memory pin for the session. |
| >1 | Check Thalamus frontmatter for `active_vault: <name>`. If set and matches a scanned hoard, use it silently. Otherwise ask the user which vault for this session. |

After binding, re-check the bound hoard's flavor list. If it contains
`claudesidian`, also load `.agent/skills/scribe-claudesidian/SKILL.md`
to layer on the extension behavior.

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
   - Delete anything no longer needed
   - Move project material to `01_Projects/<name>/`
   - Move ongoing-responsibility notes to `02_Areas/<area>/`
   - Move reference material to `03_Resources/<topic>/`
   - Update each moved note's frontmatter (`status: active`, add tags)
   - Update wikilinks if names change
3. **Organize** — keep `00_Inbox/` under 20 items; if it's growing,
   processing cadence is too slow

When processing, never auto-delete user content silently. Move into a
subfolder under `04_Archive/` if uncertain.

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

When in doubt, ask: *"sounds like you want to capture this — should I
add it to your vault inbox?"* before loading the skill and binding to
a vault.

## Multi-vault Edge Case

If Path C (keyword dip-in) triggers in a workspace with multiple
obsidian-flavored hoards and no `active_vault:` is set, the binding
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
```

- [ ] **Step 2: Verify the file structure**

```bash
ls /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/scribe/
```

Expected: `SKILL.md`.

```bash
head -10 /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/scribe/SKILL.md
```

Expected: frontmatter with `name: scribe` and the description starting with "Obsidian vault conventions".

### Task C2: Create `.agent/skills/scribe-claudesidian/SKILL.md`

**Files:**
- Create: `/Users/cervator/dev/git_ws/yggdrasil/.agent/skills/scribe-claudesidian/SKILL.md`

- [ ] **Step 1: Write the skill file**

```markdown
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

Read `<vault>/.claude/claude_config.json`. It declares Claudesidian
commands like:

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

On first activation in a session, surface the inventory once briefly:

> "Claudesidian-flavored vault detected. Commands available:
> thinking-partner, inbox-processor, weekly-synthesis, daily-review,
> research-assistant, de-ai-ify, pull-request, release. Invoke any in
> plain text — e.g. *'do a weekly synthesis'* — and I'll follow the
> matching instruction file."

If `.claude/claude_config.json` is missing (older Claudesidian or
manually trimmed), fall back to enumerating `.claude/commands/*.md`
files directly and report just the filename stems.

## Plain-Text Invocation Pattern

When the user references a Claudesidian command in plain text:

1. Match the request against the command names from the manifest.
   Match leniently — *"do a weekly synthesis"*, *"weekly synthesis"*,
   *"run the weekly synthesis command"* all map to `weekly-synthesis`.
   Shortcuts (e.g. `ws` → `weekly-synthesis`) also count.
2. Read the matching command file (`<vault>/.claude/commands/<cmd>.md`)
3. Cite the file path so the user can see what was loaded:
   *"Following `<vault>/.claude/commands/weekly-synthesis.md`..."*
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
```

- [ ] **Step 2: Verify the file structure**

```bash
ls /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/scribe-claudesidian/
```

Expected: `SKILL.md`.

```bash
head -10 /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/scribe-claudesidian/SKILL.md
```

Expected: frontmatter with `name: scribe-claudesidian`.

### Task C3: Commit Phase C

- [ ] **Step 1: Write the commit bodyfile**

Create `/Users/cervator/dev/git_ws/yggdrasil/.commits/phase-c-skills.md`:

```markdown
---
message: |
  feat(skills): add scribe and scribe-claudesidian skills

  scribe handles plain Obsidian vault conventions: PARA layout,
  frontmatter habits, wikilinks, daily notes, inbox capture loop.
  Calls `ws hoard scan` for vault discovery. Auto-loads for
  `role: scribe`; other roles dip in on capture-intent keywords.

  scribe-claudesidian extends scribe for Claudesidian-flavored vaults.
  Reads vault CLAUDE.md (or CLAUDE-BOOTSTRAP.md fallback), surfaces
  the command manifest from .claude/claude_config.json, and lets the
  user invoke /thinking-partner, /weekly-synthesis, etc. in plain
  text from the workspace root.

  Per design in docs/plans/2026-05-01-scribe-role-and-vault-templates-design.md.
add:
  - .agent/skills/scribe/SKILL.md
  - .agent/skills/scribe-claudesidian/SKILL.md
---
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/phase-c-skills.md
```

---

# Phase D — Wiring

Small additions to AGENTS.md, the orientation skill, the gdd skill role list, and the thalamus template. Each is a few-line edit.

### Task D1: Update `gdd-orientation/SKILL.md` with vault-scan step

**Files:**
- Modify: `/Users/cervator/dev/git_ws/yggdrasil/.agent/skills/gdd-orientation/SKILL.md`

- [ ] **Step 1: Read the existing Step 6 section**

Find the section "### Step 6: Trust Verification of Realms and Nested Components" with subsections 6a (active realm) and 6b (cloned components).

- [ ] **Step 2: Add a new subsection 6c for vault scan**

After subsection 6b (cloned components), insert this new subsection:

```markdown
#### 6c: Hoard vault scan

If `Thalamus.md` frontmatter has `role: null`, also call `ws hoard scan
--flavor vault` to detect any Obsidian or Claudesidian-flavored
hoards. The output is YAML; parse the entries and surface a brief
summary alongside the role question:

> "role is null. Detected vault: borgr (claudesidian), nonclaudesidian
> (obsidian). Want scribe role for vault work, or another (developer
> / designer / reviewer)?"

If `role: scribe` is already set in frontmatter, skip the question —
Step 5's role-default handling already loads the scribe skill, which
runs its own vault-binding sub-flow.

If `ws hoard scan` errors or is unavailable, note the failure and
continue — don't block orientation on it.

The vault scan is informational at orientation time only. Actual
binding (and any prompt for "which vault?") happens later, when the
scribe skill loads — driven by user intent, not orientation.
```

- [ ] **Step 3: Verify the change**

```bash
grep -A2 "6c: Hoard vault scan" /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/gdd-orientation/SKILL.md
```

Expected: the new subsection header and first lines.

### Task D2: Update `gdd/SKILL.md` to add `scribe` to the role list

**Files:**
- Modify: `/Users/cervator/dev/git_ws/yggdrasil/.agent/skills/gdd/SKILL.md`

- [ ] **Step 1: Locate the role list**

```bash
grep -n "developer\|designer\|reviewer" /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/gdd/SKILL.md | head -10
```

Find the section that enumerates roles (per the existing GDD design,
likely a definition list or table with developer / designer /
reviewer).

- [ ] **Step 2: Add `scribe` after `reviewer`**

Add a new entry following the same style as the existing roles:

```markdown
- **scribe** — Note-taking and vault work. Auto-loads
  `.agent/skills/scribe/SKILL.md` for PARA conventions, frontmatter
  habits, daily notes, and the capture-process-organize loop. Other
  roles can dip into the scribe skill on capture-intent keywords.
```

(Adjust the exact markdown style — bullets vs. table row vs. heading —
to match the surrounding entries.)

- [ ] **Step 3: Verify**

```bash
grep -A2 "scribe" /Users/cervator/dev/git_ws/yggdrasil/.agent/skills/gdd/SKILL.md | head -5
```

Expected: the new role entry visible.

### Task D3: Update `AGENTS.md`

**Files:**
- Modify: `/Users/cervator/dev/git_ws/yggdrasil/AGENTS.md`

- [ ] **Step 1: Add two rows to the Skills table**

Find the existing Skills table (around line 67–84). After the existing
rows for the GDD modes, add:

```markdown
| **Scribe** | Obsidian vault conventions: PARA, frontmatter, daily notes, wikilinks, inbox capture. Auto-loads for `role: scribe`; other roles dip in on capture-intent keywords. | [SKILL.md](./.agent/skills/scribe/SKILL.md) |
| **Scribe Claudesidian** | Extension for Claudesidian-flavored vaults: reads vault CLAUDE.md, surfaces command manifest, plain-text invocation of /thinking-partner / /weekly-synthesis / etc. Auto-loaded by scribe when the bound vault has `claudesidian` flavor. | [SKILL.md](./.agent/skills/scribe-claudesidian/SKILL.md) |
```

The two rows go between the existing GDD-mode rows and the BDD rows
(maintain alphabetical-ish grouping by feature area).

- [ ] **Step 2: Update the Hoards section**

Find the "## Hoards (personal containers)" section. Append one line at
the end mentioning the new templates:

```markdown
Hoard templates ship under `templates/hoards/<flavor>/`. Current
flavors: `thalami`, `basic`, `obsidian-vault` (vanilla Obsidian),
`claudesidian-vault` (thin wrapper around upstream
[Claudesidian](https://github.com/heyitsnoah/claudesidian)).
```

- [ ] **Step 3: Verify**

```bash
grep -c "Scribe" /Users/cervator/dev/git_ws/yggdrasil/AGENTS.md
```

Expected: at least 2 (the two skill table rows). Likely also one in
the description text.

```bash
grep "obsidian-vault\|claudesidian-vault" /Users/cervator/dev/git_ws/yggdrasil/AGENTS.md
```

Expected: the new line in the Hoards section.

### Task D4: Update `templates/thalamus.md`

**Files:**
- Modify: `/Users/cervator/dev/git_ws/yggdrasil/templates/thalamus.md`

- [ ] **Step 1: Read the existing frontmatter**

```bash
head -12 /Users/cervator/dev/git_ws/yggdrasil/templates/thalamus.md
```

- [ ] **Step 2: Add the optional `active_vault:` field with a comment**

In the frontmatter block, add the new field with a comment:

```yaml
active_vault: null  # name of the obsidian-flavored hoard scribe should
                    # auto-bind to (skip the "which vault?" prompt when
                    # multiple vaults exist). Leave null to be asked.
```

Place it after the existing role-related field, before the
`staleness_days` line.

- [ ] **Step 3: Verify**

```bash
grep "active_vault" /Users/cervator/dev/git_ws/yggdrasil/templates/thalamus.md
```

Expected: one match showing the new field.

### Task D5: Commit Phase D

- [ ] **Step 1: Write the commit bodyfile**

Create `/Users/cervator/dev/git_ws/yggdrasil/.commits/phase-d-wiring.md`:

```markdown
---
message: |
  feat(gdd): wire scribe role + skills into orientation, AGENTS.md, thalamus

  - gdd-orientation: new Step 6c surfaces detected vaults during the
    role question when role is null
  - gdd skill: adds scribe to the role list alongside developer /
    designer / reviewer
  - AGENTS.md: two new skill table rows + hoards section line listing
    obsidian-vault and claudesidian-vault flavors
  - templates/thalamus.md: documents optional active_vault: frontmatter
    field for users with multiple vaults

  Per design in docs/plans/2026-05-01-scribe-role-and-vault-templates-design.md.
add:
  - .agent/skills/gdd-orientation/SKILL.md
  - .agent/skills/gdd/SKILL.md
  - AGENTS.md
  - templates/thalamus.md
---
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/phase-d-wiring.md
```

---

# Phase E — Verification

End-to-end smoke test of the full feature. No new files; just confirm everything works in concert before declaring the feature done.

### Task E1: End-to-end smoke test

- [ ] **Step 1: Verify `ws hoard scan` against current hoards**

```bash
cd /Users/cervator/dev/git_ws/yggdrasil
ws hoard scan
```

Expected (order may vary): three records — borgr (obsidian, claudesidian), nonclaudesidian (obsidian), thalami-Cervator (thalami).

- [ ] **Step 2: Verify the help output**

```bash
ws hoard help
```

Or:
```bash
ws hoard --help
```

Expected: `scan` listed; `Available templates: thalami, basic, obsidian-vault, claudesidian-vault`.

- [ ] **Step 3: Verify orientation flow surfaces vaults**

Open a fresh Claude session in the workspace and ask "what's available
to work on today?" or similar. The orientation skill should run, call
`ws hoard scan`, and surface the detected vaults.

Expected: agent mentions detected vaults (borgr, nonclaudesidian) in
its session-start summary.

If `Thalamus.md` frontmatter has `role: null`, the agent should also
offer scribe role explicitly during the role question.

- [ ] **Step 4: Verify scribe skill loads on dip-in**

In an existing session in a non-scribe role, say:
*"jot a quick note that the deploy was rolled back to v1.2.3 today"*

Expected: agent recognizes capture intent, loads the scribe skill,
runs vault-binding (auto-binds to the single obsidian vault if you
have one, or asks if multiple), creates a note in `00_Inbox/` with
proper frontmatter and date.

- [ ] **Step 5: Verify scribe-claudesidian extension loads**

After Step 4 (or independently), verify the extension activates when
binding to a claudesidian-flavored vault. Say:
*"do a weekly synthesis on borgr"*

Expected: agent loads scribe + scribe-claudesidian, reads
`hoards/borgr/.claude/commands/weekly-synthesis.md`, cites the file
path, and follows its instructions.

- [ ] **Step 6: Verify template init still works for existing flavors**

Make sure the YAML branching didn't break the standard flow:

```bash
cd /tmp && rm -rf yggdrasil-init-test && mkdir yggdrasil-init-test && cd yggdrasil-init-test
mkdir hoards
HOARDS_DIR=$PWD/hoards ROOT_DIR=/Users/cervator/dev/git_ws/yggdrasil \
    ws hoard init basic --name test-basic
```

Expected: standard cp -R flow runs, `hoards/test-basic/` created from
`templates/hoards/basic/`. No errors.

```bash
rm -rf /tmp/yggdrasil-init-test
```

- [ ] **Step 7: Verify the design + plan docs are committed**

```bash
git -C /Users/cervator/dev/git_ws/yggdrasil log --oneline | head -8
```

Expected: see commits for phases A, B, C, D each with their
descriptive messages.

- [ ] **Step 8: Final check — pre-existing tests still pass**

If yggdrasil has any test suite (pytest, bats, etc.), run it:

```bash
cd /Users/cervator/dev/git_ws/yggdrasil
ws test 2>/dev/null || echo "no test target detected — skipping"
```

Expected: pass, or "no test target" if none configured.

- [ ] **Step 9: Optional — push the branch**

If everything looks clean and you want to land it:

```bash
ws push yggdrasil
```

Then open a CR / PR for review.

---

## Self-Review Checklist (run before declaring complete)

After implementation, do a fresh-eyes pass:

1. **Spec coverage** — go through `docs/plans/2026-05-01-scribe-role-and-vault-templates-design.md` section by section. Every requirement should map to at least one task in this plan. Known mappings:
   - Goals 1-7 → covered across all phases
   - Architecture diagram → Phases A, B, C, D collectively implement each box
   - `ws hoard scan` component → Phase A
   - scribe / scribe-claudesidian skills → Phase C
   - Templates → Phase B
   - AGENTS.md / orientation / role list / thalamus updates → Phase D
   - Vault binding sub-flow → encoded in scribe SKILL.md (Phase C, Task C1)
   - Trigger paths A-D → encoded in scribe SKILL.md "When to Load" section
   - Multi-vault edge case → encoded in scribe SKILL.md
   - Optional `/init-bootstrap` step → in claudesidian-vault README.md (Phase B, Task B4) and scribe-claudesidian SKILL.md (Phase C, Task C2)
   - Out-of-scope items → none of those should appear in any task

2. **Placeholder scan** — search the implemented files for `TBD`, `TODO`, `fill in`, `placeholder` (other than the intentional `fallback: ""` placeholder in `template.yaml` and the `<your-vault-name>` instruction in the README).

3. **Type / signature consistency** — `ws_classify_hoard()` returns CSV; `ws_hoard_scan()` parses by splitting on comma. `ws_hoard_init_from_yaml()` returns 1 for "not yaml" and 0 for "ran"; the caller branches on that.

4. **Cross-file references** — the scribe SKILL.md references `ws hoard scan` (delivered in Phase A) and `.agent/skills/scribe-claudesidian/SKILL.md` (delivered in Phase C). The orientation SKILL.md references `ws hoard scan`. AGENTS.md references both skill files. All these come together by end of Phase D.

If issues surface, fix them inline and re-run the affected smoke tests.
