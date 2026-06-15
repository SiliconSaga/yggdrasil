#!/usr/bin/env bash
# ws-lint.sh — Run the linter for a component
# ws:use-when running the component's linter via its adapter
#
# Usage:
#   ws-lint.sh <component> [args...]
#
# Resolves the lint command from the active realm's adapter
# (`commands.lint`) and runs it in the component directory. Extra args
# pass through to the linter (e.g. --fix).
#
# Structure mirrors ws-test.sh's runner detection so auto-detection
# (ruff / eslint / golangci-lint, etc.) can be added later as additional
# branches before the "not configured" error. Today only the adapter-
# provided command is supported — minimal on purpose.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Auto-source .env so tokens/config are available to linters that need them.
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

lint_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws lint <component> [args...]"
        echo ""
        echo "Run a component's linter. The command comes from the active"
        echo "realm adapter's 'commands.lint' (run 'ws actions <comp>' to see"
        echo "what's configured). Extra args pass through to the linter:"
        echo "  ws lint knarr"
        echo "  ws lint knarr --fix"
        echo ""
        echo "Shell linting (shellcheck — optional, skipped if not installed):"
        echo "  ws lint                  shellcheck the ws CLI (scripts/)"
        echo "  ws lint --shell <path>   shellcheck given files/dirs"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    lint_help 1
    exit 0
fi

# No component → lint the workspace's own shell scripts (the ws CLI itself).
# `ws lint --shell [paths...]` → shellcheck arbitrary shell paths (realm/component
# tooling). Both delegate to the optional shellcheck helper (a no-op + nag if the
# tool isn't installed), keeping shell lint orthogonal to the adapter path below.
if [[ $# -eq 0 ]]; then
    exec bash "$SCRIPT_DIR/ws-shellcheck.sh"
fi
if [[ "$1" == "--shell" ]]; then
    shift
    exec bash "$SCRIPT_DIR/ws-shellcheck.sh" "$@"
fi

comp="$1"
shift
ws_resolve_target "$comp"
cd "$COMPONENT_DIR"

# --- Detect lint command ---
# Precedence: realm adapter command first. Only the adapter path is
# implemented today; the runner/dispatch shape leaves room for
# auto-detection (e.g. ruff/eslint/golangci-lint) to slot in as extra
# branches before the "not configured" error below.
runner=""
lint_cmd=""

# 1. Realm adapter `commands.lint`
active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort the script before the
        # "No lint command configured" guidance runs. `// ""` already maps a
        # missing key to empty, so no separate "null" check is needed.
        lint_cmd=$(yq -r '.commands.lint // ""' "$adapter_file" 2>/dev/null) || lint_cmd=""
        if [[ -n "$lint_cmd" ]]; then
            runner="adapter"
        fi
    fi
fi

# 2. (future) auto-detect ruff / eslint / golangci-lint here.

if [[ -z "$runner" ]]; then
    echo "ERROR: No lint command configured for '$comp'." >&2
    echo "  Add 'commands.lint' to the realm adapter:" >&2
    echo "    realms/<realm>/adapters/$comp.yaml" >&2
    echo "  Example:" >&2
    echo "    commands:" >&2
    echo "      lint: \"python3 -m ruff check src/ tests/\"" >&2
    echo "  Run 'ws actions $comp' to see what's configured." >&2
    exit 1
fi

# --- Parse adapter command into an array for safe exec ---
# Contract mirrors ws-test.sh: whitespace-separated tokens only. Args
# with embedded whitespace/quotes are not supported — point the adapter
# at a wrapper script if you need complex quoting.
lint_argv=()
# shellcheck disable=SC2206
read -r -a lint_argv <<< "$lint_cmd"

# --- Dispatch ---
case "$runner" in
    adapter)
        "${lint_argv[@]}" "$@"
        ;;
esac
