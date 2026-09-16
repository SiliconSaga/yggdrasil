#!/usr/bin/env bats

# The change-note budget was stated in templates/commit.md and rendered by
# `ws orient`, which is two places nobody is reading while writing a body.
# Bodies ran an order of magnitude over the configured terse budget for an
# entire session before anyone noticed. These pin the reminder that puts the
# number where the writing happens.
#
# Advisory throughout: every test that expects a warning also asserts the commit
# still succeeds. A wrapper that refused a long body would be worked around, not
# obeyed.

load test_helper

setup() {
    init_synthetic_repo
}

set_style() {
    yq -i ".style.changeNotes = \"$1\"" "$ECOSYSTEM_LOCAL"
}

@test "terse budget warns past three body lines but still commits" {
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.
Two.
Three.
Four."

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"4 lines against a budget of 3"* ]]
    [[ "$output" == *"style.changeNotes: terse"* ]]
}

@test "a body at the terse budget says nothing" {
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.
Two.
Three."

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "standard is the fallback when no style is configured" {
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.
Two.
Three.
Four.
Five.
Six.
Seven.
Eight.
Nine."

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"9 lines against a budget of 8"* ]]
}

@test "detailed opts out of the reminder entirely" {
    set_style detailed
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.
Two.
Three.
Four.
Five.
Six.
Seven.
Eight.
Nine.
Ten."

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "fenced blocks do not count toward the budget" {
    # Pasted output and failing commands are evidence, not prose. Counting them
    # would flag every commit that quotes a stack trace and train the reminder
    # into noise.
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.
Two.

\`\`\`
line one of output
line two of output
line three of output
line four of output
\`\`\`"

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "blank lines do not count toward the budget" {
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.

Two.

Three."

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "a subject-only commit is never flagged" {
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject only" "test.md" ""

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "the reminder also fires on a dry run" {
    # A dry run is where someone would still act on it — warning only on the
    # real commit means the feedback arrives after the decision.
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "One.
Two.
Three.
Four."

    run_ws_commit yggdrasil --dry-run "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"against a budget of 3"* ]]
}
