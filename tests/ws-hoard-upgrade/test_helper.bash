# Shared helpers for ws-hoard-upgrade bats tests.
#
# Sources ws-hoard-upgrade.sh directly (it's a function library) and
# exercises its functions against an isolated TEMPLATES_DIR / HOARDS_DIR
# under $BATS_TEST_TMPDIR. Plugin downloads are stubbed with a fake `gh`
# on PATH so no network is touched.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup_dirs() {
    export ROOT_DIR="$BATS_TEST_TMPDIR/work"
    export TEMPLATES_DIR="$ROOT_DIR/templates"
    export HOARDS_DIR="$ROOT_DIR/hoards"
    mkdir -p "$HOARDS_DIR" "$TEMPLATES_DIR/hoards"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/ws-hoard-upgrade.sh"
}

# Build a template at $TEMPLATES_DIR/hoards/<name> with the given
# upgrade.yaml content ($2).
make_template() {
    local name="$1" yaml="$2"
    local dir="$TEMPLATES_DIR/hoards/$name"
    mkdir -p "$dir/.upgrade/regions"
    printf '%s\n' "$yaml" > "$dir/.upgrade/upgrade.yaml"
}

# Build a minimal hoard at $HOARDS_DIR/<name> with a .obsidian dir and an
# empty community-plugins.json. Caller adds files/provenance after.
make_hoard() {
    local name="$1"
    local dir="$HOARDS_DIR/$name"
    mkdir -p "$dir/.obsidian"
    printf '[]\n' > "$dir/.obsidian/community-plugins.json"
}

# Put a fake `gh` on PATH that emulates `gh release download ... --dir D`
# by writing dummy main.js + manifest.json into D. No network.
make_fake_gh() {
    local bindir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bindir"
    cat > "$bindir/gh" <<'SH'
#!/usr/bin/env bash
dir=""; prev=""
for a in "$@"; do [[ "$prev" == "--dir" ]] && dir="$a"; prev="$a"; done
if [[ -n "$dir" ]]; then
  mkdir -p "$dir"
  printf 'stub\n' > "$dir/main.js"
  printf '{"id":"stub"}\n' > "$dir/manifest.json"
fi
exit 0
SH
    chmod +x "$bindir/gh"
    export PATH="$bindir:$PATH"
}
