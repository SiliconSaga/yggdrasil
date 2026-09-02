#!/usr/bin/env bats

# Tests for `ws cr <comp> edit` — updating an existing change request's body and title through the wrapper, so the substitution and the attribution check run the way they already do on creation.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"

    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards" "$WORK/.crs"

    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"

    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
defaults:
  gddHome: https://example.test/gdd/
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"

    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'

    git init -q "$WORK"
    git -C "$WORK" config user.name "Test User"
    git -C "$WORK" config user.email "test@example.local"
    echo seed > "$WORK/file.txt"
    git -C "$WORK" add file.txt
    git -C "$WORK" commit -q -m "seed commit"
    git -C "$WORK" remote add fork https://github.com/example/fork.git
    git -C "$WORK" checkout -q -b feature/cr-edit

    GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$GH_STUB_DIR"
    # One argument per line, unescaped — %q would render a title containing a space as `New\ title` and make a passing assertion look like a failure.
    cat > "$GH_STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
esac
printf '%s\n' "gh" "$@" >> "$GH_LOG"
exit 0
SH
    chmod +x "$GH_STUB_DIR/gh"
    export PATH="$GH_STUB_DIR:$PATH"
}

write_body() {
    printf '%s\n\nRevised summary.\n' "$1" > "$WORK/.crs/edit.md"
}

@test "edit substitutes placeholders before sending the body" {
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" == *"https://example.test/gdd/"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "edit targets the pulls endpoint with the given number" {
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"repos/example/fork/pulls/42"* ]]
    [[ "$output" == *"PATCH"* ]]
}

@test "edit rejects a body with no attribution line" {
    printf 'No banner here.\n' > "$WORK/.crs/edit.md"
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "edit rejects a banner naming an account that is not the driver" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @someoneelse via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not name the driving human"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "the edit path calls the leak guard" {
    # The guard's job is bodies that never entered the substituter at all, which this path cannot produce — substitution always runs first. Assert it is wired, rather than leaving the only coverage at unit level where a dropped call would go unnoticed.
    run grep -q 'gdd_attribution_assert_resolved' "$REPO_ROOT/scripts/git-cr-edit.sh"
    [ "$status" -eq 0 ]
}

@test "edit rejects a non-numeric CR number" {
    run bash "$WS_BIN" cr yggdrasil edit abc .crs/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"numeric"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "edit rejects a CR number that could steer the API path" {
    run bash "$WS_BIN" cr yggdrasil edit "42/../../repos/other/repo/pulls/1" .crs/edit.md
    [ "$status" -ne 0 ]
    [ ! -f "$GH_LOG" ]
}

@test "edit rejects a missing bodyfile before any API call" {
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/absent.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"body file not found"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "edit passes a title through when given" {
    run bash "$WS_BIN" cr yggdrasil edit 42 --title "fix: revised title" .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"title=fix: revised title"* ]]
}

@test "edit sends no title when none is given" {
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    run cat "$GH_LOG"
    [[ "$output" != *"title="* ]]
}

@test "edit does not run the creation preflights" {
    # Stale base, source-branch verification and the changelog reminder are statements about a branch being proposed. None means anything when only a description changes, and running them would fail an edit because a branch drifted.
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    [[ "$output" != *"has moved"* ]]
    [[ "$output" != *"CHANGELOG"* ]]
}

@test "edit works from a branch named main" {
    # Creation refuses main because a CR cannot be opened from it. An edit concerns a CR that already exists, so the branch you happen to stand on is irrelevant — inheriting that guard would refuse to fix a typo for the wrong reason.
    # The seed commit already sits on the init default branch, so check it out rather than creating it. Resolve the name instead of assuming "main": init.defaultBranch is configurable and this fixture must not depend on the runner's git config.
    local default_branch
    default_branch=$(git -C "$WORK" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || default_branch=""
    [[ -n "$default_branch" ]] || default_branch=$(git -C "$WORK" for-each-ref --format='%(refname:short)' refs/heads/ | grep -Ex 'main|master' | head -n1)
    git -C "$WORK" checkout -q "$default_branch"
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
}

@test "edit reports the CR it updated" {
    run bash "$WS_BIN" cr yggdrasil edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"CR updated: #42 on example/fork"* ]]
}

@test "--remote selects an alternate remote for the edit" {
    git -C "$WORK" remote add alt https://github.com/alt/project.git
    run bash "$WS_BIN" cr yggdrasil edit 42 --remote alt .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"repos/alt/project/pulls/42"* ]]
}

@test "--title on a create is rejected rather than silently ignored" {
    # A new CR takes its title as a positional. Accepting --title there would quietly drop it.
    run bash "$WS_BIN" cr yggdrasil --title "wrong place" "test: title" .crs/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"--title applies to"* ]]
}

@test "edit with the wrong positional count fails with usage" {
    run bash "$WS_BIN" cr yggdrasil edit 42
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "create still requires exactly a title and a bodyfile" {
    run bash "$WS_BIN" cr yggdrasil "just a title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}
