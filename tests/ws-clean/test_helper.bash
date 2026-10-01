# Shared helpers for ws-clean bats tests.
#
# Each test gets an isolated $WORK directory under $BATS_TEST_TMPDIR with
# the scratch dirs ws clean operates on (.issues/.crs/.commits/.outputs/
# .tmp). Tests invoke the `ws` dispatcher directly (via bash) so the
# `clean)` routing and arg-parsing are exercised. WS_CLEAN_MINE_THRESHOLD
# is set per-test to keep the threshold logic testable without creating
# dozens of files.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

# Resolve `timeout` (Linux/Git Bash), `gtimeout` (macOS Homebrew coreutils),
# or the shared bash watchdog fallback — see tests/timeout_helper.bash. Kept
# as a function called from setup() so the shape of this helper matches the
# others; the fallback means a stock Mac runs these cases rather than
# skipping them.
detect_timeout_bin() {
    # shellcheck source=../timeout_helper.bash
    source "$REPO_ROOT/tests/timeout_helper.bash"
}

init_clean_workspace() {
    detect_timeout_bin
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components" "$WORK/realms" "$WORK/hoards"
    mkdir -p "$WORK/.issues" "$WORK/.crs" "$WORK/.commits" "$WORK/.outputs" "$WORK/.tmp"
    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"

    export ECOSYSTEM="$WORK/ecosystem.yaml"
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
YAML

    export HOSTNAME="testhost"
}

# Create $2 draft files of the right extension in scratch dir $1
# (e.g. make_drafts .commits 3, make_drafts .outputs 2).
make_drafts() {
    local dir="$1"
    local n="$2"
    local ext="md"
    [[ "$dir" == ".outputs" ]] && ext="txt"
    local i
    for (( i = 1; i <= n; i++ )); do
        printf 'draft %s\n' "$i" > "$ROOT_DIR/$dir/draft-$i.$ext"
    done
}

# Count files matching the clean globs across all scratch dirs.
count_scratch() {
    local total=0
    total=$(( total + $(find "$ROOT_DIR/.issues" -maxdepth 1 -name '*.md' -type f | wc -l) ))
    total=$(( total + $(find "$ROOT_DIR/.crs" -maxdepth 1 -name '*.md' -type f | wc -l) ))
    total=$(( total + $(find "$ROOT_DIR/.commits" -maxdepth 1 -name '*.md' -type f | wc -l) ))
    total=$(( total + $(find "$ROOT_DIR/.outputs" -maxdepth 1 -name '*.txt' -type f | wc -l) ))
    total=$(( total + $(find "$ROOT_DIR/.tmp" -mindepth 1 -maxdepth 1 | wc -l) ))
    echo "$total"
}

run_ws() {
    run "$TIMEOUT_BIN" 10 bash "$WS_BIN" "$@"
}
