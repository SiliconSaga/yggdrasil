#!/usr/bin/env bash
# ws-fmt.sh — Format a component's sources
# ws:use-when applying the component's formatter via its adapter
#
# Usage:
#   ws-fmt.sh <component> [args...]
#
# Resolves the formatter from the active realm's adapter (`commands.fmt`)
# and runs it in the component directory. Extra args pass through.
#
# `fmt` writes, `lint` checks — the split every ecosystem already makes
# (`cargo fmt` vs `cargo fmt --check`, `gofmt -w` vs `gofmt -l`,
# `black .` vs `black --check .`). So a formatting *violation* is a lint
# failure and belongs in `commands.lint`; this verb is how you fix it.
# Declaring a --check form here would give you a verb named fmt that
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

fmt_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws fmt <component> [args...]"
        echo ""
        echo "Format a component's sources — this rewrites files. The command"
        echo "comes from the active realm adapter's 'commands.fmt' (run"
        echo "'ws actions <comp>' to see what's configured). Extra args pass"
        echo "through to the formatter:"
        echo "  ws fmt kanidm"
        echo "  ws fmt kanidm --all"
        echo ""
        echo "To *check* formatting without rewriting, put the check form"
        echo "(e.g. 'cargo fmt --check') in the adapter's 'commands.lint' —"
        echo "a formatting violation is a lint failure."
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    fmt_help 1
    exit 0
fi

if [[ $# -eq 0 ]]; then
    fmt_help 2
    exit 1
fi

comp="$1"
shift
ws_resolve_target "$comp"
cd "$COMPONENT_DIR"

# --- Detect format command ---
# Precedence: realm adapter command only (see header note).
runner=""
fmt_cmd=""

# 1. Realm adapter `commands.fmt`
active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        ws_require_active_realm_trust "$active_realm" || exit 1
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort the script before the
        # "No fmt command configured" guidance runs. `// ""` already maps
        # a missing key to empty, so no separate "null" check is needed.
        fmt_cmd=$(yq -r '.commands.fmt // ""' "$adapter_file" 2>/dev/null) || fmt_cmd=""
        if [[ -n "$fmt_cmd" ]]; then
            runner="adapter"
        fi
    fi
fi

if [[ -z "$runner" ]]; then
    echo "ERROR: No fmt command configured for '$comp'." >&2
    echo "  Add 'commands.fmt' to the realm adapter:" >&2
    echo "    realms/<realm>/adapters/$comp.yaml" >&2
    echo "  Example:" >&2
    echo "    commands:" >&2
    echo "      fmt: \"cargo fmt\"" >&2
    echo "  Run 'ws actions $comp' to see what's configured." >&2
    exit 1
fi

# --- Parse adapter command into an array for safe exec ---
# Contract mirrors ws-test.sh: whitespace-separated tokens only. Args
# with embedded whitespace/quotes are not supported — point the adapter
# at a wrapper script if you need complex quoting.
fmt_argv=()
# shellcheck disable=SC2206
read -r -a fmt_argv <<< "$fmt_cmd"

# --- Dispatch ---
case "$runner" in
    adapter)
        "${fmt_argv[@]}" "$@"
        ;;
esac
