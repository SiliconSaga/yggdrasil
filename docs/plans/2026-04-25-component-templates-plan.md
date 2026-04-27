# Component Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land sub-projects A + D from `docs/plans/2026-04-25-component-templates-design.md`: introduce `templates/components/<flavor>/`, ship a flagship `gh-pages` flavor, add a `ws component init <flavor> [name]` command mirroring `ws hoard init`, and clarify template/instance/tutorial vocabulary in workspace docs.

**Architecture:** Three sequential phases — plumbing (new `ws-component.sh` + router wiring + permissions), template content (the five `gh-pages` files), and documentation (vocabulary + CLI guide updates). End-to-end verification on a synthetic fixture before committing each phase keeps intermediate states landing-ready.

**Tech Stack:** Bash (ws CLI), `yq` v4 (Mike Farah), `gh` CLI, Jekyll (default GitHub renderer — no local toolchain needed), markdown documentation.

---

## Conventions for executing this plan

- The repo lives at `D:/Dev/GitWS/yggdrasil`. The user has `<workspace>/scripts/` on PATH so `ws <cmd>` works as a bare command. **Don't prepend `bash scripts/ws`.**
- Always commit via `ws commit yggdrasil <bodyfile>` — never raw `git add` / `git commit`. Bodyfiles live in `.commits/<name>.md` (gitignored). The format is in `templates/commit.md`.
- Don't chain `ws commit && ws push` — run separately so each can be reviewed and approved independently.
- Stay on branch `design/component-templates` for the duration. The design spec is already committed at `0235d14`.
- For all file edits use Edit/Write tools with absolute Windows-style paths (e.g. `D:/Dev/GitWS/yggdrasil/AGENTS.md`).
- yggdrasil has no shell-test framework. Verification is `bash -n` syntax checks + runtime smoke tests on synthetic fixtures (using temporary `HOARDS_DIR`/path overrides) — same pattern as the realms-and-hoards landing.

---

## Files Changed Overview

### Phase A — Plumbing

- **Create** `scripts/ws-component.sh` — new subcommand handler (~200 lines)
- **Modify** `scripts/ws` — add `component)` dispatch + help-block entries
- **Modify** `.claude/settings.json` — add `ws component init *` permission patterns

### Phase B — `gh-pages` flagship template

- **Create** `templates/components/gh-pages/index.md`
- **Create** `templates/components/gh-pages/_config.yml`
- **Create** `templates/components/gh-pages/README.md` (comprehensive tutorial)
- **Create** `templates/components/gh-pages/.gitignore`
- **Create** `templates/components/gh-pages/LICENSE`

### Phase C — Documentation

- **Modify** `AGENTS.md` — add `ws component` to CLI list + Components subsection mirroring Hoards
- **Modify** `CLAUDE.md` — add `ws component` to commands inventory
- **Modify** `docs/ws-cli-guide.md` — Safe-tier table + new component section
- **Modify** `docs/getting-started/index.md` — Template/Instance/Tutorial vocabulary + recommended newcomer flow
- **Modify** `templates/README.md` — extend top-level templates table to include `components/` subdirectory

---

# Phase A — Plumbing

Lands the `ws component init` command end-to-end without any shipped templates. After Phase A you can `ws component init` and get an "Unknown flavor" error listing zero available flavors — that's expected and demonstrates the plumbing works.

### Task A1: Create `scripts/ws-component.sh`

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh`

- [ ] **Step 1: Write the file**

> **Note on drift:** the code block below is the original drafted form
> from when this plan was written. After implementation, code review on
> PR #45 surfaced refinements (yq exit-status checking, atomic
> `ecosystem.local.yaml` rollback when newly created, `--private` as
> the safe default visibility for unknown flavors, cosmetic cleanups).
> The committed `scripts/ws-component.sh` is canonical; if executing
> this plan from scratch in the future, prefer that file's current
> contents over the inlined version here. The most egregious drifts
> have been patched inline below to keep this block buildable, but
> small differences may remain.

Write `D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh` with this exact content:

```bash
#!/usr/bin/env bash
# ws-component.sh — Component management
#
# Subcommands (called via ws component):
#   init <flavor> [name] [template-args]   Scaffold a new component locally
#                                          from templates/components/<flavor>/
#   list                                   Show known flavors
#
# Templates ship under templates/components/<flavor>/.
# Currently shipped: gh-pages.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"
: "${TEMPLATES_DIR:="$ROOT_DIR/templates"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"   # for ws_resolve_ecosystem

# Resolve identity.human_account from merged ecosystem config.
# Errors with guidance if unset — required for the suggested gh repo create
# command and the inferred remote URL.
ws_resolve_human_account() {
    local eco
    eco="$(ws_resolve_ecosystem)"
    local who
    who="$(yq '.identity.human_account // ""' "$eco" 2>/dev/null)"
    if [[ -z "$who" || "$who" == "null" ]]; then
        echo "ERROR: identity.human_account is not set." >&2
        echo "  Set it in ecosystem.local.yaml so component names and remote" >&2
        echo "  URLs can be generated. Example:" >&2
        echo "    identity:" >&2
        echo "      human_account: cervator" >&2
        exit 1
    fi
    echo "$who"
}

# List the available component flavors (one per line) found in
# templates/components/.
ws_component_list_flavors() {
    if [[ ! -d "$TEMPLATES_DIR/components" ]]; then
        return
    fi
    for d in "$TEMPLATES_DIR/components"/*/; do
        [[ -d "$d" ]] || continue
        basename "$d"
    done
}

ws_component_help() {
    echo "Usage: ws component <subcommand> [args...]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init <flavor> [name] [template-args]" >&2
    echo "      Scaffold a new component into components/<name>/ from" >&2
    echo "      templates/components/<flavor>/. Auto-registers in" >&2
    echo "      ecosystem.local.yaml. Prompts for name if omitted on a tty." >&2
    echo "  list" >&2
    echo "      Show known flavors." >&2
}

ws_component_show_list() {
    echo "Known component flavors:"
    local found=0
    while IFS= read -r flavor; do
        [[ -z "$flavor" ]] && continue
        echo "  $flavor"
        found=1
    done < <(ws_component_list_flavors)
    if [[ "$found" -eq 0 ]]; then
        echo "  (none — templates/components/ is empty or absent)"
    fi
}

# Scaffold a new component from a template.
# Usage: ws_component_init <flavor> [name] [template-args...]
ws_component_init() {
    local flavor="${1:-}"
    if [[ -z "$flavor" ]]; then
        echo "ERROR: flavor is required." >&2
        ws_component_help
        exit 1
    fi
    shift

    # Validate flavor exists
    local template_dir="$TEMPLATES_DIR/components/$flavor"
    if [[ ! -d "$template_dir" ]]; then
        echo "ERROR: Unknown component flavor: '$flavor'." >&2
        echo "  Available flavors:" >&2
        local listed=0
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            echo "    $f" >&2
            listed=1
        done < <(ws_component_list_flavors)
        if [[ "$listed" -eq 0 ]]; then
            echo "    (none — templates/components/ is empty or absent)" >&2
        fi
        exit 1
    fi

    # Resolve name — first non-flag arg, prompt if missing on a tty
    local name="${1:-}"
    if [[ -n "$name" && "${name:0:1}" != "-" ]]; then
        shift
    else
        name=""
    fi
    if [[ -z "$name" ]]; then
        if [[ -t 0 ]]; then
            read -r -p "Component name: " name
        fi
        if [[ -z "$name" ]]; then
            echo "ERROR: component name required (no tty for prompt)." >&2
            echo "  Usage: ws component init $flavor <name>" >&2
            exit 1
        fi
    fi

    # Validate name
    if [[ "$name" == "yggdrasil" ]]; then
        echo "ERROR: 'yggdrasil' is the workspace root name; pick a different component name." >&2
        exit 1
    fi
    # Match the regex used by ws_validate_component in ws-realm.sh — allows
    # dotted segments (e.g. some.component) for parity with names already
    # accepted by the rest of the workspace's component handling.
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Invalid component name '$name'." >&2
        echo "  Must be lowercase alphanumeric with hyphens/dots (no trailing dots or consecutive dots)." >&2
        exit 1
    fi

    # Pre-flight checks
    local target="$COMPONENTS_DIR/$name"
    if [[ -d "$target" ]]; then
        echo "ERROR: components/$name already exists at $target." >&2
        exit 1
    fi

    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        local existing
        if ! existing="$(yq ".components.\"$name\" // \"\"" "$local_file")"; then
            echo "ERROR: failed to parse $local_file. Check YAML syntax." >&2
            exit 1
        fi
        if [[ -n "$existing" && "$existing" != "null" ]]; then
            echo "ERROR: component '$name' is already declared in ecosystem.local.yaml." >&2
            echo "  Edit the file or pick a different name." >&2
            exit 1
        fi
    fi

    # Warn if name shadows a realm-catalog component
    local eco realm_entry
    eco="$(ws_resolve_ecosystem)"
    if ! realm_entry="$(yq ".components.\"$name\" // \"missing\"" "$eco")"; then
        echo "ERROR: failed to parse merged ecosystem config." >&2
        exit 1
    fi
    if [[ "$realm_entry" != "missing" ]]; then
        echo "WARNING: '$name' is already declared in the merged ecosystem catalog." >&2
        echo "  Adding a local-layer entry will shadow it. This is allowed but unusual." >&2
        if [[ -t 0 ]]; then
            read -r -p "Continue? [y/N] " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 0
            fi
        else
            echo "  (non-tty; refusing to proceed without confirmation)" >&2
            exit 1
        fi
    fi

    # Resolve identity (errors if unset)
    local who
    who="$(ws_resolve_human_account)"

    # Per-template flag handling
    case "$flavor" in
        gh-pages)
            if [[ $# -gt 0 ]]; then
                echo "ERROR: gh-pages template does not accept extra args (got: $*)." >&2
                exit 2
            fi
            ;;
        *)
            if [[ $# -gt 0 ]]; then
                echo "ERROR: flavor '$flavor' does not accept extra args (got: $*)." >&2
                exit 2
            fi
            ;;
    esac

    # Copy template directory
    mkdir -p "$COMPONENTS_DIR"
    cp -R "$template_dir" "$target"

    # Trap rollback on subsequent failure
    local rollback_target="$target"
    trap 'rm -rf "$rollback_target" 2>/dev/null' ERR

    # git init + initial commit
    local commit_name commit_email
    commit_name="$(git config --get user.name 2>/dev/null || echo "$who")"
    commit_email="$(git config --get user.email 2>/dev/null || echo "${who}@local")"
    (
        cd "$target"
        git init -q -b main
        git add .
        git -c user.name="$commit_name" -c user.email="$commit_email" \
            commit -q -m "Initial commit (${flavor} component for ${who})"
    )

    # Add ecosystem.local.yaml entry. Field name is `repo`, matching what
    # ws-clone.sh reads (.components.<name>.repo, with fallback to
    # defaults.gitOrg + name + ".git" when unset). Canonical HTTPS + .git
    # form so a downstream `ws clone <name>` from a fresh workspace gets
    # exactly the right URL without ambiguity.
    local repo_url="https://github.com/${who}/${name}.git"
    if [[ ! -f "$local_file" ]]; then
        printf '# ecosystem.local.yaml — per-developer overrides (gitignored)\n# Created by ws component init.\n' > "$local_file"
    fi
    yq -i ".components.\"$name\".repo = \"$repo_url\"" "$local_file"

    # Disarm rollback trap — past the danger zone
    trap - ERR

    # Per-flavor visibility default for the suggested gh command. `gh repo
    # create` requires one of --public/--private/--internal in non-interactive
    # mode, so fall back to --private for unknown flavors.
    local visibility="--private"
    case "$flavor" in
        gh-pages) visibility="--public" ;;
    esac

    # Educational output
    echo ""
    echo "Component initialized: components/${name}"
    echo ""
    echo "Registered in ecosystem.local.yaml:"
    echo "  components:"
    echo "    ${name}:"
    echo "      repo: ${repo_url}"
    echo ""
    echo "This is the local-only layer of the three-layer config merge:"
    echo "  upstream ecosystem.yaml → realm/ecosystem.yaml → ecosystem.local.yaml"
    echo ""
    echo "The component is immediately usable from this workspace"
    echo "(ws status, ws push ${name}, etc.) without touching the realm."
    echo ""
    echo "When you're ready to share this component with the community:"
    echo "  1. Push the component to your remote (see suggested gh command below)"
    echo "  2. Move the entry from ecosystem.local.yaml into the realm's"
    echo "     ecosystem.yaml, with realm-appropriate fields added (tier, etc.)"
    echo "  3. Commit and push the realm"
    echo ""
    echo "Suggested next step — create and push the GitHub remote:"
    echo "  gh repo create ${who}/${name} ${visibility} \\"
    echo "    --source=components/${name} --remote=${who} --push"
    echo ""
    if [[ "$flavor" == "gh-pages" ]]; then
        echo "(--public is required for free GitHub Pages on personal accounts.)"
        echo ""
    fi
    echo "Then read components/${name}/README.md for the demo walkthrough."
}

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
        ws_component_help
        ;;
    init)
        ws_component_init "$@"
        ;;
    list)
        ws_component_show_list
        ;;
    *)
        echo "ERROR: Unknown subcommand '$SUBCMD'." >&2
        ws_component_help
        exit 1
        ;;
esac
```

- [ ] **Step 2: Mark executable and syntax-check**

```bash
chmod +x D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh && echo "syntax ok"
```

Expected: `syntax ok`.

### Task A2: Wire `ws component` into the main router

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws`

- [ ] **Step 1: Add help-block entries**

In `D:/Dev/GitWS/yggdrasil/scripts/ws`, locate the `# Commands:` block at the top of the file (around line 8-32). Find the existing line:

```bash
#   hoard list                 Show hoards and which thalami hoard is active
```

Immediately after that line, insert:

```bash
#   component init <flavor> [name]   Scaffold a new component from a template
#   component list                   Show known component flavors
```

- [ ] **Step 2: Add the dispatch case**

In the same file, locate the dispatch `case "$COMMAND" in ... esac` block (around line 580-595). Find the existing `hoard)` case:

```bash
    hoard)
        bash "$SCRIPT_DIR/ws-hoard.sh" "$@"
        ;;
```

Immediately after the closing `;;` of that case, insert:

```bash
    component)
        bash "$SCRIPT_DIR/ws-component.sh" "$@"
        ;;
```

- [ ] **Step 3: Syntax-check the router**

```bash
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws && echo "syntax ok"
```

Expected: `syntax ok`.

- [ ] **Step 4: Smoke-test the wiring**

```bash
ws component
```

Expected: prints `Usage: ws component <subcommand> [args...]` followed by the subcommand list. Exit code 0 (help is printed to stderr but exit is 0 per the help case `""|--help|-h)`).

```bash
ws component list
```

Expected: prints `Known component flavors:` followed by `(none — templates/components/ is empty or absent)`.

```bash
ws component init
```

Expected: prints `ERROR: flavor is required.` followed by usage. Exit code 1.

```bash
ws component init unknown-flavor
```

Expected: prints `ERROR: Unknown component flavor: 'unknown-flavor'.` followed by `(none — templates/components/ is empty or absent)`. Exit code 1.

### Task A3: Add `ws component` permission patterns to `.claude/settings.json`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/.claude/settings.json`

- [ ] **Step 1: Find the existing hoard patterns**

Open `D:/Dev/GitWS/yggdrasil/.claude/settings.json`. Locate the `bash scripts/ws hoard init * *` line (in the `allow` array, in the `bash scripts/ws` block).

- [ ] **Step 2: Add component patterns after the hoard patterns**

After the line:

```json
      "Bash(bash scripts/ws hoard init * *)",
```

insert:

```json
      "Bash(bash scripts/ws component)",
      "Bash(bash scripts/ws component --help)",
      "Bash(bash scripts/ws component -h)",
      "Bash(bash scripts/ws component list)",
      "Bash(bash scripts/ws component init *)",
      "Bash(bash scripts/ws component init * *)",
      "Bash(bash scripts/ws component init * * *)",
```

- [ ] **Step 3: Find the bare-`ws` block hoard patterns**

In the same file, locate the `ws hoard init * *` line (in the bare-`ws` section, further down).

- [ ] **Step 4: Add bare-`ws` component patterns**

After the line:

```json
      "Bash(ws hoard init * *)",
```

insert:

```json
      "Bash(ws component)",
      "Bash(ws component --help)",
      "Bash(ws component -h)",
      "Bash(ws component list)",
      "Bash(ws component init *)",
      "Bash(ws component init * *)",
      "Bash(ws component init * * *)",
```

- [ ] **Step 5: Validate JSON**

```bash
yq -p=json '.' D:/Dev/GitWS/yggdrasil/.claude/settings.json > /dev/null && echo "json ok"
```

Expected: `json ok`.

### Task A4: Smoke-test the plumbing on a synthetic fixture

This validates that `ws component init` runs end-to-end *before* any flavor is shipped. We'll hand-create a temporary flavor under a temp `TEMPLATES_DIR` to drive the path, then clean up.

- [ ] **Step 1: Create a temp flavor**

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/templates/components/dummy"
mkdir -p "$tmpdir/components"
echo "# Dummy" > "$tmpdir/templates/components/dummy/README.md"
echo "{}" > "$tmpdir/templates/components/dummy/dummy.yaml"
```

- [ ] **Step 2: Override env vars and run init**

```bash
TEMPLATES_DIR="$tmpdir/templates" \
COMPONENTS_DIR="$tmpdir/components" \
ROOT_DIR="$tmpdir" \
  ws component list 2>&1
```

Expected: `Known component flavors:` then `  dummy`.

- [ ] **Step 3: Run init against the dummy**

The init writes to `ecosystem.local.yaml` under `$ROOT_DIR`. We need an `identity.human_account` set somewhere yq can find it. Drop one in:

```bash
mkdir -p "$tmpdir"
cat > "$tmpdir/ecosystem.yaml" << 'EOF'
identity:
  human_account: testuser
EOF
TEMPLATES_DIR="$tmpdir/templates" \
COMPONENTS_DIR="$tmpdir/components" \
ROOT_DIR="$tmpdir" \
ECOSYSTEM="$tmpdir/ecosystem.yaml" \
  ws component init dummy testcomp 2>&1 | tail -20
```

Expected output ends with:

```
Component initialized: components/testcomp

Registered in ecosystem.local.yaml:
  components:
    testcomp:
      repo: https://github.com/testuser/testcomp.git
...
Suggested next step — create and push the GitHub remote:
  gh repo create testuser/testcomp  \
    --source=components/testcomp --remote=testuser --push

Then read components/testcomp/README.md for the demo walkthrough.
```

(Note: no `--public` for the dummy flavor — that's only for `gh-pages`.)

- [ ] **Step 4: Verify side effects**

```bash
ls "$tmpdir/components/testcomp/"
cat "$tmpdir/ecosystem.local.yaml"
git -C "$tmpdir/components/testcomp" log --oneline -1
```

Expected:
- `components/testcomp/` contains `README.md` and `dummy.yaml`
- `ecosystem.local.yaml` contains `components.testcomp.repo: https://github.com/testuser/testcomp.git`
- Initial commit message is `Initial commit (dummy component for testuser)`

- [ ] **Step 5: Verify rerun-collision behavior**

```bash
TEMPLATES_DIR="$tmpdir/templates" \
COMPONENTS_DIR="$tmpdir/components" \
ROOT_DIR="$tmpdir" \
ECOSYSTEM="$tmpdir/ecosystem.yaml" \
  ws component init dummy testcomp 2>&1 | head -5
```

Expected: `ERROR: components/testcomp already exists at ...`. Exit code 1.

- [ ] **Step 6: Cleanup**

```bash
rm -rf "$tmpdir"
echo "cleaned"
```

### Task A5: Commit Phase A

- [ ] **Step 1: Write the bodyfile**

Create `D:/Dev/GitWS/yggdrasil/.commits/component-templates-phase-a.md`:

```markdown
---
message: "feat(ws): introduce ws component init plumbing"
add:
  - .claude/settings.json
  - scripts/ws
  - scripts/ws-component.sh
---

Plumbing for component templates, parallel to ws hoard init. New
scripts/ws-component.sh handles the subcommand family
(ws component init <flavor> [name] [template-args], ws component list).

ws_component_init validates the flavor (against templates/components/),
resolves the component name (prompts on a tty if missing), checks for
local collisions, warns and confirms when shadowing a realm-catalog
component, copies the template directory into components/<name>/,
git-inits with the user's git config, registers an entry in
ecosystem.local.yaml under components.<name>.repo (the per-developer
layer of the three-layer merge), and prints educational output
explaining the local-first → upstream-when-ready flow plus a flavor-
appropriate gh repo create suggestion.

scripts/ws gains the component) dispatch case + help-block entries.
.claude/settings.json adds explicit allowlist patterns for ws component
init (no wildcards on the URL-clone form because no URL form exists
today; safe path is fully enumerated).

No flavors shipped yet — Phase B introduces gh-pages. Verified end-to-
end on a synthetic dummy flavor under a temp TEMPLATES_DIR.

Design: docs/plans/2026-04-25-component-templates-design.md.
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/component-templates-phase-a.md
```

- [ ] **Step 3: Confirm commit looks right**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 3 files changed (`.claude/settings.json`, `scripts/ws`, `scripts/ws-component.sh`).

---

# Phase B — `gh-pages` Flagship Template

Lands the actual user-facing template content. After Phase B, `ws component init gh-pages <name>` produces a complete, deployable GitHub Pages site.

### Task B1: Create `index.md` and `_config.yml`

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/index.md`
- Create: `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/_config.yml`

- [ ] **Step 1: Make the directory**

```bash
mkdir -p D:/Dev/GitWS/yggdrasil/templates/components/gh-pages
```

- [ ] **Step 2: Write `index.md`**

Write `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/index.md` with this exact content:

```markdown
---
layout: default
title: <your name>'s page
---

# Hello — this is your new GitHub Pages site

You're looking at the placeholder home page. **Edit this file
(`index.md`) to make it yours**, then commit, open a PR, and watch the
bots review your changes before you merge.

Replace this paragraph with whatever you want — a short bio, project
log, recipe collection, anything. The `_config.yml` next to this file
controls the theme and site title; tweak that whenever you're ready.

For the full tutorial walkthrough, see [`README.md`](README.md).
```

- [ ] **Step 3: Write `_config.yml`**

Write `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/_config.yml` with this exact content:

```yaml
title: <your name>'s page
description: Built with the GDD GitHub Pages template
theme: jekyll-theme-cayman

# A few other GitHub-supported themes you can swap to later by
# editing the `theme:` line above:
#   jekyll-theme-minimal, jekyll-theme-slate, jekyll-theme-architect,
#   jekyll-theme-merlot, jekyll-theme-modernist, jekyll-theme-leap-day
# For richer theming, ask your agent to walk you through forking a
# theme repo or moving to a different SSG.
```

### Task B2: Write the comprehensive `README.md`

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/README.md`

- [ ] **Step 1: Write the README**

> **Note on drift:** the README content below is the original drafted
> form. After implementation, code review on PR #45 caught two
> substantive issues that landed fixes in the committed file:
> (a) raw `git add` / `git commit -m "..."` / `git push -u` in §2 was
> replaced with the canonical `ws commit <name> <bodyfile>` /
> `ws push <name> <branch>` flow (since the component is registered
> in `ecosystem.local.yaml` and `ws` is the workspace convention);
> (b) the cwd story was clarified to keep the user in the yggdrasil
> root throughout. The committed
> `templates/components/gh-pages/README.md` is canonical.

Write `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/README.md` with this exact content:

````markdown
# Your GitHub Pages site

> **You can ask your AI agent to walk you through any step below, or
> follow this guide directly. Both paths arrive at roughly the same
> place.** The agent is non-deterministic; this guide is the
> deterministic path. They do the same thing in spirit.

This is a starter site scaffolded from the GDD `gh-pages` component
template. It deploys to GitHub Pages as-is, lets you exercise the full
GDD-and-bot-review workflow with a tiny live target, and is meant to
be edited from day one.

---

## 1. Setup checklist

After `ws component init gh-pages <name>` finished, the suggested next
step it printed was something like:

```bash
gh repo create <yourname>/<name> --public \
  --source=components/<name> --remote=<yourname> --push
```

Run that. It creates a public repo on your GitHub account, sets your
username as the remote name (avoids the generic `origin`), and pushes
the initial commit.

> **Why public?** Free GitHub Pages on personal accounts requires a
> public repo. A private Pages site is paid (GitHub Pro / Team /
> Enterprise). If you want it private, swap `--public` for `--private`
> in the suggested command and accept the cost on your end.

If you'd rather create the repo by hand:

1. Go to `https://github.com/new` while signed in.
2. Repository name: `<name>` (matching the directory). Public.
3. Skip the README / .gitignore / license options — your scaffold
   already has them.
4. Click **Create repository**.
5. Back in your terminal, set the remote and push:

   ```bash
   cd components/<name>
   git remote add <yourname> https://github.com/<yourname>/<name>.git
   git push -u <yourname> main
   ```

### Enable GitHub Pages

GitHub doesn't auto-enable Pages on new repos. You enable it once,
manually:

1. In your new repo on GitHub, click **Settings** (top nav).
2. In the left sidebar, click **Pages** (under "Code and automation").
3. Under **Source**, choose **Deploy from a branch**.
4. Under **Branch**, pick `main` and folder `/ (root)`. Click **Save**.
5. Wait ~1 minute. Refresh the Pages settings page; it'll show a green
   banner with the URL once the first build is done.

Your site lives at `https://<yourname>.github.io/<name>/`. Visit it and
you should see the placeholder page.

---

## 2. Make your first edit

The point of the demo is to feel the full GDD loop — write, propose,
review, merge — on a tiny target. Try it now:

```bash
cd components/<name>
git checkout -b first-post
```

Open `index.md` and replace the placeholder paragraph with whatever
you want. A sentence or two is enough.

Save, commit, push:

```bash
git add index.md
git commit -m "Make the home page mine"
git push -u <yourname> first-post
```

---

## 3. Open a PR and watch the bots

Open the PR:

```bash
gh pr create --fill
```

(`--fill` reuses your commit message as the PR title and body.)

Now wait for the reviewers:

- **CodeRabbit** posts a review usually within a couple of minutes.
  If you don't see one, install the [CodeRabbit GitHub App](https://github.com/marketplace/coderabbit)
  on your account first; it's free for public repos.
- **GitHub Copilot review**, if you have a Copilot subscription, can
  be requested from the PR's **Reviewers** panel — click the gear icon
  next to "Reviewers" and choose "GitHub Copilot". Copilot doesn't
  re-review automatically on every push; if you want a second pass
  after addressing feedback, click "Re-request review" in the same
  panel.

You'll see review threads appear inline in the diff. CodeRabbit's
review tends to be detailed; for a one-paragraph change it might just
suggest a wording tweak or note that everything looks fine.

---

## 4. Merge and see it live

Once you're happy with the review thread responses (or there's nothing
to address):

1. Click **Merge pull request** on the PR. **Squash and merge** is a
   reasonable default for a single-commit PR.
2. GitHub Pages rebuilds the site within a minute or so. There's no
   click required — the rebuild fires on every push to `main`.
3. Refresh `https://<yourname>.github.io/<name>/`. Your edit is live.

That's the whole loop.

---

## 5. Going further

The template stays minimal so you can take it where you want. A few
common next steps:

- **Different theme.** Edit the `theme:` line in `_config.yml`. The
  comments next to that line list other GitHub-supported themes you
  can pick from. For richer theming (custom CSS, layouts), you'd
  either fork a Jekyll theme repo or move to a different static-site
  generator (Astro, VitePress, 11ty, Hugo). Ask your agent to walk
  you through whichever path interests you — *or capture a Thalamus
  todo about the theme work and come back to it later when you have
  ideas*.
- **Custom domain.** Drop a `CNAME` file at the repo root containing
  your domain. Configure DNS to point at GitHub Pages' servers
  (instructions in your domain registrar's docs + GitHub's [custom
  domain guide](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site)).
- **More pages.** Add `<page-name>.md` files alongside `index.md`,
  link from `index.md` (Markdown links: `[About](about.md)`).
- **Comments / analytics / search.** Each is a separate add-on with
  its own setup. Ask your agent for the typical patterns — Disqus or
  utterances for comments, GoatCounter or Plausible for cookieless
  analytics, lunr or Algolia for search.

---

## What's in this directory

- `index.md` — the home page you're editing
- `_config.yml` — Jekyll config (title, theme)
- `README.md` — this file
- `.gitignore` — keeps Jekyll's local build output out of git
- `LICENSE` — MIT placeholder; replace or leave as-is once your repo
  is the source of truth

The component is registered in your workspace's `ecosystem.local.yaml`
under `components.<name>` so `ws status`, `ws push <name>`, `ws log
<name>`, etc. all work from the yggdrasil root. To share this
component with your community, move that `ecosystem.local.yaml` entry
into your realm's `ecosystem.yaml` with realm-appropriate fields
(tier, etc.) and push the realm.
````

### Task B3: Create `.gitignore` and `LICENSE`

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/.gitignore`
- Create: `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/LICENSE`

- [ ] **Step 1: Write `.gitignore`**

Write `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/.gitignore` with this exact content:

```gitignore
# Jekyll local build output
_site/
.jekyll-cache/
.jekyll-metadata

# Bundler artifacts (only present if you decide to run Jekyll locally)
.bundle/
vendor/
Gemfile.lock

# OS noise
.DS_Store
Thumbs.db
```

- [ ] **Step 2: Write `LICENSE`**

Write `D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/LICENSE` with this exact content:

```text
MIT License

Copyright (c) <year> <name>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The `<year>` and `<name>` placeholders are intentionally NOT replaced
during scaffolding — leaving them as-is signals to the user that they
should fill them in (or pick a different license).

### Task B4: Verify the full `gh-pages` flavor scaffolds correctly

- [ ] **Step 1: Confirm template files**

```bash
ls D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/
```

Expected: five files — `.gitignore  LICENSE  README.md  _config.yml  index.md`.

- [ ] **Step 2: Confirm flavor lists in CLI**

```bash
ws component list
```

Expected: `Known component flavors:` then `  gh-pages`.

- [ ] **Step 3: Run `ws component init gh-pages` end-to-end on a synthetic fixture**

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/components"
cat > "$tmpdir/ecosystem.yaml" << 'EOF'
identity:
  human_account: testuser
EOF

# Note: TEMPLATES_DIR is the real one — we want to validate the actual
# gh-pages template — but COMPONENTS_DIR and ROOT_DIR are temp.
COMPONENTS_DIR="$tmpdir/components" \
ROOT_DIR="$tmpdir" \
ECOSYSTEM="$tmpdir/ecosystem.yaml" \
  ws component init gh-pages testblog 2>&1 | tail -25
```

Expected output ends with:

```
Component initialized: components/testblog

Registered in ecosystem.local.yaml:
  components:
    testblog:
      repo: https://github.com/testuser/testblog.git
...
Suggested next step — create and push the GitHub remote:
  gh repo create testuser/testblog --public \
    --source=components/testblog --remote=testuser --push

(--public is required for free GitHub Pages on personal accounts.)

Then read components/testblog/README.md for the demo walkthrough.
```

- [ ] **Step 4: Verify the scaffolded component**

```bash
ls "$tmpdir/components/testblog/"
cat "$tmpdir/ecosystem.local.yaml"
git -C "$tmpdir/components/testblog" log --pretty='%an <%ae>: %s' -1
git -C "$tmpdir/components/testblog" branch --show-current
```

Expected:
- Five files in `components/testblog/`: `.gitignore  LICENSE  README.md  _config.yml  index.md`
- `ecosystem.local.yaml` contains `components.testblog.repo: https://github.com/testuser/testblog.git`
- Initial commit attribution uses your git config (e.g. `Cervator <cervator@gmail.com>: Initial commit (gh-pages component for testuser)`)
- Branch is `main`

- [ ] **Step 5: Cleanup**

```bash
rm -rf "$tmpdir"
echo "cleaned"
```

### Task B5: Commit Phase B

- [ ] **Step 1: Write the bodyfile**

Create `D:/Dev/GitWS/yggdrasil/.commits/component-templates-phase-b.md`:

```markdown
---
message: "feat(templates): add gh-pages flagship component template"
add:
  - templates/components/gh-pages/index.md
  - templates/components/gh-pages/_config.yml
  - templates/components/gh-pages/README.md
  - templates/components/gh-pages/.gitignore
  - templates/components/gh-pages/LICENSE
---

Five-file template for a working GitHub Pages site, scaffolded by
ws component init gh-pages <name>. Bare markdown + jekyll-theme-cayman
(GitHub-rendered, no local toolchain), with a comprehensive
tutorial-style README that walks a solo user through the full demo
loop: gh repo create → enable Pages in repo settings → first edit on a
topic branch → PR → CodeRabbit/Copilot review → merge → see it live.

The README opens with a header acknowledging both AI-assisted and
manual paths ("arrive at roughly the same place") and ends with a
"Going further" section that explicitly invites the user to ask their
agent to capture a Thalamus todo about future theme upgrades —
generalizes a useful "spot a future-work item, offer to capture it"
pattern.

Verified e2e: ws component init gh-pages testblog (under a temp
COMPONENTS_DIR) produces all five files, registers in
ecosystem.local.yaml, git-inits with the user's git config attribution,
prints the --public-flagged gh repo create suggestion, and includes
the per-flavor "free GH Pages requires public" note in the educational
output.
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/component-templates-phase-b.md
```

- [ ] **Step 3: Confirm commit**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 5 files changed under `templates/components/gh-pages/`.

---

# Phase C — Documentation

Lands the vocabulary clarification (sub-project D) and the doc updates that make `ws component init` discoverable from the standard onboarding paths. No code change.

### Task C1: Update `AGENTS.md`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/AGENTS.md`

- [ ] **Step 1: Add `ws component` to the workspace-CLI list**

In `D:/Dev/GitWS/yggdrasil/AGENTS.md`, locate the bullet listing `ws hoard init [template]` (around line 100-110). Immediately after that bullet, insert:

```markdown
- `ws component init <flavor> [name]` / `ws component list` — scaffold a
  new component from a template under `templates/components/<flavor>/`.
  Flagship flavor is `gh-pages` (a tutorial-friendly GitHub Pages site).
```

- [ ] **Step 2: Add a "Components (template-scaffolded)" subsection**

After the existing `## Hoards (personal containers)` section, before the next `---` separator, insert:

```markdown
## Components (template-scaffolded)

Components are the third member of the template family alongside hoards
and realms. `templates/components/<flavor>/` directories ship in upstream
yggdrasil; `ws component init <flavor> <name>` copies one into
`components/<name>/`, git-inits it, and registers an entry in
`ecosystem.local.yaml` (the per-developer layer of the three-layer
config merge). The component is immediately usable from the workspace
without touching the realm; when ready to share, move the entry into the
realm's `ecosystem.yaml` with realm-appropriate fields and push.

Flagship flavor is `gh-pages` — a tutorial-friendly GitHub Pages site
with a README that walks a solo user through the full edit → PR →
bot-review → merge → see-it-live loop.

See [Component Templates Design](docs/plans/2026-04-25-component-templates-design.md)
for the full picture.
```

### Task C2: Update `CLAUDE.md`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/CLAUDE.md`

- [ ] **Step 1: Add `ws component` to the available-commands list**

In `D:/Dev/GitWS/yggdrasil/CLAUDE.md`, locate the line listing `ws hoard` in the Available section. Update it from:

```markdown
  Available: `ws list`, `ws status`, `ws clone`, `ws pull`, `ws push`,
  `ws cr`, `ws issue`, `ws test`, `ws review`, `ws commit`, `ws log`, `ws clean`,
  `ws resolve`, `ws vscode`, `ws exec`, `ws realm`, `ws hoard`, `ws actions`,
  `ws help`.
```

to:

```markdown
  Available: `ws list`, `ws status`, `ws clone`, `ws pull`, `ws push`,
  `ws cr`, `ws issue`, `ws test`, `ws review`, `ws commit`, `ws log`, `ws clean`,
  `ws resolve`, `ws vscode`, `ws exec`, `ws realm`, `ws hoard`, `ws component`,
  `ws actions`, `ws help`.
```

### Task C3: Update `docs/ws-cli-guide.md`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/docs/ws-cli-guide.md`

- [ ] **Step 1: Add component subcommands to the Safe-tier table**

Locate the Safe row (around line 77). Update:

```markdown
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode`, `test`, `review` (listing/status), `log`, `clean`, `realm list`, `realm init`, `hoard list`, `hoard init`, `hoard init <template>`, `hoard init <template> <args>`, `actions` |
```

to:

```markdown
| **Safe** | Yes (allow) | No | `list`, `status`, `clone`, `pull`, `resolve`, `vscode`, `test`, `review` (listing/status), `log`, `clean`, `realm list`, `realm init`, `hoard list`, `hoard init`, `hoard init <template>`, `hoard init <template> <args>`, `component list`, `component init <flavor>`, `component init <flavor> <name>`, `actions` |
```

- [ ] **Step 2: Find the existing `ws hoard init` section header**

Scroll through `docs/ws-cli-guide.md` looking for an `## ws hoard init` or similar section that documents hoard semantics. If one doesn't exist (the file may only have the tier table), skip to Step 3.

- [ ] **Step 3: Add a `ws component init` semantics section**

Find a sensible insertion point — after any `ws hoard init` description, or at the end of the file if there's no "subcommand details" section yet. Insert:

```markdown
## ws component init

Scaffolds a new component into `components/<name>/` from a template
shipped at `templates/components/<flavor>/`.

Usage:

```bash
ws component init <flavor> [name] [template-args]
ws component list
```

Behavior:

1. Validates the flavor exists. Errors with the available-flavors list
   if not.
2. Resolves the component name. Required; prompted on a tty if omitted.
3. Pre-flight checks: `components/<name>/` doesn't exist, `<name>`
   isn't already in `ecosystem.local.yaml`. Warns + confirms if `<name>`
   shadows a realm-catalog entry.
4. Copies the template directory into `components/<name>/`.
5. `git init -b main`, initial commit using the user's git config
   (with fallback to `identity.human_account` from merged config).
6. Adds an entry to `ecosystem.local.yaml` under `components.<name>.repo`
   (matches the field `ws-clone.sh` reads). The URL is inferred from
   `identity.human_account` and the component name, in canonical
   `https://github.com/<user>/<name>.git` form.
7. Prints educational output explaining the local-first → upstream-when-
   ready flow plus a flavor-appropriate `gh repo create` suggestion.

`ecosystem.local.yaml` is the per-developer (gitignored) layer of the
three-layer merge. The new component is immediately usable from this
workspace; when ready to share with the community, move the entry into
the realm's `ecosystem.yaml` with realm-appropriate fields (tier,
chartVersion, etc.) and push the realm.

Currently shipped flavors:

- `gh-pages` — tutorial-friendly GitHub Pages site, bare markdown +
  default GitHub Jekyll theme. Comprehensive README walks the user
  through the edit → PR → bot-review → merge → see-it-live demo loop.

Per-flavor flag handling is hardcoded in `scripts/ws-component.sh`
for v1.
```

### Task C4: Update `docs/getting-started/index.md`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/docs/getting-started/index.md`

- [ ] **Step 1: Add a "Templates, instances, and tutorials" section**

In `D:/Dev/GitWS/yggdrasil/docs/getting-started/index.md`, find a sensible early-document insertion point — somewhere after the intro but before deep workspace details. Insert:

```markdown
## Templates, instances, and tutorials

The yggdrasil workspace ships templates in two shapes: in-repo
`templates/<kind>/<flavor>/` directories that an `init` command copies
out (hoards, components), and external git repos that an `init` command
clones (realms — referenced via `defaults.templateRealm` URL in the
ecosystem config).

| Kind | Source | Instance dir | Init command |
|------|--------|--------------|--------------|
| **Realm** | external git repo (URL in `defaults.templateRealm`) | `realms/realm-<community>/` (or `realms/realm-template/` for the upstream tutorial) | `ws realm init` (clones the template URL) |
| **Hoard** | `templates/hoards/<type>/` | `hoards/<type>-<username>/` | `ws hoard init <type>` (copies + git-inits) |
| **Component** | `templates/components/<flavor>/` | `components/<name>/` | `ws component init <flavor> <name>` (copies + git-inits) |

A *template* is a forkable scaffold. An *instance* is the on-disk
result of running its `init` command. A *tutorial* is an instance
deliberately suitable for newcomers — the `gh-pages` component
template produces a tutorial instance with a comprehensive README and
a designed-to-be-edited home page. Other flavors may not be tutorial-
friendly (they're production scaffolds).
```

- [ ] **Step 2: Add the `ws component init gh-pages` recommendation to the newcomer flow**

Find the section describing the recommended first commands (search for `ws clone` or similar). After whatever recommended-first-action is currently there, insert:

```markdown
### Recommended first scaffold

If you're new to GDD and want to feel the full workflow on a tiny live
target, scaffold the GitHub Pages tutorial:

```bash
ws component init gh-pages my-page
```

Then follow the printed instructions and `components/my-page/README.md`.
The tutorial walks you through creating the GitHub repo, enabling
Pages, making a first edit on a topic branch, opening a PR, watching
CodeRabbit and Copilot review, and seeing it deploy live — the whole
GDD loop on something small enough to feel in 15 minutes.
```

### Task C5: Update `templates/README.md`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/templates/README.md`

- [ ] **Step 1: Add `components/` to the Subdirectories list**

In `D:/Dev/GitWS/yggdrasil/templates/README.md`, locate the `## Subdirectories` section. Update it from:

```markdown
## Subdirectories

- `hoards/` — templates for `ws hoard init <type>` (e.g. `thalami/`).
- `external/` — gitignored landing area for fetched / externally-sourced
  templates (future "marketplace" use). Tracked only by `.gitkeep`.
```

to:

```markdown
## Subdirectories

- `hoards/` — templates for `ws hoard init <type>` (e.g. `thalami/`).
- `components/` — templates for `ws component init <flavor> <name>`
  (e.g. `gh-pages/` — a tutorial-friendly GitHub Pages site).
- `external/` — gitignored landing area for fetched / externally-sourced
  templates (future "marketplace" use). Tracked only by `.gitkeep`.
```

### Task C6: Commit Phase C

- [ ] **Step 1: Write the bodyfile**

Create `D:/Dev/GitWS/yggdrasil/.commits/component-templates-phase-c.md`:

```markdown
---
message: "docs: components vocabulary + ws component init guide"
add:
  - AGENTS.md
  - CLAUDE.md
  - docs/ws-cli-guide.md
  - docs/getting-started/index.md
  - templates/README.md
---

Land the documentation half of the component-templates work
(sub-project D from the realms-and-hoards Tutorials block). All five
files updated in lockstep so the vocabulary lands together:

- AGENTS.md gains a "Components (template-scaffolded)" subsection
  mirroring the existing Hoards section, plus a CLI list bullet for
  ws component init / list.
- CLAUDE.md adds ws component to the available-commands inventory.
- docs/ws-cli-guide.md extends the Safe-tier table to include
  component init forms, and adds a full ws component init semantics
  section explaining the local-first → upstream-when-ready flow.
- docs/getting-started/index.md introduces a "Templates, instances,
  and tutorials" vocabulary table (template = forkable scaffold;
  instance = on-disk result; tutorial = instance for newcomers) and
  adds a "Recommended first scaffold" section pointing newcomers at
  ws component init gh-pages.
- templates/README.md mentions templates/components/ alongside
  templates/hoards/ in the subdirectories list.

No code change.
```

- [ ] **Step 2: Commit**

```bash
ws commit yggdrasil .commits/component-templates-phase-c.md
```

---

# Phase D — Final verification + push

### Task D1: Final end-to-end verification

- [ ] **Step 1: Verify all the touched files compile / parse**

```bash
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh && echo "ws-component.sh ok"
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws && echo "ws ok"
yq -p=json '.' D:/Dev/GitWS/yggdrasil/.claude/settings.json > /dev/null && echo "settings.json ok"
yq '.' D:/Dev/GitWS/yggdrasil/templates/components/gh-pages/_config.yml > /dev/null && echo "_config.yml ok"
```

Expected: all four lines print "ok".

- [ ] **Step 2: Verify ws help and listings**

```bash
ws help 2>&1 | grep -E 'component (init|list)' && echo "help mentions component"
ws component list
```

Expected: help shows `component init` and `component list` lines; list shows `gh-pages`.

- [ ] **Step 3: Run the full e2e against a temp workspace one more time**

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/components"
cat > "$tmpdir/ecosystem.yaml" << 'EOF'
identity:
  human_account: testuser
EOF
COMPONENTS_DIR="$tmpdir/components" \
ROOT_DIR="$tmpdir" \
ECOSYSTEM="$tmpdir/ecosystem.yaml" \
  ws component init gh-pages finaltest 2>&1 | tail -10
ls "$tmpdir/components/finaltest/" | sort
rm -rf "$tmpdir"
```

Expected: success message ending with the gh repo create suggestion + the `--public` rationale; five files listed in alphabetical order (`.gitignore`, `LICENSE`, `README.md`, `_config.yml`, `index.md`).

- [ ] **Step 4: Confirm working tree is clean**

```bash
git -C D:/Dev/GitWS/yggdrasil status --short
```

Expected: nothing tracked-and-modified. Untracked `.commits/*.md` bodyfiles are fine — they're gitignored.

### Task D2: Push the branch and open the PR

- [ ] **Step 1: Push**

```bash
ws push yggdrasil design/component-templates
```

Expected: branch pushed to `siliconsaga` remote.

- [ ] **Step 2: Write the CR body**

Create `D:/Dev/GitWS/yggdrasil/.crs/component-templates.md`:

````markdown
> **AI-assisted change proposal.** Filed by agent driven by @Cervator via [GDD](https://github.com/SiliconSaga/yggdrasil).

## Summary

Lands sub-projects A + D from the Tutorials block of the realms-and-hoards Thalamus section: introduce **component templates** as the third member of the template family alongside hoards and realms, ship a flagship `gh-pages` flavor suitable for tutorial use, add `ws component init <flavor> [name]` mirroring `ws hoard init`, and clarify the *template / instance / tutorial* vocabulary in workspace docs.

## Scope

Three sequential commits:

- **Phase A** (`feat(ws): introduce ws component init plumbing`) — new `scripts/ws-component.sh`, router wiring in `scripts/ws`, `.claude/settings.json` allowlist patterns. No flavors shipped yet.
- **Phase B** (`feat(templates): add gh-pages flagship component template`) — five files under `templates/components/gh-pages/`: `index.md`, `_config.yml`, comprehensive tutorial-style `README.md`, `.gitignore`, `LICENSE` (MIT placeholder).
- **Phase C** (`docs: components vocabulary + ws component init guide`) — `AGENTS.md`, `CLAUDE.md`, `docs/ws-cli-guide.md`, `docs/getting-started/index.md`, `templates/README.md`.

## Why

Substrate for a soft-GA newcomer story: clone yggdrasil, run two commands, edit a page, open a PR, watch the bots review you, merge, see it live. The `gh-pages` template's README is comprehensive enough that a solo (non-AI-assisted) user can finish the loop end-to-end; AI-assisted users benefit because the agent can point at the README rather than hallucinate setup steps.

`ws component init` registers new components in `ecosystem.local.yaml` (the per-developer gitignored layer), keeping the realm's shared catalog clean. Components are immediately usable from the workspace; user upstreams the entry to the realm when ready to share — explained in the educational output.

## Test plan

- [x] `bash -n` clean on `ws-component.sh` and `ws`
- [x] `yq -p=json` validates `.claude/settings.json`
- [x] `ws help` shows `component init` / `component list`
- [x] `ws component list` shows `gh-pages`
- [x] `ws component init` errors cleanly with no flavor
- [x] `ws component init unknown` errors cleanly with the available-flavors list
- [x] **End-to-end on synthetic fixture**: `ws component init gh-pages testblog` (under temp `COMPONENTS_DIR`/`ROOT_DIR`) produces all five files, registers in `ecosystem.local.yaml`, git-inits with user's git config attribution, prints `--public`-flagged suggestion + the GH-Pages-public rationale
- [x] Re-running `ws component init gh-pages testblog` errors with "components/testblog already exists"
- [ ] CodeRabbit review

## Notes for reviewers

- **Per-flavor flag handling** is hardcoded in `scripts/ws-component.sh` for v1 (mirrors how `ws-hoard.sh` handles `--from-thalamus`). Generalized template-metadata is a Future Direction in the design doc.
- **`--public` default for `gh-pages`** is deliberate — free GitHub Pages on personal accounts requires public visibility. The README explains why; the educational output also flags it.
- **Local-first registration** to `ecosystem.local.yaml` is the deliberate design choice (vs auto-editing the realm's shared `ecosystem.yaml`). The realm boundary stays clean; user upstreams when ready.
- **Sub-projects B (additional flavors), C (mentoring-mode pass), and E (Mermaid diagrams)** are explicitly out of scope and tracked separately in the Thalamus.
- **Known minor smell:** `ws_resolve_human_account` is defined in both `ws-hoard.sh` (existing) and `ws-component.sh` (new in this PR). Both implementations are identical — five lines of yq + error guidance. Candidate for a small follow-up dedupe (move to `ws-realm.sh` as a shared identity helper, since both consumers source it). Not done in this PR to keep the change additive and avoid touching an unrelated file's function exports.

## Related

- Design: `docs/plans/2026-04-25-component-templates-design.md`
- Plan: `docs/plans/2026-04-25-component-templates-plan.md`
- Predecessor: PR #43 (realms-and-hoards), PR #44 (`ws_validate_component` recognizes hoards)
````

- [ ] **Step 3: Open the PR**

```bash
ws cr yggdrasil "Component templates: gh-pages flagship + ws component init plumbing" .crs/component-templates.md
```

Expected: PR opened on `SiliconSaga/yggdrasil`. Capture the URL for the user.

---

## After landing

Once merged, surviving Tutorials-block sub-projects:

- **B.** Additional flavors (frontend, backend, full-stack mini, MCP server template)
- **C.** Mentoring mode pass (`gdd-mentoring/SKILL.md` refresh)
- **E.** Mermaid diagrams for `docs/ecosystem-architecture.md` / `docs/getting-started/`

Each gets its own brainstorm + design + plan when picked up.
