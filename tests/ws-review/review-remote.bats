#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    WORK="$BATS_TEST_TMPDIR/work"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    BODY_LOG="$WORK/glab-post-body.txt"
    mkdir -p "$WORK/components/app" "$WORK/realms" "$WORK/hoards" "$BIN_DIR"

    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  gitProviders:
    gitlab.com: gitlab
components:
  app:
    repo: https://gitlab.com/upstream-group/project.git
YAML

    git -C "$WORK/components/app" init -q
    git -C "$WORK/components/app" config user.name "Test User"
    git -C "$WORK/components/app" config user.email "test@example.local"
    echo "hello" > "$WORK/components/app/README.md"
    git -C "$WORK/components/app" add README.md
    git -C "$WORK/components/app" commit -q -m "seed"
    git -C "$WORK/components/app" remote add origin https://gitlab.com/upstream-group/project.git
    git -C "$WORK/components/app" remote add fork https://gitlab.com/example-group/forked-project.git

    # Stub glab. The GET MR endpoint returns a DISTINCT title per project path
    # so a test can prove which project the selected remote actually queried —
    # not merely that the rendered header slug changed. POSTed note bodies are
    # logged so the reply test can assert the message reached the API verbatim.
    # Control characters in fixture bodies use JSON \u escapes exclusively —
    # raw bytes in this source would be invalid JSON and invisible to review.
    cat > "$BIN_DIR/glab" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITLAB_HOST:-}" != "${GLAB_EXPECTED_HOST:-}" ]]; then
    echo "unexpected GitLab host: ${GITLAB_HOST:-unset}" >&2
    exit 2
fi

if [[ "${1:-}" != "api" ]]; then
    echo "unexpected glab command: $*" >&2
    exit 1
fi
shift

method="GET"
path=""
body=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --method) method="$2"; shift 2 ;;
        -f) case "${2:-}" in body=*) body="${2#body=}" ;; esac; shift 2 ;;
        projects/*) path="$1"; shift ;;
        *) shift ;;
    esac
done

if [[ "$method" == "POST" && "$path" == */notes ]]; then
    printf '%s' "$body" > "${GLAB_BODY_LOG:-/dev/null}"
    echo '{"id":1}'
    exit 0
fi

case "$path" in
    projects/upstream-group%2Fproject/merge_requests/1)
        echo '{"title":"Upstream MR","state":"opened","author":{"username":"review-bot"},"source_branch":"feature/upstream","target_branch":"main","web_url":"https://gitlab.com/upstream-group/project/-/merge_requests/1"}'
        ;;
    projects/example-group%2Fforked-project/merge_requests/1)
        # Control bytes are built at runtime (printf octal) and JSON-encoded
        # by jq, so this source stays pure ASCII yet the provider payload
        # carries real ESC/BEL/C1-CSI content for the sanitizer to strip.
        jq -cn --arg t "$(printf 'Fork\007 MR')" '{title:$t, state:"opened", author:{username:"review-bot"}, source_branch:"feature/source-project", target_branch:"main", web_url:"https://gitlab.com/example-group/forked-project/-/merge_requests/1"}'
        ;;
    */merge_requests/1/approvals)
        echo '{"approved_by":[]}'
        ;;
    */merge_requests/1/discussions)
        jq -cn \
            --arg b1 "$(printf 'literal\033\007\302\233 reviewer note')" \
            --arg b2 "$(printf 'open\033\302\233 thread body')" \
            '[
              {notes: [
                {system:false, author:{username:"a.b"}, body:$b1, created_at:"2026-01-01T00:00:00Z", position:null},
                {system:false, author:{username:"aXb"}, body:"regex wildcard note", created_at:"2026-01-01T00:00:00Z", position:null}]},
              {id:"thr1", notes: [
                {system:false, resolvable:true, resolved:false, author:{username:"a.b"}, body:$b2, created_at:"2026-01-01T00:00:00Z", position:null}]}
            ]'
        ;;
    *)
        echo "unexpected glab api path: $path" >&2
        exit 1
        ;;
esac
BASH
    chmod +x "$BIN_DIR/glab"
}

run_ws_review() {
    run env \
        "PATH=$BIN_DIR:$PATH" \
        "ROOT_DIR=$WORK" \
        "COMPONENTS_DIR=$WORK/components" \
        "REALMS_DIR=$WORK/realms" \
        "HOARDS_DIR=$WORK/hoards" \
        "ECOSYSTEM=$WORK/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$WORK/ecosystem.local.yaml" \
        "GITLAB_TOKEN=dummy-token" \
        "GITLAB_HOST=ambient.example" \
        "GLAB_EXPECTED_HOST=gitlab.com" \
        "GLAB_BODY_LOG=$BODY_LOG" \
        bash "$WS_BIN" review "$@"
}

# Runtime-built control-byte probes: ESC, BEL, and the UTF-8 encoding of the
# C1 CSI control U+009B. Built via printf so this source file itself never
# carries a raw control byte.
probe_esc() { printf '\033'; }
probe_bel() { printf '\007'; }
probe_csi() { printf '\302\233'; }

@test "review errors actionably when a CR number exists on multiple remotes" {
    run_ws_review app 1 --compact

    [ "$status" -ne 0 ]
    [[ "$output" == *"CR #1 found on multiple remotes"* ]]
    [[ "$output" == *"origin=upstream-group/project"* ]]
    [[ "$output" == *"fork=example-group/forked-project"* ]]
    [[ "$output" == *"--remote <name>"* ]]
}

@test "review deduplicates one host and project across remote transports" {
    git -C "$WORK/components/app" remote remove fork
    git -C "$WORK/components/app" remote add mirror git@gitlab.com:upstream-group/project.git

    run_ws_review app 1 --compact

    [ "$status" -eq 0 ]
    [[ "$output" == *"=== CR #1 (upstream-group/project) ==="* ]]
    [[ "$output" == *"Title: Upstream MR"* ]]
    [[ "$output" != *"found on multiple remotes"* ]]
}

@test "review --remote selects a specific remote and queries its project" {
    run_ws_review app 1 --remote fork --compact

    [ "$status" -eq 0 ]
    [[ "$output" == *"=== CR #1 (example-group/forked-project) ==="* ]]
    # The distinct per-project title proves the fork project endpoint was hit,
    # not just that the header slug was relabeled.
    [[ "$output" == *"Title: Fork MR"* ]]
    [[ "$output" != *"Upstream MR"* ]]
    [[ "$output" != *"found on multiple remotes"* ]]
}

@test "reply preserves a message that begins with --remote" {
    # The <message> positional is free-form; a message that starts with
    # --remote must reach the API verbatim, not be consumed as the flag.
    # The trailing --remote selects the remote (required: CR #1 exists on both).
    run_ws_review app reply 1 abc123 '--remote=spoof' --remote fork

    [ "$status" -eq 0 ]
    [[ "$output" == *"Replied to thread on CR #1 (example-group/forked-project)"* ]]
    [ "$(cat "$BODY_LOG")" = "--remote=spoof" ]
}

@test "GitLab provider rejects a thread ID that can steer the API path" {
    run_ws_review app reply 1 'thread/../../notes' 'unsafe path probe' --remote fork

    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to reply to thread"* ]]
    [ ! -e "$BODY_LOG" ]
}

@test "GitLab provider rejects bare dot-segment thread IDs" {
    # "." and ".." pass the character allowlist yet normalize to a
    # different API path — must be rejected as exact values.
    local id
    for id in '.' '..'; do
        run_ws_review app reply 1 "$id" 'dot probe' --remote fork
        [ "$status" -ne 0 ]
        [[ "$output" == *"Failed to reply to thread"* ]]
    done
    [ ! -e "$BODY_LOG" ]
}

@test "GitLab provider rejects an invalid thread ID during resolve" {
    run_ws_review app threads 1 --resolve 'thread/../../notes' --remote fork

    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to resolve thread"* ]]
    [ ! -e "$BODY_LOG" ]
}

@test "review --reviewer matches literal login instead of regex wildcard" {
    run_ws_review app 1 --remote fork --reviewer a.b --compact

    [ "$status" -eq 0 ]
    [[ "$output" == *"literal reviewer note"* ]]
    [[ "$output" != *"regex wildcard note"* ]]
}

@test "review strips terminal control bytes from provider text" {
    run_ws_review app 1 --remote fork --reviewer a.b

    [ "$status" -eq 0 ]
    [[ "$output" == *"Title: Fork MR"* ]]
    [[ "$output" == *"literal"*"reviewer note"* ]]
    [[ "$output" != *"$(probe_esc)"* ]]
    [[ "$output" != *"$(probe_bel)"* ]]
    [[ "$output" != *"$(probe_csi)"* ]]
}

@test "notes strips terminal control bytes from provider text" {
    run_ws_review app notes 1 --remote fork

    [ "$status" -eq 0 ]
    [[ "$output" == *"literal"*"reviewer note"* ]]
    [[ "$output" != *"$(probe_esc)"* ]]
    [[ "$output" != *"$(probe_bel)"* ]]
    [[ "$output" != *"$(probe_csi)"* ]]
}

@test "threads listing strips terminal control bytes from provider text" {
    run_ws_review app threads 1 --remote fork

    [ "$status" -eq 0 ]
    [[ "$output" == *"open"*"thread body"* ]]
    [[ "$output" != *"$(probe_esc)"* ]]
    [[ "$output" != *"$(probe_csi)"* ]]
}
