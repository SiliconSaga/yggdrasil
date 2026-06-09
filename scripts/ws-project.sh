#!/usr/bin/env bash
# ws project — ADSE-aware operations on a project hoard.
# See docs/plans/2026-06-09-adse-design.md
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"
: "${ADSE_DIR:="$ROOT_DIR/components/adse"}"

ws_project_help() {
    cat <<'EOF'
Usage: ws project <name> <subcommand> [options]

  <name>  Name of the project hoard under hoards/ (must contain .project.yaml)

Subcommands:
  status              Report section coverage: present, missing, mandatory
  build [--pdf]       Assemble sections; fail if mandatory sections missing.
                      --pdf: pipe assembled markdown through pandoc to PDF.
  help                Show this help.
EOF
}

_wp_resolve_hoard() {
    local name="$1"
    local hoard_dir="$HOARDS_DIR/$name"
    if [[ ! -d "$hoard_dir" ]]; then
        echo "ERROR: hoard '$name' not found under hoards/" >&2
        return 1
    fi
    if [[ ! -f "$hoard_dir/.project.yaml" ]]; then
        echo "ERROR: '$name' is not a project hoard (.project.yaml not found)" >&2
        return 1
    fi
    echo "$hoard_dir"
}

ws_project_status() {
    local name="$1"
    local hoard_dir
    hoard_dir="$(_wp_resolve_hoard "$name")" || return 1
    python3 "$ADSE_DIR/scripts/status.py" "$hoard_dir"
}

ws_project_build() {
    local name="$1"; shift
    local pdf=false output=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pdf) pdf=true ;;
            --output) output="$2"; shift ;;
            *) echo "ERROR: unknown flag '$1'" >&2; return 1 ;;
        esac
        shift
    done
    local hoard_dir
    hoard_dir="$(_wp_resolve_hoard "$name")" || return 1
    local build_dir="$hoard_dir/.build"
    mkdir -p "$build_dir"
    local assembled="$build_dir/assembled.md"
    python3 "$ADSE_DIR/scripts/assemble.py" "$hoard_dir" --output "$assembled" || return 1
    echo "assembled → $assembled"
    if $pdf; then
        bash "$ADSE_DIR/processors/pdf/export.sh" --input "$assembled" \
            --output "${output:-$build_dir/assembled.pdf}"
    fi
}

# Dispatch: ws project help | ws project <name> <subcommand> [options]
FIRST="${1:-help}"

case "$FIRST" in
    help|--help|-h)
        ws_project_help
        ;;
    *)
        NAME="$FIRST"
        SUBCOMMAND="${2:-help}"
        shift 2 2>/dev/null || shift 1 2>/dev/null || true
        case "$SUBCOMMAND" in
            help|--help|-h)
                ws_project_help
                ;;
            status)
                ws_project_status "$NAME"
                ;;
            build)
                ws_project_build "$NAME" "$@"
                ;;
            *)
                echo "ERROR: Unknown subcommand '$SUBCOMMAND'. Run 'ws project help'." >&2
                exit 1
                ;;
        esac
        ;;
esac
