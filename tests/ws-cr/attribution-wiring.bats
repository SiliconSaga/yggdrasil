#!/usr/bin/env bats

# End-to-end guards that git-cr.sh and git-issue.sh actually route through scripts/gdd-attribution.sh rather than keeping their own copies of the banner check and the substitution.
#
# The unit behaviour lives in attribution.bats. What is tested here is the wiring, and specifically the two user-visible consequences of it: the gdd-sandbox wording variant is accepted (retiring a host-side patch on the live container), and a banner whose driver reference never resolved is refused instead of published (the yggdrasil#158 shape).

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"

    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards" "$WORK/.crs" "$WORK/.issues"

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

    git init -q "$WORK"
    git -C "$WORK" config user.name "Test User"
    git -C "$WORK" config user.email "test@example.local"
    echo seed > "$WORK/file.txt"
    git -C "$WORK" add file.txt
    git -C "$WORK" commit -q -m "seed commit"

    # A real local bare repo behind a github.com URL: git transport stays hermetic while slug and provider detection still see example/fork. Same device as remote-override.bats.
    BARE="$BATS_TEST_TMPDIR/fork.git"
    git init -q --bare "$BARE"
    git -C "$WORK" remote add fork https://github.com/example/fork.git
    git -C "$WORK" config url."$BARE".insteadOf https://github.com/example/fork.git

    BASE_COMMIT="$(git -C "$WORK" rev-parse HEAD)"
    git -C "$WORK" push -q fork "$BASE_COMMIT:refs/heads/main"
    git -C "$WORK" checkout -q -b feature/attribution-wiring
    git -C "$WORK" commit --allow-empty -q -m "advance the branch"
    git -C "$WORK" push -q fork refs/heads/feature/attribution-wiring

    GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$GH_STUB_DIR"
    cat > "$GH_STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "api repos/"*) echo main; exit 0 ;;
esac
{
  printf 'gh:'
  printf ' %q' "$@"
  printf '\n'
} >> "$GH_LOG"
case "${1:-} ${2:-}" in
  "pr create")    echo "https://github.com/example/fork/pull/1" ;;
  "issue create") echo "https://github.com/example/fork/issues/1" ;;
esac
exit 0
SH
    chmod +x "$GH_STUB_DIR/gh"
    export GH_LOG
    export PATH="$GH_STUB_DIR:$PATH"
}

write_cr_body() {
    printf '%s\n\nSummary text.\n' "$1" > "$WORK/.crs/body.md"
}

# Absolute, deliberately: `ws issue` does not resolve a relative bodyfile against ROOT_DIR the way `ws cr` does (ws_cr rewrites the last positional, ws_issue passes "$@" straight to git-issue.sh, which never cd's). These tests are about attribution, not path resolution, so they sidestep it. The asymmetry itself is fixed in the ws issue edit task.
write_issue_body() {
    printf '%s\n\nProblem text.\n' "$1" > "$WORK/.issues/body.md"
    ISSUE_BODY="$WORK/.issues/body.md"
}

# --- ws cr ---

@test "ws cr accepts the gdd-sandbox banner variant" {
    # The exact-sentence grep this replaces rejected it, which is why the live Kencierge container carries a hand-edited templates/change.md that dies on restart.
    write_cr_body '> **AI-assisted change proposal — requested over chat.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" cr yggdrasil "test: sandbox banner variant" .crs/body.md
    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"pr create"* ]]
}

@test "ws cr still accepts the shipped template banner" {
    write_cr_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" cr yggdrasil "test: shipped banner" .crs/body.md
    [ "$status" -eq 0 ]
}

@test "ws cr refuses a body with no banner" {
    write_cr_body 'No banner at all.'
    run bash "$WS_BIN" cr yggdrasil "test: no banner" .crs/body.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "ws cr points a rejected body at the change template" {
    write_cr_body 'No banner at all.'
    run bash "$WS_BIN" cr yggdrasil "test: template hint" .crs/body.md
    [[ "$output" == *"templates/change.md"* ]]
}

@test "ws cr refuses a banner naming an account that is not the driver" {
    # New under the prefix rule: the exact-match check confirmed one sentence and never confirmed the driver reference resolved to anything.
    write_cr_body '> **AI-assisted change proposal.** Filed by agent driven by @someoneelse via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" cr yggdrasil "test: wrong driver" .crs/body.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not name the driving human"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "ws cr sends a fully substituted body to the provider" {
    write_cr_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" cr yggdrasil "test: substitution" .crs/body.md
    [ "$status" -eq 0 ]
    local sent
    sent="$(cat "$GH_LOG")"
    # The body reaches gh as a --body-file path; read what that file held at call time by re-reading the resolved copy the log names.
    [[ "$sent" == *"--body-file"* ]]
    [[ "$sent" != *"@HUMAN_ACCOUNT"* ]]
}

# --- ws issue ---

@test "ws issue accepts a banner wording variant" {
    write_issue_body '> **AI-assisted issue — raised from a chat session.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" issue yggdrasil "test: issue variant" bug "$ISSUE_BODY"
    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"issue create"* ]]
}

@test "ws issue still accepts the shipped template banner" {
    write_issue_body '> **AI-assisted issue.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" issue yggdrasil "test: shipped issue banner" bug "$ISSUE_BODY"
    [ "$status" -eq 0 ]
}

@test "ws issue refuses a body with no banner" {
    write_issue_body 'No banner at all.'
    run bash "$WS_BIN" issue yggdrasil "test: no issue banner" bug "$ISSUE_BODY"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
    [ ! -f "$GH_LOG" ]
}

@test "ws issue points a rejected body at the issue template" {
    write_issue_body 'No banner at all.'
    run bash "$WS_BIN" issue yggdrasil "test: issue template hint" bug "$ISSUE_BODY"
    [[ "$output" == *"templates/issue.md"* ]]
}

@test "ws issue refuses a banner naming an account that is not the driver" {
    write_issue_body '> **AI-assisted issue.** Filed by agent driven by @someoneelse via [GDD](@GDD_HOME).'
    run bash "$WS_BIN" issue yggdrasil "test: wrong issue driver" bug "$ISSUE_BODY"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not name the driving human"* ]]
    [ ! -f "$GH_LOG" ]
}

# --- structural guards ---
#
# Cheap, and they catch the specific regression the greps are for: a future edit re-adding a local copy of the check beside the module call, which every behavioural test above would still pass.

@test "git-cr.sh keeps no exact-sentence attribution grep of its own" {
    run grep -c 'AI-assisted change proposal\\\.' "$REPO_ROOT/scripts/git-cr.sh"
    [ "$output" = "0" ]
}

@test "git-issue.sh keeps no exact-sentence attribution grep of its own" {
    run grep -c 'AI-assisted issue\\\.' "$REPO_ROOT/scripts/git-issue.sh"
    [ "$output" = "0" ]
}

@test "git-cr.sh sources the attribution module" {
    run grep -q 'gdd-attribution.sh' "$REPO_ROOT/scripts/git-cr.sh"
    [ "$status" -eq 0 ]
}

@test "git-issue.sh sources the attribution module" {
    run grep -q 'gdd-attribution.sh' "$REPO_ROOT/scripts/git-issue.sh"
    [ "$status" -eq 0 ]
}

@test "git-cr.sh calls the leak guard before publishing" {
    run grep -q 'gdd_attribution_assert_resolved' "$REPO_ROOT/scripts/git-cr.sh"
    [ "$status" -eq 0 ]
}

@test "git-issue.sh calls the leak guard before publishing" {
    run grep -q 'gdd_attribution_assert_resolved' "$REPO_ROOT/scripts/git-issue.sh"
    [ "$status" -eq 0 ]
}
