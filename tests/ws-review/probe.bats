#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_REVIEW_BIN="$REPO_ROOT/scripts/ws-review.sh"

setup() {
    export WS_FOOTER_DISABLE=1
    export REALMS_DIR="$BATS_TEST_TMPDIR/realms"
    mkdir -p "$REALMS_DIR/review-probe"
    git init -q "$REALMS_DIR/review-probe"
    git -C "$REALMS_DIR/review-probe" remote add origin https://github.com/Example/review-probe.git
    git -C "$REALMS_DIR/review-probe" remote add upstream https://github.com/Upstream/review-probe.git

    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit 0
fi
if [[ "${1:-}" == "api" ]]; then
    echo 'Post "https://api.github.com/repos/Example/review-probe/pulls/103": dial tcp: lookup api.github.com: no such host' >&2
    exit 1
fi
exit 1
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "multi-remote probe surfaces provider lookup failures instead of not found" {
    run bash "$WS_REVIEW_BIN" review-probe 103 --compact
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not verify CR #103"* ]]
    [[ "$output" == *"api.github.com"* ]]
    [[ "$output" != *"not found on any remote"* ]]
}

@test "probe does NOT swallow a 'command not found' failure as a missing CR" {
    # A tooling failure whose message merely contains "not found" (e.g.
    # 'gh: command not found') must surface, not be classified as a 404 miss.
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then exit 0; fi
if [[ "${1:-}" == "api" ]]; then
    echo 'bash: somehelper: command not found' >&2
    exit 127
fi
exit 1
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"

    run bash "$WS_REVIEW_BIN" review-probe 103 --compact
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not verify CR #103"* ]]
    [[ "$output" != *"not found on any remote"* ]]
}
