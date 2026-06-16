#!/usr/bin/env bash
# ws-whoami.sh — show or set the current session's commit identity.
# ws:use-when checking or setting who 'ws commit' will attribute as
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
source "$SCRIPT_DIR/ws-session.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: ws whoami [--set "Name <email>" | --set "Name" <email>]

  (no args)              Print the identity this session commits as (from the
                         session file), or note that there is no agent session.
  --set "Name <email>"   Write this session's identity file. For a human in
                         their own terminal.
  --set "Name" <email>   Same, but with the email as a separate arg (no angle
                         brackets on the command line) — this form passes the
                         Bash permission hook, so it's the one an AGENT uses
                         at 'ws orient'. Example:
                           ws whoami --set "Claude Opus 4.8" noreply@anthropic.com
HELP
    exit 0
fi

if [[ "${1:-}" == "--set" ]]; then
    name="${2:-}"
    email="${3:-}"
    [[ -n "$name" ]] || { echo "ERROR: --set needs an identity, e.g. --set \"Claude Opus 4.8\" noreply@anthropic.com" >&2; exit 1; }
    # Two forms: a single "Name <email>" arg (brackets; for a human terminal),
    # or "Name" + a bare email arg. The split form keeps angle brackets off the
    # command line so it survives the Bash permission hook's redirect check —
    # that's the form an agent uses. ws assembles the <email> wrapper here.
    if [[ -n "$email" ]]; then
        identity="$name <$email>"
    else
        identity="$name"
    fi
    # Require an <email> in the assembled identity (kept in sync with
    # ws-commit.sh's email_re — same shape both validate against; no shared lib).
    email_re='<[^[:space:]@<>]+@[^[:space:]@<>]+>'
    [[ "$identity" =~ $email_re ]] || { echo "ERROR: identity must include an email, e.g. --set \"Codex GPT-5\" noreply@openai.com" >&2; exit 1; }
    ws_write_session_identity "$identity" || exit 1
    echo "Session identity set: $identity"
    exit 0
fi

if [[ $# -gt 0 ]]; then
    echo "ERROR: unknown argument '$1'. Run 'ws whoami --help'." >&2; exit 1
fi

if [[ -z "$(ws_resolve_session_id)" ]]; then
    # No session id — a human/script. 'ws commit' here needs an explicit marker.
    echo "No agent session here — 'ws commit' needs --human (a human committing)"
    echo "or an established session identity (an agent: ws whoami --set \"Name\" <email>)."
    exit 0
fi
if id="$(ws_resolve_co_author "")"; then
    echo "$id"
    echo "  (via session file)"
else
    # ws_resolve_co_author printed guidance (agent session, identity cleared).
    exit 1
fi
