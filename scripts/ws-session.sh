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

# Echo the identity-file path for an arbitrary session id (filename-
# sanitized defensively), or empty if the id is empty. Used both for the
# current session and for an explicit --co-author-file <name> lookup.
ws_session_identity_path_for() {
    local id="${1:-}"
    [[ -z "$id" ]] && return 0
    local safe="${id//[^A-Za-z0-9._-]/_}"
    printf '%s' "${ROOT_DIR}/.tmp/gdd-agent-sessions/${safe}.env"
}

# Echo the identity-file path for the current session, or empty if no
# session id resolves.
ws_session_identity_path() {
    ws_session_identity_path_for "$(ws_resolve_session_id)"
}

# Echo the GDD_CO_AUTHOR value stored in an identity file, or empty if the
# path is empty / missing / sets nothing. Sourced in a subshell so the file
# can never leak into or corrupt the caller's environment.
ws_read_identity_file() {
    local path="${1:-}"
    [[ -n "$path" && -f "$path" ]] || return 0
    ( source "$path" >/dev/null 2>&1; printf '%s' "${GDD_CO_AUTHOR:-}" )
}

# Write the current session's identity file with GDD_CO_AUTHOR=<$1>.
# Returns 1 (with guidance on stderr) if no session id resolves.
ws_write_session_identity() {
    local identity="$1" path; path="$(ws_session_identity_path)"
    if [[ -z "$path" ]]; then
        echo "ERROR: No session id (GDD_SESSION_ID / CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID) — cannot write a session identity file." >&2
        echo "  For a manual commit, use 'ws commit --human' (no trailer); to simulate an agent session in a script, export GDD_SESSION_ID first." >&2
        return 1
    fi
    mkdir -p "$(dirname "$path")"
    printf 'GDD_CO_AUTHOR="%s"\n' "$identity" > "$path"
}

# Resolve the Co-Authored-By identity. First match wins:
#   $1  --co-author-file <name>  → .tmp/gdd-agent-sessions/<name>.env
#                                  (the sub-agent escape hatch)
#       the current session's identity file (an agent session)
#       none → error (the caller, a human, must pass --human to opt out of a
#              trailer; an agent must establish its identity first)
# Echoes the identity and returns 0. Returns 1 with guidance on stderr for
# any failure: a named --co-author-file that's missing, an AGENT session with
# no identity file (cleared identity — must surface, never silently mis-
# attribute), or no session at all. There is deliberately NO silent no-trailer
# fallback: an agent always has a session id, so it can never quietly skip
# attribution, and a human with no session must mark themselves with --human
# (handled by the caller) rather than be guessed at.
ws_resolve_co_author() {
    local coauthor_name="${1:-}"
    # Explicit --co-author-file <name> (sub-agent escape hatch).
    if [[ -n "$coauthor_name" ]]; then
        local path val
        path="$(ws_session_identity_path_for "$coauthor_name")"
        val="$(ws_read_identity_file "$path")"
        if [[ -n "$val" ]]; then printf '%s' "$val"; return 0; fi
        echo "ERROR: --co-author-file named '$coauthor_name' but '$path' is missing or sets no GDD_CO_AUTHOR." >&2
        echo "  A sub-agent must write that file before committing (one line: GDD_CO_AUTHOR=\"Name <email>\")." >&2
        return 1
    fi
    # Agent session: the per-session identity file. Missing → hard error
    # (identity was cleared; re-establish rather than silently mis-attribute).
    local sid; sid="$(ws_resolve_session_id)"
    if [[ -n "$sid" ]]; then
        local path val
        path="$(ws_session_identity_path)"
        val="$(ws_read_identity_file "$path")"
        if [[ -n "$val" ]]; then printf '%s' "$val"; return 0; fi
        echo "ERROR: No commit identity for this session (it may have been cleared by 'ws clean', or orientation hasn't set it)." >&2
        echo "  Re-establish: 'ws orient', or 'ws whoami --set \"Name\" <email>'." >&2
        return 1
    fi
    # No session id and no --co-author-file: don't guess. A human committing
    # manually must say so with --human; an agent must establish its identity.
    echo "ERROR: No commit identity resolved." >&2
    echo "  Agent session: run 'ws orient' or 'ws whoami --set \"Name\" <email>'." >&2
    echo "  Human committing manually: pass --human (commits with no Co-Authored-By trailer)." >&2
    return 1
}
