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
