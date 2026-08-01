#!/usr/bin/env bash
# ws-audit-permissions.sh — audit permissions.allow patterns for breadth.
# ws:use-when reviewing your Bash allowlist for over-broad patterns
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

# ─── Prerequisites ──────────────────────────────────────────────────
#
# This script parses settings.json files with jq. Without jq, the
# scan loop crashes with a terse "command not found" + exit 127.
# Surface the missing-dep case explicitly so the user gets a clear
# pointer rather than a stack trace.
if ! command -v jq >/dev/null; then
    echo "ERROR: jq is required but not found on PATH." >&2
    echo "  Run 'ws preflight' for per-OS install hints." >&2
    exit 1
fi

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
        echo "  Exit code equals the number of UNACKNOWLEDGED findings."
        echo ""
        echo "Acknowledged allowances:"
        echo "  An [audit-acknowledged] section in .claude/hooks/"
        echo "  hook-rules.local (gitignored, per-machine) lists exact"
        echo "  allow entries this workspace consciously accepts. They"
        echo "  still appear in the YAML (acknowledged: true) but don't"
        echo "  count toward the exit code or --names-only output."
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
# Author ws-related patterns in the bare `Bash(ws …)` form only:
# matching happens against the NORMALIZED entry (see scan_file), which
# collapses verbose wrapper forms (`Bash(bash scripts/ws exec …)`) to
# the bare form first — a verbose-form watchlist pattern would never
# match anything.
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
Bash(ws:*)|high|Subcommand-less ws catch-all auto-approves EVERY ws subcommand including push/cr/issue/exec. Pin the subcommand (e.g. Bash(ws commit:*)) instead.
Bash(bash *)|high|Allows running any bash script or inline bash invocation. Effectively wildcards out the hook.
Bash(sh *)|high|Same as bash * but for sh.
Bash(rm -rf *)|high|Recursive force-delete with any target. Wildcards a destructive verb.
Bash(rm *)|high|rm with arbitrary args (with -rf or without).
Bash(git -c *)|high|Git configuration injection can define executable aliases and helpers beneath an allowed command.
Bash(git * --ext-diff *)|high|Git executable helper flags can run external programs beneath a read-looking diff command.
Bash(git * ext::*)|high|Git remote helper syntax can execute a command instead of contacting a repository.
Bash(kubectl:*)|high|Blanket kubectl auto-approval covers writes to every context and overrides narrower read-only allowances.
Bash(curl *)|medium|Unscoped network egress. Sometimes legitimate (fetching public APIs); consider scoping to a domain.
Bash(wget *)|medium|Same as curl — unscoped fetch.
Bash(kubectl *)|medium|Cluster mutation. Broad but sometimes legitimate during platform work; consider scoping to read-only verbs (get, describe, logs).
Bash(docker *)|medium|Image / container mutation. Often legitimate during local dev; consider scoping if it bothers you.
Bash(npm install *)|medium|Package install can run arbitrary postinstall scripts. Legitimate for dev work, worth knowing about.
Bash(pip install *)|medium|Same as npm install — postinstall hooks run arbitrary code.
WATCHLIST
)

# ─── Acknowledged per-workspace allowances ──────────────────────────
#
# hook-rules.local (gitignored, per-machine — the same file the hook
# reads for [allow-extras]) may carry an [audit-acknowledged] section
# listing EXACT allow entries this workspace has consciously accepted.
# Matching findings are still emitted in the YAML (acknowledged: true,
# original severity kept) but do not count toward the exit code, so a
# deliberate local allowance stops reading as a problem at every
# session start. Local-only by design: an [audit-acknowledged] section
# in the COMMITTED hook-rules is ignored — project policy must not
# silence the audit for everyone.
ACK_RAW=""
_ack_file="$ROOT_DIR/.claude/hooks/hook-rules.local"
if [[ -f "$_ack_file" ]]; then
    ACK_RAW=$(awk '/^\[audit-acknowledged\]/{f=1;next} /^\[/{f=0} f && NF && $0 !~ /^[[:space:]]*#/' "$_ack_file")
fi

# Exact-match check against the acknowledged list (no globbing — an
# acknowledgment covers one known entry, not a shape).
is_acknowledged() {
    local entry="$1"
    [[ -z "$ACK_RAW" ]] && return 1
    local ack
    while IFS= read -r ack; do
        ack="${ack%$'\r'}"
        [[ -z "$ack" ]] && continue
        [[ "$entry" == "$ack" ]] && return 0
    done <<< "$ACK_RAW"
    return 1
}

# ─── Normalization patterns ─────────────────────────────────────────
#
# Normalization accepts only this workspace's OWN copies of the wrapper
# scripts: the relative form plus the absolute spellings of $ROOT_DIR
# (the msys /d/... form and the Windows-drive D:/... and d:/... forms).
# A foreign path that merely ends in scripts/ws is NOT our script and
# must keep matching Bash(bash *) — normalizing it would hide a risky
# allowance (PR #94 review finding).

# Escape a literal path for embedding in a sed -E pattern with `#` as
# the delimiter.
_re_escape() { printf '%s' "$1" | sed -E 's/[][(){}.*+?^$|\\#]/\\&/g'; }

_ROOT_ALTS="$(_re_escape "$ROOT_DIR")"
if [[ "$ROOT_DIR" =~ ^/([A-Za-z])(/.*)?$ ]]; then
    # Derive the Windows-drive spellings from the msys form so entries
    # written as D:/... (or d:/...) by Windows tooling also count as
    # in-repo. No-op on Linux/macOS roots (no single-letter prefix).
    _drv="${BASH_REMATCH[1]}"
    _rest="${BASH_REMATCH[2]}"
    _ROOT_ALTS="$_ROOT_ALTS|$(_re_escape "${_drv^^}:$_rest")|$(_re_escape "${_drv,,}:$_rest")"
fi
WS_NORM_RE="s#bash (($_ROOT_ALTS)/)?scripts/ws([ :)])#ws\3#"
BATS_NORM_RE="s#bash (($_ROOT_ALTS)/)?tests/vendor/bats-core/bin/bats tests/#bats tests/#"

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

        # Normalize the ws wrapper form to the bare `ws` form before
        # matching, mirroring the PreToolUse hook. This collapses
        # `Bash(bash scripts/ws <sub>)` and the absolute in-repo spelling
        # to `Bash(ws <sub>)`, so a narrow per-subcommand allow no longer
        # trips the broad `Bash(bash *)` watchlist entry, while the
        # subcommand-less catch-all (`...ws:*` → `ws:*`) still matches the
        # new high-severity entry. Original `$entry` is preserved for output.
        # Consequence for watchlist authors: ws-related patterns must use
        # the bare `Bash(ws …)` form — the wrapper form never survives to
        # the comparison.
        #
        # Same treatment for the vendored bats runner, but ONLY when its
        # target is inside tests/ — running the reviewed test tree is
        # risk-equivalent to the allowlisted `ws test`, while pointing the
        # runner at an arbitrary path executes arbitrary .bats shell and
        # must keep matching Bash(bash *).
        #
        # Both rules accept only in-repo paths (see WS_NORM_RE above), and
        # entries containing `..` are never normalized: a traversal in
        # either the script path (`bash ../elsewhere/scripts/ws`) or the
        # bats target (`bats tests/../tmp/evil/`) points outside the
        # reviewed tree, so those keep flagging via Bash(bash *).
        local match_entry="$entry"
        if [[ "$entry" != *..* ]]; then
            match_entry=$(printf '%s' "$entry" | sed -E \
                -e "$WS_NORM_RE" \
                -e "$BATS_NORM_RE")
        fi

        # Claude's `:*` suffix means "this command, optionally followed by
        # more arguments". Tier 5 therefore treats `Bash(sudo:*)` like the
        # dangerous `Bash(sudo *)` family. Keep the literal spelling as one
        # comparison candidate (needed for watchlist entries such as
        # `Bash(ws:*)`) and add the space-glob equivalent as a second one.
        # Findings still report the user's original entry.
        local continuation_match_entry=""
        if [[ "$match_entry" == *':*)' ]]; then
            continuation_match_entry="${match_entry%:\*)} *)"
        fi

        # Prefer an explicit watchlist spelling when one exists. For example,
        # `Bash(kubectl:*)` deliberately has a high-severity rule; its
        # continuation equivalent must not add a second medium finding from
        # `Bash(kubectl *)`.
        local literal_watchlist_match=0
        local literal_pattern _literal_severity _literal_rationale
        while IFS='|' read -r literal_pattern _literal_severity _literal_rationale; do
            [[ -z "$literal_pattern" ]] && continue
            # Quoted RHS: this loop asks whether the entry IS a watchlist
            # line verbatim, not whether it glob-matches one — a glob here
            # could suppress a continuation finding for a different entry.
            if [[ "$match_entry" == "$literal_pattern" ]]; then
                literal_watchlist_match=1
                break
            fi
        done <<< "$WATCHLIST_RAW"

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
            if [[ "$match_entry" == $pattern ]] \
                || [[ "$literal_watchlist_match" -eq 0 && -n "$continuation_match_entry" && "$continuation_match_entry" == $pattern ]]; then
                local ack="false"
                is_acknowledged "$entry" && ack="true"
                FINDINGS+=("$scope|$file|$entry|$severity|$rationale|$ack")
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
    # Acknowledged findings are skipped — this mode feeds pipelines
    # about problems, and an acknowledged entry isn't one.
    for f in "${FINDINGS[@]:-}"; do
        [[ -z "$f" ]] && continue
        IFS='|' read -r _scope _file pattern _severity _rationale _ack <<< "$f"
        [[ "$_ack" == "true" ]] && continue
        echo "$pattern"
    done
else
    # YAML emission. Findings are in insertion order: scope (user →
    # project → project-local) × allow-entry × watchlist-pattern.
    # Since the watchlist itself is declared critical → high → medium,
    # findings within a single scope/entry naturally appear in
    # severity order, but there's no GLOBAL severity sort — a medium
    # finding from the user scope can precede a critical finding from
    # the project scope. Callers that need a strict severity order
    # should pipe through `yq` or `sort` themselves. Insertion order
    # is preserved on purpose so the reader can follow each settings
    # file top-to-bottom.
    if [[ ${#FINDINGS[@]} -eq 0 ]]; then
        echo "[]"
    else
        for f in "${FINDINGS[@]}"; do
            IFS='|' read -r scope file pattern severity rationale ack <<< "$f"
            # Escape values for the YAML quote style being used:
            #   - single-quoted string: ' → ''
            #   - double-quoted string: \ → \\, " → \"
            # Real-world allow entries like `Bash(echo 'hi')` would
            # otherwise produce `pattern: 'Bash(echo 'hi')'` — invalid
            # YAML where the inner `'` closes the string early.
            # Rationales are author-controlled (no quotes in the
            # current watchlist) but the same escape applies if
            # someone adds a quote-containing entry later.
            escaped_pattern="${pattern//\'/\'\'}"
            escaped_rationale="${rationale//\\/\\\\}"
            escaped_rationale="${escaped_rationale//\"/\\\"}"
            echo "- scope: $scope"
            echo "  file: $file"
            echo "  pattern: '$escaped_pattern'"
            echo "  severity: $severity"
            echo "  rationale: \"$escaped_rationale\""
            # Acknowledged per-workspace allowance (hook-rules.local
            # [audit-acknowledged]) — shown for transparency, excluded
            # from the exit code.
            [[ "$ack" == "true" ]] && echo "  acknowledged: true"
        done
    fi
fi

# Exit code = UNACKNOWLEDGED findings count, capped at 255 (shell exit
# code limit). Callers can check `[[ $? -gt 0 ]]` for "there were
# findings worth attention" — acknowledged allowances don't count.
exit_code=0
for f in "${FINDINGS[@]:-}"; do
    [[ -z "$f" ]] && continue
    IFS='|' read -r _scope _file _pattern _severity _rationale _ack <<< "$f"
    [[ "$_ack" == "true" ]] && continue
    exit_code=$((exit_code + 1))
done
[[ "$exit_code" -gt 255 ]] && exit_code=255
exit "$exit_code"
