#!/usr/bin/env bash
# ws-build.sh — Run the build for a component
# ws:use-when building the component via its adapter
#
# Usage:
#   ws-build.sh <component> [args...]
#
# Resolves the build command from the active realm's adapter
# (`commands.build`) and runs it in the component directory. Extra args
# pass through to the build tool (e.g. --release).
#
# Structure mirrors ws-lint.sh: only the adapter-provided command is
# supported — minimal on purpose. Auto-detection (gradle / make / npm,
# etc.) can slot in as additional branches before the "not configured"
# error if evidence of need arrives.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Load .env as literal assignments for builds that need provider tokens.
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ws_load_env "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

build_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws build <component> [args...]"
        echo ""
        echo "Run a component's build. The command comes from the active"
        echo "realm adapter's 'commands.build' (run 'ws actions <comp>' to see"
        echo "what's configured). Extra args pass through to the build tool:"
        echo "  ws build terasology"
        echo "  ws build destinationsol --info"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    build_help 1
    exit 0
fi

if [[ $# -eq 0 ]]; then
    build_help 2
    exit 1
fi

comp="$1"
shift
ws_resolve_target "$comp"
cd "$COMPONENT_DIR"

# --- Detect build command ---
# Precedence: realm adapter command only (see header note).
runner=""
build_cmd=""

# 1. Realm adapter `commands.build`
active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        ws_require_active_realm_trust "$active_realm" || exit 1
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort the script before the
        # "No build command configured" guidance runs. `// ""` already maps
        # a missing key to empty, so no separate "null" check is needed.
        build_cmd=$(yq -r '.commands.build // ""' "$adapter_file" 2>/dev/null) || build_cmd=""
        if [[ -n "$build_cmd" ]]; then
            runner="adapter"
        fi
    fi
fi

if [[ -z "$runner" ]]; then
    echo "ERROR: No build command configured for '$comp'." >&2
    echo "  Add 'commands.build' to the realm adapter:" >&2
    echo "    realms/<realm>/adapters/$comp.yaml" >&2
    echo "  Example:" >&2
    echo "    commands:" >&2
    echo "      build: \"./gradlew build\"" >&2
    echo "  Run 'ws actions $comp' to see what's configured." >&2
    exit 1
fi

# --- Parse adapter command into an array for safe exec ---
# Contract mirrors ws-test.sh: whitespace-separated tokens only. Args
# with embedded whitespace/quotes are not supported — point the adapter
# at a wrapper script if you need complex quoting.
build_argv=()
# shellcheck disable=SC2206
read -r -a build_argv <<< "$build_cmd"
if [[ ${#build_argv[@]} -eq 0 ]]; then
    # A whitespace-only command survives the -n check but parses to no
    # tokens — dispatching would execute the passthrough args instead.
    echo "ERROR: commands.build for '$comp' is whitespace-only — fix the adapter." >&2
    exit 1
fi

# --- Dispatch ---
case "$runner" in
    adapter)
        "${build_argv[@]}" "$@"
        ;;
esac
