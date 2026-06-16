#!/usr/bin/env bash
# ws-session.sh — per-session identity helpers (sourced, never executed).
#
# Resolves the current agent session's id and the path to its identity
# file under .tmp/gdd-agent-sessions/<id>.env. See
# docs/plans/2026-06-15-multi-agent-attribution-design.md.

: "${ROOT_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"

# Resolve the current session id, first match wins:
#   GDD_SESSION_ID         explicit override (tests; harness w/o native id)
#   CLAUDE_CODE_SESSION_ID  Claude Code (present in every Bash call)
#   CODEX_THREAD_ID         Codex (observed; best-effort)
# Echoes the id, or empty string if none resolves.
ws_resolve_session_id() {
    printf '%s' "${GDD_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-}}}"
}

# Echo the identity-file path for the current session, or empty if no
# session id resolves. The id is filename-sanitized defensively.
ws_session_identity_path() {
    local sid; sid="$(ws_resolve_session_id)"
    [[ -z "$sid" ]] && return 0
    local safe="${sid//[^A-Za-z0-9._-]/_}"
    printf '%s' "${ROOT_DIR}/.tmp/gdd-agent-sessions/${safe}.env"
}

# Write the current session's identity file with GDD_CO_AUTHOR=<$1>.
# Returns 1 (with guidance on stderr) if no session id resolves.
ws_write_session_identity() {
    local identity="$1" path; path="$(ws_session_identity_path)"
    if [[ -z "$path" ]]; then
        echo "ERROR: No session id (GDD_SESSION_ID / CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID) — cannot write a session identity file." >&2
        echo "  In a non-agent shell, set GDD_CO_AUTHOR inline at commit time instead." >&2
        return 1
    fi
    mkdir -p "$(dirname "$path")"
    printf 'GDD_CO_AUTHOR="%s"\n' "$identity" > "$path"
}

# Resolve the Co-Authored-By identity for the current session.
# $1 = inline override (the pre-.env-source GDD_CO_AUTHOR), may be empty.
# Echoes the identity and returns 0; on failure prints guidance to stderr
# and returns 1. See the design doc's resolution chain.
ws_resolve_co_author() {
    local inline="${1:-}"
    if [[ -n "$inline" ]]; then printf '%s' "$inline"; return 0; fi
    local sid; sid="$(ws_resolve_session_id)"
    if [[ -n "$sid" ]]; then
        local path val; path="$(ws_session_identity_path)"
        if [[ -f "$path" ]]; then
            val="$( source "$path" >/dev/null 2>&1; printf '%s' "${GDD_CO_AUTHOR:-}" )"
            if [[ -n "$val" ]]; then printf '%s' "$val"; return 0; fi
        fi
        echo "ERROR: No commit identity for this session (it may have been cleared by 'ws clean', or orientation hasn't set it)." >&2
        echo "  Re-establish: 'ws orient', or 'ws whoami --set \"Name <email>\"'." >&2
        return 1
    fi
    # No agent session (human/script): discouraged .env GDD_CO_AUTHOR fallback.
    if [[ -n "${GDD_CO_AUTHOR:-}" ]]; then printf '%s' "$GDD_CO_AUTHOR"; return 0; fi
    echo "ERROR: No commit identity. In an agent session run 'ws orient' or 'ws whoami --set \"Name <email>\"'." >&2
    echo "  One-off manual commit: GDD_CO_AUTHOR=\"Name <email>\" ws commit <comp> <bodyfile>" >&2
    echo "  Repeated manual commits may set GDD_CO_AUTHOR in .env (discouraged — agent sessions ignore it)." >&2
    return 1
}
