#!/usr/bin/env bats

# Regression tests for the empty-array auth-env guard.
#
# git-auth.sh leaves GIT_AUTH_ENV empty on SSH / tokenless / unknown-host
# remotes. Call sites expand it as `env <auth-env> git <cmd>`. Under
# `set -u`, a BARE "${arr[@]}" on an EMPTY array is an "unbound variable"
# error on bash < 4.4 — and macOS ships bash 3.2, so this crashed the very
# first `ws realm init` on a stock Mac. The fix is the guarded expansion
# ${arr[@]+"${arr[@]}"}, which expands to nothing when empty on every bash.
#
# The crash is bash-version-specific, so a behavioral test on modern bash
# (4.4+) would pass with OR without the fix and could not catch a
# regression. The load-bearing guard here is therefore the STATIC pair
# below: they fail if anyone reintroduces a bare `env "${..._AUTH_ENV[@]}"`
# expansion in scripts/. The behavioral tests document intent and would
# fail on bash 3.2 in the unguarded form.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "no bare env \"\${GIT_AUTH_ENV[@]}\" expansion remains in scripts/" {
    # grep exits non-zero when there are no matches — that's the pass.
    run grep -rnF 'env "${GIT_AUTH_ENV[@]}"' "$REPO_ROOT/scripts"
    [ "$status" -ne 0 ]
}

@test "no bare env \"\${GIT_PUSH_AUTH_ENV[@]}\" expansion remains in scripts/" {
    run grep -rnF 'env "${GIT_PUSH_AUTH_ENV[@]}"' "$REPO_ROOT/scripts"
    [ "$status" -ne 0 ]
}

@test "guarded auth-env expansion is empty-array-safe under set -u" {
    # The exact call-site shape with an EMPTY array. Crashed on bash 3.2
    # in the bare form; the guarded form must run cleanly under `set -u`
    # on every bash.
    run bash -c 'set -u; declare -a e=(); env ${e[@]+"${e[@]}"} true'
    [ "$status" -eq 0 ]
}

@test "guarded auth-env expansion still passes variables through when populated" {
    # When the array HAS entries (token injected), the guard must not drop
    # them — env must still export the injected variable to the child.
    run bash -c 'set -u; declare -a e=(FOO=bar); env ${e[@]+"${e[@]}"} printenv FOO'
    [ "$status" -eq 0 ]
    [ "$output" = "bar" ]
}
