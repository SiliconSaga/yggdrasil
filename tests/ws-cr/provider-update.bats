#!/usr/bin/env bats

# Provider-level tests for gp_update_pr / gp_update_issue in both providers.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"
    BODY="$WORK/body.md"
    printf 'Updated body text.\n' > "$BODY"

    STUB_DIR="$BATS_TEST_TMPDIR/stub"
    export API_LOG="$BATS_TEST_TMPDIR/api.log"
    mkdir -p "$STUB_DIR"
    for tool in gh glab; do
        # One argument per line, unescaped: %q would render `title=New title` as `title=New\ title` and make every assertion about a value containing a space read as a code failure when it is a logging artifact.
        cat > "$STUB_DIR/$tool" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" "$@" >> "$API_LOG"
exit 0
SH
        chmod +x "$STUB_DIR/$tool"
    done
    export PATH="$STUB_DIR:$PATH"

    # github.sh calls ws_native_path on create paths; the update paths do not, but sourcing the file must not fail if the helper is absent.
    ws_native_path() { printf '%s\n' "$1"; }
}

@test "github gp_update_pr PATCHes the pulls endpoint with the body" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number 42 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"PATCH"* ]]
    [[ "$output" == *"repos/owner/repo/pulls/42"* ]]
    [[ "$output" == *"Updated body text."* ]]
}

@test "github gp_update_pr omits title when not given" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    gp_update_pr --repo owner/repo --number 42 --body-file "$BODY"
    run cat "$API_LOG"
    [[ "$output" != *"title="* ]]
}

@test "github gp_update_pr sends title when given" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    gp_update_pr --repo owner/repo --number 42 --body-file "$BODY" --title "New title"
    run cat "$API_LOG"
    [[ "$output" == *"title=New title"* ]]
}

@test "github gp_update_issue PATCHes the issues endpoint" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_issue --repo owner/repo --number 7 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"repos/owner/repo/issues/7"* ]]
}

@test "gitlab gp_update_pr PUTs the merge_requests endpoint with description" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_pr --repo group/project --number 42 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"PUT"* ]]
    [[ "$output" == *"group%2Fproject/merge_requests/42"* ]]
    [[ "$output" == *"description=Updated body text."* ]]
}

@test "gitlab gp_update_issue PUTs the issues endpoint" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_issue --repo group/project --number 7 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"group%2Fproject/issues/7"* ]]
}

@test "gitlab gp_update_pr sends title when given" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    gp_update_pr --repo group/project --number 42 --body-file "$BODY" --title "New title"
    run cat "$API_LOG"
    [[ "$output" == *"title=New title"* ]]
}

@test "a non-numeric number is rejected before any API call" {
    # The number is interpolated into an API path. A slug is provider-checked elsewhere; the number never was.
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number "1;rm" --body-file "$BODY"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}

@test "an empty number is rejected before any API call" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_pr --repo group/project --number "" --body-file "$BODY"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}

@test "a missing body file is rejected before any API call" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number 42 --body-file "$WORK/absent.md"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}

@test "an unknown argument is rejected before any API call" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number 42 --body-file "$BODY" --draft
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}
