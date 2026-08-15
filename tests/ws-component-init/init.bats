#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
COMPONENT_SCRIPT="$REPO_ROOT/scripts/ws-component.sh"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    ROOT_DIR="$WORK"
    TEMPLATES_DIR="$WORK/templates"
    COMPONENTS_DIR="$WORK/components"
    ECOSYSTEM="$WORK/ecosystem.yaml"
    ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"

    mkdir -p "$TEMPLATES_DIR/components" "$COMPONENTS_DIR"
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
}

run_component_init() {
    run env \
        ROOT_DIR="$ROOT_DIR" \
        TEMPLATES_DIR="$TEMPLATES_DIR" \
        COMPONENTS_DIR="$COMPONENTS_DIR" \
        ECOSYSTEM="$ECOSYSTEM" \
        ECOSYSTEM_LOCAL="$ECOSYSTEM_LOCAL" \
        bash "$COMPONENT_SCRIPT" init "$@"
}

@test "initializes a direct component template flavor" {
    mkdir -p "$TEMPLATES_DIR/components/basic"
    printf 'basic\n' > "$TEMPLATES_DIR/components/basic/README.md"

    run_component_init basic demo

    [ "$status" -eq 0 ]
    [ "$(cat "$COMPONENTS_DIR/demo/README.md")" = "basic" ]
    git -C "$COMPONENTS_DIR/demo" rev-parse --verify HEAD
}

@test "rejects a component flavor containing parent traversal" {
    mkdir -p "$TEMPLATES_DIR/outside"
    printf 'outside\n' > "$TEMPLATES_DIR/outside/README.md"

    run_component_init ../outside escaped

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component flavor '../outside'"* ]]
    [ ! -e "$COMPONENTS_DIR/escaped" ]
}

@test "rejects a component flavor symlinked outside the template root" {
    mkdir -p "$WORK/private-template"
    printf 'private\n' > "$WORK/private-template/README.md"
    ln -s "$WORK/private-template" "$TEMPLATES_DIR/components/linked" 2>/dev/null || true
    # MSYS without symlink support copies (exit 0) or errors — either way the
    # escape precondition cannot be constructed, so the assertion is vacuous.
    [[ -L "$TEMPLATES_DIR/components/linked" ]] || skip "real symlinks not supported on this platform"

    run_component_init linked escaped

    [ "$status" -ne 0 ]
    [[ "$output" == *"escapes the component template root"* ]]
    [ ! -e "$COMPONENTS_DIR/escaped" ]
}
