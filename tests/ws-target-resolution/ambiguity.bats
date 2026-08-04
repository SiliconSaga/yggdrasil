#!/usr/bin/env bats

load test_helper

setup() {
    init_workspace
}

@test "ws exec rejects a cloned hoard that shadows a cloned component" {
    declare_component widget
    clone_component widget
    create_hoard widget

    run_ws exec widget pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Ambiguous target name 'widget'"* ]]
    [[ "$output" == *"component"* ]]
    [[ "$output" == *"hoard"* ]]
    [[ "$output" != *"$HOARDS_DIR/widget"* ]]
}

@test "ws exec rejects a cloned hoard that shadows an uncloned declared component" {
    declare_component widget
    create_hoard widget

    run_ws exec widget pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"Ambiguous target name 'widget'"* ]]
    [[ "$output" == *"component"* ]]
    [[ "$output" == *"hoard"* ]]
}

@test "ws exec still resolves a unique declared component" {
    declare_component widget
    clone_component widget

    run_ws exec widget pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$COMPONENTS_DIR/widget"* ]]
}

@test "ws exec does not treat an unapproved realm declaration as component authority" {
    clone_component widget
    create_realm community
    cat > "$REALMS_DIR/community/ecosystem.yaml" <<'YAML'
components:
  widget:
    repo: https://example.invalid/realm-widget.git
YAML
    printf 'realm: community\n' > "$ECOSYSTEM_LOCAL"

    run_ws exec widget pwd

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust reapproval is required"* ]]
    [[ "$output" != *"$COMPONENTS_DIR/widget"* ]]
}

@test "ws exec still resolves a unique realm" {
    create_realm community

    run_ws exec community pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$REALMS_DIR/community"* ]]
}

@test "ws exec still resolves a unique hoard" {
    create_hoard notes

    run_ws exec notes pwd

    [ "$status" -eq 0 ]
    [[ "$output" == *"$HOARDS_DIR/notes"* ]]
}
