#!/usr/bin/env bash
# ws-audit-permissions.sh — audit permissions.allow patterns for breadth.
#
# Inspects Claude Code's three permission-config scopes and reports any
# entries matching a curated watchlist of patterns that are usually too
# broad to safely auto-approve. Output is YAML; an empty findings list
# means everything looks scoped reasonably. The exit code equals the
# number of findings (so callers can check `[[ $? -gt 0 ]]` without
# re-parsing the YAML).
#
# Scopes checked (in order):
#   1. $HOME/.claude/settings.json       — user-level (cross-project)
#   2. $ROOT_DIR/.claude/settings.json   — workspace-committed
#   3. $ROOT_DIR/.claude/settings.local.json — workspace per-developer
#
# Missing files are silently skipped. Malformed JSON surfaces as a
# warning to stderr, doesn't abort — partial findings are still useful.
#
# Watchlist — see WATCHLIST_RAW below. Each entry is
# `<glob-pattern>|<severity>|<rationale>`. Severity is one of:
#   critical — wildcard-only or privilege-escalating; almost never
#              correct to auto-approve
#   high     — broad enough to enable arbitrary command execution
#              or destructive operations
#   medium   — broad but sometimes legitimate (infra, package
#              install); user should explicitly confirm intent
#
# Designed as a deterministic helper so the gdd-orientation skill can
# call it on every session start without burning model tokens, and so
# CI can fail a regression that adds a watchlisted entry to the
# committed workspace settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# ─── Help ───────────────────────────────────────────────────────────

audit_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws audit-permissions [--names-only]"
        echo ""
        echo "Inspect Claude Code permissions.allow across the three"
        echo "config scopes (user, workspace, workspace-local) for"
        echo "entries matching a watchlist of patterns that are usually"
        echo "too broad to auto-approve safely."
        echo ""
        echo "Output:"
        echo "  YAML list of findings. Empty list = clean."
        echo "  Exit code equals the number of findings."
        echo ""
        echo "Flags:"
        echo "  --names-only   Emit just the matched patterns (one per"
        echo "                 line) for shell pipelines / quick scan."
        echo ""
        echo "Severity tiers:"
        echo "  critical — wildcard-only / privilege-escalating; almost"
        echo "             never correct to auto-approve"
        echo "  high     — broad enough to enable arbitrary execution"
        echo "             or destructive operations"
        echo "  medium   — broad but sometimes legitimate; user should"
        echo "             confirm intent"
        echo ""
        echo "Designed to be called by the gdd-orientation skill at"
        echo "session start to surface accidental broad allows."
    } >&"$stream"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    audit_help 1
    exit 0
fi

names_only=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --names-only) names_only=true; shift ;;
        *) echo "ERROR: unknown flag '$1'" >&2; audit_help 2; exit 2 ;;
    esac
done

# ─── Watchlist ──────────────────────────────────────────────────────
#
# Each line: <glob-pattern>|<severity>|<rationale>
#
# Patterns use bash-glob semantics (compared via `[[ str == glob ]]`).
# The Bash() wrapper is checked against the entry verbatim — both bare
# `Bash(ws exec *)` and verbose `Bash(bash scripts/ws exec *)` variants
# need their own watchlist entries because we deliberately want to
# flag both.
#
# Keep ordered roughly critical → high → medium so output is naturally
# sorted by severity when severity tiers tie on pattern match.

WATCHLIST_RAW=$(cat <<'WATCHLIST'
Bash(\*)|critical|Wildcard-only Bash auto-approves any shell command. Almost certainly a misclick on "Always Allow".
Bash(\* \*)|critical|Effectively the same as Bash(*) — any command with at least one arg.
Bash(sudo *)|critical|Privilege escalation. Allowing this means any sudo invocation auto-approves.
Bash(sudo)|critical|Bare sudo (interactive password prompt) is rarely useful as an allow pattern.
Bash(eval *)|critical|Meta-execution. Allowing eval defeats the entire permission system for anything passed through.
Bash(exec *)|critical|Replaces the shell with an arbitrary command. Same threat as eval.
Bash(ws exec *)|high|ws exec runs arbitrary commands in a component dir. The wildcard captures the command name.
Bash(ws exec * *)|high|ws exec with one arg after the component (same threat as Bash(ws exec *) but matches different arg counts).
Bash(ws exec * * *)|high|ws exec with multiple args (same threat).
Bash(bash scripts/ws exec *)|high|Verbose form of ws exec — same arbitrary-command threat.
Bash(bash scripts/ws exec * *)|high|Verbose form, multi-arg.
Bash(bash *)|high|Allows running any bash script or inline bash invocation. Effectively wildcards out the hook.
Bash(sh *)|high|Same as bash * but for sh.
Bash(rm -rf *)|high|Recursive force-delete with any target. Wildcards a destructive verb.
Bash(rm *)|high|rm with arbitrary args (with -rf or without).
Bash(curl *)|medium|Unscoped network egress. Sometimes legitimate (fetching public APIs); consider scoping to a domain.
Bash(wget *)|medium|Same as curl — unscoped fetch.
Bash(kubectl *)|medium|Cluster mutation. Broad but sometimes legitimate during platform work; consider scoping to read-only verbs (get, describe, logs).
Bash(docker *)|medium|Image / container mutation. Often legitimate during local dev; consider scoping if it bothers you.
Bash(npm install *)|medium|Package install can run arbitrary postinstall scripts. Legitimate for dev work, worth knowing about.
Bash(pip install *)|medium|Same as npm install — postinstall hooks run arbitrary code.
WATCHLIST
)

# ─── Findings collection ────────────────────────────────────────────

declare -a FINDINGS=()

# Scan one settings file. Reads .permissions.allow entries (or skips
# silently if absent), compares each against every watchlist pattern,
# records matches in FINDINGS.
#
# Args: $1 = scope label (user / project / project-local), $2 = file path
scan_file() {
    local scope="$1"
    local file="$2"
    [[ -f "$file" ]] || return 0

    # Validate JSON parses; jq returns non-zero on malformed input.
    if ! jq empty "$file" 2>/dev/null; then
        echo "WARNING: $file is not valid JSON, skipping" >&2
        return 0
    fi

    local allow_entries
    allow_entries=$(jq -r '.permissions.allow[]? // empty' "$file" 2>/dev/null || true)
    [[ -z "$allow_entries" ]] && return 0

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        # CRLF tolerance — same reasoning as the hook script.
        entry="${entry%$'\r'}"

        # Test entry against every watchlist pattern.
        #
        # Pattern is UNQUOTED on the RHS — bash treats it as a glob
        # in this position. That's deliberate: a watchlist entry like
        # `Bash(ws exec *)` should match any allow rule of the same
        # shape (`Bash(ws exec npm test)`, `Bash(ws exec foo bar)`,
        # etc.), not just the literal verbatim string. The two
        # wildcard-only watchlist entries (`Bash(\*)` and
        # `Bash(\* \*)`) escape their `*` so they match ONLY the
        # literal verbatim — otherwise their glob would match every
        # Bash() entry on disk and flood the findings list.
        while IFS='|' read -r pattern severity rationale; do
            [[ -z "$pattern" ]] && continue
            # shellcheck disable=SC2053
            if [[ "$entry" == $pattern ]]; then
                FINDINGS+=("$scope|$file|$entry|$severity|$rationale")
                # Don't break — an entry could match multiple watchlist
                # rules and the user might want to see each. Cheap.
            fi
        done <<< "$WATCHLIST_RAW"
    done <<< "$allow_entries"
}

scan_file "user" "$HOME/.claude/settings.json"
scan_file "project" "$ROOT_DIR/.claude/settings.json"
scan_file "project-local" "$ROOT_DIR/.claude/settings.local.json"

# ─── Output ─────────────────────────────────────────────────────────

if $names_only; then
    # One pattern per line, for shell pipelines / quick scan.
    for f in "${FINDINGS[@]:-}"; do
        [[ -z "$f" ]] && continue
        IFS='|' read -r _scope _file pattern _severity _rationale <<< "$f"
        echo "$pattern"
    done
else
    # YAML, sorted by severity (alphabetical works because critical <
    # high < medium under simple sort — convenient).
    if [[ ${#FINDINGS[@]} -eq 0 ]]; then
        echo "[]"
    else
        for f in "${FINDINGS[@]}"; do
            IFS='|' read -r scope file pattern severity rationale <<< "$f"
            # Quote string values defensively — patterns may contain
            # characters that YAML would otherwise mis-parse.
            echo "- scope: $scope"
            echo "  file: $file"
            echo "  pattern: '$pattern'"
            echo "  severity: $severity"
            echo "  rationale: \"$rationale\""
        done
    fi
fi

# Exit code = findings count, capped at 255 (shell exit code limit).
# Callers can check `[[ $? -gt 0 ]]` for "there were findings."
exit_code="${#FINDINGS[@]}"
[[ "$exit_code" -gt 255 ]] && exit_code=255
exit "$exit_code"
