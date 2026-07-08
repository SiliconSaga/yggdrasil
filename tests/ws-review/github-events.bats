#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN_DIR"

    cat > "$BIN_DIR/gh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

filter='.'
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jq) filter="$2"; shift 2 ;;
        *) shift ;;
    esac
done

jq -r "$filter" <<'JSON'
[
  {"type":"PushEvent","payload":{"ref":"refs/heads/feature/other"},"created_at":"2026-07-08T10:00:00Z"},
  {"type":"PushEvent","payload":{"ref":"refs/heads/feature/\"quoted\""},"created_at":"2026-07-08T09:00:00Z"}
]
JSON
BASH
    chmod +x "$BIN_DIR/gh"
}

@test "GitHub push lookup treats a quoted branch name literally" {
    run env "PATH=$BIN_DIR:$PATH" bash -c \
        'source "$1"; gp_review_push_timestamp owner/repo '\''feature/"quoted"'\'' 0' \
        _ "$REPO_ROOT/scripts/providers/github.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-08T09:00:00Z" ]
}
