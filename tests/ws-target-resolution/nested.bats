#!/usr/bin/env bats

load test_helper

setup() {
    init_workspace
}

@test "ws exec resolves a nested repo by bare name" {
    setup_nested_component

    run_ws exec terasology/Health pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$COMPONENTS_DIR/terasology/modules/Health"* ]]
}

@test "ws exec resolves a nested repo by full relative path" {
    setup_nested_component

    run_ws exec terasology/modules/Health pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$COMPONENTS_DIR/terasology/modules/Health"* ]]
}

@test "a nested name is allowed to be CamelCase where a component name is not" {
    setup_nested_component
    create_nested_repo terasology modules/WildAnimals

    run_ws exec terasology/WildAnimals pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$COMPONENTS_DIR/terasology/modules/WildAnimals"* ]]
}

@test "a directory without .git is not a nested target" {
    setup_nested_component
    mkdir -p "$COMPONENTS_DIR/terasology/modules/NotARepo"

    run_ws exec terasology/NotARepo pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"No nested repo 'NotARepo'"* ]]
}

@test "a bare name matching two nested repos is rejected as ambiguous" {
    setup_nested_component
    add_nested_glob terasology 'libs/*'
    create_nested_repo terasology libs/Health

    run_ws exec terasology/Health pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Ambiguous nested target 'terasology/Health'"* ]]
    [[ "$output" == *"modules/Health"* ]]
    [[ "$output" == *"libs/Health"* ]]
}

@test "an ambiguous bare name can be disambiguated by full path" {
    setup_nested_component
    add_nested_glob terasology 'libs/*'
    create_nested_repo terasology libs/Health

    run_ws exec terasology/libs/Health pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$COMPONENTS_DIR/terasology/libs/Health"* ]]
}

@test "a component without a nested declaration says how to add one" {
    declare_component terasology
    clone_component terasology
    mkdir -p "$COMPONENTS_DIR/terasology/modules/Health/.git"

    run_ws exec terasology/Health pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"does not declare nested repos"* ]]
    [[ "$output" == *"nested:"* ]]
}

@test "nested resolution is refused when the realm is not trusted" {
    setup_nested_component
    yq -i 'del(._gdd.realmTrust)' "$ECOSYSTEM_LOCAL"

    run_ws exec terasology/Health pwd

    [ "$status" -ne 0 ]
    [[ "$output" != *"$COMPONENTS_DIR/terasology/modules/Health"* ]]
}

@test "an undeclared host component is rejected before any path is touched" {
    setup_nested_component

    run_ws exec nosuchcomp/Health pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"no such target 'nosuchcomp'"* ]]
}

@test "traversal in the nested path is rejected" {
    setup_nested_component

    run_ws exec terasology/../../etc pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid nested path"* ]]
}

@test "an absolute-looking nested path is rejected" {
    setup_nested_component

    run_ws exec terasology//etc pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid nested path"* ]]
}

@test "a nested path with an embedded newline is rejected" {
    setup_nested_component

    run_ws exec "terasology/Health"$'\n'"evil" pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid nested path"* ]]
}

@test "an uppercase host component segment is rejected" {
    setup_nested_component

    run_ws exec Terasology/Health pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component 'Terasology'"* ]]
}

@test "a symlinked nested repo pointing outside the component is refused" {
    setup_nested_component
    mkdir -p "$BATS_TEST_TMPDIR/outside/Escapee/.git"
    if ! ln -s "$BATS_TEST_TMPDIR/outside/Escapee" "$COMPONENTS_DIR/terasology/modules/Escapee" 2>/dev/null; then
        skip "symlink creation unavailable"
    fi
    [ -L "$COMPONENTS_DIR/terasology/modules/Escapee" ] || skip "symlink created as a copy (MSYS copy-mode)"

    run_ws exec terasology/Escapee pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"resolves outside component"* ]]
}

@test "a nested glob that tries to climb out is rejected" {
    setup_nested_component
    NESTED_GLOB='../../*' yq -i '.nested = [strenv(NESTED_GLOB)]' \
        "$REALMS_DIR/community/adapters/terasology.yaml"
    approve_nested_realm

    run_ws exec terasology/Health pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid nested glob"* ]]
}

@test "plain component resolution is unaffected by nested support" {
    setup_nested_component

    run_ws exec terasology pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$COMPONENTS_DIR/terasology"* ]]
    [[ "$output" != *"modules"* ]]
}
