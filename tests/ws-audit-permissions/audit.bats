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

# ─── Critical detections ────────────────────────────────────────────

@test "detect: Bash(*) wildcard-only is critical" {
    write_settings user "Bash(*)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: critical"* ]]
    [[ "$output" == *"pattern: 'Bash(*)'"* ]]
}

@test "detect: Bash(sudo *) is critical" {
    write_settings user "Bash(sudo *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: critical"* ]]
    [[ "$output" == *"Privilege escalation"* ]]
}

@test "detect: Bash(eval *) is critical" {
    write_settings project "Bash(eval *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: critical"* ]]
}

# ─── High detections ────────────────────────────────────────────────

@test "detect: Bash(ws exec *) is high" {
    write_settings user "Bash(ws exec *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: high"* ]]
    [[ "$output" == *"ws exec runs arbitrary commands"* ]]
}

@test "detect: Bash(bash *) is high" {
    write_settings project "Bash(bash *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: high"* ]]
}

@test "detect: Bash(rm -rf *) is high" {
    write_settings user "Bash(rm -rf *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: high"* ]]
}

# ─── Medium detections ──────────────────────────────────────────────

@test "detect: Bash(curl *) is medium" {
    write_settings user "Bash(curl *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: medium"* ]]
}

@test "detect: Bash(kubectl *) is medium" {
    write_settings project-local "Bash(kubectl *)"
    run_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"severity: medium"* ]]
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
