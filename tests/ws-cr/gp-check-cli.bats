#!/usr/bin/env bats

# Tests for gp_check_cli in scripts/providers/gitlab.sh.
#
# Covers the GITLAB_TOKEN fast-path and the 'glab auth status -h <host>'
# fallback used when no token is in env (ws cr, ws issue, ws review).
# The regression case verifies that a stale second host in glab's config
# (which makes bare 'glab auth status' exit non-zero under pipefail) does
# not falsely fail the check when -h scoping is used.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GLAB_LOG="$BATS_TEST_TMPDIR/glab.log"
    export GLAB_LOG

    # shellcheck source=../../scripts/providers/gitlab.sh
    source "$REPO_ROOT/scripts/providers/gitlab.sh"

    unset GITLAB_TOKEN
    export GITLAB_HOST="gitlab.example.com"
    export GLAB_BEHAVIOR="ok"
}

# Configurable glab stub.
#
#   ok               — exits 0, prints "Logged in to <GITLAB_HOST>" (default)
#   fail-bare-pass-h — bare auth status exits 1 (simulates stale second host);
#                      -h <host> exits 0 — the pipefail regression fixture
#   fail             — exits 1, no "Logged in" output (not authenticated)
glab() {
    printf 'glab: %s\n' "$*" >> "$GLAB_LOG"
    local with_h=0
    for a; do [[ "$a" == "-h" ]] && { with_h=1; break; }; done
    case "${GLAB_BEHAVIOR:-ok}" in
        ok)
            printf '✓ Logged in to %s as testuser\n' "${GITLAB_HOST:-}"
            return 0
            ;;
        fail-bare-pass-h)
            printf '✓ Logged in to %s as testuser\n' "${GITLAB_HOST:-}"
            [[ "$with_h" -eq 1 ]] && return 0 || return 1
            ;;
        fail)
            printf 'x Not logged in to %s: 401 Unauthorized\n' "${GITLAB_HOST:-}"
            return 1
            ;;
    esac
}

@test "gp_check_cli: GITLAB_TOKEN set returns 0 without calling glab" {
    export GITLAB_TOKEN="glpat_testtoken"

    run gp_check_cli

    [ "$status" -eq 0 ]
    [ ! -s "$GLAB_LOG" ]
}

@test "gp_check_cli: authenticated host with no token in env returns 0" {
    export GLAB_BEHAVIOR="ok"

    run gp_check_cli

    [ "$status" -eq 0 ]
}

@test "gp_check_cli: -h scoping passes when bare glab auth status exits non-zero (pipefail regression)" {
    # Regression: bare 'glab auth status' exits 1 when any configured host
    # (e.g. a stale gitlab.com entry) fails, even if our target host is fine.
    # Under set -o pipefail, that non-zero propagates through the pipe even when
    # grep finds the "Logged in to <host>" string. The fix uses 'glab auth status
    # -h "$host"' to scope the check to just our host so stale hosts don't
    # pollute the exit code.
    export GLAB_BEHAVIOR="fail-bare-pass-h"

    run gp_check_cli

    [ "$status" -eq 0 ]
    [[ "$(cat "$GLAB_LOG")" == *"auth status -h gitlab.example.com"* ]]
}

@test "gp_check_cli: unauthenticated host returns 1 with error" {
    export GLAB_BEHAVIOR="fail"

    run gp_check_cli

    [ "$status" -ne 0 ]
    [[ "$output" == *"glab is not authenticated for gitlab.example.com"* ]]
}

@test "gp_check_cli: no token and no GITLAB_HOST returns 1 with error" {
    unset GITLAB_HOST

    run gp_check_cli

    [ "$status" -ne 0 ]
    [[ "$output" == *"GITLAB_TOKEN is not set and GITLAB_HOST is unknown"* ]]
}
