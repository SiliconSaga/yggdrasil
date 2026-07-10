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

require_public_session_key() {
    local key="$1"
    case "$key" in
        GDD_STANCE|GDD_ROLE|GDD_MENTORING) return 0 ;;
        GDD_K8S_*)
            echo "ERROR: '$key' is managed by the Kubernetes guard; use 'ws k8s scope' instead." >&2
            return 1
            ;;
        GDD_CO_AUTHOR)
            echo "ERROR: '$key' is managed by commit attribution; use 'ws whoami' instead." >&2
            return 1
            ;;
        *)
            echo "ERROR: '$key' is not a public session setting." >&2
            echo "  Allowed keys: GDD_STANCE, GDD_ROLE, GDD_MENTORING." >&2
            return 1
            ;;
    esac
}

sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in
    get) [[ $# -ge 1 ]] || { usage; exit 1; }; printf '%s\n' "$(ws_session_get "$1")" ;;
    set)
        [[ $# -ge 2 ]] || { usage; exit 1; }
        require_public_session_key "$1"
        ws_session_set "$1" "$2" && echo "session: set $1"
        ;;
    show)
        path="$(ws_session_identity_path)"
        if [[ -n "$path" && -f "$path" ]]; then cat "$path"; else echo "(no session file)"; fi
        ;;
    --help|-h|help) usage; exit 0 ;;
    *) usage; exit 1 ;;
esac
