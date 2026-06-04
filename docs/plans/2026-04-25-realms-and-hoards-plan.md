# Realms and Hoards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the three coordinated changes from
`docs/plans/2026-04-24-realms-and-hoards-design.md`: rename overlay → realm,
introduce top-level `hoards/` + `ws hoard` commands (canonical type:
`thalami`), and promote workspace templates out of `.agent/` to a top-level
`templates/` directory.

**Architecture:** Three sequential phases that each land in a working state.
Phase A relocates templates (independent; nothing else depends on it). Phase B
performs the realm rename atomically (script identifiers + directory + repo
name + docs all flip together — partial states would break the CLI). Phase C
introduces hoards as a new feature on top of the renamed system, then updates
GDD orientation and housekeeping to use them.

**Tech Stack:** Bash (ws CLI), `yq` v4 (Mike Farah), `gh` CLI, markdown
documentation, Mermaid diagrams.

---

## Conventions for executing this plan

- The repo lives at `D:/Dev/GitWS/yggdrasil`. The user's `scripts/` is on
  PATH so `ws <cmd>` works as a bare command. Don't prepend `bash scripts/ws`.
- Always use `ws commit <comp> <bodyfile>` for commits — never raw `git add` /
  `git commit`. Bodyfiles live in `.commits/<name>.md` (gitignored). The
  `.agent/commit-template.md` (after Phase A: `templates/commit.md`) shows
  the frontmatter format.
- Don't chain `ws commit && ws push` — run separately so each can be reviewed.
- Stay on branch `design/realms-and-hoards` for the duration. It's already
  rebased on main and contains the design spec from 2026-04-24.

---

## Files Changed Overview

### Phase A — Templates Relocation

- **Move** `.agent/{thalamus,commit,change,issue}-template.md` → `templates/{thalamus,commit,change,issue}.md`
- **Create** `templates/README.md`, `templates/external/.gitkeep`
- **Modify** `.gitignore` (add `/templates/external/*` rule)
- **Modify** `scripts/ws-commit.sh` (template path)
- **Modify** `scripts/git-cr.sh` (template path)
- **Modify** `scripts/git-issue.sh` (template path)
- **Modify** `.agent/skills/gdd-orientation/SKILL.md` (template path)
- **Modify** `AGENTS.md` (Issue / CR / Commit Drafts table)

### Phase B — Realm Rename

- **Rename** `scripts/ws-overlay.sh` → `scripts/ws-realm.sh`
- **Rename in-file** identifiers (`OVERLAYS_DIR` → `REALMS_DIR`, `ws_detect_overlay` → `ws_detect_realm`, etc.)
- **Rewrite** discovery rule (drop hardcoded `-live`; auto-detect any non-template `realm-*`)
- **Modify** `scripts/ws` (router, env vars, help text)
- **Modify** `scripts/ws-mcp-setup.sh`, `scripts/ws-clone.sh`, `scripts/ws-list.sh`, `scripts/ws-resolve.sh`, `scripts/ws-vscode.sh` (any usage of `OVERLAYS_DIR` / `ws_detect_overlay`)
- **Modify** `ecosystem.yaml`, `ecosystem.local.yaml.example` (selector key + templateOverlay → templateRealm)
- **Modify** `.gitignore` (`/overlays/*` → `/realms/*`)
- **Move on disk** `overlays/` → `realms/`; `realms/overlay-yggdrasil-live` → `realms/realm-siliconsaga`; `realms/overlay-yggdrasil-template` → `realms/realm-template`
- **Move local config** `overlay:` selector → `realm:` (only if user has it set in `ecosystem.local.yaml`)
- **Rename remote** `SiliconSaga/overlay-yggdrasil-live` → `SiliconSaga/realm-siliconsaga` via `gh repo rename`; update the realm's `origin` URL locally
- **Modify** docs: `AGENTS.md`, `CLAUDE.md`, `docs/ecosystem-architecture.md`, `docs/getting-started/index.md`, `docs/ws-cli-guide.md`
- **Modify** skills: `.agent/skills/gdd-orientation/SKILL.md`, `.agent/skills/gdd-housekeeping/SKILL.md`, `.agent/skills/mcp-usage/SKILL.md`, `.agent/skills/gdd-doc-writing/SKILL.md`
- **Modify** `.claude/settings.json` (any `ws overlay` permission patterns → `ws realm`)
- **Add** one-line inheritance reservation comment in `ws_resolve_ecosystem` and a Future Direction note in `docs/ecosystem-architecture.md`

### Phase C — Hoards

- **Create** `hoards/.gitkeep`
- **Modify** `.gitignore` (add `/hoards/*` and `!/hoards/.gitkeep`)
- **Create** `templates/hoards/thalami/README.md`, `templates/hoards/thalami/.gitignore`
- **Create** `scripts/ws-hoard.sh` (new subcommand handler; mirrors ws-realm.sh structure)
- **Modify** `scripts/ws` (add `hoard)` route + help text)
- **Modify** `.claude/settings.json` (add `ws hoard *` permission patterns)
- **Modify** `.agent/skills/gdd-orientation/SKILL.md` (hoard discovery, dual-file awareness, machine-name handling)
- **Modify** `.agent/skills/gdd-housekeeping/SKILL.md` (multi-thalami review mode)
- **Modify** `AGENTS.md` (hoard concept + ws hoard subcommand)

---

# Phase A — Templates Relocation

Independent of the realm rename. Lands cleanly on its own.

### Task A1: Create the templates directory tree and move the four files

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/templates/README.md`
- Create: `D:/Dev/GitWS/yggdrasil/templates/external/.gitkeep`
- Move: `.agent/thalamus-template.md` → `templates/thalamus.md`
- Move: `.agent/commit-template.md` → `templates/commit.md`
- Move: `.agent/change-template.md` → `templates/change.md`
- Move: `.agent/issue-template.md` → `templates/issue.md`
- Modify: `.gitignore`

- [ ] **Step 1: Move the four template files preserving git history**

```bash
cd D:/Dev/GitWS/yggdrasil
mkdir -p templates templates/external
git mv .agent/thalamus-template.md templates/thalamus.md
git mv .agent/commit-template.md templates/commit.md
git mv .agent/change-template.md templates/change.md
git mv .agent/issue-template.md templates/issue.md
```

- [ ] **Step 2: Create `templates/README.md`**

```markdown
# Templates

Workspace scaffolding used by `ws` commands and (future) `ws hoard init`.

## Top-level templates

| File | Used by | Purpose |
|------|---------|---------|
| `thalamus.md` | `gdd-orientation` skill | Seed for a new `Thalamus.md` |
| `commit.md` | `ws commit` | Commit bodyfile frontmatter + body |
| `change.md` | `ws cr` | CR (PR/MR) body |
| `issue.md` | `ws issue` | Issue body |

## Subdirectories

- `hoards/` — templates for `ws hoard init <type>` (e.g. `thalami/`).
- `external/` — gitignored landing area for fetched / externally-sourced
  templates (future "marketplace" use). Tracked only by `.gitkeep`.

## Leaf-to-directory promotion

A template starts as a single file (e.g. `thalamus.md`). If it grows
multi-file, it becomes a directory (`thalamus/`) containing an entry file
(by convention `default.md`). Consumers should resolve in that order.
```

- [ ] **Step 3: Create `templates/external/.gitkeep`**

```bash
: > D:/Dev/GitWS/yggdrasil/templates/external/.gitkeep
```

- [ ] **Step 4: Update `.gitignore` to ignore external template payloads**

Add this block immediately after the `# Generated ArgoCD manifests` block in `.gitignore`:

```gitignore
# External / fetched templates (future marketplace) — gitignored payloads,
# only the .gitkeep is tracked.
/templates/external/*
!/templates/external/.gitkeep
```

- [ ] **Step 5: Verify the moves and structure**

```bash
ls D:/Dev/GitWS/yggdrasil/templates
ls D:/Dev/GitWS/yggdrasil/templates/external
ls D:/Dev/GitWS/yggdrasil/.agent | grep -E '(thalamus|commit|change|issue)-template' || echo "OK: no leftover templates in .agent"
```

Expected: `README.md commit.md change.md external issue.md thalamus.md` in `templates/`; `.gitkeep` in `templates/external/`; no leftovers in `.agent/`.

### Task A2: Repoint script consumers at the new template paths

**Files to modify:**
- `scripts/ws-commit.sh`
- `scripts/git-cr.sh`
- `scripts/git-issue.sh`

- [ ] **Step 1: Find all script references to the old paths**

```bash
cd D:/Dev/GitWS/yggdrasil
grep -rn 'agent/.*-template\.md' scripts/ 2>&1
```

- [ ] **Step 2: Update each script**

For each occurrence, replace `.agent/<name>-template.md` with `templates/<name>.md`:
- `.agent/commit-template.md` → `templates/commit.md`
- `.agent/change-template.md` → `templates/change.md`
- `.agent/issue-template.md` → `templates/issue.md`

Use `Edit` per occurrence. Be precise with the old path string so you don't catch unrelated context.

- [ ] **Step 3: Smoke test that ws commit still works**

```bash
cd D:/Dev/GitWS/yggdrasil
ws commit --help 2>&1 || ws help 2>&1 | head -25
```

(Either should succeed without error about a missing template file.)

### Task A3: Repoint the orientation skill at the new thalamus template path

**Files to modify:**
- `.agent/skills/gdd-orientation/SKILL.md`

- [ ] **Step 1: Find the existing reference**

```bash
grep -n 'thalamus-template\|.agent/thalamus' D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-orientation/SKILL.md
```

- [ ] **Step 2: Update the reference**

Replace `.agent/thalamus-template.md` with `templates/thalamus.md`. The skill currently says, in Step 1:

```
  If the user agrees, first verify that `.gitignore` contains an entry for
  `Thalamus.md` — if it doesn't, warn the human and add it before creating
  the file to prevent accidental commits. Then copy
  `.agent/thalamus-template.md` to `Thalamus.md` in the workspace root.
```

→ change the last sentence to:

```
  the file to prevent accidental commits. Then copy
  `templates/thalamus.md` to `Thalamus.md` in the workspace root.
```

### Task A4: Update `AGENTS.md` template path table

**Files to modify:**
- `AGENTS.md`

- [ ] **Step 1: Update the "Issue / CR / Commit Drafts" table**

Locate the table:

```markdown
| `.agent/issue-template.md` | Committed template for issues |
| `.agent/change-template.md` | Committed template for CR bodies |
| `.agent/commit-template.md` | Committed template for `ws commit` bodyfiles (frontmatter format) |
```

Replace with:

```markdown
| `templates/issue.md` | Committed template for issues |
| `templates/change.md` | Committed template for CR bodies |
| `templates/commit.md` | Committed template for `ws commit` bodyfiles (frontmatter format) |
```

- [ ] **Step 2: Search for any other template-path references in AGENTS.md and CLAUDE.md**

```bash
grep -n 'agent/.*-template\.md' D:/Dev/GitWS/yggdrasil/AGENTS.md D:/Dev/GitWS/yggdrasil/CLAUDE.md
```

Update any hits using the same mapping as Task A2.

### Task A5: Commit Phase A

- [ ] **Step 1: Write the bodyfile**

Create `.commits/templates-relocation.md`:

```markdown
---
message: "refactor: promote templates out of .agent/ to top-level templates/"
add:
  - .gitignore
  - .agent/skills/gdd-orientation/SKILL.md
  - AGENTS.md
  - scripts/ws-commit.sh
  - scripts/git-cr.sh
  - scripts/git-issue.sh
  - templates/README.md
  - templates/thalamus.md
  - templates/commit.md
  - templates/change.md
  - templates/issue.md
  - templates/external/.gitkeep
remove:
  - .agent/thalamus-template.md
  - .agent/commit-template.md
  - .agent/change-template.md
  - .agent/issue-template.md
---

Templates are workspace scaffolding, not agent-specific. Promote the four
template files out of `.agent/` into top-level `templates/`, drop the
redundant `-template` suffix (the directory name already says they're
templates), and reserve `templates/external/` (gitignored) as a future
landing area for fetched / externally-sourced templates.

Adds a leaf-to-directory promotion pattern in the README so a template
that grows multi-file later becomes a directory without breaking
consumers. Repoints script consumers (`ws commit`, `git-cr.sh`,
`git-issue.sh`) and the gdd-orientation skill at the new paths.

Subdirectory `templates/hoards/` is reserved for the upcoming `ws hoard
init <type>` work (Phase C of the realms-and-hoards landing).
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/templates-relocation.md
```

- [ ] **Step 3: Sanity-test the workspace still works**

```bash
ws help | head -10
ws status 2>&1 | head -10
```

Should succeed without errors. If `ws status` warns about modified files, investigate before proceeding.

---

# Phase B — Realm Rename

Atomic. Until every change in this phase lands, intermediate states have
broken paths (e.g. scripts that source `ws-realm.sh` while the file is still
named `ws-overlay.sh`). Execute as a single sequence; commit only at the end.

### Task B1: Rename `scripts/ws-overlay.sh` to `scripts/ws-realm.sh`

**Files:**
- Move: `scripts/ws-overlay.sh` → `scripts/ws-realm.sh`

- [ ] **Step 1: Move the file with git history**

```bash
cd D:/Dev/GitWS/yggdrasil
git mv scripts/ws-overlay.sh scripts/ws-realm.sh
```

### Task B2: Rewrite `scripts/ws-realm.sh` for realm vocabulary and discovery

This is the biggest single change. The new content replaces the old discovery
rule (`overlay-yggdrasil-live` then `overlay-yggdrasil-template`) with the
new rule from the spec: scan `realms/` for any `realm-*` not named
`realm-template`; error if multiple; fall back to `realm-template`.

**Files to modify:**
- `scripts/ws-realm.sh`

- [ ] **Step 1: Replace the file header comment block**

Replace the first ~14 lines (header + subcommand list + shared functions list) with:

```bash
#!/usr/bin/env bash
# ws-realm.sh — Realm management and shared config merge functions
#
# Subcommands (called via ws realm):
#   init            Clone template realm for tutorials
#   <git-url>       Clone community realm from a git URL
#   use <name>      Set active realm in ecosystem.local.yaml
#   list            Show available realms and which is active
#   actions <comp>  List adapter commands for a component
#
# Also provides shared functions sourced by other ws-* scripts:
#   ws_detect_realm       — detect active realm directory name
#   ws_resolve_ecosystem  — three-layer config merge (upstream + realm + local)
#                           (Inheritance reservation: the merge generalizes to
#                           N layers if multi-realm chains land later.)
```

- [ ] **Step 2: Rename env vars and shared identifiers throughout the file**

Use `Edit` with `replace_all: true` for each rename, in order:

1. `OVERLAYS_DIR` → `REALMS_DIR` (replace_all: true)
2. `ws_detect_overlay` → `ws_detect_realm` (replace_all: true)
3. `ws_overlay_help` → `ws_realm_help` (replace_all: true)
4. `ws_overlay_init` → `ws_realm_init` (replace_all: true)
5. `ws_overlay_use` → `ws_realm_use` (replace_all: true)
6. `ws_overlay_list` → `ws_realm_list` (replace_all: true)
7. `ws_overlay_clone_url` → `ws_realm_clone_url` (replace_all: true)

Then update the `: "${REALMS_DIR:="$ROOT_DIR/overlays"}"` line specifically:

```bash
: "${REALMS_DIR:="$ROOT_DIR/realms"}"
```

- [ ] **Step 3: Replace `ws_detect_realm` with the new discovery rule**

Find the function (currently uses `OVERLAYS_DIR`/`ws_detect_overlay` after Step 2 → uses `REALMS_DIR`/`ws_detect_realm`) and replace its body. The new function:

```bash
# Detect the active realm directory name.
# Returns the realm directory name (not the full path) or empty string.
#
# Discovery rule:
#   1. ecosystem.local.yaml `realm:` selector, if set and dir exists
#   2. Single non-template realm in realms/ (matches realm-* but not realm-template)
#   3. realm-template, if present
#   4. Empty (no realm active)
#
# Errors if step 2 finds multiple non-template realms (ambiguous).
ws_detect_realm() {
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        local selector
        if ! selector="$(yq '.realm // ""' "$local_file")"; then
            echo "ERROR: Failed to parse $local_file. Check YAML syntax." >&2
            exit 1
        fi
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$REALMS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi

    # Auto-detect: a single realm-* that is not realm-template
    local candidates=()
    if [[ -d "$REALMS_DIR" ]]; then
        for d in "$REALMS_DIR"/realm-*/; do
            [[ -d "$d" ]] || continue
            local dname
            dname="$(basename "$d")"
            [[ "$dname" == "realm-template" ]] && continue
            candidates+=("$dname")
        done
    fi

    case "${#candidates[@]}" in
        0)
            if [[ -d "$REALMS_DIR/realm-template" ]]; then
                echo "realm-template"
                return
            fi
            echo ""
            ;;
        1)
            echo "${candidates[0]}"
            ;;
        *)
            echo "ERROR: Multiple non-template realms found in realms/: ${candidates[*]}." >&2
            echo "  Set 'realm: <name>' in ecosystem.local.yaml to pick one." >&2
            exit 1
            ;;
    esac
}
```

- [ ] **Step 4: Update `ws_resolve_ecosystem` body and add the inheritance reservation comment**

In `ws_resolve_ecosystem`:
1. Rename `local overlay_file=""` → `local realm_file=""` and `local active_overlay` → `local active_realm`.
2. Update the body's variable references: `overlay_file` → `realm_file`, `active_overlay` → `active_realm`.
3. Update the error message: `"ERROR: Active overlay '$active_overlay'..."` → `"ERROR: Active realm '$active_realm'..."`.
4. Add a one-line inheritance comment at the top of the function body (after the cache check):

```bash
    # Inheritance reservation: today the merge is upstream + realm + local
    # (three layers). When multi-realm inheritance lands, this generalizes
    # to N layers with child-wins semantics — no new identifier needed.
```

- [ ] **Step 5: Update `ws_realm_help` text**

```bash
ws_realm_help() {
    echo "Usage: ws realm <subcommand>" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init            Clone the template realm for tutorials" >&2
    echo "  <git-url>       Clone a community realm" >&2
    echo "  use <name>      Set active realm in ecosystem.local.yaml" >&2
    echo "  list            Show available realms and which is active" >&2
    echo "" >&2
    echo "Also available via ws:" >&2
    echo "  ws actions <comp>   List adapter commands for a component" >&2
}
```

- [ ] **Step 6: Update `ws_realm_init` for the new template name and config key**

Two changes:
1. The config key for the template URL changes: `defaults.templateOverlay` → `defaults.templateRealm`.
2. The target directory: `overlay-yggdrasil-template` → `realm-template`.

After Step 2's `replace_all` for `OVERLAYS_DIR` → `REALMS_DIR`, the function body references `$REALMS_DIR/overlay-yggdrasil-template`. Replace:

```bash
    local target="$REALMS_DIR/overlay-yggdrasil-template"
```

with:

```bash
    local target="$REALMS_DIR/realm-template"
```

And replace:

```bash
    template_url=$(yq '.defaults.templateOverlay // ""' "$eco" 2>/dev/null)
```

with:

```bash
    template_url=$(yq '.defaults.templateRealm // ""' "$eco" 2>/dev/null)
```

Update the error message to reference `defaults.templateRealm`. Update the `echo "Template overlay ready..."` line to say `realm`.

- [ ] **Step 7: Update `ws_realm_clone_url` — drop hardcoded -live name**

The new behavior derives the local directory name from the URL's repo basename rather than hardcoding `overlay-yggdrasil-live`. Replace the function:

```bash
ws_realm_clone_url() {
    local url="$1"
    if [[ ! "$url" =~ ^(https?://|git@) ]]; then
        echo "ERROR: Unknown subcommand or invalid URL '$url'." >&2
        echo "  Run 'ws realm' for usage." >&2
        exit 1
    fi

    # Derive realm directory name from the URL's repo basename
    local basename
    basename="${url##*/}"
    basename="${basename%.git}"
    if [[ ! "$basename" =~ ^realm-[A-Za-z0-9._-]+$ ]]; then
        echo "ERROR: realm repo name must match 'realm-<community>' (got: $basename)." >&2
        echo "  Rename the repo on the host or fork it under a compliant name." >&2
        exit 1
    fi

    local target="$REALMS_DIR/$basename"
    if [[ -d "$target" ]]; then
        echo "ERROR: Realm '$basename' already exists at $target." >&2
        echo "  Remove it first or use 'ws realm use' to switch." >&2
        exit 1
    fi
    mkdir -p "$REALMS_DIR"
    echo "CLONE: community realm -> $target"
    git clone "$url" "$target"
    echo ""
    echo "Community realm ready. Run 'ws clone --all' to clone components."
}
```

- [ ] **Step 8: Update `ws_realm_use`, `ws_realm_list`, error messages**

In `ws_realm_use`:
- Replace `Usage: ws overlay use <name>` → `Usage: ws realm use <name>`.
- Replace `yq -i ".overlay = \"$name\""` → `yq -i ".realm = \"$name\""`.
- Replace `echo "overlay: \"$name\""` → `echo "realm: \"$name\""`.
- Update prose error messages from "overlay" → "realm".

In `ws_realm_list`:
- Replace `echo "=== Overlays ==="` → `echo "=== Realms ==="`.
- Replace `Run 'ws overlay init'...` line to use `ws realm init`.

Anywhere a function still says "overlay" in user-facing output, change it to "realm". Search:

```bash
grep -n 'overlay\|Overlay' D:/Dev/GitWS/yggdrasil/scripts/ws-realm.sh | grep -v '^[[:space:]]*#'
```

Address each remaining hit in user-facing strings. Comments above the inheritance reservation block are fine to leave referencing the historical "overlay" if needed.

- [ ] **Step 9: Update the dispatch case block**

Find:

```bash
case "$SUBCMD" in
    ""|--help|-h)
        ws_overlay_help
```

This becomes (after replace_all from Step 2):

```bash
case "$SUBCMD" in
    ""|--help|-h)
        ws_realm_help
```

— already correct from the global rename. Just verify by re-reading.

- [ ] **Step 10: Syntax check**

```bash
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-realm.sh && echo "syntax ok"
```

### Task B3: Update `scripts/ws` (main router)

**Files:**
- `scripts/ws`

- [ ] **Step 1: Replace `OVERLAYS_DIR` and the source line**

Find:

```bash
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
OVERLAYS_DIR="$ROOT_DIR/overlays"
```

Replace with:

```bash
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
REALMS_DIR="$ROOT_DIR/realms"
```

Find:

```bash
# shellcheck source=ws-overlay.sh
source "$SCRIPT_DIR/ws-overlay.sh"
```

Replace with:

```bash
# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"
```

- [ ] **Step 2: Update the help block**

In the `# Commands:` block at the top of the file, replace these four lines:

```
#   overlay init      Clone template overlay for tutorials
#   overlay <url>     Clone a community overlay
#   overlay use <name> Set active overlay
#   overlay list      Show available overlays
```

with:

```
#   realm init        Clone template realm for tutorials
#   realm <url>       Clone a community realm
#   realm use <name>  Set active realm
#   realm list        Show available realms
```

- [ ] **Step 3: Update the case dispatch**

Find:

```bash
    overlay)
        bash "$SCRIPT_DIR/ws-overlay.sh" "$@"
        ;;
```

Replace with:

```bash
    realm)
        bash "$SCRIPT_DIR/ws-realm.sh" "$@"
        ;;
```

And find:

```bash
    actions)
        bash "$SCRIPT_DIR/ws-overlay.sh" actions "$@"
        ;;
```

Replace with:

```bash
    actions)
        bash "$SCRIPT_DIR/ws-realm.sh" actions "$@"
        ;;
```

- [ ] **Step 4: Sweep remaining "overlay" mentions in `scripts/ws`**

```bash
grep -n 'overlay\|Overlay' D:/Dev/GitWS/yggdrasil/scripts/ws
```

Address user-facing prose. Don't touch references that quote real existing identifiers from sourced scripts (there shouldn't be any after Steps 1–3).

### Task B4: Update consumer scripts that reference overlay identifiers

**Files to scan and update:**
- `scripts/ws-mcp-setup.sh`
- `scripts/ws-clone.sh`
- `scripts/ws-list.sh`
- `scripts/ws-resolve.sh`
- `scripts/ws-vscode.sh`
- `scripts/ws-status.sh`, `scripts/ws-pull.sh`, `scripts/ws-test.sh`, `scripts/ws-review.sh` (probably don't reference overlay; verify and skip if so)

- [ ] **Step 1: Find all references**

```bash
grep -rn 'OVERLAYS_DIR\|ws_detect_overlay\|ws-overlay\.sh\|overlays/\|overlay-yggdrasil' D:/Dev/GitWS/yggdrasil/scripts/
```

- [ ] **Step 2: Apply renames**

For each file with hits, apply these mappings:
- `OVERLAYS_DIR` → `REALMS_DIR`
- `ws_detect_overlay` → `ws_detect_realm`
- `ws-overlay.sh` → `ws-realm.sh`
- Path strings `overlays/` → `realms/`
- Path strings `overlay-yggdrasil-live` → (drop hardcoded; if needed, derive via `ws_detect_realm`)
- Path strings `overlay-yggdrasil-template` → `realm-template`

Use `Edit` with `replace_all: true` per identifier per file.

- [ ] **Step 3: Update `scripts/ws-mcp-setup.sh` specifically**

The Cursor note at the bottom says "overlays/$active_overlay/$mcp_doc". After the global rename in Step 2 it becomes "realms/$active_realm/$mcp_doc". Verify the variable rename matches:

```bash
grep -n 'active_overlay\|active_realm' D:/Dev/GitWS/yggdrasil/scripts/ws-mcp-setup.sh
```

If you see `active_overlay`, rename → `active_realm` (replace_all: true).

- [ ] **Step 4: Syntax-check every script**

```bash
for f in D:/Dev/GitWS/yggdrasil/scripts/ws*.sh D:/Dev/GitWS/yggdrasil/scripts/ws; do
    bash -n "$f" && echo "OK $f" || echo "FAIL $f"
done
```

All should report OK.

### Task B5: Update ecosystem config files

**Files:**
- `ecosystem.yaml` (upstream defaults)
- `ecosystem.local.yaml.example` (per-developer example)

- [ ] **Step 1: Find `templateOverlay` references**

```bash
grep -n 'templateOverlay\|overlay:' D:/Dev/GitWS/yggdrasil/ecosystem.yaml D:/Dev/GitWS/yggdrasil/ecosystem.local.yaml.example
```

- [ ] **Step 2: Rename**

In each file:
- `templateOverlay:` → `templateRealm:`
- The example value (some `overlay-yggdrasil-template` URL) → the new `realm-template` URL. The actual upstream template repo will be renamed in Task B7; for now use the post-rename name (`SiliconSaga/realm-template`).
- Any commented-out example `overlay: <name>` → `realm: <name>`.

### Task B6: Move directories on disk and update `.gitignore`

This is the local filesystem rename. **Do this on a clean working tree** (no
uncommitted changes to scripts mid-rename) so any failure leaves a recoverable
state.

**Files:**
- Move: `overlays/` → `realms/` (and rename child directories)
- Modify: `.gitignore`

- [ ] **Step 1: Confirm clean working tree**

```bash
cd D:/Dev/GitWS/yggdrasil
git status --short
```

Expect only the staged/unstaged Phase B edits up to this point. Don't proceed if there are unrelated dirty paths.

- [ ] **Step 2: Update `.gitignore`**

Find:

```gitignore
# Overlay repos — cloned by ws overlay, ignored by yggdrasil's Git.
/overlays/*
!/overlays/.gitkeep
```

Replace with:

```gitignore
# Realm repos — cloned by ws realm, ignored by yggdrasil's Git.
/realms/*
!/realms/.gitkeep
```

- [ ] **Step 3: Move the directory**

```bash
cd D:/Dev/GitWS/yggdrasil
git mv overlays/.gitkeep realms/.gitkeep 2>/dev/null || (mkdir -p realms && git mv overlays/.gitkeep realms/.gitkeep)
# The realm subdirectories are gitignored — move them with plain mv:
mv overlays/overlay-yggdrasil-live realms/realm-siliconsaga 2>/dev/null || true
mv overlays/overlay-yggdrasil-template realms/realm-template 2>/dev/null || true
# Remove the now-empty overlays/ directory
rmdir overlays 2>/dev/null || true
```

If any `mv` failed because the source didn't exist (e.g. you don't have the template cloned), that's fine — skip it.

- [ ] **Step 4: Update local `ecosystem.local.yaml` if it has the old key**

```bash
if [[ -f D:/Dev/GitWS/yggdrasil/ecosystem.local.yaml ]]; then
    grep -n '^overlay:' D:/Dev/GitWS/yggdrasil/ecosystem.local.yaml || echo "(no overlay: key — nothing to migrate)"
fi
```

If the grep returns a line, edit the file: `overlay: <name>` → `realm: <new-name>` where `<new-name>` is the post-rename realm directory (probably `realm-siliconsaga`).

- [ ] **Step 5: Sanity-check `ws realm list`**

```bash
ws realm list
```

Expected output (assuming the user has the live realm renamed): `=== Realms ===` followed by `* realm-siliconsaga (active)` (and `realm-template` listed beneath if cloned).

If this errors, debug before moving on. The most likely failures: a script still references `OVERLAYS_DIR` or `ws_detect_overlay` (from Task B4), or `realms/.gitkeep` is missing (in which case `mkdir -p realms && touch realms/.gitkeep`).

### Task B7: Rename the GitHub repo and update local remotes

**Files (no local files; remote rename + git remote update):**

- [ ] **Step 1: Rename the GitHub repo**

```bash
gh repo rename --repo SiliconSaga/overlay-yggdrasil-live realm-siliconsaga
```

If the user prefers to do this manually in the GitHub UI, skip the gh
command and have them confirm the rename completed. GitHub auto-redirects
old URLs.

- [ ] **Step 2: Update the realm's local origin URL**

```bash
cd D:/Dev/GitWS/yggdrasil/realms/realm-siliconsaga
git remote -v
```

If `origin` (or whatever remote) still points at the old URL, update it:

```bash
git remote set-url <remote-name> https://github.com/SiliconSaga/realm-siliconsaga.git
git remote -v
```

- [ ] **Step 3: Optional — also rename the template repo**

If `SiliconSaga/overlay-yggdrasil-template` still exists, rename it too:

```bash
gh repo rename --repo SiliconSaga/overlay-yggdrasil-template realm-template
```

And update local origin in `realms/realm-template/` similarly.

### Task B8: Update docs (vocabulary sweep)

**Files to modify:**
- `AGENTS.md`
- `CLAUDE.md`
- `docs/ecosystem-architecture.md`
- `docs/getting-started/index.md`
- `docs/ws-cli-guide.md`

- [ ] **Step 1: Find all hits**

```bash
grep -rn '\boverlay\b\|\boverlays\b\|overlay-yggdrasil\|OVERLAYS_DIR\|ws_detect_overlay\|ws-overlay\.sh' D:/Dev/GitWS/yggdrasil/AGENTS.md D:/Dev/GitWS/yggdrasil/CLAUDE.md D:/Dev/GitWS/yggdrasil/docs/
```

- [ ] **Step 2: Apply mapping per hit**

| Old | New |
|-----|-----|
| `overlay` (noun) | `realm` |
| `overlays` (plural) | `realms` |
| `overlays/` (path) | `realms/` |
| `overlay-yggdrasil-live` | `realm-siliconsaga` (community-specific example) |
| `overlay-yggdrasil-template` | `realm-template` |
| `ws overlay` (CLI) | `ws realm` |
| `OVERLAYS_DIR` | `REALMS_DIR` |
| `ws_detect_overlay` | `ws_detect_realm` |
| `ws-overlay.sh` | `ws-realm.sh` |
| `templateOverlay` | `templateRealm` |

For each file, edit per occurrence. Read 5–10 lines of context around each
hit so prose still scans well after the swap (e.g. "active overlay marker"
becomes "active realm marker").

- [ ] **Step 3: Add the inheritance reservation note in `docs/ecosystem-architecture.md`**

In the section that explains the three-layer config merge, add a one-line
note (or short paragraph if the section is short on context):

```markdown
> **Inheritance future:** the merge generalizes to N layers if multi-realm
> chains land later (e.g. corp → dept → team). No new identifier needed —
> the same upstream → realm(s) → local pattern with child-wins semantics.
> See [Realms and Hoards Design](plans/2026-04-24-realms-and-hoards-design.md#future-directions).
```

### Task B9: Update GDD skills for realm vocabulary

**Files to modify:**
- `.agent/skills/gdd-orientation/SKILL.md`
- `.agent/skills/gdd-housekeeping/SKILL.md`
- `.agent/skills/mcp-usage/SKILL.md`
- `.agent/skills/gdd-doc-writing/SKILL.md`

- [ ] **Step 1: Find hits**

```bash
grep -rn '\boverlay\b\|\boverlays\b\|overlay-yggdrasil\|OVERLAYS_DIR\|ws_detect_overlay' D:/Dev/GitWS/yggdrasil/.agent/skills/
```

- [ ] **Step 2: Apply the same mapping table from Task B8 Step 2**

Pay particular attention to:
- `gdd-orientation/SKILL.md` Step 6 (trust verification of overlays) — rename "Active overlay" header to "Active realm", update the overlay scan, etc.
- `mcp-usage/SKILL.md` — the recently-fixed "ws overlay list" snippet becomes "ws realm list"; update the surrounding prose ("active realm is prefixed with `*`").

### Task B10: Update `.claude/settings.json` permission patterns

**Files to modify:**
- `.claude/settings.json`

- [ ] **Step 1: Find any `ws overlay` permission entries**

```bash
grep -n 'ws overlay\|ws-overlay' D:/Dev/GitWS/yggdrasil/.claude/settings.json
```

- [ ] **Step 2: Replace with `ws realm` equivalents**

For each entry, swap `ws overlay` → `ws realm` (and `bash scripts/ws overlay` → `bash scripts/ws realm`).

### Task B11: Sanity-test the full system

- [ ] **Step 1: Verify discovery**

```bash
cd D:/Dev/GitWS/yggdrasil
ws realm list
```

Expected: `=== Realms ===` with `* realm-siliconsaga (active)` (or whichever realm this user has).

- [ ] **Step 2: Verify ecosystem resolution**

```bash
ws list
```

Should print components from the merged ecosystem config without errors.

- [ ] **Step 3: Verify mcp-setup still routes correctly**

```bash
ws mcp-setup --dry-run 2>&1 | head -10
```

Should either print the dry-run JSON for declared MCP servers or "No mcp.servers declared..." — both are valid post-rename outcomes.

- [ ] **Step 4: Verify status / clone-status checks**

```bash
ws status 2>&1 | head -20
```

Should not error.

### Task B12: Commit Phase B

- [ ] **Step 1: Write the bodyfile `.commits/realm-rename.md`**

```markdown
---
message: "refactor: rename overlay → realm (clean cut)"
add:
  - .gitignore
  - .agent/skills/gdd-orientation/SKILL.md
  - .agent/skills/gdd-housekeeping/SKILL.md
  - .agent/skills/mcp-usage/SKILL.md
  - .agent/skills/gdd-doc-writing/SKILL.md
  - .claude/settings.json
  - AGENTS.md
  - CLAUDE.md
  - docs/ecosystem-architecture.md
  - docs/getting-started/index.md
  - docs/ws-cli-guide.md
  - ecosystem.yaml
  - ecosystem.local.yaml.example
  - realms/.gitkeep
  - scripts/ws
  - scripts/ws-realm.sh
  - scripts/ws-mcp-setup.sh
  - scripts/ws-clone.sh
  - scripts/ws-list.sh
  - scripts/ws-resolve.sh
  - scripts/ws-vscode.sh
remove:
  - overlays/.gitkeep
---

Norse-theme rename: "overlay" carried no inherent meaning, "realm" fits
("realms of Yggdrasil"). Clean cut, no deprecation aliases — the workspace
has one live user and migration is a one-shot.

Touches everything: directory `overlays/ → realms/`, script
`ws-overlay.sh → ws-realm.sh`, env var `OVERLAYS_DIR → REALMS_DIR`,
shell function `ws_detect_overlay → ws_detect_realm`, CLI subcommand
`ws overlay → ws realm`, `ecosystem.local.yaml` selector key
`overlay: → realm:`, ecosystem config key `templateOverlay → templateRealm`,
docs and skills throughout.

Discovery rule simplified: drop the hardcoded `-live` suffix; auto-detect
any single non-template `realm-*` directory; error on multiple; fall back
to `realm-template`. Naming pattern becomes `realm-<community>`
(e.g. `realm-siliconsaga`) — the workspace name no longer leaks into the
realm name.

Adds an inheritance reservation comment in `ws_resolve_ecosystem` and a
matching note in `docs/ecosystem-architecture.md`. The three-layer merge
already templates the pattern; landing N-layer realm inheritance later
is a small generalization.

Pair with the GitHub repo rename
`SiliconSaga/overlay-yggdrasil-live → SiliconSaga/realm-siliconsaga`.
GitHub auto-redirects the old URLs, so existing local clones keep working
until they're rebased through this commit.
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/realm-rename.md
```

- [ ] **Step 3: Verify the commit**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
git -C D:/Dev/GitWS/yggdrasil status
```

Status should be clean.

---

# Phase C — Hoards

Builds on the renamed system. Introduces a new top-level directory and a
new `ws hoard` subcommand family.

### Task C1: Create the `hoards/` directory and ignore rule

**Files:**
- Create: `hoards/.gitkeep`
- Modify: `.gitignore`

- [ ] **Step 1: Create the directory**

```bash
cd D:/Dev/GitWS/yggdrasil
mkdir -p hoards
: > hoards/.gitkeep
```

- [ ] **Step 2: Update `.gitignore`**

Add this block immediately after the `# Realm repos` block (added in Phase B):

```gitignore
# Hoard repos — personal containers cloned by ws hoard, ignored by yggdrasil's Git.
/hoards/*
!/hoards/.gitkeep
```

### Task C2: Create the `templates/hoards/thalami/` template

**Files:**
- Create: `templates/hoards/thalami/README.md`
- Create: `templates/hoards/thalami/.gitignore`

- [ ] **Step 1: Make the directory and write the README**

```bash
mkdir -p D:/Dev/GitWS/yggdrasil/templates/hoards/thalami
```

Write `templates/hoards/thalami/README.md`:

````markdown
# Thalami Hoard

Personal hoard holding per-machine Thalamus files. Each machine you use
yggdrasil on contributes one `<machine>-thalamus.md` file. Preferences,
observations, and concerns sync between machines via this repo's git
history.

## Layout

```text
thalami-<username>/
  README.md
  <machine>-thalamus.md     # one per machine; e.g. win10-desktop-thalamus.md
  <machine>-thalamus.md
  ...
```

Internal layout is intentionally flat — the repo's name already says
`thalami`. If subdirectory structure becomes useful later, it can be
introduced via a config-level path-template override.

## Machine name

Defaults to `hostname -s` (short hostname). Override via
`machine: <name>` in `ecosystem.local.yaml` if your hostname is awkward
or unstable across boots.

## Privacy posture

The hoard is **personal but committed** to a private repo of your choice.
This is a different posture from the workspace-local `Thalamus.md`, which
is gitignored and stays on one machine. Treat the hoard as
"cross-machine, low-secrecy" content — observations about a friction
point, preferences, recurring concerns. For "don't-check-in" notes,
keep using a root `Thalamus.md` as a scratch file alongside the hoard.

## Pushing to your remote

The `ws hoard init` flow creates this hoard as a local git repo without
a remote. To push:

```bash
gh repo create <yourname>/thalami-<yourname> --private --source=hoards/thalami-<yourname>
```

Or any equivalent on GitLab / Gitea / etc.
````

- [ ] **Step 2: Write `.gitignore`**

Write `templates/hoards/thalami/.gitignore`:

```gitignore
# OS noise
.DS_Store
Thumbs.db
```

### Task C3: Create `scripts/ws-hoard.sh` skeleton with shared helpers

**Files:**
- Create: `scripts/ws-hoard.sh`

- [ ] **Step 1: Write the skeleton with header, env, and helper functions**

```bash
#!/usr/bin/env bash
# ws-hoard.sh — Hoard management
#
# Subcommands (called via ws hoard):
#   init [template] [args...]   Scaffold a new hoard locally
#                               (template defaults to 'thalami')
#   <git-url>                   Clone an existing hoard from a git URL
#   list                        Show hoards and which thalami hoard is active
#
# Templates ship under templates/hoards/<name>/.
# Currently shipped: thalami.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"
: "${TEMPLATES_DIR:="$ROOT_DIR/templates"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"   # for ws_resolve_ecosystem

# Resolve identity.human_account from merged ecosystem config.
# Errors with guidance if unset — required for hoard naming.
ws_resolve_human_account() {
    local eco
    eco="$(ws_resolve_ecosystem)"
    local who
    who="$(yq '.identity.human_account // ""' "$eco" 2>/dev/null)"
    if [[ -z "$who" || "$who" == "null" ]]; then
        echo "ERROR: identity.human_account is not set." >&2
        echo "  Set it in ecosystem.local.yaml so hoard names can be generated." >&2
        echo "  Example:" >&2
        echo "    identity:" >&2
        echo "      human_account: cervator" >&2
        exit 1
    fi
    echo "$who"
}

# Resolve the machine name. Defaults to `hostname -s`; override via
# `machine: <name>` in ecosystem.local.yaml.
ws_resolve_machine_name() {
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        local override
        override="$(yq '.machine // ""' "$local_file" 2>/dev/null)"
        if [[ -n "$override" && "$override" != "null" ]]; then
            echo "$override"
            return
        fi
    fi
    hostname -s
}

# Detect the active thalami hoard.
# Returns the hoard directory name (not full path), or empty.
#
# Discovery rule:
#   1. ecosystem.local.yaml `hoards.thalami:` selector
#   2. Single thalami-* directory in hoards/
#   3. None
ws_detect_thalami_hoard() {
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        local selector
        selector="$(yq '.hoards.thalami // ""' "$local_file" 2>/dev/null)"
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$HOARDS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi

    local candidates=()
    if [[ -d "$HOARDS_DIR" ]]; then
        for d in "$HOARDS_DIR"/thalami-*/; do
            [[ -d "$d" ]] || continue
            candidates+=("$(basename "$d")")
        done
    fi

    case "${#candidates[@]}" in
        0) echo "" ;;
        1) echo "${candidates[0]}" ;;
        *)
            echo "ERROR: Multiple thalami-* hoards found in hoards/: ${candidates[*]}." >&2
            echo "  Set 'hoards.thalami: <name>' in ecosystem.local.yaml to pick one." >&2
            exit 1
            ;;
    esac
}

# Resolve the path to the per-machine thalamus file in the active hoard.
# Echoes the absolute path or empty if no active hoard.
# (Path template is currently fixed; see design spec for the future
# config-driven override.)
ws_resolve_thalamus_path() {
    local hoard
    hoard="$(ws_detect_thalami_hoard)"
    [[ -z "$hoard" ]] && echo "" && return
    local machine
    machine="$(ws_resolve_machine_name)"
    echo "$HOARDS_DIR/$hoard/${machine}-thalamus.md"
}
```

- [ ] **Step 2: Append the help and dispatch logic**

Continue the file:

```bash
ws_hoard_help() {
    echo "Usage: ws hoard <subcommand> [args...]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init [template] [args]   Scaffold a new hoard locally (default: thalami)" >&2
    echo "                           Per-template args:" >&2
    echo "                             thalami --from-thalamus" >&2
    echo "                                  Move root Thalamus.md into the new hoard" >&2
    echo "  <git-url>                Clone an existing hoard" >&2
    echo "  list                     Show hoards and which thalami hoard is active" >&2
}

# Stubs implemented in subsequent tasks
ws_hoard_init() { echo "TODO: implemented in C4"; exit 1; }
ws_hoard_clone_url() { echo "TODO: implemented in C5"; exit 1; }
ws_hoard_list() { echo "TODO: implemented in C6"; exit 1; }

# Guard: if sourced by another script, stop here
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

SUBCMD="${1:-}"
shift 2>/dev/null || true

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
    *)
        ws_hoard_clone_url "$SUBCMD"
        ;;
esac
```

- [ ] **Step 3: Mark executable and syntax-check**

```bash
chmod +x D:/Dev/GitWS/yggdrasil/scripts/ws-hoard.sh
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-hoard.sh && echo "syntax ok"
```

### Task C4: Implement `ws hoard init` (with thalami template)

**Files to modify:**
- `scripts/ws-hoard.sh`

- [ ] **Step 1: Replace the `ws_hoard_init` stub**

```bash
# ws_hoard_init [template] [template-args...]
# Default template: thalami.
# Per-template args:
#   thalami --from-thalamus    Move root Thalamus.md into the new hoard
ws_hoard_init() {
    local template="${1:-thalami}"
    shift 2>/dev/null || true

    local template_dir="$TEMPLATES_DIR/hoards/$template"
    if [[ ! -d "$template_dir" ]]; then
        echo "ERROR: Unknown hoard template: '$template'." >&2
        echo "  Available templates:" >&2
        for d in "$TEMPLATES_DIR/hoards"/*/; do
            [[ -d "$d" ]] && echo "    $(basename "$d")"
        done >&2
        exit 1
    fi

    local who
    who="$(ws_resolve_human_account)"
    local target="$HOARDS_DIR/${template}-${who}"
    if [[ -d "$target" ]]; then
        echo "ERROR: Hoard already exists at $target." >&2
        echo "  Remove it first if you want to start over." >&2
        exit 1
    fi

    # Per-template arg handling
    local from_thalamus=false
    case "$template" in
        thalami)
            for arg in "$@"; do
                case "$arg" in
                    --from-thalamus) from_thalamus=true ;;
                    *)
                        echo "ERROR: unknown arg for thalami template: '$arg'." >&2
                        exit 2
                        ;;
                esac
            done
            ;;
        *)
            if [[ $# -gt 0 ]]; then
                echo "ERROR: template '$template' does not accept extra args (got: $*)." >&2
                exit 2
            fi
            ;;
    esac

    # Confirm before doing anything destructive
    if [[ "$from_thalamus" == true ]]; then
        local root_thalamus="$ROOT_DIR/Thalamus.md"
        if [[ ! -f "$root_thalamus" ]]; then
            echo "ERROR: --from-thalamus requested but $root_thalamus does not exist." >&2
            exit 1
        fi
        local machine
        machine="$(ws_resolve_machine_name)"
        echo "About to:"
        echo "  1. Copy template from: $template_dir → $target"
        echo "  2. Move:               $root_thalamus → $target/${machine}-thalamus.md"
        echo "  3. git init the new hoard with an initial commit"
        echo ""
        read -r -p "Proceed? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # Copy template directory
    mkdir -p "$HOARDS_DIR"
    cp -R "$template_dir" "$target"

    # Apply per-template seeding
    if [[ "$template" == "thalami" ]]; then
        local machine
        machine="$(ws_resolve_machine_name)"
        if [[ "$from_thalamus" == true ]]; then
            mv "$ROOT_DIR/Thalamus.md" "$target/${machine}-thalamus.md"
            echo "Moved Thalamus.md → $target/${machine}-thalamus.md"
        else
            # Seed an empty machine thalamus from the workspace template
            cp "$TEMPLATES_DIR/thalamus.md" "$target/${machine}-thalamus.md"
        fi
    fi

    # git init + initial commit
    (
        cd "$target"
        git init -q
        git add .
        git -c user.email="hoard@local" -c user.name="hoard-init" \
            commit -q -m "Initial commit (${template} hoard for ${who})"
    )

    echo ""
    echo "Hoard initialized: $target"
    echo ""
    echo "Push to your own remote when ready, e.g.:"
    echo "  gh repo create ${who}/${template}-${who} --private --source=${target#$ROOT_DIR/}"
    echo ""
    echo "Or set up the remote manually:"
    echo "  cd $target"
    echo "  git remote add origin <your-url>"
    echo "  git push -u origin main"
}
```

- [ ] **Step 2: Smoke-test the no-args path**

```bash
cd D:/Dev/GitWS/yggdrasil
# Sanity: stub gone, real command runs
ws hoard --help
```

Don't actually run `ws hoard init` yet — that creates a hoard. Defer to Task C7's smoke test, which tests on a synthetic fixture.

### Task C5: Implement `ws hoard <git-url>`

**Files to modify:**
- `scripts/ws-hoard.sh`

- [ ] **Step 1: Replace the `ws_hoard_clone_url` stub**

```bash
ws_hoard_clone_url() {
    local url="$1"
    if [[ ! "$url" =~ ^(https?://|git@) ]]; then
        echo "ERROR: Unknown subcommand or invalid URL '$url'." >&2
        echo "  Run 'ws hoard' for usage." >&2
        exit 1
    fi

    # Derive hoard directory name from the URL's repo basename
    local basename
    basename="${url##*/}"
    basename="${basename%.git}"
    if [[ ! "$basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: hoard repo name must be a safe directory name (got: $basename)." >&2
        exit 1
    fi

    local target="$HOARDS_DIR/$basename"
    if [[ -d "$target" ]]; then
        echo "ERROR: Hoard '$basename' already exists at $target." >&2
        exit 1
    fi

    mkdir -p "$HOARDS_DIR"
    echo "CLONE: hoard -> $target"
    git clone "$url" "$target"
    echo ""
    echo "Hoard cloned. If this is a thalami hoard, the active machine's thalamus"
    echo "file is at $target/$(ws_resolve_machine_name)-thalamus.md (created on first session if absent)."
}
```

### Task C6: Implement `ws hoard list`

**Files to modify:**
- `scripts/ws-hoard.sh`

- [ ] **Step 1: Replace the `ws_hoard_list` stub**

```bash
ws_hoard_list() {
    echo "=== Hoards ==="
    local active_thalami
    active_thalami="$(ws_detect_thalami_hoard)"
    local found=0
    if [[ -d "$HOARDS_DIR" ]]; then
        for d in "$HOARDS_DIR"/*/; do
            [[ -d "$d" ]] || continue
            local dname
            dname="$(basename "$d")"
            [[ "$dname" == ".gitkeep" ]] && continue
            found=1
            local marker="    "
            if [[ "$dname" == "$active_thalami" ]]; then
                marker="  * "
            fi
            local label=""
            if [[ "$dname" == thalami-* && "$dname" == "$active_thalami" ]]; then
                label=" (active thalami)"
            fi
            echo "${marker}${dname}${label}"
        done
    fi
    if [[ "$found" -eq 0 ]]; then
        echo "  (none)"
        echo ""
        echo "Run 'ws hoard init' to scaffold one, or 'ws hoard <git-url>' to clone."
    fi
}
```

### Task C7: Wire `ws hoard` into the main router

**Files to modify:**
- `scripts/ws`

- [ ] **Step 1: Add the help-block entries**

In the `# Commands:` block at the top of `scripts/ws`, immediately after the `realm list` line, insert:

```
#   hoard init [template]      Scaffold a new hoard (default: thalami)
#   hoard <url>                Clone an existing hoard
#   hoard list                 Show hoards and which thalami hoard is active
```

- [ ] **Step 2: Add the dispatch case**

Find the `realm)` case in the dispatch block (added in Task B3) and add this case directly below:

```bash
    hoard)
        bash "$SCRIPT_DIR/ws-hoard.sh" "$@"
        ;;
```

- [ ] **Step 3: Smoke-test the wiring**

```bash
ws hoard --help
ws hoard list
```

Both should produce output without errors.

### Task C8: Update `.claude/settings.json` permission patterns

**Files to modify:**
- `.claude/settings.json`

- [ ] **Step 1: Add hoard patterns**

Add these entries to the appropriate permission list (mirror the existing `ws realm` style):

```json
"Bash(ws hoard)",
"Bash(ws hoard *)",
"Bash(ws hoard * *)",
"Bash(ws hoard * * *)",
"Bash(bash scripts/ws hoard)",
"Bash(bash scripts/ws hoard *)",
"Bash(bash scripts/ws hoard * *)",
"Bash(bash scripts/ws hoard * * *)"
```

- [ ] **Step 2: Validate JSON**

```bash
yq -p=json '.' D:/Dev/GitWS/yggdrasil/.claude/settings.json > /dev/null && echo "json ok"
```

### Task C9: Update `gdd-orientation` skill — hoard discovery and dual-file logic

**Files to modify:**
- `.agent/skills/gdd-orientation/SKILL.md`

- [ ] **Step 1: Add hoard awareness to Step 1 (Check for Thalamus.md)**

After the existing Step 1 (which handles the no-Thalamus.md case at root), insert a new step that runs first:

```markdown
### Step 1a: Resolve the active thalamus file

Determine which Thalamus file to read by inspecting the workspace directly:

1. Look in `hoards/` for a directory matching `thalami-*`. If one exists,
   it's the active thalami hoard. (If multiple exist, look for the
   `hoards.thalami:` selector in `ecosystem.local.yaml`.)
2. If a thalami hoard is active:
   - **Primary:** `hoards/thalami-<user>/<machine>-thalamus.md` where
     `<machine>` is from `hostname -s` (or the `machine:` override in
     `ecosystem.local.yaml`).
   - **Scratch:** root `Thalamus.md` if it exists. Read this too on
     orientation, but writes default to the primary.
3. If no thalami hoard is active:
   - Use root `Thalamus.md` as today (existing behavior).

Scripts that need a deterministic answer can source `scripts/ws-hoard.sh`
and call the `ws_resolve_thalamus_path` helper.

Briefly note the resolution to the human:

> "Reading hoard thalamus (`win10-desktop-thalamus.md`) — 5 observations,
> 1 concern. No scratch file."

If both exist:

> "Hoard thalamus (5 obs, 1 concern) + scratch (1 item). Writes default
> to the hoard."
```

- [ ] **Step 2: Update During-Session Writes table**

Find the table under "## During-Session Writes" and add a precedence note immediately above it:

```markdown
**File precedence for writes:** if a thalami hoard is active, writes go to
the per-machine hoard file. Writes to the scratch root `Thalamus.md` happen
only on explicit user request ("write that to scratch").
```

- [ ] **Step 3: Add a "Machine name" sub-section near the discovery section**

Add a small subsection (3–4 lines) explaining `hostname -s` default and the
`machine:` override key. Place it in or just after the Step 1a content.

### Task C10: Update `gdd-housekeeping` skill — multi-thalami review mode

**Files to modify:**
- `.agent/skills/gdd-housekeeping/SKILL.md`

- [ ] **Step 1: Add a new section before "What Housekeeping Is NOT"**

```markdown
## Multi-Thalami Review (when a thalami hoard is active)

If `hoards/thalami-<user>/` is the active hoard, housekeeping can audit
across every `<machine>-thalamus.md` file in the hoard. Use this to catch
preferences/observations that should be promoted across machines or
duplicates that should be merged.

### When to use multi-thalami mode

- The human asks to "review across machines" or similar
- Housekeeping on a single machine surfaces a preference that obviously
  applies everywhere ("user prefers terse responses") — pivot to
  multi-thalami to promote it
- Periodic: once or twice a year, even without a specific trigger

### Process

1. List every `<machine>-thalamus.md` file in the active hoard. Note the
   machine names.
2. For Preferences and Observations specifically, identify items that:
   - Appear on one machine but seem universal — candidates for promotion.
   - Appear on multiple machines with similar wording — candidates for
     dedup (consolidate to one canonical entry; keep machine-specific
     variations only if they're actually distinct).
3. Walk the candidates with the human, item by item. For each, decide:
   - Promote everywhere: add to every other machine file (with the
     human's blessing).
   - Keep machine-specific: leave it alone.
   - Dedup: pick the best phrasing, drop the others.
4. Update `last_audit` in each touched machine file.
5. Note in the audit log entry which machines were reviewed.

### Compare-only — no shared file in v1

V1 does not introduce a shared `common-thalamus.md`. If multi-thalami
review repeatedly promotes the same preference to every machine over many
audits, that's evidence to add a shared file in v2. Until then, the
N×duplication is acceptable cost for design simplicity.
```

### Task C11: Update `AGENTS.md` for hoard concept and `ws hoard`

**Files to modify:**
- `AGENTS.md`

- [ ] **Step 1: Update the "Workspace CLI (ws)" section**

In the existing list of `ws` subcommands worth highlighting (e.g. where
`ws gitlab-auth` and `ws diagnose` are called out), add:

```markdown
- `ws hoard init [template]` / `ws hoard <url>` / `ws hoard list` —
  manage personal hoards (per-user containers). Canonical type is
  `thalami` for per-machine Thalamus sync.
```

- [ ] **Step 2: Add a "Hoards" subsection or short paragraph**

Place after the existing "## Workspace CLI" section (or wherever realms are
discussed):

```markdown
## Hoards (personal containers)

Hoards are personal git repos under `hoards/`, named `<type>-<username>`.
The canonical v1 type is `thalami` (per-machine Thalamus files for
preference/observation sync across machines). Other personal stuff (an
Obsidian vault, sample projects, etc.) can live in `hoards/` but isn't
orientation-visible — those are the user's own business.

Active thalami hoard discovery: auto-detects `hoards/thalami-*` (single
match expected); set `hoards.thalami: <name>` in `ecosystem.local.yaml`
to override. Per-machine file is `<machine>-thalamus.md` where `<machine>`
defaults to `hostname -s`.

See [Realms and Hoards Design](docs/plans/2026-04-24-realms-and-hoards-design.md)
for the full picture.
```

### Task C12: Sanity-test the full hoard flow on a synthetic fixture

- [ ] **Step 1: Verify discovery works with no hoard**

```bash
cd D:/Dev/GitWS/yggdrasil
ws hoard list
```

Expected: `=== Hoards ===` then `(none)` and the init suggestion.

- [ ] **Step 2: Run `ws hoard init` on a synthetic fixture**

We don't want to create the real user's hoard until they explicitly migrate.
Use a temp `HOARDS_DIR` to verify the code path:

```bash
HOARDS_DIR=/tmp/test-hoards ws hoard init thalami 2>&1 | head -30
```

If `identity.human_account` isn't set in the user's local config, this will
correctly error with the setup guidance. That's a successful test of the
guard. If it IS set, we'll get a hoard scaffolded under `/tmp/test-hoards/thalami-<user>/` — verify and remove:

```bash
ls /tmp/test-hoards/
rm -rf /tmp/test-hoards
```

- [ ] **Step 3: Verify the orientation skill resolves the new path**

Read `.agent/skills/gdd-orientation/SKILL.md` and confirm Step 1a is
present and references `hoards/thalami-<user>/<machine>-thalamus.md`.

### Task C13: Commit Phase C

- [ ] **Step 1: Write the bodyfile `.commits/hoards.md`**

```markdown
---
message: "feat(hoard): introduce hoards/ + ws hoard subcommand family"
add:
  - .gitignore
  - .claude/settings.json
  - .agent/skills/gdd-orientation/SKILL.md
  - .agent/skills/gdd-housekeeping/SKILL.md
  - AGENTS.md
  - hoards/.gitkeep
  - scripts/ws
  - scripts/ws-hoard.sh
  - templates/hoards/thalami/README.md
  - templates/hoards/thalami/.gitignore
---

Personal hoard concept lands. New top-level `hoards/` directory (gitignored
like `realms/` and `components/`) and a `ws hoard` subcommand family —
mirrors the realm CLI shape but for personal grab-bag containers.

Canonical v1 hoard type is `thalami`: per-machine Thalamus files
(`<hostname>-thalamus.md`) so preferences, observations, and concerns
sync across the machines a single user works on. Discovery uses the same
auto-detect-or-override pattern as realms (`hoards.thalami: <name>` in
`ecosystem.local.yaml`).

`ws hoard init [template]` scaffolds a new hoard from `templates/hoards/<template>/`.
The thalami template ships with a README explaining the privacy posture
(personal but committed to a private repo of your choice — different from
the workspace-local `Thalamus.md` scratch). Per-template flags: thalami
accepts `--from-thalamus` to *move* the workspace's root `Thalamus.md`
into the new hoard with a y/N confirm.

`ws hoard <git-url>` clones an existing hoard (e.g. from another machine).
`ws hoard list` shows what's checked out and marks the active thalami
hoard.

GDD skills updated for the dual-file model:
- `gdd-orientation`: hoard thalamus is primary when active; root
  `Thalamus.md` becomes scratch. The "scratch for free" emergence pattern
  from the design doc just falls out of the precedence rule.
- `gdd-housekeeping`: new multi-thalami review mode walks every
  `<machine>-thalamus.md` to surface promotion candidates across machines.
  Compare-only in v1 — no shared/common file.

Other hoard types (obsidian, claudesidian, etc.) are noted as future
work; the directory and command structure already accommodate them.
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/hoards.md
```

- [ ] **Step 3: Sanity-test the workspace one more time**

```bash
ws help | grep -E '(realm|hoard)'
ws realm list
ws hoard list
ws status
```

All should run without errors.

---

## Optional: User's actual Thalamus.md migration

This is an opt-in step the user can take when they choose. It's not part of
the implementation plan because it touches the user's personal data and
should happen at their discretion.

```bash
cd D:/Dev/GitWS/yggdrasil
ws hoard init thalami --from-thalamus
# Confirm y/N
gh repo create cervator/thalami-cervator --private --source=hoards/thalami-cervator
cd hoards/thalami-cervator
git remote add origin https://github.com/cervator/thalami-cervator.git
git push -u origin main
```

After this, on a second machine:

```bash
git clone <yggdrasil>
cd yggdrasil
ws realm <community-realm-url>
ws hoard https://github.com/cervator/thalami-cervator.git
# First session creates <new-machine>-thalamus.md from template
```

---

## Push and open a CR

After all three phases land in commits on `design/realms-and-hoards`:

- [ ] **Step 1: Push the branch**

```bash
ws push yggdrasil design/realms-and-hoards
```

- [ ] **Step 2: Open the CR**

Write a CR body in `.crs/realms-and-hoards.md` referencing the design spec
and listing the three commits. Then:

```bash
ws cr yggdrasil "Realms and hoards: rename overlay → realm, introduce hoards/" .crs/realms-and-hoards.md
```

- [ ] **Step 3: Triage the CodeRabbit review when it lands**

Use `gdd-review-triage` skill. Expect mostly nitpicks — the changes are
mechanical refactors and a small new feature.
