#!/usr/bin/env bats

# Tests for ws-test's Gradle-adapter filter handling. A class-name selector is
# resolved on disk to its owning subproject. When that is the subproject the
# adapter already targets, the filtered run keeps the adapter's task (so a
# filtered run and a bare run answer the same question, under the same timeout
# and tag set) and cleans that task's own cache. A class owned by some other
# subproject falls back to the conventional :sub:test.

load test_helper

setup() {
    setup_synthetic_realm

    cat > "$ROOT_DIR/gradlew" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
EOF
    chmod +x "$ROOT_DIR/gradlew"

    mkdir -p "$ROOT_DIR/engine-tests/src/test/java/org/example"
    touch "$ROOT_DIR/engine-tests/src/test/java/org/example/FooTest.java"
    mkdir -p "$ROOT_DIR/other/src/test/java/org/example"
    touch "$ROOT_DIR/other/src/test/java/org/example/BarTest.java"
}

@test "gradle adapter: a filtered run keeps the adapter's task and cleans it" {
    write_adapter_test "./gradlew :engine-tests:unitTest"
    run_ws_test yggdrasil FooTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS::engine-tests:cleanUnitTest :engine-tests:unitTest --tests *.FooTest"* ]]
}

@test "gradle adapter: a conventional test task still pairs with cleanTest" {
    write_adapter_test "./gradlew :engine-tests:test"
    run_ws_test yggdrasil FooTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS::engine-tests:cleanTest :engine-tests:test --tests *.FooTest"* ]]
}

@test "gradle adapter: base flags survive alongside the adapter's task" {
    write_adapter_test "./gradlew --no-daemon :engine-tests:unitTest"
    run_ws_test yggdrasil FooTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:--no-daemon :engine-tests:cleanUnitTest :engine-tests:unitTest --tests *.FooTest"* ]]
}

@test "gradle adapter: a class in another subproject falls back to its :test task" {
    write_adapter_test "./gradlew :engine-tests:unitTest"
    run_ws_test yggdrasil BarTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS::other:cleanTest :other:test --tests *.BarTest"* ]]
}

@test "gradle adapter: --task names a sibling task for a filtered run" {
    write_adapter_test "./gradlew :engine-tests:unitTest"
    run_ws_test yggdrasil FooTest --task integrationTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS::engine-tests:cleanIntegrationTest :engine-tests:integrationTest --tests *.FooTest"* ]]
    [[ "$output" != *"--task"* ]]
}

@test "gradle adapter: --task=name applies to a class in another subproject" {
    write_adapter_test "./gradlew :engine-tests:unitTest"
    run_ws_test yggdrasil BarTest --task=integrationTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS::other:cleanIntegrationTest :other:integrationTest --tests *.BarTest"* ]]
}

@test "gradle adapter: --task without a filter swaps the adapter's task name" {
    write_adapter_test "./gradlew --no-daemon :engine-tests:unitTest"
    run_ws_test yggdrasil --task integrationTest
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:--no-daemon :engine-tests:integrationTest"* ]]
    [[ "$output" != *"unitTest"* ]]
}

@test "--task with no task name is refused before anything runs" {
    write_adapter_test "./gradlew :engine-tests:unitTest"
    run_ws_test yggdrasil FooTest --task
    [ "$status" -ne 0 ]
    [[ "$output" == *"--task needs a task name"* ]]
    [[ "$output" != *"ARGS:"* ]]
}

@test "--task is refused for a non-Gradle adapter" {
    write_adapter_test "./pytest"
    run_ws_test yggdrasil --task integrationTest
    [ "$status" -ne 0 ]
    [[ "$output" == *"--task is only supported for Gradle"* ]]
    [[ "$output" != *"ARGS:"* ]]
}

@test "gradle adapter: no filter runs the adapter command as written" {
    write_adapter_test "./gradlew :engine-tests:unitTest"
    run_ws_test yggdrasil
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS::engine-tests:unitTest"* ]]
    [[ "$output" != *"--tests"* ]]
}
