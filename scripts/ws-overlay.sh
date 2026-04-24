#!/usr/bin/env bash
# ws-overlay.sh — Overlay management and shared config merge functions
#
# Subcommands (called via ws overlay):
#   init            Clone template overlay for tutorials
#   <git-url>       Clone community overlay as overlay-yggdrasil-live
#   use <name>      Set active overlay in ecosystem.local.yaml
#   list            Show available overlays and which is active
#   actions <comp>  List adapter commands for a component
#
# Also provides shared functions sourced by other ws-* scripts:
#   ws_detect_overlay     — detect active overlay directory name
#   ws_resolve_ecosystem  — three-layer config merge (upstream + overlay + local)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${ECOSYSTEM:="$ROOT_DIR/ecosystem.yaml"}"
: "${OVERLAYS_DIR:="$ROOT_DIR/overlays"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"

_RESOLVED_ECOSYSTEM=""
COMPONENT_DIR=""  # Set by ws_validate_component

# ---------------------------------------------------------------------------
# Shared functions (used by ws-clone.sh, ws-list.sh, ws, etc.)
# ---------------------------------------------------------------------------

# Validate a component name against ecosystem.yaml.
# Usage: ws_validate_component <name>
# Sets: COMPONENT_DIR to the resolved path.
# Accepts "yggdrasil" (workspace root), overlay directory names, and
# components declared in the merged ecosystem config.
ws_validate_component() {
    local name="$1"

    # "yggdrasil" refers to the workspace root, not a component
    if [[ "$name" == "yggdrasil" ]]; then
        COMPONENT_DIR="$ROOT_DIR"
        return 0
    fi

    # Check if name is an overlay directory (uses broader name pattern)
    if [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ -d "$OVERLAYS_DIR/$name/.git" ]]; then
        COMPONENT_DIR="$OVERLAYS_DIR/$name"
        return 0
    fi

    # Reject component names that don't match safe pattern.
    # Use bash regex directly — grep matches per-line and would pass
    # newline-injected names like "mimir\nevil" (CVE-style bypass).
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Invalid component name '$name'. Must be lowercase alphanumeric with hyphens/dots (no trailing dots or consecutive dots)." >&2
        exit 1
    fi

    # Check yq is available
    if ! command -v yq &>/dev/null; then
        echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
        exit 1
    fi

    # Check component exists in merged ecosystem config
    local eco
    eco="$(ws_resolve_ecosystem)"
    local exists
    exists=$(yq ".components[\"$name\"] // \"missing\"" "$eco")
    if [[ "$exists" == "missing" ]]; then
        echo "ERROR: '$name' is not declared in ecosystem config." >&2
        echo "  Run 'ws list' to see available components." >&2
        exit 1
    fi

    COMPONENT_DIR="$COMPONENTS_DIR/$name"

    # Check if cloned locally
    if [[ ! -d "$COMPONENT_DIR" ]]; then
        echo "ERROR: '$name' is not cloned locally." >&2
        echo "  Run 'ws clone $name' to clone it." >&2
        exit 1
    fi
}

# Detect the active overlay directory name.
# Returns the overlay directory name (not the full path) or empty string.
ws_detect_overlay() {
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        local selector
        if ! selector="$(yq '.overlay // ""' "$local_file")"; then
            echo "ERROR: Failed to parse $local_file. Check YAML syntax." >&2
            exit 1
        fi
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$OVERLAYS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi
    if [[ -d "$OVERLAYS_DIR/overlay-yggdrasil-live" ]]; then
        echo "overlay-yggdrasil-live"
        return
    fi
    if [[ -d "$OVERLAYS_DIR/overlay-yggdrasil-template" ]]; then
        echo "overlay-yggdrasil-template"
        return
    fi
    echo ""
}

# Produce a merged ecosystem config (upstream + overlay + local).
# Returns the path to a temp file. Cleanup happens at script exit.
ws_resolve_ecosystem() {
    if [[ -n "$_RESOLVED_ECOSYSTEM" && -f "$_RESOLVED_ECOSYSTEM" ]]; then
        echo "$_RESOLVED_ECOSYSTEM"
        return
    fi

    local base="$ROOT_DIR/ecosystem.yaml"
    local overlay_file=""
    local local_file="$ROOT_DIR/ecosystem.local.yaml"

    local active_overlay
    active_overlay="$(ws_detect_overlay)"
    if [[ -n "$active_overlay" ]]; then
        overlay_file="$OVERLAYS_DIR/$active_overlay/ecosystem.yaml"
        if [[ ! -f "$overlay_file" ]]; then
            echo "ERROR: Active overlay '$active_overlay' has no ecosystem.yaml." >&2
            echo "  The overlay may be incomplete or corrupted." >&2
            exit 1
        fi
    fi

    local merged
    merged="$(mktemp)"
    if [[ -n "$overlay_file" ]]; then
        yq eval-all 'select(fileIndex == 0) *d select(fileIndex == 1)' \
            "$base" "$overlay_file" > "$merged"
    else
        cp "$base" "$merged"
    fi
    if [[ -f "$local_file" ]]; then
        local tmp
        tmp="$(mktemp)"
        yq eval-all 'select(fileIndex == 0) *d select(fileIndex == 1)' \
            "$merged" "$local_file" > "$tmp"
        mv "$tmp" "$merged"
    fi

    _RESOLVED_ECOSYSTEM="$merged"
    echo "$merged"
}

trap 'rm -f "$_RESOLVED_ECOSYSTEM" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# Subcommands — only run when called directly (not when sourced)
# ---------------------------------------------------------------------------

# Guard: if sourced by another script, stop here — don't parse $1 as a command
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

ws_overlay_help() {
    echo "Usage: ws overlay <subcommand>" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init            Clone the template overlay for tutorials" >&2
    echo "  <git-url>       Clone a community overlay as overlay-yggdrasil-live" >&2
    echo "  use <name>      Set active overlay in ecosystem.local.yaml" >&2
    echo "  list            Show available overlays and which is active" >&2
    echo "" >&2
    echo "Also available via ws:" >&2
    echo "  ws actions <comp>   List adapter commands for a component" >&2
}

ws_overlay_init() {
    # Copy ecosystem.local.yaml.example if no local config exists.
    # Must happen BEFORE ws_resolve_ecosystem — the example file contains
    # defaults.templateOverlay which the merge needs to find.
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    local example_file="$ROOT_DIR/ecosystem.local.yaml.example"
    if [[ ! -f "$local_file" && -f "$example_file" ]]; then
        cp "$example_file" "$local_file"
        echo "Created ecosystem.local.yaml from example."
        echo "  Edit it to set your identity.human_account."
        echo ""
    fi

    local eco
    eco="$(ws_resolve_ecosystem)"
    local template_url
    template_url=$(yq '.defaults.templateOverlay // ""' "$eco" 2>/dev/null)
    if [[ -z "$template_url" || "$template_url" == "null" ]]; then
        echo "ERROR: No template overlay URL configured." >&2
        echo "  Set defaults.templateOverlay in ecosystem.local.yaml or your overlay." >&2
        exit 1
    fi

    local target="$OVERLAYS_DIR/overlay-yggdrasil-template"
    if [[ -d "$target" ]]; then
        echo "SKIP: Template overlay already exists at $target"
        return 0
    fi
    mkdir -p "$OVERLAYS_DIR"
    echo "CLONE: template overlay -> $target"
    git clone "$template_url" "$target"
    echo ""
    echo "Template overlay ready. Run 'ws clone --all' to clone tutorial components."
}

ws_overlay_use() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: ws overlay use <name>" >&2
        exit 1
    fi
    local name="$1"
    # Validate overlay name — prevent path traversal
    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid overlay name '$name'. Must be alphanumeric with dots, dashes, underscores." >&2
        exit 1
    fi
    if [[ ! -d "$OVERLAYS_DIR/$name" ]]; then
        echo "ERROR: Overlay '$name' not found in overlays/." >&2
        echo "  Available overlays:" >&2
        for d in "$OVERLAYS_DIR"/*/; do
            [[ -d "$d" ]] && echo "    $(basename "$d")"
        done
        exit 1
    fi
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        yq -i ".overlay = \"$name\"" "$local_file"
    else
        echo "overlay: \"$name\"" > "$local_file"
    fi
    echo "Active overlay set to: $name"
}

ws_overlay_list() {
    echo "=== Overlays ==="
    local active
    active="$(ws_detect_overlay)"
    local found=0
    for d in "$OVERLAYS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local dname
        dname="$(basename "$d")"
        [[ "$dname" == ".gitkeep" ]] && continue
        found=1
        if [[ "$dname" == "$active" ]]; then
            echo "  * $dname (active)"
        else
            echo "    $dname"
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo "  (none)"
        echo ""
        echo "Run 'ws overlay init' for tutorials, or 'ws overlay <url>' for your community."
    fi
}

ws_overlay_clone_url() {
    local url="$1"
    # Basic URL validation
    if [[ ! "$url" =~ ^(https?://|git@) ]]; then
        echo "ERROR: Unknown subcommand or invalid URL '$url'." >&2
        echo "  Run 'ws overlay' for usage." >&2
        exit 1
    fi
    local target="$OVERLAYS_DIR/overlay-yggdrasil-live"
    if [[ -d "$target" ]]; then
        echo "ERROR: Live overlay already exists at $target." >&2
        echo "  Remove it first or use 'ws overlay use' to switch." >&2
        exit 1
    fi
    mkdir -p "$OVERLAYS_DIR"
    echo "CLONE: community overlay -> $target"
    git clone "$url" "$target"
    echo ""
    echo "Community overlay ready. Run 'ws clone --all' to clone components."
}

ws_actions() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: ws actions <component>" >&2
        exit 1
    fi
    local comp="$1"

    # Validate component name (safe pattern, exists in config)
    if [[ ! "$comp" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Invalid component name '$comp'." >&2
        exit 1
    fi

    local eco
    eco="$(ws_resolve_ecosystem)"
    local exists
    exists=$(yq ".components[\"$comp\"] // \"missing\"" "$eco")
    if [[ "$exists" == "missing" ]]; then
        echo "ERROR: '$comp' is not declared in ecosystem config." >&2
        exit 1
    fi

    echo "=== $comp ==="

    # Check for adapter file in active overlay
    local active_overlay
    active_overlay="$(ws_detect_overlay)"
    local adapter_file=""
    if [[ -n "$active_overlay" ]]; then
        adapter_file="$OVERLAYS_DIR/$active_overlay/adapters/$comp.yaml"
    fi

    local has_configured=0
    if [[ -n "$adapter_file" && -f "$adapter_file" ]]; then
        echo "Configured (from overlay):"
        local commands
        commands=$(yq -r '.commands // {} | to_entries | .[] | "  " + .key + "    " + .value' "$adapter_file" 2>/dev/null)
        if [[ -n "$commands" ]]; then
            echo "$commands"
            has_configured=1
        fi
    fi

    # Auto-detection check
    local comp_dir="$COMPONENTS_DIR/$comp"
    if [[ -d "$comp_dir" ]]; then
        echo "Auto-detected:"
        local has_auto=0
        if [[ -f "$comp_dir/gradlew" ]]; then
            echo "  build    ./gradlew build"
            echo "  test     ./gradlew test"
            has_auto=1
        elif [[ -f "$comp_dir/Makefile" ]]; then
            echo "  build    make build (if target exists)"
            echo "  test     make test (if target exists)"
            has_auto=1
        elif [[ -f "$comp_dir/go.mod" ]]; then
            echo "  test     go test ./..."
            has_auto=1
        elif [[ -f "$comp_dir/pyproject.toml" ]]; then
            echo "  test     uv run pytest"
            has_auto=1
        elif [[ -f "$comp_dir/package.json" ]]; then
            echo "  test     npm test"
            has_auto=1
        fi
        if [[ "$has_auto" -eq 0 ]]; then
            if [[ "$has_configured" -eq 1 ]]; then
                echo "  (none - overlay commands take precedence)"
            else
                echo "  (none detected)"
                echo ""
                echo "Configure an adapter file: overlays/<overlay>/adapters/$comp.yaml"
            fi
        fi
    else
        echo "(not cloned locally — run 'ws clone $comp')"
    fi
}

# ---------------------------------------------------------------------------
# Command dispatch (when called directly)
# ---------------------------------------------------------------------------

SUBCMD="${1:-}"
shift 2>/dev/null || true

case "$SUBCMD" in
    ""|--help|-h)
        ws_overlay_help
        ;;
    init)
        ws_overlay_init
        ;;
    use)
        ws_overlay_use "$@"
        ;;
    list)
        ws_overlay_list
        ;;
    actions)
        ws_actions "$@"
        ;;
    *)
        ws_overlay_clone_url "$SUBCMD"
        ;;
esac
