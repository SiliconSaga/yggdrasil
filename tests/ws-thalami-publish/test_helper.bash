# Shared fixture for ws-thalami-publish bats tests.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_THALAMI_BIN="$REPO_ROOT/scripts/ws-thalami.sh"

# Build an isolated workspace under $BATS_TEST_TMPDIR.
init_publish_workspace() {
    WORK="$BATS_TEST_TMPDIR/work"
    export ROOT_DIR="$WORK"
    export HOARDS_DIR="$WORK/hoards"
    mkdir -p "$HOARDS_DIR/thalami" "$HOARDS_DIR/obsidian-Cervator/notes" \
             "$HOARDS_DIR/team-thalami-cfr"
    export HOSTNAME="testhost"

    export ECOSYSTEM="$WORK/ecosystem.yaml"
    printf 'components: []\n' > "$ECOSYSTEM"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    printf 'identity:\n  human_account: testuser\n' > "$ECOSYSTEM_LOCAL"

    cat > "$HOARDS_DIR/thalami/testhost-thalamus.md" <<EOF
---
mode: flow
user: Cervator
vault: $HOARDS_DIR/obsidian-Cervator
arcs:
  - id: observability-improvements
    name: Observability improvements
    status: active
    started: 2026-05-20
    last_touched: 2026-06-04
    next: "summarize meeting"
    published: true
  - id: private-spike
    name: Private spike
    status: active
    started: 2026-06-01
    last_touched: 2026-06-03
    next: "noodle"
---
# Thalamus
EOF

    printf '#team/observability-improvements\n\nMeeting notes 1\n' \
        > "$HOARDS_DIR/obsidian-Cervator/notes/meeting1.md"
    printf '#team/observability-improvements #private\n\nsecret\n' \
        > "$HOARDS_DIR/obsidian-Cervator/notes/secret.md"
    printf 'unrelated note\n' \
        > "$HOARDS_DIR/obsidian-Cervator/notes/other.md"
}

run_publish() { run bash "$WS_THALAMI_BIN" publish "$@"; }
