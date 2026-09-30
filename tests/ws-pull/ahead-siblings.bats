#!/usr/bin/env bats
#
# Regression cover for the failure that let a release get cut from stale source:
# a fork-cloned component tracks its FORK, so `ws pull` follows the fork and
# reports "Already up to date" while the canonical upstream sits ahead. The
# checkout looks current and isn't.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    UPSTREAM="$BATS_TEST_TMPDIR/upstream.git"
    FORK="$BATS_TEST_TMPDIR/fork.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    export ROOT_DIR="$WORK"
    export REALMS_DIR="$WORK/realms"
    export COMPONENTS_DIR="$WORK/components"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    mkdir -p "$WORK/scripts" "$REALMS_DIR" "$COMPONENTS_DIR" "$HOARDS_DIR"
    cp "$REPO_ROOT/scripts/ws-pull.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"
    PULL_BIN="$WORK/scripts/ws-pull.sh"
    printf 'components:\n  app:\n    repo: %s\n' "$UPSTREAM" > "$ECOSYSTEM"
    printf 'notes: keep\n' > "$ECOSYSTEM_LOCAL"

    # Seed a canonical repo, then a fork of it at the same commit. -b main: the
    # tracking setup below names the branch, so it must not depend on the
    # host's init.defaultBranch (unset on CI runners, arbitrary elsewhere).
    git init -q -b main "$SEED"
    git -C "$SEED" config user.name "Test Author"
    git -C "$SEED" config user.email "author@example.test"
    printf 'v1\n' > "$SEED/app.txt"
    git -C "$SEED" add app.txt
    git -C "$SEED" commit -q -m "seed"
    git clone -q --bare "$SEED" "$UPSTREAM"
    git clone -q --bare "$SEED" "$FORK"
    git -C "$SEED" remote add upstream "$UPSTREAM"

    # Clone the FORK — this is what ws clone-fork produces, so local main
    # tracks the fork and the canonical remote is a second, untracked remote.
    git clone -q "$FORK" "$COMPONENTS_DIR/app"
    git -C "$COMPONENTS_DIR/app" remote rename origin fork
    git -C "$COMPONENTS_DIR/app" remote add canonical "$UPSTREAM"
    git -C "$COMPONENTS_DIR/app" config user.name "Test User"
    git -C "$COMPONENTS_DIR/app" config user.email "user@example.test"
    git -C "$COMPONENTS_DIR/app" branch --set-upstream-to=fork/main main
}

advance_upstream() {
    printf '%s\n' "$1" > "$SEED/app.txt"
    git -C "$SEED" add app.txt
    git -C "$SEED" commit -q -m "$1"
    git -C "$SEED" push -q upstream HEAD
}

@test "pull highlights a canonical remote that is ahead of the tracked fork" {
    advance_upstream "v2"

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    # The pull itself legitimately succeeds against the fork...
    [[ "$output" == *"PULL: app"* ]]
    # ...but the untracked canonical remote must be surfaced.
    [[ "$output" == *"AHEAD: canonical/"* ]]
    [[ "$output" == *"1 commit(s) ahead"* ]]
    [[ "$output" == *"ws clone-fork app"* ]]
}

@test "pull counts multiple commits the canonical remote is ahead by" {
    advance_upstream "v2"
    advance_upstream "v3"

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" == *"2 commit(s) ahead"* ]]
}

@test "pull stays quiet when the canonical remote matches the tracked fork" {
    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL: app"* ]]
    [[ "$output" != *"AHEAD:"* ]]
}

@test "pull stays quiet when the fork is ahead of canonical" {
    # The ordinary in-progress case: local work pushed to the fork only.
    printf 'local\n' > "$COMPONENTS_DIR/app/app.txt"
    git -C "$COMPONENTS_DIR/app" add app.txt
    git -C "$COMPONENTS_DIR/app" commit -q -m "local work"
    git -C "$COMPONENTS_DIR/app" push -q fork HEAD

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" != *"AHEAD:"* ]]
}

@test "an unreachable extra remote does not fail the pull" {
    git -C "$COMPONENTS_DIR/app" remote add broken "$BATS_TEST_TMPDIR/does-not-exist.git"
    advance_upstream "v2"

    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [[ "$output" == *"AHEAD: canonical/"* ]]
}

@test "a sibling remote using helper syntax is skipped without running the helper" {
    # `<name>::<address>` makes git exec git-remote-<name> from PATH. Every
    # other ws URL sink refuses that shape before git sees it; the advisory
    # fetch must too, since it reaches remotes ws never vetted.
    mkdir -p "$WORK/bin"
    printf '#!/usr/bin/env bash\ntouch "%s/helper-ran"\nexit 1\n' "$BATS_TEST_TMPDIR" > "$WORK/bin/git-remote-marker"
    chmod +x "$WORK/bin/git-remote-marker"
    git -C "$COMPONENTS_DIR/app" remote add helper "marker::anything"
    advance_upstream "v2"

    export PATH="$WORK/bin:$PATH"
    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/helper-ran" ]
    # Skipping one remote does not silence the check for the rest.
    [[ "$output" == *"AHEAD: canonical/"* ]]
}

@test "a sibling remote whose vcs setting names a helper is fetched by URL, not through the helper" {
    # remote.<name>.vcs routes every fetch of that remote NAME through
    # git-remote-<vcs>, whatever the URL says. Fetching the validated URL
    # directly sidesteps the setting; the refspec still updates the named
    # remote-tracking ref, so the comparison and the message are unchanged.
    mkdir -p "$WORK/bin"
    printf '#!/usr/bin/env bash\ntouch "%s/helper-ran"\nexit 1\n' "$BATS_TEST_TMPDIR" > "$WORK/bin/git-remote-marker"
    chmod +x "$WORK/bin/git-remote-marker"
    git -C "$COMPONENTS_DIR/app" config remote.canonical.vcs marker
    advance_upstream "v2"

    export PATH="$WORK/bin:$PATH"
    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/helper-ran" ]
    [[ "$output" == *"AHEAD: canonical/"* ]]
}

@test "the sibling fetch has every credential prompt path closed" {
    # A private or SSH sibling must be skipped, never waited on: the pull it
    # follows already succeeded. This shim replaces git on PATH, records the
    # prompt-controlling environment the sibling fetch is handed, and fails the
    # way an unauthenticated fetch does. Only direct `git fetch` calls hit it;
    # the pull's own internal fetch runs from git's exec path.
    mkdir -p "$WORK/bin"
    local real_git
    real_git="$(command -v git)"
    cat > "$WORK/bin/git" <<BASH
#!/usr/bin/env bash
for arg in "\$@"; do
    if [[ "\$arg" == "fetch" ]]; then
        {
            echo "GIT_TERMINAL_PROMPT=\${GIT_TERMINAL_PROMPT-unset}"
            echo "GIT_ASKPASS=\${GIT_ASKPASS-unset}"
            echo "GCM_INTERACTIVE=\${GCM_INTERACTIVE-unset}"
            echo "GIT_SSH_COMMAND=\${GIT_SSH_COMMAND-unset}"
            echo "GIT_CONFIG_KEY_0=\${GIT_CONFIG_KEY_0-unset}"
            echo "GIT_CONFIG_VALUE_0=\${GIT_CONFIG_VALUE_0-unset}"
        } > "$WORK/fetch-env.txt"
        exit 1
    fi
done
exec "$real_git" "\$@"
BASH
    chmod +x "$WORK/bin/git"

    export PATH="$WORK/bin:$PATH"
    export GIT_ASKPASS="$WORK/bin/gui-askpass"
    run bash "$PULL_BIN" app

    [ "$status" -eq 0 ]
    [ -f "$WORK/fetch-env.txt" ]
    grep -qx 'GIT_TERMINAL_PROMPT=0' "$WORK/fetch-env.txt"
    grep -qx 'GIT_ASKPASS=' "$WORK/fetch-env.txt"
    grep -qx 'GCM_INTERACTIVE=never' "$WORK/fetch-env.txt"
    grep -qx 'GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' "$WORK/fetch-env.txt"
    # No token resolves for a filesystem remote, so this is the tokenless path:
    # the credential helper must still be blanked, or a custom one can prompt.
    grep -qx 'GIT_CONFIG_KEY_0=credential.helper' "$WORK/fetch-env.txt"
    grep -qx 'GIT_CONFIG_VALUE_0=' "$WORK/fetch-env.txt"
}
