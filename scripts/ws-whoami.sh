#!/usr/bin/env bash
# ws-whoami.sh — show or set the current session's commit identity.
# ws:use-when checking or setting who 'ws commit' will attribute as
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
_INLINE_CO_AUTHOR="${GDD_CO_AUTHOR:-}"
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"
source "$SCRIPT_DIR/ws-session.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: ws whoami [--set "Name <email>"]

  (no args)            Print the identity this session commits as, and how
                       it resolved (inline / session file / none).
  --set "Name <email>" Write this session's identity file (the re-establish
                       path; what 'ws orient' does automatically).
HELP
    exit 0
fi

if [[ "${1:-}" == "--set" ]]; then
    identity="${2:-}"
    [[ -n "$identity" ]] || { echo "ERROR: --set needs an identity, e.g. --set \"Codex GPT-5 <noreply@openai.com>\"" >&2; exit 1; }
    # Require an <email> in the identity (kept in sync with ws-commit.sh's
    # email_re — the same shape both validates against; no shared lib exists).
    email_re='<[^[:space:]@<>]+@[^[:space:]@<>]+>'
    [[ "$identity" =~ $email_re ]] || { echo "ERROR: identity must include an email in angle brackets, e.g. \"Codex GPT-5 <noreply@openai.com>\"" >&2; exit 1; }
    ws_write_session_identity "$identity" || exit 1
    echo "Session identity set: $identity"
    exit 0
fi

if [[ $# -gt 0 ]]; then
    echo "ERROR: unknown argument '$1'. Run 'ws whoami --help'." >&2; exit 1
fi

if id="$(ws_resolve_co_author "$_INLINE_CO_AUTHOR")"; then
    if [[ -n "$_INLINE_CO_AUTHOR" ]]; then src="inline GDD_CO_AUTHOR"
    elif [[ -n "$(ws_resolve_session_id)" ]]; then src="session file"
    else src="discouraged .env"; fi
    echo "$id"
    echo "  (via $src)"
else
    exit 1
fi
