#!/usr/bin/env bash
# ws-run.sh — Run a named adapter action for a component
# ws:use-when executing an adapter-declared action beyond test/lint/build
#
# Usage:
#   ws-run.sh <component> <action> [args...]
#
# Resolves `commands.<action>` from the active realm's adapter and runs
# it in the component directory. Extra args pass through to the command.
# The dedicated verbs (test, lint, build) keep their own dispatch paths
# and are rejected here so there is exactly one way to run each.
#
# Unlike test/lint/build, `ws run` is deliberately NOT pre-allowed in
# .claude/settings.json — adapter-declared actions can launch long-lived
# or interactive processes (a game, a server), so each invocation stays
# behind the normal permission prompt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Load .env as literal assignments for actions that need provider tokens.
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ws_load_env "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

run_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws run <component> <action> [args...]"
        echo ""
        echo "Run a named action from the active realm adapter's 'commands.<action>'"
        echo "(run 'ws actions <comp>' to see what's declared). Extra args pass"
        echo "through to the command:"
        echo "  ws run terasology run"
        echo "  ws run terasology clean"
        echo ""
        echo "test, lint, and build have dedicated verbs — use 'ws test', 'ws lint',"
        echo "or 'ws build' for those."
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    run_help 1
    exit 0
fi

if [[ $# -lt 2 ]]; then
    run_help 2
    exit 1
fi

comp="$1"
action="$2"
shift 2

# Action names are adapter map keys — constrain the shape before it goes
# anywhere near a yq lookup, so an odd token cannot alter the query.
if [[ ! "$action" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    echo "ERROR: Invalid action name '$action' (lowercase letters, digits, '-', '_')." >&2
    exit 1
fi

case "$action" in
    test|lint|build)
        echo "ERROR: '$action' has a dedicated verb — use 'ws $action $comp' instead." >&2
        exit 1
        ;;
esac

ws_resolve_target "$comp"
cd "$COMPONENT_DIR"

# --- Resolve the action command (adapter only) ---
run_cmd=""

active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        ws_require_active_realm_trust "$active_realm" || exit 1
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort before the "not
        # configured" guidance runs. The action name travels via env so
        # it is data to yq, never part of the expression.
        run_cmd=$(WS_RUN_ACTION="$action" yq -r '.commands[strenv(WS_RUN_ACTION)] // ""' "$adapter_file" 2>/dev/null) || run_cmd=""
    fi
fi

if [[ -z "$run_cmd" ]]; then
    echo "ERROR: No '$action' action configured for '$comp'." >&2
    echo "  Add 'commands.$action' to the realm adapter:" >&2
    echo "    realms/<realm>/adapters/$comp.yaml" >&2
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

"${run_argv[@]}" "$@"
