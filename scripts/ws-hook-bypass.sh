#!/usr/bin/env bash
# ws-hook-bypass.sh — write a session-scoped bypass marker for a
# Tier 2 [redirect-commands], Tier 2b [scoped-redirect-commands],
# or Tier 3 [adapter-redirect-commands] slug. The marker lets the
# matching command run for the rest of the current agent session.
#
# ws:use-when requesting a session-scoped bypass of a Tier 2, Tier 2b, or Tier 3 redirect-deny
#
# Usage:
#   ws hook-bypass <slug> [--reason "<text>"]
#
# <slug> must appear as column 1 of a row in .claude/hooks/hook-rules
# under [redirect-commands] (Tier 2), [adapter-redirect-commands]
# (Tier 3), or [scoped-redirect-commands] (Tier 2b), or be a built-in
# tool-deny slug (currently: powershell —
# unblocks the hook's whole-tool PowerShell deny for the session).
# The script writes .tmp/hook-bypass/<slug>.bypass with frontmatter
# the PreToolUse hook parses (session_id, slug, created_at, reason).
#
# The subcommand pattern `ws hook-bypass [a-z]*` is on the committed
# [ask-commands] baseline, so every invocation force-prompts the human —
# that's the security gate. The slug validation here guards against
# typos and accidental marker creation for unknown slugs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT can be set by callers (tests) or falls back to one
# level up from this script's directory (scripts/) — the yggdrasil root.
: "${PROJECT_ROOT:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
ROOT_DIR="$PROJECT_ROOT"
# shellcheck source=ws-session.sh
source "$SCRIPT_DIR/ws-session.sh"

HOOK_RULES="$PROJECT_ROOT/.claude/hooks/hook-rules"

usage() {
    cat <<'HELP'
Usage: ws hook-bypass <slug> [--reason "<text>"]

  <slug>           Bypass slug — must match a row in [redirect-commands]
                   (Tier 2), [scoped-redirect-commands] (Tier 2b), or
                   [adapter-redirect-commands] (Tier 3) in
                   .claude/hooks/hook-rules, or a built-in tool-deny slug
                   (powershell). Run with an unknown slug to see the list
                   of known slugs.
  --reason "<txt>" Optional. Captured in the marker file and echoed into
                   each BYPASS-ALLOW audit-log entry for retro grep.

Writes .tmp/hook-bypass/<slug>.bypass with the current GDD agent session id
(GDD_SESSION_ID, CLAUDE_CODE_SESSION_ID, or CODEX_THREAD_ID).
The PreToolUse hook honors this marker for matching commands in this
session only. ws clean (or any .tmp/ purge) sweeps stale markers.

Examples (keep --reason free of shell composition tokens like ; && | —
the hook scans the whole command string and would deny them):
  ws hook-bypass git-commit --reason "git commit --amend not supported by ws commit yet"
  ws hook-bypass gh-pr-create --reason "cross-fork PR, ws cr lacks --upstream support today"
HELP
}

# --help / -h
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# No args → usage + exit 1
if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
fi

slug="$1"
shift

# Parse optional --reason
reason=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            [[ $# -ge 2 ]] || { echo "ERROR: --reason requires a value" >&2; exit 1; }
            reason="$2"
            shift 2 ;;
        --reason=*)
            reason="${1#--reason=}"
            shift ;;
        *)
            echo "ERROR: Unknown argument '$1'" >&2
            usage >&2
            exit 1 ;;
    esac
done

# Enumerate known slugs from hook-rules. This is a deliberately minimal
# re-implementation of the [redirect-commands] + [scoped-redirect-commands]
# + [adapter-redirect-commands] parses in the hook itself
# (gdd-permission-hook.sh _parse_rules_file) — we only need column 1
# (the slug), not the full slug|pattern|... unpack. Keep the shared bits
# (CRLF strip, section detection, slug regex) in sync if the hook-rules
# format changes.
#
# All three sections share the slug shape and column-1 position, so a
# single parse with a section-membership check covers all tiers. Tier 2b
# scoped-redirect and Tier 3 adapter-redirect denies both instruct users
# to bypass via `ws hook-bypass`, so the script must accept those slugs
# too — otherwise the deny message tells users to do something the script
# refuses to do.
# Built-in slugs not derived from hook-rules rows. `powershell` gates
# the hook's whole-tool PowerShell deny (there's no per-command pattern
# row for it — the branch in gdd-permission-hook.sh hardcodes the
# marker path .tmp/hook-bypass/powershell.bypass).
known_slugs=(powershell)
if [[ -f "$HOOK_RULES" ]]; then
    in_section=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        # Trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == "#"* ]] && continue
        if [[ "$line" == "["*"]" ]]; then
            in_section="${line#\[}"
            in_section="${in_section%\]}"
            continue
        fi
        if [[ "$in_section" == "redirect-commands" \
              || "$in_section" == "scoped-redirect-commands" \
              || "$in_section" == "adapter-redirect-commands" ]]; then
            # Column 1 (slug) — substring up to first " | "
            if [[ "$line" == *" | "* ]]; then
                s="${line%% | *}"
                # Trim trailing whitespace
                s="${s%"${s##*[![:space:]]}"}"
                # Only accept valid slug shape (must start with a letter,
                # matching the hook parser; keeps the ask-pattern catchable).
                if [[ "$s" =~ ^[a-z][a-z0-9-]*$ ]]; then
                    known_slugs+=("$s")
                fi
            fi
        fi
    done < "$HOOK_RULES"
fi

# Validate slug
slug_ok=0
for s in ${known_slugs[@]+"${known_slugs[@]}"}; do
    if [[ "$s" == "$slug" ]]; then
        slug_ok=1
        break
    fi
done
if [[ "$slug_ok" != "1" ]]; then
    echo "ERROR: Unknown slug '$slug'." >&2
    if [[ ${#known_slugs[@]} -gt 0 ]]; then
        echo "Known slugs (from $HOOK_RULES):" >&2
        for s in ${known_slugs[@]+"${known_slugs[@]}"}; do
            echo "  - $s" >&2
        done
    else
        echo "No [redirect-commands], [scoped-redirect-commands], or [adapter-redirect-commands] entries found in $HOOK_RULES." >&2
    fi
    exit 1
fi

# Resolve the session id through the same canonical helper used by session
# config, attribution, and the guarded Kubernetes wrapper. The value must equal
# the hook payload's `.session_id` for the bypass marker to match.
session_id="$(ws_resolve_session_id)"
if [[ -z "$session_id" ]]; then
    echo "ERROR: no GDD agent session id in the environment." >&2
    echo "  Expected \$GDD_SESSION_ID, \$CLAUDE_CODE_SESSION_ID, or \$CODEX_THREAD_ID." >&2
    echo "  This command only makes sense inside an active agent session;" >&2
    echo "  the marker keys off the session id, so without it the hook can never" >&2
    echo "  match the marker against a session." >&2
    exit 1
fi

# Write the marker
marker_dir="$PROJECT_ROOT/.tmp/hook-bypass"
marker_path="$marker_dir/$slug.bypass"
mkdir -p "$marker_dir"

# ISO-8601 UTC, no microseconds — readable and stable across hosts.
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# printf '%s' per field (not a heredoc) so each value is written
# literally — a reason containing a '$' or backtick is never re-expanded.
{
    printf 'session_id: %s\n' "$session_id"
    printf 'slug: %s\n'       "$slug"
    printf 'created_at: %s\n' "$created_at"
    printf 'reason: %s\n'     "$reason"
} > "$marker_path"

echo "bypass marker written: $marker_path (session ${session_id:0:8}...)"
