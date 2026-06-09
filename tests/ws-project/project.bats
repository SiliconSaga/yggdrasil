#!/usr/bin/env bats
load test_helper

setup() { init_project_workspace; }

@test "ws project help lists status and build subcommands" {
    run_project help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"build"* ]]
}

@test "status errors when hoard does not exist" {
    run_project nonexistent status
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "status errors when hoard has no .project.yaml" {
    mkdir -p "$HOARDS_DIR/bare-hoard"
    run_project bare-hoard status
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a project hoard"* ]]
}

@test "status reports missing mandatory sections with exit 1" {
    make_project_hoard empty-project
    run_project empty-project status
    [ "$status" -ne 0 ]
    [[ "$output" == *"purpose-scope"* ]]
    [[ "$output" == *"MISSING"* ]]
    [[ "$output" == *"architecture"* ]]
}

@test "status reports present sections" {
    make_project_hoard full-project --with-mandatory
    run_project full-project status
    [ "$status" -eq 0 ]
    [[ "$output" == *"purpose-scope"* ]]
    [[ "$output" == *"architecture"* ]]
    [[ "$output" == *"present"* ]]
}

@test "status shows optional missing sections without failing" {
    make_project_hoard full-project --with-mandatory
    run_project full-project status
    [ "$status" -eq 0 ]
    [[ "$output" == *"design-alternatives"* ]]
    [[ "$output" == *"missing"* ]]
}

@test "build fails with exit 1 when mandatory sections are missing" {
    make_project_hoard incomplete-project
    run_project incomplete-project build
    [ "$status" -ne 0 ]
    [[ "$output" == *"mandatory"* ]]
}

@test "build succeeds and writes assembled.md when mandatory sections present" {
    make_project_hoard ok-project --with-mandatory
    run_project ok-project build
    [ "$status" -eq 0 ]
    [ -f "$HOARDS_DIR/ok-project/.build/assembled.md" ]
}

@test "build assembled.md contains doc-control block with project title" {
    make_project_hoard ok-project --with-mandatory
    run_project ok-project build
    [ "$status" -eq 0 ]
    grep -q "Test Project" "$HOARDS_DIR/ok-project/.build/assembled.md"
}

@test "build assembled.md contains content from mandatory section files in order" {
    make_project_hoard ok-project --with-mandatory
    run_project ok-project build
    assembled="$HOARDS_DIR/ok-project/.build/assembled.md"
    [ -f "$assembled" ]
    # purpose-scope should appear before architecture
    purpose_line=$(grep -n "This is the purpose" "$assembled" | cut -d: -f1)
    arch_line=$(grep -n "Main arch description" "$assembled" | cut -d: -f1)
    [ "$purpose_line" -lt "$arch_line" ]
}

@test "build skips files under working/" {
    make_project_hoard ok-project --with-mandatory
    cat > "$HOARDS_DIR/ok-project/working/scratch.md" <<'MD'
---
sadd_section: purpose-scope
---
# Should not appear
This should not be in the assembled doc.
MD
    run_project ok-project build
    [ "$status" -eq 0 ]
    run grep "Should not appear" "$HOARDS_DIR/ok-project/.build/assembled.md"
    [ "$status" -ne 0 ]
}
