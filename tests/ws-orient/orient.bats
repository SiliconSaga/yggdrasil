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

# ─── 4c — active realm detection ────────────────────────────────────

@test "ws orient: prints 'Active realm: none' when no realm is present" {
    # init_workspace creates an empty realms/ directory, so the
    # detect helper returns empty. The empty case must still
    # produce a clear status line — silence would be ambiguous.
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm: none"* ]]
}

@test "ws orient: surfaces the active realm name when one is present" {
    # Drop a fixture realm; auto-detection picks the single
    # non-template realm-* directory under realms/.
    mkdir -p "$WORK/realms/realm-fixture"
    cat > "$WORK/realms/realm-fixture/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    cat > "$WORK/realms/realm-fixture/AGENTS.md" <<'MD'
# realm-fixture
MD
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm: realm-fixture"* ]]
    # Pointer to the realm's AGENTS.md so the agent can navigate
    # to the canonical realm guide without further discovery.
    [[ "$output" == *"AGENTS.md"* ]]
}

# ─── 4d — per-component adapters with resolved command ──────────────

# Helper: drop a fixture realm + a cloned component dir. Used by the
# adapter tests below so each test can opt into wiring an adapter
# (or not).
_seed_realm_and_component() {
    local comp="$1"
    mkdir -p "$WORK/realms/realm-fixture/adapters"
    cat > "$WORK/realms/realm-fixture/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    # .git as a real dir marks the component as cloned for orient's
    # enumeration. No actual git operations happen — orient is
    # read-only and never invokes git on the component.
    mkdir -p "$WORK/components/$comp/.git"
}

@test "ws orient: wired adapter surfaces 'ws test [runs: …]' with the resolved command" {
    _seed_realm_and_component knarrlike
    cat > "$WORK/realms/realm-fixture/adapters/knarrlike.yaml" <<'YAML'
commands:
  test: "python3 -m pytest --ignore=tests/features"
  lint: "python3 -m ruff check src/ tests/"
YAML
    run_ws orient
    [ "$status" -eq 0 ]
    # Adapter-trust mitigation per design § Adapter trust: the
    # executed command must be visible from `ws orient` output, not
    # hidden behind the ws wrapper. Pin both the `runs:` token and
    # the actual command tail so an agent can verify what fires.
    [[ "$output" == *"ws test"* ]]
    [[ "$output" == *"runs: python3 -m pytest --ignore=tests/features"* ]]
    [[ "$output" == *"ws lint"* ]]
    [[ "$output" == *"runs: python3 -m ruff check"* ]]
}

@test "ws orient: cloned component without an adapter prints the wire-it hint" {
    _seed_realm_and_component bareclone
    # No adapter file. The orient output should call this out
    # explicitly so the unwired state is discoverable, not silent.
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"bareclone"* ]]
    [[ "$output" == *"no test/lint adapter"* ]]
    [[ "$output" == *"realm-fixture/adapters/bareclone.yaml"* ]]
}

@test "ws orient: components section is present even when no clones exist" {
    # init_workspace alone — no components cloned. Section must
    # still be emitted with a clear "(no components cloned)"
    # status so agents can distinguish "section was rendered but
    # empty" from "section is missing because of a regression."
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Components"* ]]
    [[ "$output" == *"no components cloned"* ]]
}
