#!/usr/bin/env bats

# End-to-end tests for `ws review <comp> edit` — rewriting a comment you already posted, with the attribution banner reattached.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    WORK="$BATS_TEST_TMPDIR/work"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    BODY_LOG="$WORK/glab-put-body.txt"
    PATH_LOG="$WORK/glab-put-path.txt"
    mkdir -p "$WORK/components/app" "$WORK/realms" "$WORK/hoards" "$BIN_DIR" "$WORK/.crs"

    cat > "$WORK/ecosystem.yaml" <<'YAML'
defaults:
  gitProviders:
    gitlab.com: gitlab
  gddHome: https://example.test/gdd/
identity:
  human_account: reviewer
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

    printf 'Corrected explanation.\n' > "$WORK/.crs/note.md"

    cat > "$BIN_DIR/glab" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

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

if [[ "$method" == "PUT" && "$path" == */notes/* ]]; then
    printf '%s' "$body" > "${GLAB_BODY_LOG:-/dev/null}"
    printf '%s' "$path" > "${GLAB_PATH_LOG:-/dev/null}"
    echo '{"id":1}'
    exit 0
fi

case "$path" in
    projects/upstream-group%2Fproject/merge_requests/1)
        echo '{"title":"Upstream MR","state":"opened","author":{"username":"review-bot"},"source_branch":"feature/upstream","target_branch":"main","web_url":"https://gitlab.com/upstream-group/project/-/merge_requests/1"}'
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
        "ECOSYSTEM_LOCAL=$WORK/ecosystem.yaml" \
        "GITLAB_TOKEN=dummy-token" \
        "GITLAB_HOST=gitlab.com" \
        "GLAB_BODY_LOG=$BODY_LOG" \
        "GLAB_PATH_LOG=$PATH_LOG" \
        bash "$WS_BIN" review "$@"
}

@test "edit rewrites a note through the nested notes endpoint" {
    run_ws_review app edit 1 note-701 "$WORK/.crs/note.md"

    [ "$status" -eq 0 ]
    [[ "$(cat "$PATH_LOG")" == "projects/upstream-group%2Fproject/merge_requests/1/notes/701" ]]
}

@test "an edited comment carries the attribution banner" {
    run_ws_review app edit 1 note-701 "$WORK/.crs/note.md"

    [ "$status" -eq 0 ]
    [[ "$(cat "$BODY_LOG")" == "> _Agent-authored comment"* ]]
    [[ "$(cat "$BODY_LOG")" == *"@reviewer"* ]]
}

@test "the edited body follows the banner verbatim" {
    run_ws_review app edit 1 note-701 "$WORK/.crs/note.md"

    [ "$status" -eq 0 ]
    [[ "$(cat "$BODY_LOG")" == *$'\n\n'"Corrected explanation." ]]
}

@test "the banner is regenerated, not carried over from the old body" {
    # A comment posted without a banner gains one on its first edit — the case that motivated the verb. Nothing in the flow reads the existing comment, so this is structural: assert the banner comes from the generator.
    run grep -q 'ws_gdd_attribution_line "comment"' "$REPO_ROOT/scripts/ws-review.sh"
    [ "$status" -eq 0 ]
}

@test "edit reports the comment it updated" {
    run_ws_review app edit 1 note-701 "$WORK/.crs/note.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated comment note-701 on CR #1"* ]]
}

@test "an unprefixed comment id is rejected" {
    run_ws_review app edit 1 701 "$WORK/.crs/note.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"comment id must be"* ]]
    [ ! -e "$BODY_LOG" ]
}

@test "a comment id with a non-numeric tail is rejected" {
    run_ws_review app edit 1 "note-7;rm" "$WORK/.crs/note.md"

    [ "$status" -ne 0 ]
    [ ! -e "$BODY_LOG" ]
}

@test "a comment id with a path separator is rejected" {
    run_ws_review app edit 1 "note-7/../../projects/other" "$WORK/.crs/note.md"

    [ "$status" -ne 0 ]
    [ ! -e "$BODY_LOG" ]
}

@test "a non-numeric CR number is rejected" {
    run_ws_review app edit abc note-701 "$WORK/.crs/note.md"

    [ "$status" -ne 0 ]
    [ ! -e "$BODY_LOG" ]
}

@test "a missing bodyfile is rejected before any API call" {
    run_ws_review app edit 1 note-701 "$WORK/.crs/absent.md"

    [ "$status" -ne 0 ]
    [[ "$output" == *"body file not found"* ]]
    [ ! -e "$BODY_LOG" ]
}

@test "the wrong positional count fails with usage" {
    run_ws_review app edit 1 note-701

    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "edit appears in the review help" {
    run_ws_review app --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"edit <cr#> <comment-id> <bodyfile>"* ]]
}
