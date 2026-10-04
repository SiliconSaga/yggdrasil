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
  *"/pulls/comments/501") payload="{\"pull_request_url\":\"${COMMENT_API:-https://api.github.com}/repos/${COMMENT_REPO:-owner/repo}/pulls/${COMMENT_PR:-1}\"}" ;;
  *"/issues/comments/601") payload="{\"issue_url\":\"${COMMENT_API:-https://api.github.com}/repos/${COMMENT_REPO:-owner/repo}/issues/${COMMENT_PR:-1}\"}" ;;
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

@test "gitlab inline comment output carries a note- prefixed id" {
    # Executes the function rather than counting source text: a grep passes even if the jq filter emits a malformed id, attaches it to the wrong record, or produces nothing at all.
    cat > "$STUB_DIR/glab" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "glab" "$@" >> "$API_LOG"
echo '[{"notes":[{"id":701,"type":"DiffNote","system":false,"author":{"username":"rev"},"body":"inline text","position":{"new_path":"a.sh","new_line":10}}]}]'
SH
    chmod +x "$STUB_DIR/glab"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_review_list_comments group/project 1
    [[ "$output" == *"id:note-701"* ]]
    [[ "$output" == *"inline text"* ]]
    [[ "$output" == *"a.sh:10"* ]]
}

@test "gitlab note output carries a note- prefixed id" {
    cat > "$STUB_DIR/glab" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "glab" "$@" >> "$API_LOG"
echo '[{"notes":[{"id":801,"system":false,"author":{"username":"rev"},"body":"note text","position":null}]}]'
SH
    chmod +x "$STUB_DIR/glab"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_review_list_notes group/project 1
    [[ "$output" == *"id:note-801"* ]]
    [[ "$output" == *"note text"* ]]
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

@test "github comment edits refuse other PRs and repositories without PATCH" {
    source "$REPO_ROOT/scripts/providers/github.sh"
    local comment
    for comment in inline-501 issue-601; do
        : > "$API_LOG"
        export COMMENT_PR=2
        run gp_update_comment owner/repo 1 "$comment" "new text"
        [ "$status" -ne 0 ]
        [[ "$output" == *"Nothing was edited"* ]]
        run grep -Fx PATCH "$API_LOG"
        [ "$status" -ne 0 ]
        unset COMMENT_PR
        export COMMENT_REPO=someone/else
        run gp_update_comment owner/repo 1 "$comment" "new text"
        [ "$status" -ne 0 ]
        unset COMMENT_REPO
        run grep -Fx PATCH "$API_LOG"
        [ "$status" -ne 0 ]
    done
}

@test "github comment edits refuse missing ownership information without PATCH" {
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_comment owner/repo 1 inline-999 "new text"
    [ "$status" -ne 0 ]
    run grep -Fx PATCH "$API_LOG"
    [ "$status" -ne 0 ]
}

@test "github comment ownership accepts case variants, repos-named slugs and enterprise URLs" {
    source "$REPO_ROOT/scripts/providers/github.sh"
    local slug comment api
    for api in https://api.github.com https://git.example.test/api/v3; do
        export COMMENT_API="$api"
        for slug in owner/repos repos/project Owner/Repo; do
            export COMMENT_REPO="$slug"
            for comment in inline-501 issue-601; do
                run gp_update_comment "$slug" 1 "$comment" "new text"
                [ "$status" -eq 0 ]
            done
        done
    done
    export COMMENT_REPO=OWNER/REPO
    run gp_update_comment owner/repo 1 inline-501 "new text"
    [ "$status" -eq 0 ]
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
