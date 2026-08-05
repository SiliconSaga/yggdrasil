#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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
    REAL_TR="$(type -P tr)"
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
    if [[ "${GH_PR_CREATE_ADVERSARIAL_OUTPUT:-}" == "1" ]]; then
      printf 'provider printable diagnostic\n'
      printf 'provider controls: ESC\033[31mred\033[0m BEL\007 C1\302\23331mgreen\302\2330m\n'
      printf 'provider raw C1 controls: DCS\220\234 APC\237\234 PM\236\234 SOS\230\234\n'
      printf 'provider Unicode diagnostic: “quoted text”\n'
      printf 'selected: <https://github.com/alt/project/pull/1\033[0m\047\042>.\n'
      printf 'provider BEL hyperlink: \033]8;;https://github.com/alt/project/pull/999\007visible BEL link\033]8;;\007\n'
      printf 'provider ST hyperlink: \033]8;;https://github.com/alt/project/pull/998\033\\visible café ST link\033]8;;\033\\\n'
      printf 'provider UTF-8 C1 hyperlink: \302\2358;;https://github.com/alt/project/pull/997\302\234visible C1 link\302\2358;;\302\234\n'
      printf 'provider mixed C1 hyperlink: \2358;;https://github.com/alt/project/pull/996\033\\visible mixed C1 link\2358;;\033\\\n'
      printf 'provider ESC DCS: \033Phttps://github.com/alt/project/pull/990\033\\\n'
      printf 'provider raw DCS: \220https://github.com/alt/project/pull/989\234\n'
      printf 'provider UTF-8 DCS: \302\220https://github.com/alt/project/pull/988\302\234\n'
      printf 'provider ESC SOS: \033Xhttps://github.com/alt/project/pull/987\033\\\n'
      printf 'provider raw SOS: \230https://github.com/alt/project/pull/986\234\n'
      printf 'provider UTF-8 SOS: \302\230https://github.com/alt/project/pull/985\302\234\n'
      printf 'provider ESC PM: \033^https://github.com/alt/project/pull/984\033\\\n'
      printf 'provider raw PM: \236https://github.com/alt/project/pull/983\234\n'
      printf 'provider UTF-8 PM: \302\236https://github.com/alt/project/pull/982\302\234\n'
      printf 'provider ESC APC: \033_https://github.com/alt/project/pull/981\033\\\n'
      printf 'provider raw APC: \237https://github.com/alt/project/pull/980\234\n'
      printf 'provider UTF-8 APC: \302\237https://github.com/alt/project/pull/979\302\234\n'
      printf 'provider malformed UTF-8 before raw APC: \355\237xhttps://github.com/alt/project/pull/977\234\n'
      printf 'provider CSI to ESC OSC: \033[\033]8;;https://github.com/alt/project/pull/976\033\\\n'
      printf 'provider CSI to raw OSC: \033[\2358;;https://github.com/alt/project/pull/975\234\n'
      printf 'provider CSI to UTF-8 OSC: \033[\302\2358;;https://github.com/alt/project/pull/974\302\234\n'
      printf 'userinfo decoy: https://attacker.example@github.com/alt/project/pull/666\n'
      printf 'https://unrelated.example/not-the-created-pr\n'
      printf 'provider unterminated APC: \033_https://github.com/alt/project/pull/978\n'
    else
      echo "https://github.com/alt/project/pull/1"
    fi
    if [[ "${GH_PR_CREATE_ADVERSARIAL_STDERR:-}" == "1" ]]; then
      printf 'provider stderr printable diagnostic\n' >&2
      printf 'provider stderr controls: ESC\033[31mred\033[0m DCS\220 APC\237\n' >&2
      printf 'provider stderr hyperlink: \2358;;https://github.com/alt/project/pull/995\033\\visible stderr link\2358;;\033\\\n' >&2
    fi
    exit 0
    ;;
esac
echo "unexpected gh invocation: $*" >&2
exit 1
SH
    chmod +x "$GH_STUB_DIR/gh"
    export GH_LOG
    export REAL_TR
    export PATH="$GH_STUB_DIR:$PATH"
}

write_failing_iconv() {
    cat > "$GH_STUB_DIR/iconv" <<'SH'
#!/usr/bin/env bash
exit 127
SH
    chmod +x "$GH_STUB_DIR/iconv"
}

write_stderr_rejecting_tr() {
    cat > "$GH_STUB_DIR/tr" <<'SH'
#!/usr/bin/env bash
input="$(</dev/stdin)"
if [[ "$input" == *"provider stderr printable diagnostic"* ]]; then
    exit 70
fi
printf '%s' "$input" | "$REAL_TR" "$@"
SH
    chmod +x "$GH_STUB_DIR/tr"
}

@test "ws cr --remote selects an alternate fork remote" {
    run bash "$WS_BIN" cr yggdrasil --remote alt "test: alternate CR remote" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$output" == *"Opening CR for alt/project/feature/cr-remote-override"* ]]
    [[ "$(cat "$GH_LOG")" == *"--repo alt/project"* ]]
    [[ "$(cat "$GH_LOG")" == *"--head feature/cr-remote-override"* ]]
}

@test "ws cr sanitizes provider output and promotes only a selected-host URL" {
    export GH_PR_CREATE_ADVERSARIAL_OUTPUT=1
    run bash "$WS_BIN" cr yggdrasil --remote alt "test: safe CR output" .crs/body.md

    [ "$status" -eq 0 ]
    local esc bel c1_csi raw_dcs raw_apc failures=""
    esc="$(printf '\033')"
    bel="$(printf '\007')"
    c1_csi="$(printf '\302\233')"
    raw_dcs="$(printf '\220')"
    raw_apc="$(printf '\237')"
    [[ "$output" != *"$esc"* ]] || failures="${failures} ESC"
    [[ "$output" != *"$bel"* ]] || failures="${failures} BEL"
    [[ "$output" != *"$c1_csi"* ]] || failures="${failures} UTF-8-C1-CSI"
    [[ "$output" != *"$raw_dcs"* ]] || failures="${failures} raw-C1-DCS"
    [[ "$output" != *"$raw_apc"* ]] || failures="${failures} raw-C1-APC"
    [[ "$output" == *"provider printable diagnostic"* ]] || failures="${failures} printable-text-missing"
    [[ "$output" == *"provider Unicode diagnostic: “quoted text”"* ]] || failures="${failures} Unicode-text-missing"
    [[ "$output" == *"visible BEL link"* ]] || failures="${failures} BEL-link-label-missing"
    [[ "$output" == *"visible café ST link"* ]] || failures="${failures} Unicode-ST-link-label-missing"
    [[ "$output" == *"visible C1 link"* ]] || failures="${failures} C1-link-label-missing"
    [[ "$output" == *"visible mixed C1 link"* ]] || failures="${failures} mixed-C1-link-label-missing"
    [[ "$output" != *"[0m"* ]] || failures="${failures} SGR-remnant"
    [[ "$output" != *"]8;;"* ]] || failures="${failures} OSC-remnant"
    [[ "$output" != *"/pull/999"* ]] || failures="${failures} BEL-hidden-target-replayed"
    [[ "$output" != *"/pull/998"* ]] || failures="${failures} ST-hidden-target-replayed"
    [[ "$output" != *"/pull/997"* ]] || failures="${failures} C1-hidden-target-replayed"
    [[ "$output" != *"/pull/996"* ]] || failures="${failures} mixed-C1-hidden-target-replayed"
    local hidden_id
    for hidden_id in {974..990}; do
        [[ "$output" != *"/pull/$hidden_id"* ]] || failures="${failures} string-control-target-$hidden_id-replayed"
    done
    [[ "$output" == *"✓ CR ready: https://github.com/alt/project/pull/1" ]] || failures="${failures} clean-selected-host-URL-missing"
    [[ "$output" != *"✓ CR ready: https://github.com/alt/project/pull/1[0m)."* ]] || failures="${failures} decorated-URL-promoted"
    [[ "$output" != *"✓ CR ready: https://github.com/alt/project/pull/1)."* ]] || failures="${failures} trailing-punctuation-promoted"
    [[ "$output" != *"✓ CR ready: https://github.com/alt/project/pull/1'\">"* ]] || failures="${failures} closing-delimiters-promoted"
    [[ "$output" != *"✓ CR ready: https://attacker.example@github.com/alt/project/pull/666"* ]] || failures="${failures} userinfo-URL-promoted"
    [[ "$output" != *"✓ CR ready: https://unrelated.example/not-the-created-pr"* ]] || failures="${failures} unrelated-host-promoted"
    [[ -z "$failures" ]] || {
        printf 'unsafe provider-output behavior:%s\n' "$failures"
        printf '%s\n' "$output"
        false
    }
}

@test "ws cr sanitizes provider stderr without changing its stream" {
    export GH_PR_CREATE_ADVERSARIAL_STDERR=1
    run --separate-stderr bash "$WS_BIN" cr yggdrasil --remote alt "test: safe CR stderr" .crs/body.md

    [ "$status" -eq 0 ]
    local esc raw_dcs raw_apc failures=""
    esc="$(printf '\033')"
    raw_dcs="$(printf '\220')"
    raw_apc="$(printf '\237')"
    [[ "$stderr" != *"$esc"* ]] || failures="${failures} stderr-ESC"
    [[ "$stderr" != *"$raw_dcs"* ]] || failures="${failures} stderr-raw-C1-DCS"
    [[ "$stderr" != *"$raw_apc"* ]] || failures="${failures} stderr-raw-C1-APC"
    [[ "$stderr" == *"provider stderr printable diagnostic"* ]] || failures="${failures} stderr-printable-text-missing"
    [[ "$stderr" == *"visible stderr link"* ]] || failures="${failures} stderr-link-label-missing"
    [[ "$stderr" != *"[0m"* ]] || failures="${failures} stderr-SGR-remnant"
    [[ "$stderr" != *"]8;;"* ]] || failures="${failures} stderr-OSC-remnant"
    [[ "$stderr" != *"/pull/995"* ]] || failures="${failures} stderr-hidden-target-replayed"
    [[ "$output" == *"✓ CR ready: https://github.com/alt/project/pull/1"* ]] || failures="${failures} stdout-ready-URL-missing"
    [[ "$output" != *"provider stderr printable diagnostic"* ]] || failures="${failures} stderr-replayed-on-stdout"
    [[ -z "$failures" ]] || {
        printf 'unsafe provider-stderr behavior:%s\n' "$failures"
        printf 'stdout:\n%s\nstderr:\n%s\n' "$output" "$stderr"
        false
    }
}

@test "ws cr preserves safe ASCII provider output when iconv is unavailable" {
    write_failing_iconv
    export GH_PR_CREATE_ADVERSARIAL_OUTPUT=1

    run bash "$WS_BIN" cr yggdrasil --remote alt "test: safe CR fallback" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$output" == *"provider printable diagnostic"* ]]
    [[ "$output" == *"provider Unicode diagnostic: quoted text"* ]]
    [[ "$output" != *"“"* ]]
    [[ "$output" != *"”"* ]]
    [[ "$output" == *"✓ CR ready: https://github.com/alt/project/pull/1"* ]]
}

@test "ws cr preserves safe stdout and its URL when stderr sanitization fails" {
    write_stderr_rejecting_tr
    export GH_PR_CREATE_ADVERSARIAL_STDERR=1

    run --separate-stderr bash "$WS_BIN" cr yggdrasil --remote alt "test: partial sanitizer failure" .crs/body.md

    [ "$status" -eq 0 ]
    [[ "$output" == *"https://github.com/alt/project/pull/1"* ]]
    [[ "$output" == *"✓ CR ready: https://github.com/alt/project/pull/1"* ]]
    [[ "$stderr" == *"Provider stderr could not be sanitized and was not replayed"* ]]
    [[ "$stderr" != *"provider stderr printable diagnostic"* ]]
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

@test "stale-base: missing target branch fails closed before CR creation" {
    git -C "$ALT_BARE" update-ref -d refs/heads/main

    run bash "$WS_BIN" cr yggdrasil --remote alt "test: missing base" .crs/body.md

    [ "$status" -ne 0 ]
    [[ "$output" == *"target branch 'main' is not known on remote 'alt'"* ]]
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
