#!/usr/bin/env bats

load test_helper

setup() {
    init_workspace
}

@test "switches a component to an existing branch" {
    setup_component_repo
    git -C "$COMPONENTS_DIR/terasology" branch feature/x

    run_ws checkout terasology feature/x

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "feature/x" ]
}

@test "creates a branch with -b" {
    setup_component_repo

    run_ws checkout terasology feature/new -b

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "feature/new" ]
}

@test "--create is accepted as the long form of -b" {
    setup_component_repo

    run_ws checkout terasology feature/long --create

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "feature/long" ]
}

@test "switches a nested repo without touching its host" {
    setup_nested_component

    run_ws checkout terasology/modules/Cooking fix/recipes -b

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology/modules/Cooking")" = "fix/recipes" ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "main" ]
}

@test "refuses path-restore mode outright" {
    setup_component_repo
    printf 'edited\n' > "$COMPONENTS_DIR/terasology/seed.txt"

    run_ws checkout terasology -- seed.txt

    [ "$status" -ne 0 ]
    [[ "$output" == *"switches branches only"* ]]
    # The edit must survive: discarding it is the accident this refusal prevents.
    [ "$(cat "$COMPONENTS_DIR/terasology/seed.txt")" = "edited" ]
}

@test "requires both a target and a branch" {
    setup_component_repo

    run_ws checkout terasology

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a target and a branch"* ]]
}

@test "rejects an unknown option" {
    setup_component_repo

    run_ws checkout terasology main --force

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "rejects a branch name that looks like a path escape" {
    setup_component_repo

    run_ws checkout terasology ../evil -b

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid branch name"* ]]
}

@test "rejects extra positional arguments" {
    setup_component_repo

    run_ws checkout terasology main extra

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

@test "reports a missing branch instead of creating it" {
    setup_component_repo

    run_ws checkout terasology nope

    [ "$status" -ne 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "main" ]
}

@test "refuses an undeclared nested repo" {
    setup_nested_component

    run_ws checkout terasology/modules/Ghost main

    [ "$status" -ne 0 ]
}

@test "--help exits cleanly without needing a target" {
    run_ws checkout --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws checkout"* ]]
}

@test "--cr fetches a change request head into cr/<n> and switches to it" {
    setup_cr_fixture

    run_ws checkout terasology --cr 7

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "cr/7" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD)" = "$CR_SHA" ]
    [[ "$output" == *"change request #7 on origin, refs/pull/7/head"* ]]
}

@test "--pr and --mr are aliases of --cr" {
    setup_cr_fixture

    run_ws checkout terasology --pr 7
    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "cr/7" ]

    run_ws checkout terasology main
    run_ws checkout terasology --mr 7
    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "cr/7" ]
}

@test "--cr run again follows a moved change request" {
    setup_cr_fixture
    run_ws checkout terasology --cr 7
    [ "$status" -eq 0 ]
    publish_cr_head "$COMPONENTS_DIR/terasology" 7 "second change"

    run_ws checkout terasology --cr 7

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "cr/7" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD)" = "$CR_SHA" ]
}

@test "--cr works on a nested module repo" {
    setup_nested_cr_fixture

    run_ws checkout terasology/modules/Cooking --cr 3

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology/modules/Cooking")" = "cr/3" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology/modules/Cooking" rev-parse HEAD)" = "$CR_SHA" ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "main" ]
}

@test "--cr fetches a merge request ref from a GitLab remote" {
    setup_cr_fixture
    make_origin_gitlab "$COMPONENTS_DIR/terasology"
    publish_cr_head "$COMPONENTS_DIR/terasology" 9 "mr change" refs/merge-requests/9/head

    run_ws checkout terasology --cr 9

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "cr/9" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD)" = "$CR_SHA" ]
    [[ "$output" == *"refs/merge-requests/9/head"* ]]
}

@test "--cr fails when no remote carries the change request" {
    setup_cr_fixture

    run_ws checkout terasology --cr 99

    [ "$status" -ne 0 ]
    [[ "$output" == *"No remote"*"#99"* ]]
}

@test "--cr refuses a branch argument and -b" {
    setup_cr_fixture

    run_ws checkout terasology main --cr 7
    [ "$status" -ne 0 ]
    [[ "$output" == *"--cr takes no branch"* ]]

    run_ws checkout terasology --cr 7 -b
    [ "$status" -ne 0 ]
    [[ "$output" == *"--cr takes no branch"* ]]
}

@test "--cr rejects a remote name that starts with a dash" {
    setup_cr_fixture

    run_ws checkout terasology --cr 7 --remote -evil

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid remote name"* ]]
}

@test "--cr rejects a non-numeric number" {
    setup_cr_fixture

    run_ws checkout terasology --cr seven

    [ "$status" -ne 0 ]
    [[ "$output" == *"positive integer"* ]]
}
