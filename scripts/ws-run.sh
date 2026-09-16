#!/usr/bin/env bash
# ws-run.sh — Run a component (game, dev server, sandbox, …)
# ws:use-when launching the component itself via its adapter
#
# Usage:
#   ws-run.sh <component> [args...]
#
# Resolves the run command from the active realm's adapter
# (`commands.run`) and runs it in the component directory. Extra args
# pass through to the command.
#
# Structure mirrors ws-build.sh: only the adapter-provided command is
# supported — minimal on purpose.
#
# Unlike test/lint/build, `ws run` is deliberately NOT pre-allowed in
# .claude/settings.json — a run command is typically a long-lived or
# interactive process (a game, a server), so each invocation stays
# behind the normal permission prompt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Load .env as literal assignments for run targets that need tokens.
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ws_load_env "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

run_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws run <component> [args...]"
        echo ""
        echo "Run the component itself — launch the game, start the dev server,"
        echo "bring up the sandbox. The command comes from the active realm"
        echo "adapter's 'commands.run' (run 'ws actions <comp>' to see what's"
        echo "configured). Extra args pass through:"
        echo "  ws run terasology"
        echo "  ws run leidangr --port 3001"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    run_help 1
    exit 0
fi

if [[ $# -eq 0 ]]; then
    run_help 2
    exit 1
fi

comp="$1"
shift
ws_resolve_target "$comp"
cd "$COMPONENT_DIR"

# --- Detect run command ---
# Precedence: realm adapter command only (see header note).
runner=""
run_cmd=""

# 1. Realm adapter `commands.run`
active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        ws_require_active_realm_trust "$active_realm" || exit 1
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort the script before the
        # "No run command configured" guidance runs. `// ""` already maps
        # a missing key to empty, so no separate "null" check is needed.
        run_cmd=$(yq -r '.commands.run // ""' "$adapter_file" 2>/dev/null) || run_cmd=""
        if [[ -n "$run_cmd" ]]; then
            runner="adapter"
        fi
    fi
fi

if [[ -z "$runner" ]]; then
    echo "ERROR: No run command configured for '$comp'." >&2
    echo "  Add 'commands.run' to the realm adapter:" >&2
    echo "    realms/<realm>/adapters/$comp.yaml" >&2
    echo "  Example:" >&2
    echo "    commands:" >&2
    echo "      run: \"./gradlew :facades:PC:run\"" >&2
    echo "  Run 'ws actions $comp' to see what's configured." >&2
    exit 1
fi

# --- Parse adapter command into an array for safe exec ---
# Contract mirrors ws-test.sh: whitespace-separated tokens only. Args
# with embedded whitespace/quotes are not supported — point the adapter
# at a wrapper script if you need complex quoting.
run_argv=()
# shellcheck disable=SC2206
read -r -a run_argv <<< "$run_cmd"
if [[ ${#run_argv[@]} -eq 0 ]]; then
    # A whitespace-only command survives the -n check but parses to no
    # tokens — dispatching would execute the passthrough args instead.
    echo "ERROR: commands.run for '$comp' is whitespace-only — fix the adapter." >&2
    exit 1
fi

# --- Dispatch ---
case "$runner" in
    adapter)
        "${run_argv[@]}" "$@"
        ;;
esac
