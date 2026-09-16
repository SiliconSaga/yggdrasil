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
