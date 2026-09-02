#!/usr/bin/env bash
# gdd-attribution.sh — attribution banner and placeholder resolution for agent-authored text
#
# Sourced by git-cr.sh, git-issue.sh, git-cr-edit.sh, git-issue-edit.sh and ws-review.sh. Every path that publishes agent-authored text to a tracker goes through here, so the guarantees cannot diverge between the create path and the edit path — which is exactly how they diverged before: substitution and the banner check lived on creation only, so an edit through raw `gh pr edit --body-file` ran neither.
#
# Requires ws-realm.sh (for ws_resolve_ecosystem) to be sourced first.

GDD_ATTRIBUTION_HOME_DEFAULT="https://siliconsaga.github.io/yggdrasil/gdd/"

_gdd_attribution_no_account() {
    echo "ERROR: identity.human_account not set in ecosystem config." >&2
    echo "  Set it in ecosystem.local.yaml (see ecosystem.local.yaml.example)." >&2
}

# Resolve identity.human_account. Fails closed: a banner cannot be written, or meaningfully checked, without knowing who is driving.
gdd_attribution_human_account() {
    local eco="" human=""
    eco=$(ws_resolve_ecosystem 2>/dev/null) || eco=""
    if [[ -z "$eco" ]]; then
        _gdd_attribution_no_account
        return 1
    fi
    human=$(yq '.identity.human_account // ""' "$eco" 2>/dev/null) || human=""
    [[ "$human" == "null" ]] && human=""
    if [[ -z "$human" ]]; then
        _gdd_attribution_no_account
        return 1
    fi
    printf '%s\n' "$human"
}

# Resolve defaults.gddHome, falling back to the published GDD docs URL.
gdd_attribution_gdd_home() {
    local eco="" raw=""
    eco=$(ws_resolve_ecosystem 2>/dev/null) || eco=""
    if [[ -n "$eco" ]]; then
        raw=$(yq '.defaults.gddHome // ""' "$eco" 2>/dev/null) || raw=""
        if [[ -n "$raw" && "$raw" != "null" ]]; then
            printf '%s\n' "$raw"
            return 0
        fi
    fi
    printf '%s\n' "$GDD_ATTRIBUTION_HOME_DEFAULT"
}

# Validate the banner on a bodyfile's first line.
#
# The rule is a prefix match rather than the exact sentence it replaces, because the exact form rejected `> **AI-assisted change proposal — requested over chat.**` — a banner that carries the attribution perfectly well, shipped by gdd-sandbox's own template and patched around by hand inside the live container. What the check exists to require is the attribution, not one particular sentence.
#
# It is nonetheless STRICTER than what it replaces, because gdd_attribution_check_driver below verifies the resolved account afterwards. The old check confirmed one sentence and never confirmed that the driver reference resolved to anything at all.
#
# Usage: gdd_attribution_check <bodyfile> [template-hint]
gdd_attribution_check() {
    local bodyfile="$1" hint="${2:-templates/change.md}"
    local first="" re='^> \*\*AI-assisted [^*]+\*\*'
    first=$(head -n 1 "$bodyfile")
    if [[ ! "$first" =~ $re ]]; then
        echo "ERROR: body file is missing the AI attribution line." >&2
        echo "  The first line must be a blockquote whose bold run opens \"AI-assisted \" and closes on the same line, e.g." >&2
        echo "    > **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)." >&2
        echo "  Copy $hint rather than writing the line by hand — the template evolves." >&2
        return 1
    fi
}

# Verify the banner names the resolved driving human. Run on the SUBSTITUTED body, never on the template.
# Usage: gdd_attribution_check_driver <resolved-bodyfile> <human-account>
gdd_attribution_check_driver() {
    local bodyfile="$1" human="$2" first=""
    first=$(head -n 1 "$bodyfile")
    if [[ "$first" != *"@${human}"* ]]; then
        echo "ERROR: the attribution line does not name the driving human." >&2
        echo "  After substitution the first line must contain '@${human}'." >&2
        echo "  Leave '@HUMAN_ACCOUNT' in the body — it is substituted for you." >&2
        return 1
    fi
}

# Substitute @HUMAN_ACCOUNT and @GDD_HOME into a temp copy and print its path. The caller owns cleanup.
# Usage: gdd_attribution_substitute <bodyfile> <human-account> <gdd-home>
gdd_attribution_substitute() {
    local bodyfile="$1" human="$2" gdd_home="$3"
    local out="" esc_human="" esc_home=""
    out=$(mktemp) || return 1
    esc_human=$(printf '%s' "$human" | sed 's/[&|\\]/\\&/g')
    esc_home=$(printf '%s' "$gdd_home" | sed 's/[&|\\]/\\&/g')
    sed -e "s|@HUMAN_ACCOUNT|@${esc_human}|g" \
        -e "s|@GDD_HOME|${esc_home}|g" \
        "$bodyfile" > "$out"
    printf '%s\n' "$out"
}

# Refuse to publish a body still carrying either placeholder.
#
# Deliberately separate from gdd_attribution_substitute rather than folded into it. Its value is catching bodies that were NEVER substituted — including ones written by tooling this workspace does not own — and a check that only runs inside the substituter cannot see those. yggdrasil#158 published "driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" with both literal; BOTH being unresolved is what proves the body never entered the substituter at all, rather than a substitution having failed.
#
# Scans the whole body, not just the banner: a placeholder typed further down is just as unresolved, and just as silent, because an unsubstituted placeholder is valid Markdown.
#
# Usage: gdd_attribution_assert_resolved <file>
gdd_attribution_assert_resolved() {
    local file="$1" human_leak="" home_leak="" found=""
    if grep -q '@HUMAN_ACCOUNT' "$file"; then human_leak=1; fi
    if grep -q '@GDD_HOME' "$file"; then home_leak=1; fi
    if [[ -n "$human_leak" && -n "$home_leak" ]]; then
        found="@HUMAN_ACCOUNT and @GDD_HOME"
    elif [[ -n "$human_leak" ]]; then
        found="@HUMAN_ACCOUNT"
    elif [[ -n "$home_leak" ]]; then
        found="@GDD_HOME"
    else
        return 0
    fi
    echo "ERROR: refusing to publish — the body still contains the unsubstituted placeholder $found." >&2
    echo "  An unsubstituted placeholder is valid Markdown, so nothing downstream would have noticed." >&2
    echo "  Publish through ws cr / ws issue (create or edit) so substitution runs." >&2
    return 1
}

# Generate the attribution banner for agent-authored text that has no template to copy from — review replies and top-level comments.
#
# Deliberately shorter than the banner a change-request or issue body carries. A body banner is read once, at the top of a review; a reply banner repeats on every reply, and a dozen of them down one thread reads as shouting. It stays a marked, translatable sentence rather than being dropped entirely: a machine account is legible as a robot only to a reader who parses English bot-naming conventions, which is the reader an international project most needs the banner for.
#
# Usage: ws_gdd_attribution_line <label>   (label e.g. "reply", "comment")
ws_gdd_attribution_line() {
    local label="$1" human="" gdd_home=""
    human=$(gdd_attribution_human_account) || return 1
    gdd_home=$(gdd_attribution_gdd_home)
    printf '> _Agent-authored %s — @%s via [GDD](%s)._\n' "$label" "$human" "$gdd_home"
}
