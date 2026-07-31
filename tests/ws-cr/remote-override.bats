#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    GIT_CR_BIN="$REPO_ROOT/scripts/git-cr.sh"

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
components: {}
YAML
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML

    BODYFILE="$WORK/.crs/body.md"
    cat > "$BODYFILE" <<'MD'
> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).

Body text.
MD

    git init -q "$WORK"
    git -C "$WORK" config user.name "Test User"
    git -C "$WORK" config user.email "test@example.local"
    echo "seed" > "$WORK/file.txt"
    git -C "$WORK" add file.txt
    git -C "$WORK" commit -q -m "seed commit"
    git -C "$WORK" checkout -q -b feature/cr-remote-override
    git -C "$WORK" remote add fork https://github.com/example/fork.git
    git -C "$WORK" remote add alt https://github.com/alt/project.git

    # The tip guard live-queries the remote (git ls-remote), so the fake
    # https URL is backed by a real local bare repo via an insteadOf
    # rewrite: git-transport operations stay hermetic while the URL-derived
    # logic (slug extraction, provider detect) still sees alt/project.
    ALT_BARE="$BATS_TEST_TMPDIR/alt-project.git"
    git init -q --bare "$ALT_BARE"
    git -C "$WORK" config url."$ALT_BARE".insteadOf https://github.com/alt/project.git
    # A second URL on the remote (git pushes to all, fetches from the FIRST)
    # pins that provider detection and slug extraction read the first entry —
    # every test in this file fails on host/slug mismatch if the last-entry
    # form regresses.
    git -C "$WORK" remote set-url --add alt https://second.invalid/other/wrong.git

    BASE_COMMIT="$(git -C "$WORK" rev-parse HEAD)"
    git -C "$WORK" commit --allow-empty -q -m "advance branch fixtures"
    git -C "$WORK" branch feature/from-linked-worktree
    git -C "$WORK" branch feature/local-only
    git -C "$WORK" branch feature/diverged
    git -C "$WORK" branch feature/stale-fetch
    # Remote truth in the bare repo: current-branch + worktree branch at the
    # local tips; diverged parked at the base commit; stale-fetch also parked
    # at base while its tracking ref below falsely claims the local tip — the
    # stale-fetch window a tracking-ref-only comparison cannot see.
    git -C "$WORK" push -q "$ALT_BARE" refs/heads/feature/cr-remote-override
    git -C "$WORK" push -q "$ALT_BARE" refs/heads/feature/from-linked-worktree
    git -C "$WORK" push -q "$ALT_BARE" "$BASE_COMMIT:refs/heads/feature/diverged"
    git -C "$WORK" push -q "$ALT_BARE" "$BASE_COMMIT:refs/heads/feature/stale-fetch"
    # Target branch for the stale-base preflight: parked at the base commit,
    # which every fixture branch contains — the check passes unless a test
    # deliberately moves it.
    git -C "$WORK" push -q "$ALT_BARE" "$BASE_COMMIT:refs/heads/main"
    git -C "$WORK" update-ref refs/remotes/alt/feature/from-linked-worktree refs/heads/feature/from-linked-worktree
    git -C "$WORK" update-ref refs/remotes/alt/feature/diverged "$BASE_COMMIT"
    git -C "$WORK" update-ref refs/remotes/alt/feature/stale-fetch refs/heads/feature/stale-fetch

    GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$GH_STUB_DIR"
    cat > "$GH_STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status")
    exit 0
    ;;
  "api repos/"*)
    echo main
    exit 0
    ;;
  "pr create")
    {
      printf 'pr:'
      printf ' %q' "$@"
      printf '\n'
    } > "$GH_LOG"
    echo "https://github.com/alt/project/pull/1"
    exit 0
    ;;
esac
echo "unexpected gh invocation: $*" >&2
exit 1
SH
    chmod +x "$GH_STUB_DIR/gh"
    export GH_LOG
    export PATH="$GH_STUB_DIR:$PATH"
}

@test "ws cr --remote selects an alternate fork remote" {
    run bash "$WS_BIN" cr yggdrasil --remote alt "test: alternate CR remote" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening CR for alt/project/feature/cr-remote-override"* ]]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
    [[ "$(cat "$GH_LOG")" == *"--head feature/cr-remote-override"* ]]
}

@test "GIT_CR_REMOTE selects an alternate fork remote" {
    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=alt bash "$2" "test: alternate CR remote" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening CR for alt/project/feature/cr-remote-override"* ]]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
    [[ "$(cat "$GH_LOG")" == *"--head feature/cr-remote-override"* ]]
}

@test "ws cr --source-branch submits a non-HEAD remote-tracked branch" {
    run bash "$WS_BIN" cr yggdrasil --remote alt --source-branch feature/from-linked-worktree "test: branch override" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening CR for alt/project/feature/from-linked-worktree"* ]]
    [[ "$(cat "$GH_LOG")" == *"--head feature/from-linked-worktree"* ]]
}

@test "ws cr --source-branch rejects a following option as the branch name" {
    run bash "$WS_BIN" cr yggdrasil --source-branch --upstream "test: invalid branch" .crs/body.md

    [ "$status" -ne 0 ]
    [[ "$output" == *"--source-branch requires a branch name"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --source-branch rejects an invalid branch name" {
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote alt --source-branch "bad..branch" "test: invalid branch" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid source branch 'bad..branch'"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --source-branch rejects a branch missing locally" {
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote alt --source-branch feature/missing-local "test: missing branch" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"source branch 'feature/missing-local' does not exist locally"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --source-branch rejects a branch absent from the selected remote" {
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote alt --source-branch feature/local-only "test: unpushed branch" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"source branch 'feature/local-only' is not known on remote 'alt'"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --source-branch rejects a stale remote-tracking branch" {
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote alt --source-branch feature/diverged "test: diverged branch" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"source branch 'feature/diverged' does not match remote 'alt'"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --source-branch surfaces a transport failure distinctly from a missing branch" {
    # A remote whose transport target doesn't exist: the guard must say
    # verification FAILED (connectivity/auth), not "push the branch".
    git -C "$WORK" remote add dead https://github.com/dead/project.git
    git -C "$WORK" config url."$BATS_TEST_TMPDIR/missing.git".insteadOf https://github.com/dead/project.git
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote dead --source-branch feature/diverged "test: transport failure" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"could not verify"* ]]
    [[ "$output" != *"is not known on remote"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --source-branch rejects a moved remote hidden by a stale tracking ref" {
    # The tracking ref equals the local tip (looks fresh), but the remote's
    # real branch has different content — only a live remote query catches it.
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote alt --source-branch feature/stale-fetch "test: stale fetch" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"source branch 'feature/stale-fetch' does not match remote 'alt'"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "ws cr --remote rejects a following option as the remote name" {
    run bash "$WS_BIN" cr yggdrasil --remote --upstream "test: invalid remote" .crs/body.md

    [ "$status" -ne 0 ]
    [[ "$output" == *"--remote requires a git remote name"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --remote rejects a following option as the remote name" {
    run bash -c 'cd "$1" || exit 1; bash "$2" --remote --upstream "test: invalid remote" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"--remote requires a git remote name"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "git-cr.sh --upstream refuses a same-provider cross-host token route" {
    # Re-create rather than set-url: the shared fixture gives alt a second URL,
    # and set-url refuses to modify a multi-valued remote.<name>.url.
    git -C "$WORK" remote remove alt
    git -C "$WORK" remote add alt https://github.enterprise.test/upstream/project.git
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
defaults:
  gitProviders:
    github.enterprise.test: github
components: {}
YAML

    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=fork bash "$2" --upstream "test: cross-host CR" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Cross-host CR creation is not supported"* ]]
    [[ "$output" == *"github.com"* ]]
    [[ "$output" == *"github.enterprise.test"* ]]
    [[ ! -f "$GH_LOG" ]]
}

# ─── stale-base preflight ───────────────────────────────────────────

# Advance the bare repo's main past the fixture branches from a scratch
# clone, so the moved tip's commit object does NOT exist in $WORK — this
# exercises the check's fetch-before-compare path as well as the compare.
_move_remote_main() {
    local scratch="$BATS_TEST_TMPDIR/mover"
    git clone -q "$ALT_BARE" "$scratch"
    git -C "$scratch" config user.name "Mover"
    git -C "$scratch" config user.email "mover@example.local"
    git -C "$scratch" checkout -q main
    echo moved > "$scratch/moved.txt"
    git -C "$scratch" add moved.txt
    git -C "$scratch" commit -q -m "someone else's merge"
    git -C "$scratch" push -q origin main
}

@test "stale-base: fresh target branch passes the preflight" {
    run bash "$WS_BIN" cr yggdrasil --remote alt "test: fresh base" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
}

@test "stale-base: moved target branch fails with a rebase pointer" {
    _move_remote_main

    run bash "$WS_BIN" cr yggdrasil --remote alt "test: moved base" .crs/body.md

    [ "$status" -ne 0 ]
    [[ "$output" == *"has moved"* ]]
    [[ "$output" == *"Rebase first"* ]]
    [[ "$output" == *"--stale-base-ok"* ]]
    [[ ! -f "$GH_LOG" ]]
}

@test "stale-base: --stale-base-ok submits against the moved base" {
    _move_remote_main

    run bash "$WS_BIN" cr yggdrasil --remote alt --stale-base-ok "test: stacked CR" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
}

@test "stale-base: GIT_CR_STALE_BASE_OK env form also skips the preflight" {
    _move_remote_main

    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=alt GIT_CR_STALE_BASE_OK=1 bash "$2" "test: stacked CR" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
}

@test "stale-base: --upstream path passes the preflight against a fresh upstream" {
    # fork remote = 'fork' (identity.forkRemote), so 'alt' is the detected
    # upstream — its bare-repo backing exercises the same preflight on the
    # cross-fork path.
    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=fork bash "$2" --upstream "test: upstream CR" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening cross-fork CR"* ]]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
}

@test "stale-base: --upstream path fails when the upstream default branch moved" {
    _move_remote_main

    run bash -c 'cd "$1" || exit 1; GIT_CR_REMOTE=fork bash "$2" --upstream "test: upstream CR" "$3"' bash "$WORK" "$GIT_CR_BIN" "$BODYFILE"

    [ "$status" -ne 0 ]
    [[ "$output" == *"has moved"* ]]
    [[ "$output" == *"--stale-base-ok"* ]]
    [[ ! -f "$GH_LOG" ]]
}
