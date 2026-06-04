#!/usr/bin/env bash
# ws thalami — publish personal published:true arcs (+ tagged Vault notes)
# into a team-thalami hoard. See docs/gdd/team-thalami-quickstart.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"

# shared helpers (ws_resolve_ecosystem, ws_detect_thalami_hoard,
# ws_resolve_thalamus_path, etc.)
source "$SCRIPT_DIR/ws-realm.sh"
source "$SCRIPT_DIR/ws-hoard.sh"

ws_thalami_help() {
    cat <<'EOF'
Usage: ws thalami <subcommand>

Subcommands:
  publish [--to <hoard>] [--vault <path>] [--user <name>] [--dry-run] [--yes]
        Mirror this machine's published:true arcs (and their
        #team/<arc-id>-tagged Vault notes) into a team-thalami hoard.
        Write-only — review then commit the team hoard yourself.

  help  Show this help.
EOF
}

# Implemented in later steps.
ws_thalami_publish() {
    echo "ws thalami publish: not yet implemented" >&2
    return 1
}

SUBCMD="${1:-}"
shift 2>/dev/null || true
case "$SUBCMD" in
    ""|help|--help|-h) ws_thalami_help ;;
    publish)           ws_thalami_publish "$@" ;;
    *) echo "ERROR: Unknown thalami subcommand '$SUBCMD'. Run 'ws thalami help'." >&2; exit 1 ;;
esac
