#!/usr/bin/env bash
# ws-pii.sh — refuse to publish a personal identifier the repo has never held.
#
# NOT a credential scanner. Tokens and keys are high-entropy with recognizable
# shapes and gitleaks-class tools handle them well. This covers the opposite
# case: an ordinary email address that is harmless in a local sample file and
# harmful in a published document. The incident that prompted it — an address
# filled into a sample manifest, read later by an agent doing unrelated work,
# and carried into a documentation pass — leaves no trace a secret scanner
# would notice.
#
# The whole design rests on one observation: shape does not separate the cases,
# novelty does. This repository's tree already contains `noreply@anthropic.com`,
# `git@github.com`, `test@example.local` and about ninety other email-shaped
# strings, every one of them legitimate. A pattern match alone would fire on
# nearly every commit and be muted within a week. So a candidate only counts
# when the repository has never contained it before.
#
# Deliberately email-only. Phone numbers, IP addresses and hostnames are where
# scanners of this kind turn into noise; add a class when an incident asks for
# it, not in advance.

# Local parts that name a role rather than a person. A new role address is not
# a privacy problem, and `git@` in particular is an SSH remote rather than a
# mailbox.
_WS_PII_ROLE_LOCALPARTS="noreply no-reply donotreply git admin webmaster postmaster hostmaster support info security abuse"

# Domains reserved for documentation and testing — RFC 2606 and RFC 6761. An
# address here cannot belong to anyone.
_WS_PII_RESERVED_SUFFIXES=".example .invalid .test .localhost example.com example.org example.net example.edu"

# Per-repository allowlist. One value per line; `#` comments and blanks ignored.
# Committed on purpose: an exemption is a decision, and it should be reviewable
# rather than living in someone's shell history.
WS_PII_ALLOW_FILE="${WS_PII_ALLOW_FILE:-.gdd-pii-allow}"

_ws_pii_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Emails present in the text. Unique, lowercased for comparison.
#
# Letters are legal in a local part, so a raw scan captures the `n` of a `\n`
# escape inside a quoted string (`nknown.contact@…`) — never the value a human
# wrote in an allowlist. A backslash cannot be part of an address, so blanking
# the escape loses nothing. The diff's `+` marker is NOT stripped here: in
# prose a leading `+` can be a real local part, and only
# ws_pii_staged_added_lines knows its input is a diff.
_ws_pii_extract() {
    printf '%s\n' "$1" \
        | sed -e 's/\\[nrt]/ /g' \
        | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u \
        || true
}

_ws_pii_is_role_address() {
    local local_part="${1%%@*}" role
    for role in $_WS_PII_ROLE_LOCALPARTS; do
        [[ "$local_part" == "$role" ]] && return 0
    done
    return 1
}

# Exact domain or a dot-delimited subdomain — never a bare suffix, or
# `notexample.com` would pass as reserved.
_ws_pii_is_reserved_domain() {
    local domain="${1#*@}" suffix
    for suffix in $_WS_PII_RESERVED_SUFFIXES; do
        suffix="${suffix#.}"
        [[ "$domain" == "$suffix" || "$domain" == *".$suffix" ]] && return 0
    done
    return 1
}

_ws_pii_is_allowlisted() {
    local value="$1" repo="$2" line
    local file="$repo/$WS_PII_ALLOW_FILE"
    [[ -f "$file" ]] || return 1
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [[ -n "$line" ]] || continue
        [[ "$(_ws_pii_lower "$line")" == "$value" ]] && return 0
    done < "$file"
    return 1
}

# Already somewhere in the committed tree. This is the load-bearing filter: it
# is what lets the check block rather than merely warn, because what survives it
# is genuinely new to the repository rather than merely email-shaped.
#
# Searches HEAD rather than the working tree — an uncommitted sample file is
# exactly where the leaked value was sitting, so counting it as prior art would
# defeat the check on the one case it exists for.
#
# Whole-address match: a substring search would let `a@one.co.uk` ride in on a
# committed `data@one.co.uk`. The boundaries are the characters an address can
# contain, so anything else — or a line edge — ends it.
_ws_pii_in_repo() {
    local value="$1" repo="$2" escaped
    git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || return 1
    escaped="$(printf '%s' "$value" | sed -e 's/[.+]/\\&/g')"
    git -C "$repo" grep -qiE -- "(^|[^A-Za-z0-9._%+-])${escaped}([^A-Za-z0-9.-]|\$)" HEAD 2>/dev/null
}

# ws_pii_guard <label> <text> [repo_dir] [override]
#
# Prints any findings and returns non-zero. Callers decide whether that blocks;
# every current caller does. <override> is the caller's own one-off escape
# ("re-run with --allow-pii", "set CR_ALLOW_PII=1") — they differ per command,
# so the message names the one that works where it is printed.
ws_pii_guard() {
    local label="$1" text="$2" repo="${3:-$PWD}" override="${4:-}"
    local candidate found=0

    [[ -n "$text" ]] || return 0
    type -P git >/dev/null 2>&1 || return 0

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        _ws_pii_is_role_address "$candidate" && continue
        _ws_pii_is_reserved_domain "$candidate" && continue
        _ws_pii_is_allowlisted "$candidate" "$repo" && continue
        _ws_pii_in_repo "$candidate" "$repo" && continue
        if [[ $found -eq 0 ]]; then
            echo "ERROR: $label contains an email address this repository has never held." >&2
            found=1
        fi
        echo "  $candidate" >&2
    done < <(_ws_pii_extract "$text")

    [[ $found -eq 0 ]] && return 0

    echo "" >&2
    echo "  A local sample or scratch file is the usual source — check where it came from before" >&2
    echo "  deciding it is safe. Published addresses stay in history and may be indexed." >&2
    echo "" >&2
    echo "  If it belongs here, record the decision by adding it to $WS_PII_ALLOW_FILE" >&2
    if [[ -n "$override" ]]; then
        echo "  (one value per line, committed), or $override to skip this check once." >&2
    else
        echo "  (one value per line, committed)." >&2
    fi
    return 1
}

# ws_pii_guard_publication <label> <title> <bodyfile> <repo_dir> <override>
#
# Title and body together: both are published, and the create and edit paths of
# ws cr / ws issue all come through here so none of the four can drift.
ws_pii_guard_publication() {
    local label="$1" title="$2" bodyfile="$3" repo="$4" override="$5"
    ws_pii_guard "$label" "$title
$(cat "$bodyfile")" "$repo" "$override"
}

# Added lines of the staged diff, diff marker removed — the only part of a
# change that can publish something new. Context and removed lines cannot.
# [index_file] reads a scratch index instead, which is how a dry run scans what
# it WOULD stage rather than what happens to be staged already.
ws_pii_staged_added_lines() {
    local repo="${1:-$PWD}" index_file="${2:-}"
    if [[ -n "$index_file" ]]; then
        GIT_INDEX_FILE="$index_file" git -C "$repo" diff --cached -U0 --no-color 2>/dev/null
    else
        git -C "$repo" diff --cached -U0 --no-color 2>/dev/null
    fi \
        | grep -E '^\+' \
        | grep -vE "^\+\+\+" \
        | sed -e 's/^+//' || true
}
