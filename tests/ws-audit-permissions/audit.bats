#!/usr/bin/env bats

# Tests for ws-audit-permissions. The helper inspects three scopes
# of Claude Code permission settings and flags entries matching a
# watchlist of broad / risky patterns. Exit code = findings count;
# clean output is "[]" with exit 0.

load test_helper

setup() {
    init_audit_env
}

# ─── Clean cases ────────────────────────────────────────────────────

@test "no settings files at all: empty findings, exit 0" {
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "narrowly-scoped allow entries: no findings" {
    write_settings project "Bash(ws status)
Bash(ws log)
Bash(ws hoard list)
Bash(git -C * status)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "glob: wildcard-only watchlist entry does NOT over-match narrow allows" {
    # `Bash(\*)` in the watchlist must match ONLY the literal
    # `Bash(*)` pattern in an allow list — not `Bash(ls)` or
    # `Bash(ws status)`. This is the over-match guard for the
    # escaped wildcard. Regression here would flag every narrow
    # allow entry as critical.
    write_settings project "Bash(ls)
Bash(ws status)
Bash(cat *)
Bash(git -C * status)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "glob: Bash(ws exec *) watchlist entry matches concrete ws exec allow" {
    # If the user has `Bash(ws exec npm test)` in their allow list,
    # the audit's `Bash(ws exec *)` watchlist entry should flag it
    # as a `high`-severity broad pattern. This is the glob-match
    # direction that the previous quoted-pattern bug broke silently.
    # The entry may match multiple watchlist patterns (the broader
    # `Bash(ws exec *)` and the more-specific `Bash(ws exec * *)`
    # for 2-arg shapes), so exit code is "at least one", not exact.
    write_settings user "Bash(ws exec npm test)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
    [[ "$output" == *"ws exec runs arbitrary commands"* ]]
}

@test "glob: Bash(curl *) matches both verbatim and concrete entries" {
    # Verbatim form (user clicked Always Allow on a literal
    # wildcard pattern) AND a concrete invocation (user clicked
    # Allow on `curl https://...`) should both be flagged. The
    # watchlist entry `Bash(curl *)` covers both via glob.
    write_settings user "Bash(curl *)
Bash(curl https://example.com/api)"
    run_audit
    [ "$status" -eq 2 ]
    # Both findings present in output
    [[ "$output" == *"Bash(curl *)"* ]]
    [[ "$output" == *"Bash(curl https://example.com/api)"* ]]
}

# ─── Critical detections ────────────────────────────────────────────

@test "detect: Bash(*) wildcard-only is critical" {
    write_settings user "Bash(*)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: critical"* ]]
    [[ "$output" == *"pattern: 'Bash(*)'"* ]]
}

@test "detect: Bash(sudo *) is critical" {
    write_settings user "Bash(sudo *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: critical"* ]]
    [[ "$output" == *"Privilege escalation"* ]]
}

@test "detect: Bash(eval *) is critical" {
    write_settings project "Bash(eval *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: critical"* ]]
}

# ─── High detections ────────────────────────────────────────────────

@test "detect: Bash(ws exec *) is high" {
    write_settings user "Bash(ws exec *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
    [[ "$output" == *"ws exec runs arbitrary commands"* ]]
}

@test "detect: Bash(bash *) is high" {
    write_settings project "Bash(bash *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "detect: Bash(rm -rf *) is high" {
    write_settings user "Bash(rm -rf *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

# ─── Medium detections ──────────────────────────────────────────────

@test "detect: Bash(curl *) is medium" {
    write_settings user "Bash(curl *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: medium"* ]]
}

@test "detect: Bash(kubectl *) is medium" {
    write_settings project-local "Bash(kubectl *)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: medium"* ]]
}

@test "detect: canonical Bash(kubectl:*) blanket allow is high" {
    write_settings project-local "Bash(kubectl:*)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bash(kubectl:*)"* ]]
    [[ "$output" == *"high"* ]]
}

# ─── Scope labeling ─────────────────────────────────────────────────

@test "scope label: user-scope finding is labeled user" {
    write_settings user "Bash(sudo *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"scope: user"* ]]
}

@test "scope label: project-scope finding is labeled project" {
    write_settings project "Bash(sudo *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"scope: project"* ]]
}

@test "scope label: project-local-scope finding is labeled project-local" {
    write_settings project-local "Bash(sudo *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"scope: project-local"* ]]
}

# ─── Multi-finding cases ────────────────────────────────────────────

@test "multiple findings across scopes: exit code equals count" {
    write_settings user "Bash(sudo *)"
    write_settings project "Bash(ws exec *)
Bash(curl *)"
    run_audit
    [ "$status" -eq 3 ]
    [[ "$output" == *"sudo"* ]]
    [[ "$output" == *"ws exec"* ]]
    [[ "$output" == *"curl"* ]]
}

# ─── --names-only ───────────────────────────────────────────────────

@test "--names-only: emits just patterns, one per line" {
    write_settings user "Bash(sudo *)"
    write_settings project "Bash(ws exec *)"
    run_audit --names-only
    [ "$status" -eq 2 ]
    [[ "$output" == *"Bash(sudo *)"* ]]
    [[ "$output" == *"Bash(ws exec *)"* ]]
    [[ "$output" != *"severity:"* ]]
    [[ "$output" != *"rationale:"* ]]
}

@test "--names-only with clean state: empty output, exit 0" {
    run_audit --names-only
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── YAML output safety ─────────────────────────────────────────────

@test "YAML escape: pattern with single quotes produces valid YAML" {
    # Allow entries can contain single quotes (e.g., `Bash(echo 'hi')`).
    # Without escaping, the YAML emission would produce
    # `pattern: 'Bash(echo 'hi')'` — invalid YAML where the inner `'`
    # closes the string early. Fix doubles inner `'` to `''`, which
    # is the YAML-correct way to literal-escape a single quote inside
    # a single-quoted string.
    #
    # Pattern matches the wildcard-bash watchlist entry so the audit
    # has something to emit. The `echo` part is irrelevant to the
    # match — we just need ANY quote in the allow string.
    write_settings project "Bash(bash 'unsafe' *)"
    run_audit
    # Findings include this entry (matches `bash *` watchlist).
    [ "$status" -gt 0 ]
    # Doubled inner quotes — YAML-correct escape.
    [[ "$output" == *"'Bash(bash ''unsafe'' *)'"* ]]
    # Final YAML parses cleanly via yq (round-trip check).
    parsed_pattern="$(echo "$output" | yq -r '.[0].pattern' 2>/dev/null)"
    [ "$parsed_pattern" = "Bash(bash 'unsafe' *)" ]
}

# ─── Robustness ─────────────────────────────────────────────────────

@test "malformed JSON: warns to stderr, continues" {
    echo "{ not valid json" > "$WORK/.claude/settings.json"
    # Set up a valid user-scope so the audit has something to find.
    write_settings user "Bash(sudo *)"
    run_audit
    # Stderr warning + finding from the valid scope. Exit 1 for the
    # one real finding (malformed file contributes nothing).
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"not valid JSON"* ]] || [[ "$output" == *"not valid JSON"* ]]
}

@test "CRLF line endings in settings.json: still matches" {
    {
        printf '{\r\n'
        printf '  "permissions": {\r\n'
        printf '    "allow": [\r\n'
        printf '      "Bash(sudo *)"\r\n'
        printf '    ]\r\n'
        printf '  }\r\n'
        printf '}\r\n'
    } > "$WORK/.claude/settings.json"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"sudo"* ]]
}

@test "settings.json with no permissions.allow: no findings" {
    echo '{"other": "config"}' > "$WORK/.claude/settings.json"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# ─── --help ─────────────────────────────────────────────────────────

@test "--help: exits 0 and prints usage" {
    run_audit --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"audit-permissions"* ]]
    [[ "$output" == *"watchlist"* ]] || [[ "$output" == *"broad"* ]]
}

@test "unknown flag: exits 2 with error" {
    run_audit --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]] || [[ "$stderr" == *"unknown flag"* ]]
}

# ─── B3: ws-wrapper normalization + catch-all ───────────────────────
#
# Narrow per-subcommand allows written in the verbose wrapper form
# (`Bash(bash scripts/ws <sub> ...)`) used to trip the broad
# `Bash(bash *)` watchlist entry — ~120 false positives on a clean
# config. The matcher now normalizes the wrapper form to the bare
# `ws` form before matching (reporting still shows the original
# entry), and the genuinely-broad subcommand-less catch-all
# `Bash(ws:*)` / `Bash(bash scripts/ws:*)` gets its own high entry.

@test "normalize: bash scripts/ws <subcommand> literals are NOT flagged" {
    write_settings project "Bash(bash scripts/ws help)
Bash(bash scripts/ws review * *)
Bash(bash scripts/ws status)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "detect: Bash(bash scripts/ws:*) catch-all is high" {
    write_settings project-local "Bash(bash scripts/ws:*)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
    # Original (un-normalized) entry is what gets REPORTED.
    [[ "$output" == *"Bash(bash scripts/ws:*)"* ]]
}

@test "detect: normalized Bash(ws:*) catch-all is high" {
    write_settings project-local "Bash(ws:*)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "normalize: subcommand-pinned :* is NOT flagged" {
    write_settings project "Bash(bash scripts/ws commit:*)
Bash(ws commit:*)
Bash(bash scripts/ws test * *)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "normalize: ws exec danger is preserved through normalization" {
    write_settings user "Bash(bash scripts/ws exec mimir rm)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
    [[ "$output" == *"ws exec runs arbitrary commands"* ]]
}

@test "normalize: absolute IN-REPO ws wrapper literal is NOT flagged" {
    # Absolute spelling of this workspace's own scripts/ws normalizes.
    write_settings project-local "Bash(bash $ROOT_DIR/scripts/ws status)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "normalize: FOREIGN absolute ws wrapper path still flags" {
    # Any scripts/ws outside this workspace is not our script — it
    # must keep matching Bash(bash *), not normalize to Bash(ws …).
    write_settings project-local "Bash(bash /opt/elsewhere/scripts/ws status)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "normalize: FOREIGN absolute bats runner path still flags" {
    write_settings project-local "Bash(bash /opt/elsewhere/tests/vendor/bats-core/bin/bats tests/x/)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "normalize: absolute IN-REPO bats runner is NOT flagged" {
    write_settings project "Bash(bash $ROOT_DIR/tests/vendor/bats-core/bin/bats tests/ws-smoke/)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "normalize: vendored bats runner scoped to tests/ is NOT flagged" {
    # The focused TDD loop (`bash tests/vendor/bats-core/bin/bats
    # tests/<dir>/`) is risk-equivalent to the already-allowlisted
    # `ws test` — same vendored runner, same reviewed test tree — so
    # its allow entries shouldn't trip Bash(bash *).
    write_settings project "Bash(bash tests/vendor/bats-core/bin/bats tests/*)
Bash(bash tests/vendor/bats-core/bin/bats tests/ws-smoke/)"
    run_audit
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "normalize: bats runner against a NON-tests path still flags" {
    # Outside the reviewed test tree the runner executes arbitrary
    # .bats shell — keep the prompt.
    write_settings project-local "Bash(bash tests/vendor/bats-core/bin/bats /tmp/evil/)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "normalize: path traversal in the bats target still flags" {
    # tests/../ escapes the reviewed tree — normalization must not
    # suppress the Bash(bash *) finding for it.
    write_settings project-local "Bash(bash tests/vendor/bats-core/bin/bats tests/../tmp/evil/)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "normalize: path traversal in the ws wrapper path still flags" {
    # A wrapper path that climbs out of the workspace is not our ws
    # script — same traversal rule as the bats runner.
    write_settings project-local "Bash(bash ../elsewhere/scripts/ws status)"
    run_audit
    [ "$status" -gt 0 ]
    [[ "$output" == *"severity: high"* ]]
}

# ─── Acknowledged per-workspace allowances ──────────────────────────
#
# hook-rules.local (gitignored, per-machine) can carry an
# [audit-acknowledged] section listing exact allow entries this
# workspace has consciously accepted. Matching findings still appear
# in the YAML (with acknowledged: true, severity kept) but don't
# count toward the exit code — so a deliberate local allowance stops
# reading as a problem at every session start.

write_ack() {
    mkdir -p "$WORK/.claude/hooks"
    {
        echo "[audit-acknowledged]"
        printf '%s\n' "$@"
    } > "$WORK/.claude/hooks/hook-rules.local"
}

@test "ack: acknowledged finding is reported but not counted" {
    write_settings project-local "Bash(bash -n:*)"
    write_ack "Bash(bash -n:*)"
    run_audit
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bash(bash -n:*)"* ]]
    [[ "$output" == *"acknowledged: true"* ]]
    [[ "$output" == *"severity: high"* ]]
}

@test "ack: only the exact entry is acknowledged, others still count" {
    write_settings project-local "Bash(bash -n:*)
Bash(sudo *)"
    write_ack "Bash(bash -n:*)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: critical"* ]]
}

@test "ack: --names-only skips acknowledged findings" {
    write_settings project-local "Bash(bash -n:*)
Bash(sudo *)"
    write_ack "Bash(bash -n:*)"
    run_audit --names-only
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bash(sudo *)"* ]]
    [[ "$output" != *"bash -n"* ]]
}

@test "ack: [audit-acknowledged] in the COMMITTED hook-rules is ignored" {
    # Acknowledgments are per-machine judgment — the committed baseline
    # must not silence the audit for everyone (mirrors the allow-extras
    # local-only rule).
    write_settings project-local "Bash(bash -n:*)"
    mkdir -p "$WORK/.claude/hooks"
    {
        echo "[audit-acknowledged]"
        echo "Bash(bash -n:*)"
    } > "$WORK/.claude/hooks/hook-rules"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" != *"acknowledged: true"* ]]
}
