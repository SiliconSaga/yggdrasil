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

# Read a single KEY from the session file (or a given path). Data-only —
# never sourced. Prints the value of the first matching KEY= line; empty
# if absent. Usage: ws_session_get <KEY> [path]
ws_session_get() {
    local key="${1:-}" path="${2:-}"
    [[ -n "$path" ]] || path="$(ws_session_identity_path)"
    [[ -n "$key" && -n "$path" && -f "$path" ]] || return 0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            "$key="*) printf '%s' "${line#"$key="}"; return 0 ;;
        esac
    done < "$path"
}

# Atomic read-modify-write of one KEY in the session file, preserving all
# other keys. Writes to a temp file in the same dir then mv (atomic rename)
# so a concurrent reader never sees a half-written file. Usage:
# ws_session_set <KEY> <VALUE>
ws_session_set() {
    local key="${1:-}" value="${2:-}" path; path="$(ws_session_identity_path)"
    if [[ -z "$path" ]]; then
        echo "ERROR: No session id (GDD_SESSION_ID / CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID) — cannot write session config." >&2
        echo "  Running in a plain terminal? Ask your agent to run this command instead — scope changes require the agent session." >&2
        return 1
    fi
    [[ -n "$key" ]] || { echo "ERROR: ws_session_set requires a KEY." >&2; return 1; }
    # The file is env-style KEY=VALUE lines; a key with '=', a newline, or other
    # non-identifier characters would corrupt or inject sibling entries.
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        echo "ERROR: session key must be an env-style identifier (letters, digits, underscore; not leading with a digit)." >&2
        return 1
    }
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        echo "ERROR: session value cannot contain newlines." >&2
        return 1
    fi
    mkdir -p "$(dirname "$path")"
    # Serialize the read-modify-write so two concurrent writers (e.g. a
    # foreground and a backgrounded call sharing this session id) can't both
    # read the old file and have the later mv drop the earlier writer's key.
    # An mkdir lock is atomic across processes; the wait is bounded so a crashed
    # writer's stale lock degrades to a (still atomic) unlocked write instead of
    # deadlocking forever. We track whether THIS call acquired the lock and only
    # release it then — timing out must never rmdir another live writer's lock.
    local lockdir="${path}.lock" _try=0 _have_lock=0 _max="${WS_SESSION_LOCK_TRIES:-100}" _max_valid=0
    if [[ "$_max" =~ ^[0-9]+$ && ${#_max} -le 5 ]]; then
        _max=$((10#$_max))
        (( _max <= 10000 )) && _max_valid=1
    fi
    if [[ "$_max_valid" -ne 1 ]]; then
        echo "WARNING: WS_SESSION_LOCK_TRIES must be a decimal integer from 0 to 10000; using 100." >&2
        _max=100
    fi
    while (( _try < _max )); do
        if mkdir "$lockdir" 2>/dev/null; then _have_lock=1; break; fi
        _try=$((_try + 1)); sleep 0.05
    done
    local tmp; tmp="$(mktemp "$(dirname "$path")/.session.XXXXXX")"
    local found=0 line
    if [[ -f "$path" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            case "$line" in
                "$key="*) printf '%s=%s\n' "$key" "$value" >> "$tmp"; found=1 ;;
                *)        printf '%s\n' "$line" >> "$tmp" ;;
            esac
        done < "$path"
    fi
    [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$path"
    [[ "$_have_lock" -eq 1 ]] && { rmdir "$lockdir" 2>/dev/null || true; }
}

# Echo the GDD_CO_AUTHOR value stored in an identity file, or empty if the
# path is empty / missing / sets nothing. Identity files are data, not shell:
# delegates to ws_session_get which parses the first GDD_CO_AUTHOR= line
# directly so shell syntax in an identity is preserved literally and never
# executed.
ws_read_identity_file() {
    local path="${1:-}"
    [[ -n "$path" && -f "$path" ]] || return 0
    ws_session_get "GDD_CO_AUTHOR" "$path"
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
    if [[ "$identity" == *$'\n'* || "$identity" == *$'\r'* ]]; then
        echo "ERROR: session identity cannot contain newlines." >&2
        return 1
    fi
    ws_session_set "GDD_CO_AUTHOR" "$identity"
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
        echo "  A sub-agent must write that file before committing (one line: GDD_CO_AUTHOR=Name <email>)." >&2
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
