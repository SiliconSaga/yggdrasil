#!/usr/bin/env bats

# The token-injection auth path rides GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n env
# entries, which git only honors from 2.31 — below that the injection is a
# SILENT no-op and HTTPS auth falls through to whatever OS credential manager
# holds (found live on a git 2.28 host during the GA clone-fork e2e). The
# preflight floor turns that silent posture break into a loud requirement.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/ws-preflight.sh"

# Build a stub `git` that reports the given version string, in a PATH-prepended
# dir. Everything else preflight probes stays resolved from the real PATH.
make_git_stub() {
    local version="$1"
    STUB_DIR="$BATS_TEST_TMPDIR/stub-bin"
    mkdir -p "$STUB_DIR"
    cat > "$STUB_DIR/git" <<EOF
#!/usr/bin/env bash
echo "git version $version"
EOF
    chmod +x "$STUB_DIR/git"
}

@test "preflight flags git below the 2.31 token-injection floor" {
    make_git_stub "2.28.0.windows.1"

    run env "PATH=$STUB_DIR:$PATH" bash "$PREFLIGHT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"git — found, but version check failed"* ]]
}

@test "preflight accepts git at or above the 2.31 floor" {
    make_git_stub "2.31.0"

    run env "PATH=$STUB_DIR:$PATH" bash "$PREFLIGHT"

    [[ "$output" == *"✓ git"* ]]
    [[ "$output" != *"git — found, but version check failed"* ]]
}

@test "preflight accepts a modern git (major or minor beyond the floor)" {
    make_git_stub "2.55.0.windows.3"

    run env "PATH=$STUB_DIR:$PATH" bash "$PREFLIGHT"

    [[ "$output" == *"✓ git"* ]]
    [[ "$output" != *"git — found, but version check failed"* ]]
}
