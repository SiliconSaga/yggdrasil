#!/usr/bin/env bats

# Tests for `ws issue <comp> edit`, and for the bodyfile-path resolution `ws issue` create gained alongside it.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"

    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards" "$WORK/.issues"

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

    write_body '> **AI-assisted issue.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'

    git init -q "$WORK"
    git -C "$WORK" config user.name "Test User"
    git -C "$WORK" config user.email "test@example.local"
    echo seed > "$WORK/file.txt"
    git -C "$WORK" add file.txt
    git -C "$WORK" commit -q -m "seed commit"
    git -C "$WORK" remote add fork https://github.com/example/fork.git

    GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$GH_STUB_DIR"
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
    printf '%s\n\nRevised problem statement.\n' "$1" > "$WORK/.issues/edit.md"
}

@test "issue edit substitutes placeholders before sending" {
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "issue edit targets the issues endpoint" {
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"repos/example/fork/issues/7"* ]]
    [[ "$output" == *"PATCH"* ]]
}

@test "issue edit rejects a body with no attribution line" {
    printf 'No banner.\n' > "$WORK/.issues/edit.md"
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "issue edit rejects a banner naming an account that is not the driver" {
    write_body '> **AI-assisted issue.** Filed by agent driven by @someoneelse via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not name the driving human"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "the issue edit path calls the leak guard" {
    run grep -q 'gdd_attribution_assert_resolved' "$REPO_ROOT/scripts/git-issue-edit.sh"
    [ "$status" -eq 0 ]
}

@test "issue edit rejects a non-numeric issue number" {
    run bash "$WS_BIN" issue yggdrasil edit abc .issues/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"numeric"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "issue edit rejects a missing bodyfile before any API call" {
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/absent.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"body file not found"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "issue edit passes a title through" {
    run bash "$WS_BIN" issue yggdrasil edit 7 --title "revised title" .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"title=revised title"* ]]
}

@test "issue edit sends no title when none is given" {
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/edit.md
    run cat "$GH_LOG"
    [[ "$output" != *"title="* ]]
}

@test "issue edit reports the issue it updated" {
    run bash "$WS_BIN" issue yggdrasil edit 7 .issues/edit.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"Issue updated: #7 on example/fork"* ]]
}

@test "issue edit with the wrong positional count fails with usage" {
    run bash "$WS_BIN" issue yggdrasil edit 7
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "a relative bodyfile resolves against the workspace root, not the caller's cwd" {
    # ws_cr always did this; ws_issue passed "$@" straight through and git-issue.sh never cd's, so a relative path was read against wherever `ws` happened to be invoked from. Invisible when standing in the workspace root, broken everywhere else.
    cd "$BATS_TEST_TMPDIR"
    run bash "$WS_BIN" issue yggdrasil "test: relative bodyfile" bug .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    # The stub logs one argument per line, so the subcommand words are on separate lines.
    [[ "$output" == *"create"* ]]
    [[ "$output" == *"example/fork"* ]]
}

@test "an absolute bodyfile is left alone" {
    run bash "$WS_BIN" issue yggdrasil "test: absolute bodyfile" bug "$WORK/.issues/edit.md"
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    # The stub logs one argument per line, so the subcommand words are on separate lines.
    [[ "$output" == *"create"* ]]
    [[ "$output" == *"example/fork"* ]]
}

@test "issue create still requires title, label and bodyfile" {
    run bash "$WS_BIN" issue yggdrasil "a title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}
