#!/usr/bin/env bats

load test_helper

setup() {
    init_workspace
}

@test "detects develop as the trunk when there is no main or master" {
    setup_develop_component

    run_ws log app --oneline

    [ "$status" -eq 0 ]
    [[ "$output" == *"ahead of develop"* ]]
    [[ "$output" == *"first"* ]]
    [[ "$output" == *"second"* ]]
}

@test "still prefers main when both main and develop exist" {
    declare_component app
    make_repo "$COMPONENTS_DIR/app" main
    git_in "$COMPONENTS_DIR/app" branch develop
    git_in "$COMPONENTS_DIR/app" switch -q -c feature/x
    commit_in "$COMPONENTS_DIR/app" "only"

    run_ws log app --oneline

    [ "$status" -eq 0 ]
    [[ "$output" == *"ahead of main"* ]]
}

@test "--stat shows changed files" {
    setup_develop_component

    run_ws log app --stat

    [ "$status" -eq 0 ]
    [[ "$output" == *"work.txt"* ]]
}

@test "--against compares with an explicit ref" {
    setup_develop_component
    git_in "$COMPONENTS_DIR/app" tag baseline HEAD~1

    run_ws log app --oneline --against baseline

    [ "$status" -eq 0 ]
    [[ "$output" == *"ahead of baseline"* ]]
    [[ "$output" == *"second"* ]]
    [[ "$output" != *"first"* ]]
}

@test "--against rejects a ref that does not exist" {
    setup_develop_component

    run_ws log app --against nope

    [ "$status" -ne 0 ]
    [[ "$output" == *"nope"* ]]
}

@test "--incoming shows what the upstream has that we do not" {
    declare_component app
    make_repo "$BATS_TEST_TMPDIR/upstream" develop
    git clone -q "$BATS_TEST_TMPDIR/upstream" "$COMPONENTS_DIR/app"
    git -C "$COMPONENTS_DIR/app" config user.email "test@example.invalid"
    git -C "$COMPONENTS_DIR/app" config user.name "Test"
    commit_in "$BATS_TEST_TMPDIR/upstream" "landed elsewhere"
    git_in "$COMPONENTS_DIR/app" fetch -q origin

    run_ws log app --incoming --oneline

    [ "$status" -eq 0 ]
    [[ "$output" == *"landed elsewhere"* ]]
    [[ "$output" == *"incoming"* ]]
}

@test "--incoming reports nothing to pull when already current" {
    declare_component app
    make_repo "$BATS_TEST_TMPDIR/upstream" develop
    git clone -q "$BATS_TEST_TMPDIR/upstream" "$COMPONENTS_DIR/app"

    run_ws log app --incoming

    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing incoming"* ]]
}

@test "--incoming explains itself when the branch has no upstream" {
    setup_develop_component

    run_ws log app --incoming

    [ "$status" -ne 0 ]
    [[ "$output" == *"no upstream"* ]]
}

@test "--incoming and --against are refused together" {
    setup_develop_component

    run_ws log app --incoming --against develop

    [ "$status" -ne 0 ]
    [[ "$output" == *"--incoming"* ]]
}

@test "works against a nested repo" {
    declare_component terasology
    make_repo "$COMPONENTS_DIR/terasology" develop
    make_repo "$COMPONENTS_DIR/terasology/modules/Cooking" develop
    git_in "$COMPONENTS_DIR/terasology/modules/Cooking" switch -q -c fix/recipes
    commit_in "$COMPONENTS_DIR/terasology/modules/Cooking" "fix separators"

    mkdir -p "$REALMS_DIR/community/adapters" "$REALMS_DIR/community/.git"
    printf 'components: {}\n' > "$REALMS_DIR/community/ecosystem.yaml"
    printf 'nested:\n  - "modules/*"\n' > "$REALMS_DIR/community/adapters/terasology.yaml"
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"
    run bash "$WS_BIN" realm use --trust community
    [ "$status" -eq 0 ]

    run_ws log terasology/modules/Cooking --oneline

    [ "$status" -eq 0 ]
    [[ "$output" == *"fix separators"* ]]
}

@test "reports a clear error when no trunk can be found" {
    declare_component app
    make_repo "$COMPONENTS_DIR/app" wip
    git_in "$COMPONENTS_DIR/app" switch -q -c feature/x
    commit_in "$COMPONENTS_DIR/app" "only"

    run_ws log app

    [ "$status" -ne 0 ]
    [[ "$output" == *"--against"* ]]
}
