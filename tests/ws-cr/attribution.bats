#!/usr/bin/env bats

# Unit tests for scripts/gdd-attribution.sh — the module that owns the AI-attribution banner and placeholder resolution for every path that publishes agent-authored text to a tracker.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"

    export ROOT_DIR="$WORK"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
defaults:
  gddHome: https://example.test/gdd/
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/ws-realm.sh"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/gdd-attribution.sh"
}

write_body() {
    printf '%s\n' "$1" > "$WORK/body.md"
    printf '\nBody text.\n' >> "$WORK/body.md"
}

clear_human_account() {
    cat > "$ECOSYSTEM" <<'YAML'
identity: {}
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"
}

@test "the shipped change template banner passes the check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "the shipped issue template banner passes the check" {
    write_body '> **AI-assisted issue.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "the gdd-sandbox wording variant passes the check" {
    # The sandbox ships a template opening "— requested over chat." The old exact-sentence grep rejected it, which is why the live instance carries a host-side patch to its own templates/change.md — a patch that dies on a container restart.
    write_body '> **AI-assisted change proposal — requested over chat.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "a bold run that does not close on the first line fails the check" {
    write_body '> **AI-assisted change proposal. Filed by agent driven by @HUMAN_ACCOUNT.'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
}

@test "a first line that is not a blockquote fails the check" {
    write_body '**AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT.'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -ne 0 ]
}

@test "a blockquote with no AI-assisted opener fails the check" {
    write_body '> **Change proposal.** Filed by agent driven by @HUMAN_ACCOUNT.'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -ne 0 ]
}

@test "the check names the template it wants copied" {
    write_body 'No banner.'
    run gdd_attribution_check "$WORK/body.md" "templates/issue.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"templates/issue.md"* ]]
}

@test "a banner naming a different account fails the driver check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @someoneelse via [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" testuser
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not name the driving human"* ]]
}

@test "a longer account starting with the driver fails the driver check" {
    # Configured `testuser` must not be satisfied by `@testuser2`, which names a DIFFERENT person. A substring test accepted it, which is the exact "someone else is credited as the driver" case this check exists to catch.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser2 via [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" testuser
    [ "$status" -ne 0 ]
}

@test "a mention followed by a comma still passes the driver check" {
    # The boundary must admit ordinary prose: a trailing delimiter is not part of the username.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser, via [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" testuser
    [ "$status" -eq 0 ]
}

@test "a mention followed by a period still passes the driver check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser. See [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" testuser
    [ "$status" -eq 0 ]
}

@test "a mention at end of line passes the driver check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser'
    run gdd_attribution_check_driver "$WORK/body.md" testuser
    [ "$status" -eq 0 ]
}

@test "a dotted account is not satisfied by its own prefix" {
    # GitLab permits a dot inside a username, so a dot cannot simply end a mention: configured `a` must not accept `@a.b`, who is a different person.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @a.b via [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" 'a'
    [ "$status" -ne 0 ]
}

@test "a dot in the account cannot match an arbitrary character" {
    # GitLab permits a dot in a username, and an unescaped dot in the pattern would match any character — reopening the hole from the other side, so `a.b` would accept `@axb`.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @axb via [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" 'a.b'
    [ "$status" -ne 0 ]
}

@test "a substituted banner passes the driver check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    resolved=$(gdd_attribution_substitute "$WORK/body.md" testuser https://example.test/gdd/)
    run gdd_attribution_check_driver "$resolved" testuser
    [ "$status" -eq 0 ]
}

@test "substitution replaces both placeholders" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    resolved=$(gdd_attribution_substitute "$WORK/body.md" testuser https://example.test/gdd/)
    run cat "$resolved"
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" == *"https://example.test/gdd/"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "substitution leaves the rest of the body untouched" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    resolved=$(gdd_attribution_substitute "$WORK/body.md" testuser https://example.test/gdd/)
    run cat "$resolved"
    [[ "$output" == *"Body text."* ]]
}

@test "substitution survives an account containing regex-significant characters" {
    # The substituter builds a sed expression, so an account or home URL carrying & | or a backslash must be escaped rather than interpreted.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    resolved=$(gdd_attribution_substitute "$WORK/body.md" 'a&b' 'https://example.test/x|y/')
    run cat "$resolved"
    [[ "$output" == *"@a&b"* ]]
    [[ "$output" == *"https://example.test/x|y/"* ]]
}

@test "the resolved guard refuses a body still carrying @HUMAN_ACCOUNT" {
    # The yggdrasil#158 regression: the published body read "driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" with both literal.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](https://example.test/gdd/).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" == *"refusing to publish"* ]]
}

@test "the resolved guard refuses a body still carrying @GDD_HOME" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](@GDD_HOME).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"@GDD_HOME"* ]]
}

@test "the resolved guard names both placeholders when both leak" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"@HUMAN_ACCOUNT and @GDD_HOME"* ]]
}

@test "the resolved guard catches a placeholder below the first line" {
    # The guard is not a banner check — it scans the whole body, because a placeholder can be typed anywhere and is just as unresolved there.
    printf '> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](https://example.test/gdd/).\n\nSee @GDD_HOME for details.\n' > "$WORK/body.md"
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
}

@test "the resolved guard passes a fully substituted body" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](https://example.test/gdd/).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "human_account resolves from ecosystem config" {
    run gdd_attribution_human_account
    [ "$status" -eq 0 ]
    [ "$output" = "testuser" ]
}

@test "an unset human_account fails closed" {
    clear_human_account
    run gdd_attribution_human_account
    [ "$status" -ne 0 ]
    [[ "$output" == *"identity.human_account not set"* ]]
}

@test "gddHome resolves from ecosystem config" {
    run gdd_attribution_gdd_home
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.test/gdd/" ]
}

@test "resolve_message substitutes placeholders in an in-memory message" {
    # Review replies and comments assemble text in memory rather than from a bodyfile, so they never reached the bodyfile substitution — a reply containing @HUMAN_ACCOUNT published it literally, which is the defect this whole module exists to prevent.
    run gdd_attribution_resolve_message 'see @HUMAN_ACCOUNT and [GDD](@GDD_HOME)'
    [ "$status" -eq 0 ]
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" == *"https://example.test/gdd/"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "resolve_message survives an ampersand in gddHome" {
    # Bash 5.2 enables patsub_replacement by default, so an unquoted `&` in the replacement expands to the MATCHED text — which both corrupted the URL and put `@GDD_HOME` back into the output, defeating the whole function.
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
defaults:
  gddHome: https://example.test/gdd/?a=1&b=2
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"
    run gdd_attribution_resolve_message 'see [GDD](@GDD_HOME)'
    [ "$status" -eq 0 ]
    [ "$output" = 'see [GDD](https://example.test/gdd/?a=1&b=2)' ]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "resolve_message leaves ordinary text untouched" {
    run gdd_attribution_resolve_message 'Addressed in abc123 — no placeholders here.'
    [ "$status" -eq 0 ]
    [ "$output" = 'Addressed in abc123 — no placeholders here.' ]
}

@test "resolve_message fails closed with no human_account" {
    clear_human_account
    run gdd_attribution_resolve_message 'see @HUMAN_ACCOUNT'
    [ "$status" -ne 0 ]
}

@test "the reply banner uses the compact italic form" {
    run ws_gdd_attribution_line reply
    [ "$status" -eq 0 ]
    [ "$output" = '> _Agent-authored reply — @testuser via [GDD](https://example.test/gdd/)._' ]
}

@test "the comment banner carries its own label" {
    run ws_gdd_attribution_line comment
    [ "$status" -eq 0 ]
    [[ "$output" == '> _Agent-authored comment — '* ]]
}

@test "the reply banner is shorter than the body banner" {
    # Not cosmetic: replies stack down a thread while a body banner is read once at the top of a review. If a future edit re-lengthens it, this fails loudly.
    local reply body
    reply=$(ws_gdd_attribution_line reply)
    body='> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](https://example.test/gdd/).'
    [ "${#reply}" -lt "${#body}" ]
}

@test "the reply banner fails closed with no human_account" {
    clear_human_account
    run ws_gdd_attribution_line reply
    [ "$status" -ne 0 ]
}

@test "ws-realm.sh no longer defines the attribution line" {
    run grep -c 'ws_gdd_attribution_line()' "$REPO_ROOT/scripts/ws-realm.sh"
    [ "$output" = "0" ]
}

@test "ws-review.sh sources the attribution module" {
    run grep -q 'gdd-attribution.sh' "$REPO_ROOT/scripts/ws-review.sh"
    [ "$status" -eq 0 ]
}

@test "gddHome falls back to the GDD docs URL when unset" {
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"
    run gdd_attribution_gdd_home
    [ "$status" -eq 0 ]
    [ "$output" = "https://siliconsaga.github.io/yggdrasil/gdd/" ]
}
