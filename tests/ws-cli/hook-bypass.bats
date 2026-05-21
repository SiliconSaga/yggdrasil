#!/usr/bin/env bats

# Tests for `ws hook-bypass <slug> [--reason "<text>"]`.
#
# The subcommand validates <slug> against [redirect-commands] entries
# in .claude/hooks/hook-rules, reads $CLAUDE_SESSION_ID, and writes
# .tmp/hook-bypass/<slug>.bypass with frontmatter.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ws-hook-bypass.sh"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/.claude/hooks"
    # Synthetic hook-rules with three slugs.
    cat > "$WORK/.claude/hooks/hook-rules" <<'EOF'
[redirect-commands]
git-commit   | git commit*    | Use ws commit
git-push     | git push*      | Use ws push
gh-pr-create | gh pr create*  | Use ws cr
EOF
    export PROJECT_ROOT="$WORK"
}

@test "valid slug + session id writes marker" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 0 ]
    [ -f "$WORK/.tmp/hook-bypass/git-commit.bypass" ]
    grep -q '^session_id: session-abc$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    grep -q '^slug: git-commit$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    grep -q '^reason: $' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "--reason populates the reason field" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" git-commit --reason "amend last commit"
    [ "$status" -eq 0 ]
    grep -q '^reason: amend last commit$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "unknown slug exits 1 with helpful message" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" not-a-slug
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown slug"* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"git-push"* ]]
    [[ "$output" == *"gh-pr-create"* ]]
    [ ! -d "$WORK/.tmp/hook-bypass" ]
}

@test "missing CLAUDE_SESSION_ID exits 1" {
    unset CLAUDE_SESSION_ID
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_SESSION_ID"* ]]
    [ ! -f "$WORK/.tmp/hook-bypass/git-commit.bypass" ]
}

@test ".tmp/hook-bypass/ auto-created if absent" {
    export CLAUDE_SESSION_ID="session-abc"
    [ ! -d "$WORK/.tmp/hook-bypass" ]
    run bash "$SCRIPT" git-push
    [ "$status" -eq 0 ]
    [ -d "$WORK/.tmp/hook-bypass" ]
    [ -f "$WORK/.tmp/hook-bypass/git-push.bypass" ]
}

@test "re-running same slug overwrites the marker" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT" git-commit --reason "first reason"
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" git-commit --reason "second reason"
    [ "$status" -eq 0 ]
    grep -q '^reason: second reason$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    ! grep -q '^reason: first reason$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--reason"* ]]
}

@test "-h is treated the same as --help" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no args prints usage and exits 1" {
    export CLAUDE_SESSION_ID="session-abc"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
