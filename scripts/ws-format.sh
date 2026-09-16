#!/usr/bin/env bash
# ws-format.sh — Format a component's sources
# ws:use-when applying the component's formatter via its adapter
#
# Usage:
#   ws-format.sh <component> [args...]
#
# Resolves the formatter from the active realm's adapter (`commands.format`)
# and runs it in the component directory. Extra args pass through.
#
# `format` writes, `lint` checks — the split every ecosystem already makes
# (`cargo fmt` vs `cargo fmt --check`, `gofmt -w` vs `gofmt -l`,
# `black .` vs `black --check .`). So a formatting *violation* is a lint
# failure and belongs in `commands.lint`; this verb is how you fix it.
# Declaring a --check form here would give you a verb named format that
# refuses to format.
#
# Structure mirrors ws-build.sh: only the adapter-provided command is
# supported — minimal on purpose.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Load .env as literal assignments for formatters that need provider tokens.
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ws_load_env "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

format_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws format <component> [args...]"
        echo ""
        echo "Format a component's sources — this rewrites files. The command"
        echo "comes from the active realm adapter's 'commands.format' (run"
        echo "'ws actions <comp>' to see what's configured). Extra args pass"
        echo "through to the formatter:"
        echo "  ws format kanidm"
        echo "  ws format kanidm --all"
        echo ""
        echo "To *check* formatting without rewriting, put the check form"
        echo "(e.g. 'cargo fmt --check') in the adapter's 'commands.lint' —"
        echo "a formatting violation is a lint failure."
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    format_help 1
    exit 0
fi

if [[ $# -eq 0 ]]; then
    format_help 2
    exit 1
fi

comp="$1"
shift
ws_resolve_target "$comp"
cd "$COMPONENT_DIR"

# --- Detect format command ---
# Precedence: realm adapter command only (see header note).
runner=""
format_cmd=""

# 1. Realm adapter `commands.format`
active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        ws_require_active_realm_trust "$active_realm" || exit 1
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort the script before the
        # "No format command configured" guidance runs. `// ""` already maps
        # a missing key to empty, so no separate "null" check is needed.
        format_cmd=$(yq -r '.commands.format // ""' "$adapter_file" 2>/dev/null) || format_cmd=""
        if [[ -n "$format_cmd" ]]; then
            runner="adapter"
        fi
    fi
fi

if [[ -z "$runner" ]]; then
    echo "ERROR: No format command configured for '$comp'." >&2
    echo "  Add 'commands.format' to the realm adapter:" >&2
    echo "    realms/<realm>/adapters/$comp.yaml" >&2
    echo "  Example:" >&2
    echo "    commands:" >&2
    echo "      format: \"cargo fmt\"" >&2
    echo "  Run 'ws actions $comp' to see what's configured." >&2
    exit 1
fi

# --- Parse adapter command into an array for safe exec ---
# Contract mirrors ws-test.sh: whitespace-separated tokens only. Args
# with embedded whitespace/quotes are not supported — point the adapter
# at a wrapper script if you need complex quoting.
format_argv=()
# shellcheck disable=SC2206
read -r -a format_argv <<< "$format_cmd"
if [[ ${#format_argv[@]} -eq 0 ]]; then
    # A whitespace-only command survives the -n check but parses to no
    # tokens — dispatching would execute the passthrough args instead.
    echo "ERROR: commands.format for '$comp' is whitespace-only — fix the adapter." >&2
    exit 1
fi

# --- Dispatch ---
case "$runner" in
    adapter)
        "${format_argv[@]}" "$@"
        ;;
esac
