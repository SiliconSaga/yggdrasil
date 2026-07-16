#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    AUTHOR="$BATS_TEST_TMPDIR/realm-author"
    REMOTE="$BATS_TEST_TMPDIR/realm-remote.git"
    export ROOT_DIR="$WORK"
    export REALMS_DIR="$WORK/realms"
    export COMPONENTS_DIR="$WORK/components"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    mkdir -p "$WORK/scripts" "$REALMS_DIR" "$COMPONENTS_DIR/app" "$HOARDS_DIR"
    cp "$REPO_ROOT/scripts/ws-pull.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"
    PULL_BIN="$WORK/scripts/ws-pull.sh"
    printf 'components: {}\n' > "$ECOSYSTEM"
    printf 'notes: keep\n' > "$ECOSYSTEM_LOCAL"

    git init -q "$AUTHOR"
    git -C "$AUTHOR" config user.name "Test Author"
    git -C "$AUTHOR" config user.email "author@example.test"
    mkdir -p "$AUTHOR/adapters" "$AUTHOR/tools"
    printf 'components: {}\n' > "$AUTHOR/ecosystem.yaml"
    printf 'commands:\n  test: bash "../../realms/realm.test/tools/run-tests.sh"\n' > "$AUTHOR/adapters/app.yaml"
    printf '#!/usr/bin/env bash\necho original\n' > "$AUTHOR/tools/run-tests.sh"
    printf 'realm documentation\n' > "$AUTHOR/README.md"
    git -C "$AUTHOR" add ecosystem.yaml adapters/app.yaml tools/run-tests.sh README.md
    git -C "$AUTHOR" commit -q -m "seed realm"
    git clone -q --bare "$AUTHOR" "$REMOTE"
    git -C "$AUTHOR" remote add origin "$REMOTE"
    git clone -q "$REMOTE" "$REALMS_DIR/realm.test"

    run bash "$WS_BIN" realm use --trust realm.test
    [ "$status" -eq 0 ]
}

push_realm_change() {
    git -C "$AUTHOR" add "$@"
    git -C "$AUTHOR" commit -q -m "update realm"
    git -C "$AUTHOR" push -q origin HEAD
}

@test "pull reports when active realm trust inputs changed" {
    printf 'commands:\n  test: uv run pytest -q\n' > "$AUTHOR/adapters/app.yaml"
    push_realm_change adapters/app.yaml

    run bash "$PULL_BIN" realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"reapproval"* ]]
    [[ "$output" == *"ws realm use realm.test"* ]]
}

@test "direct realm pull remains available when trust is already stale" {
    printf 'commands:\n  test: uv run pytest -q\n' > "$AUTHOR/adapters/app.yaml"
    push_realm_change adapters/app.yaml
    git -C "$REALMS_DIR/realm.test" pull -q --rebase

    run bash "$PULL_BIN" realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"reapproval"* ]]
}

@test "pulling documentation-only realm changes does not require reapproval" {
    printf 'expanded realm documentation\n' > "$AUTHOR/README.md"
    push_realm_change README.md

    run bash "$PULL_BIN" realm.test

    [ "$status" -eq 0 ]
    [[ "$output" != *"reapproval"* ]]
}

@test "pull reports when an adapter-referenced realm file changes" {
    printf '#!/usr/bin/env bash\necho changed\n' > "$AUTHOR/tools/run-tests.sh"
    push_realm_change tools/run-tests.sh

    run bash "$PULL_BIN" realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"reapproval"* ]]
    [[ "$output" == *"ws realm use realm.test"* ]]
}
