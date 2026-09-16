#!/usr/bin/env bats

# `ws gh` / `ws glab` take no target and run at the workspace root, so a
# subcommand that mutates the repo it stands in hits yggdrasil itself. The
# PreToolUse hook denies these for Claude Code; these tests cover the wrapper,
# which is what protects every other harness and a human's own terminal.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    export WS_FOOTER_DISABLE=1
    # A token so the guard is what fails, not the auth gate below it.
    export GH_TOKEN=test-token
    export GITLAB_TOKEN=test-token
}

@test "ws gh refuses pr checkout" {
    run bash "$WS_BIN" gh pr checkout 123

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
    [[ "$output" == *"ws exec <comp> gh pr checkout"* ]]
}

@test "ws gh refuses pr checkout even when --repo makes it look scoped" {
    run bash "$WS_BIN" gh pr checkout 5334 --repo MovingBlocks/Terasology

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws gh refuses pr checkout behind a short flag and extra args" {
    run bash "$WS_BIN" gh pr checkout 5334 -R MovingBlocks/Terasology --detach

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws gh refuses the co alias for pr checkout" {
    run bash "$WS_BIN" gh co 123

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws gh refuses pr co, the real alias gh ships" {
    run bash "$WS_BIN" gh pr co 123

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws gh refuses pr checkout when a value-taking option comes first" {
    # The scanner skipped anything starting with '-' and then took the next
    # word as the command group. A separated option value therefore became the
    # group, "pr" became the subcommand, and the guard matched nothing at all.
    run bash "$WS_BIN" gh --repo MovingBlocks/Terasology pr checkout 5334

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws gh still reads the command path when the option carries its own value" {
    # --repo=value keeps the value in the same word, so no lookahead is wanted;
    # this guards against the skip consuming a real command word.
    run bash "$WS_BIN" gh --repo=MovingBlocks/Terasology pr checkout 5334

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws gh refuses repo sync" {
    run bash "$WS_BIN" gh repo sync

    [ "$status" -ne 0 ]
    [[ "$output" == *"mutates the repo it runs in"* ]]
    [[ "$output" == *"ws pull"* ]]
}

@test "ws gh refuses repo clone" {
    run bash "$WS_BIN" gh repo clone MovingBlocks/Terasology

    [ "$status" -ne 0 ]
    [[ "$output" == *"clone into the workspace root"* ]]
    [[ "$output" == *"ws clone"* ]]
}

@test "ws gh does not block read-only pr subcommands" {
    run bash "$WS_BIN" gh pr view --help

    [ "$status" -eq 0 ]
    [[ "$output" != *"rewrites the working tree"* ]]
}

@test "ws gh does not block api calls" {
    run bash "$WS_BIN" gh api --help

    [ "$status" -eq 0 ]
    [[ "$output" != *"mutates the repo"* ]]
}

@test "ws glab refuses mr checkout when -R comes first" {
    # glab really does take -R at root level, so this is a spelling a person
    # would type rather than a contrived one.
    run bash "$WS_BIN" glab -R group/project mr checkout 42

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws glab refuses the mr co alias" {
    run bash "$WS_BIN" glab mr co 42

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
}

@test "ws glab refuses mr checkout" {
    run bash "$WS_BIN" glab mr checkout 12

    [ "$status" -ne 0 ]
    [[ "$output" == *"rewrites the working tree"* ]]
    [[ "$output" == *"ws exec <comp> glab mr checkout"* ]]
}

@test "ws glab refuses repo clone" {
    run bash "$WS_BIN" glab repo clone group/project

    [ "$status" -ne 0 ]
    [[ "$output" == *"clone into the workspace root"* ]]
}
