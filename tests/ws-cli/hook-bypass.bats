#!/usr/bin/env bats

# Tests for `ws hook-bypass <slug> [--reason "<text>"]`.
#
# The subcommand validates <slug> against [redirect-commands] entries
# in .claude/hooks/hook-rules, resolves the Claude Code session id
# (CLAUDE_CODE_SESSION_ID, falling back to CLAUDE_SESSION_ID), and
# writes .tmp/hook-bypass/<slug>.bypass with frontmatter.

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
    # Pin a deterministic session id. The REAL environment exports
    # CLAUDE_CODE_SESSION_ID (the live session UUID); override it with a
    # fixed test value and clear the CLAUDE_SESSION_ID fallback so the
    # script's resolution is predictable regardless of ambient env.
    export CLAUDE_CODE_SESSION_ID="session-abc"
    unset CLAUDE_SESSION_ID
}

@test "valid slug + session id writes marker" {
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 0 ]
    [ -f "$WORK/.tmp/hook-bypass/git-commit.bypass" ]
    grep -q '^session_id: session-abc$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    grep -q '^slug: git-commit$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
    grep -q '^reason: $' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "--reason populates the reason field" {
    run bash "$SCRIPT" git-commit --reason "amend last commit"
    [ "$status" -eq 0 ]
    grep -q '^reason: amend last commit$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "CLAUDE_SESSION_ID fallback is honored when CLAUDE_CODE_SESSION_ID is unset" {
    unset CLAUDE_CODE_SESSION_ID
    export CLAUDE_SESSION_ID="fallback-xyz"
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 0 ]
    grep -q '^session_id: fallback-xyz$' "$WORK/.tmp/hook-bypass/git-commit.bypass"
}

@test "unknown slug exits 1 with helpful message" {
    run bash "$SCRIPT" not-a-slug
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown slug"* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"git-push"* ]]
    [[ "$output" == *"gh-pr-create"* ]]
    [ ! -d "$WORK/.tmp/hook-bypass" ]
}

@test "missing session id exits 1" {
    unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_CODE_SESSION_ID"* ]]
    [ ! -f "$WORK/.tmp/hook-bypass/git-commit.bypass" ]
}

@test "built-in powershell slug is accepted without a hook-rules row" {
    run bash "$SCRIPT" powershell --reason "hook debugging"
    [ "$status" -eq 0 ]
    [ -f "$WORK/.tmp/hook-bypass/powershell.bypass" ]
    grep -q '^slug: powershell$' "$WORK/.tmp/hook-bypass/powershell.bypass"
    grep -q '^reason: hook debugging$' "$WORK/.tmp/hook-bypass/powershell.bypass"
}

@test "unknown-slug listing includes the built-in powershell slug" {
    run bash "$SCRIPT" not-a-slug
    [ "$status" -eq 1 ]
    [[ "$output" == *"powershell"* ]]
}

@test ".tmp/hook-bypass/ auto-created if absent" {
    [ ! -d "$WORK/.tmp/hook-bypass" ]
    run bash "$SCRIPT" git-push
    [ "$status" -eq 0 ]
    [ -d "$WORK/.tmp/hook-bypass" ]
    [ -f "$WORK/.tmp/hook-bypass/git-push.bypass" ]
}

@test "re-running same slug overwrites the marker" {
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
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "missing hook-rules file: any slug is unknown, no marker written" {
    rm -f "$WORK/.claude/hooks/hook-rules"
    run bash "$SCRIPT" git-commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown slug"* ]]
    [ ! -d "$WORK/.tmp/hook-bypass" ]
}

@test "adapter-redirect slugs are accepted (Tier 3 alongside Tier 2)" {
    # The Tier 3 [adapter-redirect-commands] deny message instructs
    # users to bypass via `ws hook-bypass <slug>`. The script must
    # accept those slugs too — otherwise the deny message tells users
    # to do something the script refuses to do. Pin the contract.
    cat > "$WORK/.claude/hooks/hook-rules" <<'EOF'
[redirect-commands]
git-commit          | git commit*    | Use ws commit

[adapter-redirect-commands]
adapter-redirect-pytest  | pytest*       | test
adapter-redirect-ruff    | ruff*         | lint
EOF
    run bash "$SCRIPT" adapter-redirect-pytest --reason "investigating raw pytest"
    [ "$status" -eq 0 ]
    [ -f "$WORK/.tmp/hook-bypass/adapter-redirect-pytest.bypass" ]
    grep -q '^slug: adapter-redirect-pytest$' "$WORK/.tmp/hook-bypass/adapter-redirect-pytest.bypass"
}

@test "unknown-slug error lists both [redirect-commands] and [adapter-redirect-commands] slugs" {
    # Make sure the helpful-message branch enumerates BOTH tiers so a
    # user typing an adapter-redirect slug close to but not matching
    # an entry sees its real cousins, not just the Tier 2 list.
    cat > "$WORK/.claude/hooks/hook-rules" <<'EOF'
[redirect-commands]
git-commit          | git commit*    | Use ws commit

[adapter-redirect-commands]
adapter-redirect-pytest  | pytest*       | test
EOF
    run bash "$SCRIPT" no-such-slug
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown slug"* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"adapter-redirect-pytest"* ]]
}
