#!/usr/bin/env bats

# Comment ids in ws review output, and gp_update_comment's routing off the id kind.
#
# `ws review` printed ids for threads but never for notes or inline comments, so a reader could see a comment and had no way to name it. That is a gap on its own, and the prerequisite for editing one.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    STUB_DIR="$BATS_TEST_TMPDIR/stub"
    export API_LOG="$BATS_TEST_TMPDIR/api.log"
    mkdir -p "$STUB_DIR"

    # The list functions build their entire output inside a --jq filter, so a stub returning raw JSON would test nothing — it would pass against a filter that emits no id at all. Apply the filter with real jq, the way gh does.
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
endpoint=""
filter=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--jq" ]]; then filter="$arg"; prev=""; continue; fi
  case "$arg" in
    --jq) prev="--jq" ;;
    api|--method|PATCH|-f) prev="" ;;
    -*) prev="" ;;
    *) [[ -z "$endpoint" && "$arg" == *"/"* ]] && endpoint="$arg"; prev="" ;;
  esac
done
printf '%s\n' "gh" "$@" >> "$API_LOG"
case "$endpoint" in
  *"/pulls/1/comments")  payload='[{"id":501,"user":{"login":"rev"},"path":"a.sh","line":10,"body":"inline text"}]' ;;
  *"/issues/1/comments") payload='[{"id":601,"user":{"login":"rev"},"body":"note text"}]' ;;
  *) payload='[]' ;;
esac
if [[ -n "$filter" ]]; then
  printf '%s' "$payload" | jq -r "$filter"
fi
exit 0
SH
    chmod +x "$STUB_DIR/gh"

    cat > "$STUB_DIR/glab" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "glab" "$@" >> "$API_LOG"
exit 0
SH
    chmod +x "$STUB_DIR/glab"
    export PATH="$STUB_DIR:$PATH"

    ws_native_path() { printf '%s\n' "$1"; }
}

@test "github inline comment output carries an inline- prefixed id" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_review_list_comments owner/repo 1
    [[ "$output" == *"id:inline-501"* ]]
    [[ "$output" == *"inline text"* ]]
}

@test "github note output carries an issue- prefixed id" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_review_list_notes owner/repo 1
    [[ "$output" == *"id:issue-601"* ]]
    [[ "$output" == *"note text"* ]]
}

@test "github inline comment output keeps its path and line" {
    # The id is added beside the existing locator, not in place of it.
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_review_list_comments owner/repo 1
    [[ "$output" == *"a.sh:10"* ]]
}

@test "gitlab list functions emit a note- prefixed id" {
    run grep -c 'id:note-' "$REPO_ROOT/scripts/providers/gitlab.sh"
    [ "$output" = "2" ]
}

@test "gp_update_comment routes an inline id to the pulls endpoint" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_comment owner/repo 1 inline-501 "new text"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"repos/owner/repo/pulls/comments/501"* ]]
}

@test "gp_update_comment routes an issue id to the issues endpoint" {
    # GitHub edits a top-level note and an inline review comment through different resources; reading the kind off the id is what avoids probing both.
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_comment owner/repo 1 issue-601 "new text"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"repos/owner/repo/issues/comments/601"* ]]
}

@test "gp_update_comment rejects an unknown id kind" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_comment owner/repo 1 thread-501 "new text"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown comment id kind"* ]]
    [ ! -s "$API_LOG" ]
}

@test "gp_update_comment rejects a non-numeric id tail" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_comment owner/repo 1 "issue-6;rm" "new text"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}

@test "gitlab gp_update_comment PUTs the nested notes endpoint" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_comment group/project 1 note-701 "new text"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"group%2Fproject/merge_requests/1/notes/701"* ]]
    [[ "$output" == *"PUT"* ]]
}

@test "gitlab gp_update_comment rejects a github-shaped id" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_comment group/project 1 inline-701 "new text"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}
