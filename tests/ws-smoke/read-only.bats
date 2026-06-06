#!/usr/bin/env bats

# Smoke tests for read-only ws subcommands. These run the actual
# commands (via the `ws` dispatcher) against a synthetic empty
# workspace. They verify two things at once:
#
#   1. The commands themselves still produce output and exit 0 —
#      catches regressions when the ws CLI evolves.
#   2. The commands complete quickly (10s timeout in run_ws) —
#      catches infinite-loop / hang regressions that would also
#      manifest as session stalls when the hook is active.

load test_helper

setup() {
    init_workspace
}

# ─── help variants ──────────────────────────────────────────────────

@test "ws help: exits 0 and prints usage" {
    run_ws help
    [ "$status" -eq 0 ]
    [[ "$output" == *"ws <command>"* ]]
}

@test "ws help: lists every dispatched subcommand from scripts/ws" {
    # Regression guard for the omission CodeRabbit caught on PR #88
    # (`orient` was wired into the dispatcher but absent from help)
    # AND the follow-up finding on PR #89 that a hard-pinned list
    # missed 11 dispatched commands. Derive the expected list from
    # the dispatcher's `case "$COMMAND" in` block so every new
    # subcommand auto-enrolls into the regression guard — no
    # hand-edit needed when adding one.
    #
    # Parsing rules: extract each label line (`    <name>)`), strip
    # whitespace + trailing `)`, split alias groups on `|`, keep
    # only bare lowercase-and-hyphen names (drops `*)`, `--help`,
    # `-h`, etc. — those are flag forms or fallbacks, not commands).
    local dispatched=() line label labels label_group
    while IFS= read -r line; do
        # Match "    <label-group>)" where label-group may contain
        # alias delimiters (`|`), wildcards (`*`), and hyphens.
        # The captured group strips leading whitespace + trailing
        # ) and beyond in one step — avoids the bash-${var## } trap
        # of stripping only a single literal space character.
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z*][a-zA-Z0-9_|*-]*)\) ]]; then
            label_group="${BASH_REMATCH[1]}"
            IFS='|' read -ra labels <<<"$label_group"
            for label in "${labels[@]}"; do
                # Bare lowercase-and-hyphen labels are dispatched
                # subcommands; everything else (`--help`, `-h`,
                # `*`) is a flag form / fallback.
                [[ "$label" =~ ^[a-z][a-z0-9-]*$ ]] && dispatched+=("$label")
            done
        fi
    done < <(awk '/^case .*COMMAND.* in/,/^esac/' "$WS_BIN")

    # Sanity: if the parser pulled nothing, the dispatcher's case
    # shape changed and this test silently became a no-op. Fail loud.
    [ "${#dispatched[@]}" -gt 0 ] || { echo "dispatch parser found no commands — case-block shape changed?"; return 1; }

    run_ws help
    [ "$status" -eq 0 ]
    for cmd in "${dispatched[@]}"; do
        [[ "$output" == *"$cmd"* ]] || { echo "missing in ws help: $cmd"; return 1; }
    done
}

@test "ws --help: exits 0 and prints usage" {
    run_ws --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"ws <command>"* ]]
}

@test "ws hoard --help: exits 0 (subcommand-level help)" {
    run_ws hoard --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"hoard"* ]]
}

# Consistency pin: top-level `ws` accepts `help`/`--help`/`-h` and
# rewrites `ws help <subcmd>` → `ws <subcmd> --help`. Subscripts
# (ws-hoard.sh, ws-realm.sh) should accept the same trio so a user
# typing `ws hoard help` lands on the help text instead of falling
# through to clone-from-URL handling. These tests pin that.

@test "ws hoard help: bare 'help' word works (consistency with top-level)" {
    run_ws hoard help
    [ "$status" -eq 0 ]
    [[ "$output" == *"hoard"* ]]
}

@test "ws help hoard: rewrite form works" {
    run_ws help hoard
    [ "$status" -eq 0 ]
    [[ "$output" == *"hoard"* ]]
}

@test "ws realm --help: exits 0 (subcommand-level help)" {
    run_ws realm --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"realm"* ]]
}

@test "ws realm help: bare 'help' word works" {
    run_ws realm help
    [ "$status" -eq 0 ]
    [[ "$output" == *"realm"* ]]
}

@test "ws commit --help: exits 0 and mentions bodyfile" {
    run_ws commit --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"bodyfile"* ]]
}

@test "ws push --help: exits 0 (per-subcommand help works)" {
    run_ws push --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"push"* ]]
}

@test "ws review --help: exits 0 (per-subcommand help works)" {
    run_ws review --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"review"* ]]
}

# ─── list (empty ecosystem) ─────────────────────────────────────────

@test "ws list: empty ecosystem produces deterministic output" {
    run_ws list
    [ "$status" -eq 0 ]
    # With no components declared, output should not error
    [[ "$output" != *"ERROR"* ]]
}

# ─── hoard list / scan ──────────────────────────────────────────────

@test "ws hoard list: empty hoards/ produces deterministic output" {
    run_ws hoard list
    [ "$status" -eq 0 ]
    [[ "$output" != *"ERROR"* ]]
}

@test "ws hoard scan --names-only: empty hoards/ produces no output" {
    run_ws hoard scan --names-only
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── timeout sanity ─────────────────────────────────────────────────
# Each test runs through `run_ws` which wraps with `timeout 10`. If a
# subcommand ever starts to stall (the hook's infinite-loop bug
# manifested this way before we added the prev-equals-dir guard), the
# test fails with exit 124 — clear and immediate signal.

@test "no smoke command times out" {
    # Run a handful of subcommands back-to-back, asserting none of
    # them hits the timeout (exit code 124).
    run_ws help
    [ "$status" -ne 124 ]
    run_ws list
    [ "$status" -ne 124 ]
    run_ws hoard --help
    [ "$status" -ne 124 ]
    run_ws hoard list
    [ "$status" -ne 124 ]
}
