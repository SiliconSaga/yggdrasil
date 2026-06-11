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
    # Regression guard: subcommands wired into the dispatcher must
    # also appear in `ws help`, and the expected list must stay in
    # sync with what's actually dispatched. Derive the expected list
    # from the dispatcher's `case "$COMMAND" in` block so every new
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
    # Match space-delimited so `clone` doesn't false-positive on
    # `clone-fork` (which would silently pass without the bracket).
    # The help block format always puts the command between leading indent
    # whitespace and either an argument hint or an aligned
    # description — both shapes carry a trailing space after the
    # command token.
    for cmd in "${dispatched[@]}"; do
        [[ "$output" == *" $cmd "* ]] || { echo "missing in ws help: $cmd"; return 1; }
    done
}

@test "ws --help: exits 0 and prints usage" {
    run_ws --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"ws <command>"* ]]
}

# ─── command-output footer ──────────────────────────────────────────

# The footer is a one-line stderr nudge appended after every
# successful `ws` subcommand dispatch — keeps the `ws orient` meta-
# rule discoverable mid-session without requiring agents to memorize
# it. Suppressed for `orient` itself (no recursive recommendation),
# for the help command, for any subcommand's --help variant, and via
# `WS_FOOTER_DISABLE=1`. Stderr so it never contaminates captured
# stdout (e.g. `commit=$(ws log --oneline)`).

# Footer suppresses automatically when `BATS_TEST_NAME` is set so
# the rest of the bats suite isn't disrupted by the stderr line.
# These footer-focused tests opt back in by unsetting that env var
# for the child process (`env -u BATS_TEST_NAME …`) so we can
# verify the user-facing behavior.

@test "ws status: footer prints to stderr after dispatch" {
    run bash -c "env -u BATS_TEST_NAME $TIMEOUT_BIN 10 bash $WS_BIN status 2>$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    local stderr_content
    stderr_content="$(cat "$BATS_TEST_TMPDIR/stderr.txt")"
    [[ "$stderr_content" == *"ws orient"* ]]
    [[ "$stderr_content" == *"switching tasks"* ]]
}

@test "ws status: footer stays out of stdout" {
    # Capture-output is a common pattern (var=\$(ws list)); a footer
    # on stdout would contaminate that. Pin the separation.
    run bash -c "env -u BATS_TEST_NAME $TIMEOUT_BIN 10 bash $WS_BIN status 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" != *"switching tasks"* ]]
}

@test "ws orient: footer does NOT fire (no recursive self-recommend)" {
    run bash -c "env -u BATS_TEST_NAME $TIMEOUT_BIN 10 bash $WS_BIN orient 2>$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/stderr.txt")" != *"switching tasks"* ]]
}

@test "ws help: footer does NOT fire on the help command itself" {
    run bash -c "env -u BATS_TEST_NAME $TIMEOUT_BIN 10 bash $WS_BIN help 2>$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/stderr.txt")" != *"switching tasks"* ]]
}

@test "ws hoard --help: footer does NOT fire on subcommand help" {
    run bash -c "env -u BATS_TEST_NAME $TIMEOUT_BIN 10 bash $WS_BIN hoard --help 2>$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/stderr.txt")" != *"switching tasks"* ]]
}

@test "WS_FOOTER_DISABLE=1: footer is silenced even with BATS_TEST_NAME cleared" {
    # Opt-out env var. Clear BATS_TEST_NAME to remove the auto-skip
    # so this test exercises the explicit WS_FOOTER_DISABLE branch.
    run bash -c "env -u BATS_TEST_NAME WS_FOOTER_DISABLE=1 $TIMEOUT_BIN 10 bash $WS_BIN status 2>$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/stderr.txt")" != *"switching tasks"* ]]
}

@test "ws under bats (BATS_TEST_NAME set): footer auto-skips so suite assertions hold" {
    # Belt-and-braces guard: confirm the auto-skip mechanism the
    # rest of the suite relies on actually works. If a refactor
    # ever loses this, dozens of unrelated output-shape tests would
    # start failing — surface that here first.
    run "$TIMEOUT_BIN" 10 bash "$WS_BIN" status
    [ "$status" -eq 0 ]
    [[ "$output" != *"switching tasks"* ]]
}

@test "footer: no ANSI escape sequences when stderr isn't a terminal" {
    # bats' `run` pipes stderr — !isatty(2) — so the footer must
    # emit plain text. Captured logs / CI output / `2> file`
    # redirects all hit this branch; raw escape sequences in those
    # contexts are visible garbage.
    run bash -c "env -u BATS_TEST_NAME $TIMEOUT_BIN 10 bash $WS_BIN status 2>$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    local stderr_content
    stderr_content="$(cat "$BATS_TEST_TMPDIR/stderr.txt")"
    [[ "$stderr_content" == *"switching tasks"* ]]
    # The dim/reset ANSI sequence escape characters must NOT appear.
    # $'\e' is the bash-evaluated escape literal; grep -F treats it
    # as a fixed substring (no regex), so it triggers only on the
    # actual ESC byte, not on the printable backslash-e form.
    ! grep -qF $'\e[2m' "$BATS_TEST_TMPDIR/stderr.txt"
    ! grep -qF $'\e[0m' "$BATS_TEST_TMPDIR/stderr.txt"
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

@test "ws issue --help: exits 0 and prints usage" {
    run_ws issue --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws issue"* ]]
}

@test "ws issue -h: exits 0" {
    run_ws issue -h
    [ "$status" -eq 0 ]
}

@test "ws issue --help: works in any arg position" {
    run_ws issue some-comp --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws issue"* ]]
}

@test "ws cr --help: exits 0 and prints usage" {
    run_ws cr --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws cr"* ]]
}

@test "ws exec --help: exits 0 and prints usage" {
    run_ws exec --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws exec"* ]]
}

@test "ws diagnose --help: exits 0 and names all target kinds" {
    run_ws diagnose --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws diagnose"* ]]
    [[ "$output" == *"realm"* ]]
    [[ "$output" == *"hoard"* ]]
}

@test "ws exec: --help inside the wrapped command is NOT intercepted" {
    # `ws exec <comp> git --help` must pass --help through to the
    # wrapped command, so only position-1 --help prints ws usage.
    # Nonexistent component → resolver error, not the ws exec help.
    run_ws exec no-such-comp git --help
    [ "$status" -ne 0 ]
    [[ "$output" != *"Usage: ws exec"* ]]
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
    # Footer auto-skips under bats so $output is just fd1; no
    # special handling needed.
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
