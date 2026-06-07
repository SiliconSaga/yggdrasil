#!/usr/bin/env bats

# Smoke tests for the yggdrasil shell-test pipeline.
#
# Kept at top-level (not under tests/<topic>/) so newcomers' first
# read of the test tree finds it immediately as a sanity check —
# topic suites live in tests/ws-hoard-scan/, tests/ws-hoard-init/, etc.
#
# These exist solely to prove that bats is wired up and that
# `bash scripts/ws test yggdrasil` discovers and runs *.bats files
# in the workspace tests/ directory. Real test coverage lives in
# topic-specific files alongside this one (Phase A.3 onward).

@test "bats is wired up and can run a trivial assertion" {
    run echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "ws CLI is on disk and prints help" {
    run bash "${BATS_TEST_DIRNAME}/../scripts/ws" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ─── AGENTS.md L0 contract (Task 7 of gdd-orientation-capability-index) ─

# AGENTS.md is the L0 layer of the progressive-disclosure buffet:
# slim utilities menu + reflex contract + hard pointer at the
# orientation skill. Deeper content (skills table, full workspace
# CLI, code style, etc.) is discoverable via `ws orient` + per-
# subcommand `--help` rather than inline. These tests pin the
# load-bearing markers so a future edit that loses them surfaces
# here first.

@test "AGENTS.md exists at the workspace root" {
    [ -f "${BATS_TEST_DIRNAME}/../AGENTS.md" ]
}

@test "AGENTS.md carries the reflex contract marker" {
    # The reflex contract is the heart of L0 — it's what agents
    # consult mid-session before reaching for raw git/gh/glab.
    # Pin both the section heading and a representative verb so a
    # rename surfaces this test.
    local agents="${BATS_TEST_DIRNAME}/../AGENTS.md"
    grep -q "Reflex Contract" "$agents"
    grep -q "ws commit" "$agents"
    grep -q "ws push" "$agents"
}

@test "AGENTS.md points at the orientation skill" {
    # The single hard pointer to gdd-orientation is the only
    # session-start reach AGENTS.md mandates. If this line ever
    # drops, agents miss the orientation flow entirely.
    grep -q ".agent/skills/gdd-orientation/SKILL.md" "${BATS_TEST_DIRNAME}/../AGENTS.md"
}

@test "AGENTS.md points at ws orient as the discovery surface" {
    # ws orient is the L1 of the buffet — the deterministic menu
    # agents fall back to mid-session when not sure what verbs /
    # adapters / skills exist. AGENTS.md must surface it as the
    # discovery surface so the L0→L1 transition is explicit.
    grep -q "ws orient" "${BATS_TEST_DIRNAME}/../AGENTS.md"
}

@test "AGENTS.md mandates ws orient at session start (MUST language)" {
    # Pin the firmer session-start directive: agents must EXECUTE
    # `ws orient` on every fresh dispatch, not treat it as a loose
    # discovery aid. The MUST keyword + Execute pair surfaces in
    # the Session Start block and again in Operational Rules.
    local agents="${BATS_TEST_DIRNAME}/../AGENTS.md"
    grep -q "MUST" "$agents"
    grep -q "Execute \`ws orient\`" "$agents"
}
