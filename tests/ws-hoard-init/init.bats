#!/usr/bin/env bats

# Lock in `ws hoard init` flows:
#
#   - Standard cp -R flow against shipped templates that have no template.yaml
#   - Yaml-driven clone-on-init flow when template.yaml IS present, including:
#       * upstream → fallback → hard-fail ordering
#       * post_clone steps (strip_git, apply_bridge)
#   - --name validation, existing-target rejection
#   - Help text contract: lists all four current templates
#
# Network-free: tests that exercise the clone path use a bare git repo
# created in $BATS_TEST_TMPDIR with a file:// URL.

load test_helper

setup() {
    init_workspace
}

# ---------------------------------------------------------------------------
# Help output
# ---------------------------------------------------------------------------

@test "ws hoard help lists every template under templates/hoards/ dynamically" {
    run bash "$REPO_ROOT/scripts/ws" hoard
    # Help dispatch (no args / --help / -h) prints to stderr and naturally
    # returns 0 from the last echo. Lock the exact status so a regression
    # that flips the exit code surfaces here.
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available templates:"* ]]
    # Derive the expected list from disk so adding a fifth template under
    # templates/hoards/ automatically gets picked up here. If help text
    # drifts (e.g. someone reverts to a hardcoded list), this test fails.
    local d name
    for d in "$REPO_ROOT/templates/hoards"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == .* ]] && continue
        [[ "$output" == *"$name"* ]] || {
            echo "missing template '$name' in help output" >&2
            return 1
        }
    done
}

@test "ws hoard --help lists every template under templates/hoards/ dynamically" {
    run bash "$REPO_ROOT/scripts/ws" hoard --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available templates:"* ]]
    local d name
    for d in "$REPO_ROOT/templates/hoards"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == .* ]] && continue
        [[ "$output" == *"$name"* ]] || {
            echo "missing template '$name' in help output" >&2
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# Standard cp -R flow (no template.yaml)
# ---------------------------------------------------------------------------

@test "standard flow: obsidian-vault scaffolds expected file structure" {
    run_hoard_init obsidian-vault --name test-obsidian
    [ "$status" -eq 0 ]
    [ -d "$HOARDS_DIR/test-obsidian" ]
    # Welcome doc + PARA folders shipped with the obsidian-vault template
    [ -f "$HOARDS_DIR/test-obsidian/00_Inbox/Welcome.md" ]
    [ -d "$HOARDS_DIR/test-obsidian/10_Projects" ]
    [ -d "$HOARDS_DIR/test-obsidian/20_Areas" ]
    [ -d "$HOARDS_DIR/test-obsidian/30_Resources" ]
    [ -d "$HOARDS_DIR/test-obsidian/40_Archive" ]
    [ -d "$HOARDS_DIR/test-obsidian/.obsidian" ]
    # ws_hoard_init's git init step ran post-copy
    [ -d "$HOARDS_DIR/test-obsidian/.git" ]
}

@test "standard flow: basic template scaffolds and git-inits" {
    run_hoard_init basic --name test-basic
    [ "$status" -eq 0 ]
    [ -d "$HOARDS_DIR/test-basic" ]
    [ -f "$HOARDS_DIR/test-basic/README.md" ]
    [ -d "$HOARDS_DIR/test-basic/.git" ]
}

@test "init writes .hoard.yaml provenance for a template with an upgrade recipe" {
    run_hoard_init obsidian-vault --name test-prov
    [ "$status" -eq 0 ]
    [ -f "$HOARDS_DIR/test-prov/.hoard.yaml" ]
    grep -qF "template: obsidian-vault" "$HOARDS_DIR/test-prov/.hoard.yaml"
}

# ---------------------------------------------------------------------------
# --name validation
# ---------------------------------------------------------------------------

@test "--name with spaces is rejected before any clone/copy happens" {
    run_hoard_init obsidian-vault --name "bad name"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--name must be a safe directory name"* ]]
    # Nothing landed on disk
    [ ! -d "$HOARDS_DIR/bad name" ]
    [ -z "$(ls -A "$HOARDS_DIR" 2>/dev/null)" ]
}

@test "--name with slashes is rejected" {
    run_hoard_init obsidian-vault --name "bad/path"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--name must be a safe directory name"* ]]
}

@test "--name without value errors out (exit 2)" {
    run_hoard_init obsidian-vault --name
    [ "$status" -eq 2 ]
    [[ "$output" == *"--name requires a value"* ]]
}

# ---------------------------------------------------------------------------
# Existing target dir
# ---------------------------------------------------------------------------

@test "init refuses to overwrite an existing hoard dir" {
    mkdir -p "$HOARDS_DIR/already-here"
    echo "preserved" > "$HOARDS_DIR/already-here/sentinel.txt"
    run_hoard_init obsidian-vault --name already-here
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
    # Sentinel file untouched
    [ -f "$HOARDS_DIR/already-here/sentinel.txt" ]
    [ "$(cat "$HOARDS_DIR/already-here/sentinel.txt")" = "preserved" ]
}

# ---------------------------------------------------------------------------
# Unknown template
# ---------------------------------------------------------------------------

@test "unknown template name errors with the available-templates list" {
    run_hoard_init does-not-exist --name foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown hoard template"* ]]
    [[ "$output" == *"Available templates"* ]]
}

# ---------------------------------------------------------------------------
# Yaml-driven flow: clone failure paths
# ---------------------------------------------------------------------------

@test "yaml flow: unreachable upstream + unreachable fallback errors with both URLs" {
    # Point TEMPLATES_DIR at the fixture templates root; the fixture's
    # template.yaml has both URLs unreachable.
    export TEMPLATES_DIR="$FIXTURES_DIR/templates"
    run_hoard_init unreachable-vault --name fail-vault
    [ "$status" -ne 0 ]
    # Should mention both URLs in the error
    [[ "$output" == *"upstream"* ]]
    [[ "$output" == *"fallback"* ]]
    [[ "$output" == *"/nonexistent/path/upstream-bare-does-not-exist.git"* ]]
    [[ "$output" == *"/nonexistent/path/fallback-bare-does-not-exist.git"* ]]
    # Target dir was not left half-created
    [ ! -d "$HOARDS_DIR/fail-vault" ]
}

@test "yaml flow: unreachable upstream with no fallback errors clearly" {
    # Build a synthetic template at runtime — same as unreachable-vault
    # but no fallback set. Lets us assert the no-fallback error branch
    # without polluting the fixtures dir with a near-duplicate.
    local tdir="$BATS_TEST_TMPDIR/templates/hoards/no-fallback-vault"
    mkdir -p "$tdir"
    cat > "$tdir/template.yaml" <<'YAML'
upstream: /nonexistent/path/upstream-only.git
pin: ""
fallback: ""
post_clone:
  - strip_git
YAML
    export TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"

    run_hoard_init no-fallback-vault --name fail-vault
    [ "$status" -ne 0 ]
    [[ "$output" == *"clone failed"* ]]
    [[ "$output" == *"/nonexistent/path/upstream-only.git"* ]]
    [ ! -d "$HOARDS_DIR/fail-vault" ]
}

# ---------------------------------------------------------------------------
# Yaml-driven flow: success path with bridge overlay
# ---------------------------------------------------------------------------

@test "yaml flow: clone + strip_git + apply_bridge runs end to end" {
    # Stand up a synthetic upstream bare repo
    local upstream_url
    upstream_url="$(make_bare_upstream synthetic)"

    # Generate a fresh template.yaml inside the fixture template dir
    # pointing at the bare upstream we just built. Each test gets its
    # own temp templates root so this doesn't race.
    local tdir="$BATS_TEST_TMPDIR/templates/hoards/synthetic-vault"
    mkdir -p "$tdir/gdd-bridge"
    cp -R "$FIXTURES_DIR/templates/hoards/synthetic-vault/." "$tdir/"
    cat > "$tdir/template.yaml" <<YAML
upstream: $upstream_url
pin: ""
fallback: ""
post_clone:
  - strip_git
  - apply_bridge
YAML
    export TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"

    run_hoard_init synthetic-vault --name my-synth
    [ "$status" -eq 0 ]
    [ -d "$HOARDS_DIR/my-synth" ]
    # Upstream's seed file made it through
    [ -f "$HOARDS_DIR/my-synth/README.md" ]
    # Bridge overlay landed
    [ -f "$HOARDS_DIR/my-synth/AGENTS.md" ]
    [ -f "$HOARDS_DIR/my-synth/BRIDGE_README.md" ]
    [[ "$(cat "$HOARDS_DIR/my-synth/AGENTS.md")" == *"Synthetic bridge AGENTS.md"* ]]
    # strip_git ran AND ws_hoard_init's own git init re-initialized:
    # there should be a .git/ directory but the log should only show
    # ws_hoard_init's "Initial commit" — not the seed commits from upstream.
    [ -d "$HOARDS_DIR/my-synth/.git" ]
    run git -C "$HOARDS_DIR/my-synth" log --oneline
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == *"Initial commit"* ]]
}

@test "yaml flow: fallback used when upstream fails" {
    # Upstream URL is bogus; fallback points at a real bare repo. The
    # helper should fall through cleanly.
    local fallback_url
    fallback_url="$(make_bare_upstream synthetic-fb)"

    local tdir="$BATS_TEST_TMPDIR/templates/hoards/fallback-vault"
    mkdir -p "$tdir/gdd-bridge"
    echo "# Bridge" > "$tdir/gdd-bridge/AGENTS.md"
    cat > "$tdir/template.yaml" <<YAML
upstream: /nonexistent/path/never-resolves.git
pin: ""
fallback: $fallback_url
post_clone:
  - strip_git
  - apply_bridge
YAML
    export TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"

    run_hoard_init fallback-vault --name fb-vault
    [ "$status" -eq 0 ]
    [ -d "$HOARDS_DIR/fb-vault" ]
    [ -f "$HOARDS_DIR/fb-vault/README.md" ]
    [ -f "$HOARDS_DIR/fb-vault/AGENTS.md" ]
    [[ "$output" == *"trying fallback"* ]]
}

@test "yaml flow: missing upstream field errors clearly" {
    local tdir="$BATS_TEST_TMPDIR/templates/hoards/no-upstream-vault"
    mkdir -p "$tdir"
    cat > "$tdir/template.yaml" <<'YAML'
pin: ""
fallback: ""
post_clone: []
YAML
    export TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"

    run_hoard_init no-upstream-vault --name nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the 'upstream' field"* ]]
}

@test "yaml flow: post_clone without apply_bridge skips bridge overlay" {
    # Same synthetic template but post_clone only does strip_git. The
    # bridge dir exists in the template but should NOT be applied.
    local upstream_url
    upstream_url="$(make_bare_upstream stripgit-only)"

    local tdir="$BATS_TEST_TMPDIR/templates/hoards/stripgit-only-vault"
    mkdir -p "$tdir/gdd-bridge"
    echo "should-not-land" > "$tdir/gdd-bridge/SKIP.md"
    cat > "$tdir/template.yaml" <<YAML
upstream: $upstream_url
pin: ""
fallback: ""
post_clone:
  - strip_git
YAML
    export TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"

    run_hoard_init stripgit-only-vault --name nobridge
    [ "$status" -eq 0 ]
    [ -d "$HOARDS_DIR/nobridge" ]
    [ ! -f "$HOARDS_DIR/nobridge/SKIP.md" ]
}

@test "yaml flow: unknown post_clone step warns but continues" {
    local upstream_url
    upstream_url="$(make_bare_upstream unknownstep)"

    local tdir="$BATS_TEST_TMPDIR/templates/hoards/unknownstep-vault"
    mkdir -p "$tdir"
    cat > "$tdir/template.yaml" <<YAML
upstream: $upstream_url
pin: ""
fallback: ""
post_clone:
  - bogus_step
  - strip_git
YAML
    export TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"

    run_hoard_init unknownstep-vault --name unknown-step
    [ "$status" -eq 0 ]
    [[ "$output" == *"unknown post_clone step 'bogus_step'"* ]]
    [ -d "$HOARDS_DIR/unknown-step" ]
    # strip_git still ran — followed by ws_hoard_init's own git init
    [ -d "$HOARDS_DIR/unknown-step/.git" ]
}
