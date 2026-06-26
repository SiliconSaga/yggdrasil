#!/usr/bin/env bash
# ws-session-config.sh — get/set/show per-session config keys.
# ws:use-when reading or setting this session's stance/role/mentoring config
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
source "$SCRIPT_DIR/ws-session.sh"

usage() {
    echo "Usage: ws session get <KEY> | set <KEY> <VALUE> | show" >&2
}

sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in
    get) [[ $# -ge 1 ]] || { usage; exit 1; }; ws_session_get "$1" ;;
    set) [[ $# -ge 2 ]] || { usage; exit 1; }; ws_session_set "$1" "$2" && echo "session: set $1" ;;
    show)
        path="$(ws_session_identity_path)"
        if [[ -n "$path" && -f "$path" ]]; then cat "$path"; else echo "(no session file)"; fi
        ;;
    --help|-h|help) usage; exit 0 ;;
    *) usage; exit 1 ;;
esac
