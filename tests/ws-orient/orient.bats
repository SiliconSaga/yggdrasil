#!/usr/bin/env bats

# Tests for `ws orient` — the deterministic discovery menu (Phase 1,
# Task 4 of the GDD orientation + capability index arc).
#
# Task 4a scope (this file initially): scaffold + dispatch + header.
# Sub-steps 4b-4e bolt on additional assertions as those sections
# land:
#   4b — subcommand survey rows
#   4c — active realm detection
#   4d — per-component adapter enumeration with resolved-command surfacing
#   4e — skill index
#
# Reuses the ws-smoke test_helper so the dispatcher and timeout
# behavior match the rest of the smoke suite — `ws orient` is a
# read-only discovery command, same shape as `ws status` / `ws list`.

load ../ws-smoke/test_helper

setup() {
    init_workspace
}

# ─── 4a — scaffold + dispatch + header ─────────────────────────────

@test "ws orient: runs and prints a titled header" {
    run_ws orient
    [ "$status" -eq 0 ]
    # Header pins the literal command name in backticks so a future
    # rename surfaces here and forces the doc/help update alongside.
    [[ "$output" == *"Workspace toolset (\`ws orient\`)"* ]]
}

@test "ws orient: dispatcher routes the subcommand (no 'unknown command' error)" {
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unknown command"* ]]
    [[ "$output" != *"unknown command"* ]]
}

@test "ws orient: completes well under the smoke timeout (read-only)" {
    run_ws orient
    # 124 = `timeout` killed the process. Catches a future regression
    # where orient grows expensive (e.g. tree-walks every component).
    [ "$status" -ne 124 ]
}

# ─── 4b — subcommand survey ─────────────────────────────────────────

@test "ws orient: prints a subcommand survey with the 'use when' phrase" {
    run_ws orient
    [ "$status" -eq 0 ]
    # The plan specifies the 'use when' framing for each row — pin
    # the literal so a future cosmetic rephrase surfaces here first.
    [[ "$output" == *"use when"* ]]
}

@test "ws orient: subcommand survey lists the headline verbs (commit, test, lint, orient)" {
    # Plan-mandated rows (Task 4b assertions). Other rows live in
    # the authored survey table and can drift; these four are
    # pinned because they're the verbs the surrounding plan tasks
    # (5/6/7/8) revolve around.
    run_ws orient
    [ "$status" -eq 0 ]
    for verb in commit test lint orient; do
        [[ "$output" == *"$verb"* ]] || { echo "missing survey row: $verb"; return 1; }
    done
}
