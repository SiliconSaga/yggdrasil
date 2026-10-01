# Resolve a `timeout`-style command for the bats helpers: GNU coreutils
# `timeout` (Linux, Git Bash), Homebrew's `gtimeout` (macOS with coreutils),
# or — on a stock Mac, which has neither — a bash watchdog with the same
# `timeout N cmd…` shape, written to a temp file so it is a real executable.
#
# A file rather than a shell function because the helpers do not only call
# `"$TIMEOUT_BIN"` directly: some tests reach it through `bash -c "…"` or
# `env VAR=… "$TIMEOUT_BIN" …`, and a function is invisible to both. It
# preserves the caller's stdin (a backgrounded job in a non-interactive shell
# otherwise reads /dev/null, and the hook tests feed their payload that way)
# and reports 124 on expiry the way coreutils does. Bash 3.2 compatible, since
# the machine that needs it is the one with the old bash.
#
# Sourced by tests/ws-smoke/test_helper.bash and tests/hook/test_helper.bash;
# sets TIMEOUT_BIN. Safe to source more than once.

# WS_TEST_FORCE_TIMEOUT_FALLBACK=1 skips the coreutils lookup so the fallback
# can be exercised on a host that has `timeout` — the only way CI covers the
# stock-Mac path.
if [[ -z "${TIMEOUT_BIN:-}" ]]; then
    if [[ -z "${WS_TEST_FORCE_TIMEOUT_FALLBACK:-}" ]] && command -v timeout >/dev/null 2>&1; then
        TIMEOUT_BIN="$(command -v timeout)"
    elif [[ -z "${WS_TEST_FORCE_TIMEOUT_FALLBACK:-}" ]] && command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_BIN="$(command -v gtimeout)"
    else
        TIMEOUT_BIN="$(mktemp "${BATS_RUN_TMPDIR:-${TMPDIR:-/tmp}}/ws-timeout-fallback.XXXXXX")"
        cat > "$TIMEOUT_BIN" <<'SH'
#!/usr/bin/env bash
# bash stand-in for coreutils `timeout N cmd…` — see tests/timeout_helper.bash.
secs="$1"
shift
# Hand the command our stdin explicitly: a job started with & in a
# non-interactive shell otherwise reads from /dev/null.
exec 9<&0
"$@" <&9 &
pid=$!
exec 9<&-
( sleep "$secs"; kill "$pid" 2>/dev/null ) &
watchdog=$!
rc=0
wait "$pid" || rc=$?
kill "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null
[[ "$rc" -eq 143 ]] && rc=124
exit "$rc"
SH
        chmod +x "$TIMEOUT_BIN"
    fi
    export TIMEOUT_BIN
fi
