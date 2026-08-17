#!/usr/bin/env bats

# The sweep must never pull a repo nested inside a component. Those are
# independent upstreams whose checkout state the host project's own tooling
# manages, and moving one behind its back is how a working tree and a build go
# out of sync. Explicit single-target pulls stay available — that escape hatch
# is what the NOTE points at, so the note and the skip are tested together.
#
# ws-pull.sh derives ROOT_DIR from its own location rather than the environment,
# so the scripts are copied into the fixture workspace and run from there
# (matching trust.bats). Running $REPO_ROOT/scripts/ws-pull.sh directly would
# sweep the real workspace.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

seed_repo() {
    local bare="$1" author="$2"
    git init -q --bare "$bare"
    git clone -q "$bare" "$author" 2>/dev/null
    git -C "$author" config user.name "Test Author"
    git -C "$author" config user.email "author@example.test"
    printf 'seed\n' > "$author/README.md"
    git -C "$author" add README.md
    git -C "$author" commit -q -m "seed"
    git -C "$author" push -q -u origin HEAD
}

advance() {
    local author="$1"
    printf 'moved\n' >> "$author/README.md"
    git -C "$author" add README.md
    git -C "$author" commit -q -m "advance"
    git -C "$author" push -q origin HEAD
}

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    export ROOT_DIR="$WORK"
    export REALMS_DIR="$WORK/realms"
    export COMPONENTS_DIR="$WORK/components"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export WS_FOOTER_DISABLE=1

    mkdir -p "$WORK/scripts" "$REALMS_DIR" "$COMPONENTS_DIR" "$HOARDS_DIR"
    for script in ws-pull.sh ws-realm.sh ws-env.sh git-auth.sh git-remote.sh; do
        cp "$REPO_ROOT/scripts/$script" "$WORK/scripts/"
    done
    PULL_BIN="$WORK/scripts/ws-pull.sh"

    HOST_AUTHOR="$BATS_TEST_TMPDIR/host-author"
    NEST_AUTHOR="$BATS_TEST_TMPDIR/nest-author"
    seed_repo "$BATS_TEST_TMPDIR/host.git" "$HOST_AUTHOR"
    # The host ignores modules/ exactly as Terasology does. Without this the
    # nested clone leaves the host dirty and the sweep skips it, which would
    # make the "host still pulls" control pass for the wrong reason.
    printf 'modules/\n' > "$HOST_AUTHOR/.gitignore"
    git -C "$HOST_AUTHOR" add .gitignore
    git -C "$HOST_AUTHOR" commit -q -m "ignore modules"
    git -C "$HOST_AUTHOR" push -q origin HEAD
    seed_repo "$BATS_TEST_TMPDIR/nest.git" "$NEST_AUTHOR"

    git clone -q "$BATS_TEST_TMPDIR/host.git" "$COMPONENTS_DIR/terasology"
    git clone -q "$BATS_TEST_TMPDIR/nest.git" "$COMPONENTS_DIR/terasology/modules/Health"

    printf 'identity: {}\ncomponents: {}\n' > "$ECOSYSTEM"
    yq -i '.components.terasology = {"repo": "https://example.invalid/t.git"}' "$ECOSYSTEM"

    git init -q "$REALMS_DIR/community"
    mkdir -p "$REALMS_DIR/community/adapters"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    cat > "$REALMS_DIR/community/adapters/terasology.yaml" <<'YAML'
nested:
  - "modules/*"
YAML
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]
}

nested_head() {
    git -C "$COMPONENTS_DIR/terasology/modules/Health" rev-parse HEAD
}

host_head() {
    git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD
}

@test "the sweep pulls the host component but leaves its nested repo alone" {
    # Both remotes advance, so a sweep that pulled nothing at all cannot pass:
    # the host assertion is the control for the nested one.
    local nested_before host_before
    nested_before="$(nested_head)"
    host_before="$(host_head)"
    advance "$HOST_AUTHOR"
    advance "$NEST_AUTHOR"

    run bash "$PULL_BIN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL: terasology"* ]]
    [ "$(host_head)" != "$host_before" ]
    [ "$(nested_head)" = "$nested_before" ]
}

@test "the sweep names the nested repos it did not pull" {
    run bash "$PULL_BIN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTE: 1 nested repo(s) not pulled"* ]]
    [[ "$output" == *"ws pull terasology/<repo>"* ]]
}

@test "a component declaring no nesting gets no note" {
    yq -i '.components.plain = {"repo": "https://example.invalid/p.git"}' "$ECOSYSTEM"
    git clone -q "$BATS_TEST_TMPDIR/host.git" "$COMPONENTS_DIR/plain"

    run bash "$PULL_BIN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL: plain"* ]]
    [ "$(printf '%s\n' "$output" | grep -c 'nested repo(s) not pulled')" -eq 1 ]
}

@test "an explicit pull by bare repo name does move the nested repo" {
    local before
    before="$(nested_head)"
    advance "$NEST_AUTHOR"

    run bash "$PULL_BIN" terasology/Health

    [ "$status" -eq 0 ]
    [ "$(nested_head)" != "$before" ]
}

@test "an explicit pull by full relative path does move the nested repo" {
    local before
    before="$(nested_head)"
    advance "$NEST_AUTHOR"

    run bash "$PULL_BIN" terasology/modules/Health

    [ "$status" -eq 0 ]
    [ "$(nested_head)" != "$before" ]
}

@test "losing realm trust stops the sweep rather than widening it" {
    # Nested declarations are realm-supplied, so trust drift withdraws them. The
    # failure mode worth guarding is drift being read as "nothing declared,
    # therefore sweep everything".
    #
    # What actually happens is stronger: stale trust aborts the whole sweep with
    # a reapproval error, so nothing is pulled at all. Pinned as the real
    # contract — if a later change downgrades this to "carry on without the
    # declaration", the nested assertion below is what catches it.
    #
    # The drift has to be semantic: the trust fingerprint is canonical JSON of
    # the adapter's values, so a comment or a reformat is deliberately not drift.
    # The nested declaration itself is left intact, so the only thing withdrawing
    # it is the loss of trust.
    local nested_before host_before
    nested_before="$(nested_head)"
    host_before="$(host_head)"
    cat > "$REALMS_DIR/community/adapters/terasology.yaml" <<'YAML'
commands:
  test: "echo drifted"
nested:
  - "modules/*"
YAML
    advance "$HOST_AUTHOR"
    advance "$NEST_AUTHOR"

    run bash "$PULL_BIN"

    [ "$status" -ne 0 ]
    [[ "$output" == *"reapproval is required"* ]]
    [ "$(nested_head)" = "$nested_before" ]
    # The host too — an abort, not a partial sweep that skipped only the nested.
    [ "$(host_head)" = "$host_before" ]
}
