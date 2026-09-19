#!/usr/bin/env bats

# The change-note budget was stated in templates/commit.md and rendered by
# `ws orient` — two places nobody reads while writing a body — and bodies ran
# far over it. These pin the reminder that puts the number where the writing
# happens.
#
# Counted in WORDS. Prose here is never hard-wrapped, so a line is a paragraph of
# any length; a line budget passed three 90-word paragraphs as "3 lines".
#
# Advisory throughout: every test that expects a note also asserts success.

load test_helper

setup() {
    init_synthetic_repo
    # shellcheck source=../../scripts/ws-budget.sh
    source "$REPO_ROOT/scripts/ws-budget.sh"
}

set_style() {
    yq -i ".style.changeNotes = \"$1\"" "$ECOSYSTEM_LOCAL"
}

# words <n> → n space-separated words on one line.
words() {
    local i out=""
    for (( i = 0; i < $1; i++ )); do out+="word "; done
    printf '%s' "${out% }"
}

@test "terse budget notes a commit body past 50 words but still commits" {
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" "$(words 51)"

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"commit body is 51 words against a budget of 50"* ]]
    [[ "$output" == *"style.changeNotes: terse"* ]]
}

@test "a body at the terse budget says nothing" {
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" "$(words 50)"

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "one long paragraph is over budget even though it is a single line" {
    # The case a line count could not see.
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" "$(words 90)"

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"90 words against a budget of 50"* ]]
}

@test "standard is the fallback when no style is configured" {
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" "$(words 121)"

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"121 words against a budget of 120"* ]]
}

@test "detailed opts out of the reminder entirely" {
    set_style detailed
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" "$(words 400)"

    run_ws_commit yggdrasil "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" != *"against a budget"* ]]
}

@test "fenced blocks do not count toward the budget" {
    # Pasted output is evidence, not prose. Counting it would flag every commit
    # that quotes a failure and train the note into noise.
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" \
        "$(words 10)

\`\`\`
$(words 200)
\`\`\`"

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
    # Noting only on the real commit puts the feedback after the decision.
    set_style terse
    echo "changed" >> "$REPO_DIR/test.md"
    write_bodyfile "$REPO_DIR/body.md" "test: subject" "test.md" "$(words 51)"

    run_ws_commit yggdrasil --dry-run "$REPO_DIR/body.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"against a budget of 50"* ]]
}

@test "CR and issue bodies carry their own, larger budgets" {
    run ws_budget_note cr "$(words 121)" terse
    [ "$status" -eq 0 ]
    [[ "$output" == *"cr body is 121 words against a budget of 120"* ]]

    run ws_budget_note issue "$(words 151)" terse
    [ "$status" -eq 0 ]
    [[ "$output" == *"issue body is 151 words against a budget of 150"* ]]

    run ws_budget_note issue "$(words 300)" standard
    [ -z "$output" ]
}

@test "the attribution banner and headings are structure, not prose" {
    # A CR body is a banner blockquote plus headed sections; counting those would
    # charge every body for the template it was copied from.
    run ws_budget_note cr "> **AI-assisted change proposal.** $(words 40)

## Summary

$(words 120)" terse

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "an unrecognised style falls back to standard rather than silence" {
    run ws_budget_note commit "$(words 121)" rambling
    [ "$status" -eq 0 ]
    [[ "$output" == *"budget of 120 (style.changeNotes: standard)"* ]]
}
