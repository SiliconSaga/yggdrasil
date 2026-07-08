#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN_DIR"

    cat > "$BIN_DIR/gh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

filter='.'
path=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jq) filter="$2"; shift 2 ;;
        repos/*) path="$1"; shift ;;
        *) shift ;;
    esac
done

if [[ "$path" == "repos/owner/repo/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]]; then
    jq -r "$filter" <<'JSON'
{"commit":{"committer":{"date":"2026-07-08T08:30:00Z"}}}
JSON
    exit 0
fi

jq -r "$filter" <<'JSON'
[
  {"type":"PushEvent","payload":{"ref":"refs/heads/feature/other","before":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"created_at":"2026-07-08T10:00:00Z"},
  {"type":"PushEvent","payload":{"ref":"refs/heads/feature/\"quoted\"","before":"cccccccccccccccccccccccccccccccccccccccc"},"created_at":"2026-07-08T09:00:00Z"},
  {"type":"PushEvent","payload":{"ref":"refs/heads/feature/review","before":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"created_at":"2026-07-08T09:30:00Z"}
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

@test "GitHub previous-push lookup falls back through the latest event before SHA" {
    run --separate-stderr env "PATH=$BIN_DIR:$PATH" bash -c \
        'source "$1"; gp_review_push_timestamp owner/repo feature/review 1' \
        _ "$REPO_ROOT/scripts/providers/github.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-08T08:30:00Z" ]
    [[ "$stderr" == *"using its prior head commit time"* ]]
}
