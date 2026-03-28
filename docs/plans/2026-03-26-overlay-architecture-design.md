# Yggdrasil Overlay Architecture — Design Spec

**Date:** 2026-03-26
**Status:** Draft
**Extends:** [GDD Design](2026-03-12-gdd-design.md)

---

## Summary

Yggdrasil becomes a generic meta-workspace — scaffolding around any community's projects. Community-specific configuration (components, identity, build adapters, AI context) moves from hardcoded `ecosystem.yaml` entries to a separate overlay repo that lives in `overlays/`. Users interact with `ws overlay` commands; the underlying complexity is transparent.

The design principle: **always functional, progressively richer.** A bare project with no overlay works. An overlay makes it better. Per-component adapters make it better still.

---

## The Overlay Concept

### What is an overlay?

A small git repo containing community-specific configuration for a Yggdrasil workspace. It declares which components to work on, how to build them, where AI context lives, and what identity to use for contributions.

### Why not just put this in ecosystem.yaml?

- **Shareability:** One person sets up the overlay, everyone clones it. No per-machine config file edits.
- **No agentic cruft in target repos:** Components stay clean. The overlay provides context externally.
- **Multi-community:** A user contributing to SiliconSaga and a different community can switch overlays, not maintain two Yggdrasil forks.
- **Separation of concerns:** Yggdrasil provides methodology and tools. The overlay provides "for what and for whom."

---

## Directory Structure

```
yggdrasil/
  ecosystem.yaml              # Upstream defaults (empty/minimal)
  ecosystem.local.yaml        # Per-developer overrides + optional overlay selector
  components/                 # Code repos (gitignored, independent git repos)
    terasology/
    nordri/
    ...
  overlays/                   # Config repos (gitignored, independent git repos)
    overlay-yggdrasil-live/   # Active community config
    overlay-yggdrasil-template/  # Tutorial/example overlay
  scripts/
    ws                        # Unified CLI — gains overlay awareness
  .agent/                     # GDD skills, templates
  docs/                       # Methodology and getting-started docs
```

Both `components/` and `overlays/` are gitignored with a `.gitkeep` tracked.

---

## Overlay Repo Structure

```
overlay-yggdrasil-live/       # e.g. SiliconSaga/overlay-yggdrasil-live on GitHub
  ecosystem.yaml              # Components, defaults, identity
  adapters/                   # Per-component config (optional)
    terasology.yaml
    nordri.yaml
    vordu.yaml
  README.md
```

### ecosystem.yaml (overlay)

```yaml
defaults:
  chartRegistry: oci://ghcr.io/siliconsaga
  gitOrg: https://github.com/SiliconSaga
  gitea:
    internalUrl: "http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/{repo}.git"

identity:
  agent_account: agent-refr
  co_authored_by: "Claude Opus 4.6"
  # human_account is personal — set in ecosystem.local.yaml

components:
  nordri:
    tier: 1
    chartVersion: "0.0.0"
    path: "platform/fundamentals"
    namespace: argocd
  terasology:
    tier: 3
    chartVersion: "0.0.0"
    chartName: "ts-game"
    namespace: terasology
  # ... other SiliconSaga components
```

### Adapter files (per-component)

```yaml
# adapters/terasology.yaml
commands:
  build: "./gradlew build"
  test: "./gradlew test"
  run: "./gradlew run"
  clean: "./gradlew clean"

ai_context:
  # Freeform pointers for GDD orientation to discover
  - path: "CONTRIBUTING.md"
    description: "Contribution guidelines and PR conventions"
  - path: ".groovy/scripts/"
    description: "Groovy utility scripts for content authoring"
  - path: "docs/architecture.md"
    description: "Module architecture overview"
```

Adapter files are optional. Components without an adapter file use auto-detection fallbacks.

---

## Overlay Detection and Selection

### Naming convention

- `overlay-yggdrasil-live` — the active community overlay
- `overlay-yggdrasil-template` — ships with tutorials, used when no live overlay exists

### Lookup order

```
1. Selector in ecosystem.local.yaml (if set)
2. overlays/overlay-yggdrasil-live (if present)
3. overlays/overlay-yggdrasil-template (if present)
4. None — upstream ecosystem.yaml only
```

### Optional selector

```yaml
# ecosystem.local.yaml
# overlay: overlay-yggdrasil-live      # uncomment to override auto-detection
```

The selector enables switching between overlays (e.g. live vs test) without moving directories. Auto-detection works for the common case; the selector is there when you need it.

---

## Config Merge

Three-layer merge, applied in order:

```
ecosystem.yaml (upstream Yggdrasil — empty defaults)
    ↓ deep merge
overlay/ecosystem.yaml (community config)
    ↓ deep merge
ecosystem.local.yaml (per-developer overrides)
```

### Merge semantics

- **Deep merge** using `yq` — nested keys are merged recursively. If the
  overlay sets `gitea.internalUrl` but not `chartRegistry`, the upstream
  `chartRegistry` survives.
- `components`: overlay completely owns the component list. Upstream ships
  empty.
- `identity`: overlay provides, local can override individual fields.
- Unknown top-level keys pass through — overlays can add custom fields.

### Implementation: `ws_resolve_ecosystem()`

A shared shell function that produces a merged temp file. Called once at the
start of any `ws` command that needs ecosystem config.

```bash
ws_resolve_ecosystem() {
    local base="$ROOT_DIR/ecosystem.yaml"
    local overlay_file=""
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    local merged

    # Find active overlay
    local active_overlay
    active_overlay="$(ws_detect_overlay)"
    if [[ -n "$active_overlay" ]]; then
        overlay_file="$ROOT_DIR/overlays/$active_overlay/ecosystem.yaml"
    fi

    # Three-layer deep merge via yq
    merged="$(mktemp)"
    if [[ -n "$overlay_file" && -f "$overlay_file" ]]; then
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$base" "$overlay_file" > "$merged"
    else
        cp "$base" "$merged"
    fi
    if [[ -f "$local_file" ]]; then
        local tmp="$(mktemp)"
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$merged" "$local_file" > "$tmp"
        mv "$tmp" "$merged"
    fi

    echo "$merged"
}
```

All `ws` functions that read ecosystem config use the merged file via
`ws_resolve_ecosystem()`. The temp file is cleaned up at script exit.

### Identity and attribution

`ws commit` reads `identity` from the merged ecosystem config:

- `co_authored_by` → used in the `Co-Authored-By` git trailer
- `agent_account` → shared, set in the overlay
- `human_account` → personal, set in `ecosystem.local.yaml`

Attribution is built at runtime from these fields. When `human_account`
is unset, attribution omits the human reference. `CLAUDE_MODEL` env var
overrides `co_authored_by` when set.

`ws pr` and `ws issue` identity integration is planned but not yet
implemented.

---

## ws CLI Changes

### New commands

```bash
ws overlay init                    # Clone template repo → overlays/overlay-yggdrasil-template
ws overlay <git-url>               # Clone community overlay → overlays/overlay-yggdrasil-live
                                   # Errors if -live exists (only one live overlay)
ws overlay use <name>              # Set active overlay in ecosystem.local.yaml
ws overlay list                    # Show available overlays, mark which is active
ws actions <comp>                  # List available adapter commands for a component
```

**`ws overlay init` source:** Clones from a known GitHub URL
(e.g. `SiliconSaga/overlay-yggdrasil-template`). The URL is configured in
upstream `ecosystem.yaml` under `defaults.templateOverlay`.

**`ws overlay <git-url>` behavior:** Always targets the `overlay-yggdrasil-live`
directory. If it already exists, error with guidance: "Live overlay already
exists. Remove it first or use `ws overlay use` to switch." Only one live
overlay at a time.

**`ws actions <comp>` output:**
```
=== terasology ===
Configured (from overlay):
  build    ./gradlew build
  test     ./gradlew test
  run      ./gradlew run
  clean    ./gradlew clean
Auto-detected:
  (none — overlay commands take precedence)
```
When no adapter exists, shows only auto-detected commands. When no commands
found at all, shows guidance to configure an adapter file.

### Modified commands

- **`ws list`** — reads components from merged ecosystem config. If zero
  components found, shows guidance: "No components declared. Run
  `ws overlay init` to get started, or `ws overlay <url>` for your community."
- **`ws clone --all`** — same zero-component safety check before cloning.
- **`ws clone`** — resolves `gitOrg` from merged config defaults.
- **`ws test/build/run <comp>`** *(not yet implemented)* — will check adapter
  config before auto-detection. When an adapter defines the requested command,
  it replaces auto-detection for that invocation. The current `ws_test`
  auto-detection logic (Makefile → Go → Python) becomes the fallback, not
  the primary path. `ws actions <comp>` already shows what commands are
  configured vs auto-detected.
- **`ws commit/pr/issue`** *(not yet implemented)* — will read identity config
  from merged ecosystem config for attribution templates.

### Adapter command resolution *(planned)*

```text
ws build terasology
    ↓
1. Read merged ecosystem config (ws_resolve_ecosystem)
2. Active overlay has adapters/terasology.yaml?
3. "build" command defined?
   → Yes: cd components/terasology && execute mapped command
   → No: fall back to auto-detection
```

### Auto-detection fallback (when no adapter defines the command)

The existing `ws test` detection logic becomes the general fallback:

```text
gradlew present     → Gradle (./gradlew <command>)
Makefile present    → Make
go.mod present      → Go
pyproject.toml present → Python
package.json present   → npm/yarn
Nothing recognized  → Error with guidance to configure adapter
```

Adapter commands always take precedence over auto-detection when both exist.

---

## AI Context Discovery (Orientation Integration)

The GDD orientation skill gains overlay awareness during trust verification (Step 6):

### When overlay has ai_context pointers

Read the adapter file's `ai_context` section. Use the pointers to know exactly which files to examine in the component. Apply trust hierarchy as usual (ecosystem = trusted, non-ecosystem = verify).

### When no ai_context but component has standard files

Auto-detect:
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- `.agent/skills/*/SKILL.md`
- `CONTRIBUTING.md`
- `docs/ARCHITECTURE.md` or similar

### Bare project

GDD works with workspace-level skills only. The agent may suggest:

> "This component has no AI context configured. Want me to explore the codebase, or should we add pointers in the overlay?"

This encourages gradual adoption without requiring it.

---

## The Template Overlay

Ships with upstream Yggdrasil. Cloned by `ws overlay init`. Contains:

```
overlay-yggdrasil-template/
  ecosystem.yaml          # Example components (tutorial-friendly projects)
  adapters/
    example.yaml          # Shows the adapter format
  README.md               # "Fork or copy this to create your own overlay"
```

The template's ecosystem.yaml would declare a few simple tutorial components — public repos that anyone can clone and explore without auth setup. The SiliconSaga game repos (terasology, destinationsol) could serve this role since they're public and have visible changes.

---

## User Experience

### New user, exploring GDD

```bash
git clone https://github.com/SiliconSaga/yggdrasil.git
cd yggdrasil
ws overlay init                    # gets the template with tutorial components
ws clone --all                     # clones tutorial components
# Start Claude Code, say hello, ask for Mentoring mode
```

Three commands to a working GDD session with tutorial content.

### Existing community member

```bash
git clone https://github.com/SiliconSaga/yggdrasil.git
cd yggdrasil
ws overlay https://github.com/SiliconSaga/overlay-yggdrasil-live.git
ws clone --all                     # clones components declared in the overlay
```

Two `ws` commands after the initial clone.

### Creating a new community overlay

The simplest path: fork `SiliconSaga/overlay-yggdrasil-template` on GitHub,
rename it, edit the ecosystem.yaml and adapter files, then:

```bash
ws overlay https://github.com/YourOrg/overlay-yggdrasil-live.git
```

A future `ws overlay new` wizard could scaffold this interactively — create
a new git repo in `overlays/overlay-yggdrasil-live`, copy the template
structure, and prompt for basic config (org URL, components, identity).

---

## User-Facing Complexity Assessment

Areas where users interact with overlay concepts:

| Action | Complexity | Notes |
|--------|-----------|-------|
| `ws overlay init` | Low | One command, gets tutorials |
| `ws overlay <url>` | Low | One command, community provides the URL |
| `ws clone --all` | None | Same as today, just reads from overlay |
| `ws build/test <comp>` | None | Transparent — adapter resolution is invisible |
| Creating an overlay | Medium | Requires understanding the ecosystem.yaml format and adapter files |
| Switching overlays | Low | `ws overlay use <name>` |
| Writing adapter files | Medium | YAML config, but only needed for custom build systems |

The common path (clone, overlay, work) is 2-3 commands with no config file editing. The medium-complexity actions (creating overlays, writing adapters) are one-time setup tasks done by a community maintainer, not every user.

---

## Migration

Clean cut, no backward compatibility scaffolding:

1. Create `overlays/` directory structure in upstream Yggdrasil
2. Create `overlay-yggdrasil-live` repo on SiliconSaga GitHub with current ecosystem.yaml content + adapter files
3. Create `overlay-yggdrasil-template` with tutorial content
4. Implement `ws overlay` commands
5. Empty upstream `ecosystem.yaml`
6. Update docs and getting-started
7. Test on fresh workspace, then pull into existing workspaces

Timing: implement on one machine while the other stays on current setup. Validate, then migrate.

---

## Future Directions

- **`ws overlay new` wizard** — interactive setup for creating a community overlay from scratch
- **Overlay inheritance** — an overlay could extend another overlay (e.g. a team overlay extends the org overlay). Not needed yet.
- **MCP server config in overlays** — component-specific MCP servers declared in adapter files, started on demand
- **Per-environment overlays** — `overlay-yggdrasil-staging`, `overlay-yggdrasil-prod` for different deployment targets
- **Overlay marketplace/registry** — discover community overlays. Very distant future.
