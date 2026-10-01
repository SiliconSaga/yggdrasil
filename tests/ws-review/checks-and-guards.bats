#!/usr/bin/env bats

# Three review-flow papercuts against a stubbed GitHub:
#   - `ws review <comp> checks <cr#>` answers "is CI green" in one call, and
#     the same summary heads the full review.
#   - `threads --resolve-all` sweeps only what was open BEFORE the last push;
#     a bot round that landed after it is new feedback, not stale.
#   - `reply` refuses an id that is not a thread id, and a thread that belongs
#     to a different CR, before anything is posted.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"
    WORK="$BATS_TEST_TMPDIR/work"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    export API_LOG="$WORK/gh-api.log"
    mkdir -p "$WORK/components/app" "$WORK/realms" "$WORK/hoards" "$BIN_DIR"

    cat > "$WORK/ecosystem.yaml" <<'YAML'
identity:
  human_account: reviewer
components:
  app:
    repo: https://github.com/owner/repo.git
YAML

    git -C "$WORK/components/app" init -q -b feature
    git -C "$WORK/components/app" config user.name "Test User"
    git -C "$WORK/components/app" config user.email "test@example.local"
    echo "hello" > "$WORK/components/app/README.md"
    git -C "$WORK/components/app" add README.md
    git -C "$WORK/components/app" commit -q -m "seed"
    git -C "$WORK/components/app" remote add origin https://github.com/owner/repo.git

    # The review header fetches the base branch for its drift check; a real
    # fetch of github.com has no place in a test. Fail it the way an
    # unauthenticated fetch does; everything else goes to the real git.
    local real_git
    real_git="$(command -v git)"
    cat > "$BIN_DIR/git" <<BASH
#!/usr/bin/env bash
for arg in "\$@"; do
    [[ "\$arg" == "fetch" ]] && exit 1
done
exec "$real_git" "\$@"
BASH
    chmod +x "$BIN_DIR/git"

    # gh stub: picks a payload by endpoint (or by the GraphQL operation named
    # in the query), applies any --jq with real jq the way gh does, and logs
    # every call so a test can prove what was and was not sent.
    cat > "$BIN_DIR/gh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "gh $*" >> "$API_LOG"
[[ "${1:-}" == "auth" ]] && exit 0

filter=""
endpoint=""
query=""
node_id=""
slurp=0
prev=""
for arg in "$@"; do
    case "$prev" in
        --jq) filter="$arg"; prev=""; continue ;;
        -f|-F)
            case "$arg" in
                query=*) query="${arg#query=}" ;;
                id=*)    node_id="${arg#id=}" ;;
            esac
            prev=""; continue ;;
    esac
    case "$arg" in
        --jq|-f|-F) prev="$arg" ;;
        --slurp) slurp=1 ;;
        repos/*) [[ -z "$endpoint" ]] && endpoint="${arg%%\?*}" ;;
        graphql) endpoint="graphql" ;;
    esac
done

SHA="dddddddddddddddddddddddddddddddddddddddd"
payload=""
case "$endpoint" in
    repos/owner/repo/pulls/1)
        payload="{\"title\":\"Checks PR\",\"state\":\"open\",\"user\":{\"login\":\"author\"},\"head\":{\"ref\":\"feature\",\"sha\":\"$SHA\"},\"base\":{\"ref\":\"main\"},\"html_url\":\"https://github.com/owner/repo/pull/1\"}"
        ;;
    repos/owner/repo/commits/$SHA/check-runs)
        if [[ "${CHECKS_API_DOWN:-}" == "1" ]]; then
            echo "HTTP 502" >&2
            exit 1
        fi
        if [[ "${CHECKS_ALL_GREEN:-}" == "1" ]]; then
            payload='{"check_runs":[{"name":"Full suite","status":"completed","conclusion":"success","html_url":"https://ci/1"}]}'
        else
            payload='{"check_runs":[{"name":"Full suite","status":"completed","conclusion":"success","html_url":"https://ci/1"},{"name":"lint","status":"completed","conclusion":"failure","html_url":"https://ci/2"}]}'
        fi
        ;;
    repos/owner/repo/commits/$SHA/status)
        payload='{"statuses":[{"context":"CodeRabbit","state":"success","target_url":"https://cr/1"}]}'
        ;;
    repos/owner/repo/pulls/1/reviews|repos/owner/repo/pulls/1/comments|repos/owner/repo/issues/1/comments)
        payload='[]'
        ;;
    repos/owner/repo/events)
        if [[ "${NO_PUSH_INFO:-}" == "1" ]]; then
            payload='[]'
        else
            payload="[{\"type\":\"PushEvent\",\"created_at\":\"2026-09-30T12:00:00Z\",\"payload\":{\"ref\":\"refs/heads/feature\",\"before\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"head\":\"$SHA\"}}]"
        fi
        ;;
    repos/owner/repo/branches/feature)
        payload="{\"commit\":{\"sha\":\"$SHA\"}}"
        ;;
    repos/owner/repo/commits/$SHA/check-suites)
        payload='[{"total_count":0,"check_suites":[]}]'
        ;;
    graphql)
        case "$query" in
            *reviewThreads*)
                payload='{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"PRRT_old","isResolved":false,"comments":{"nodes":[{"createdAt":"2026-09-30T11:00:00Z"}]}},{"id":"PRRT_new","isResolved":false,"comments":{"nodes":[{"createdAt":"2026-09-30T13:00:00Z"}]}}]}}}}}'
                ;;
            *"node(id"*)
                case "$node_id" in
                    PRRT_old|PRRT_new) payload='{"data":{"node":{"pullRequest":{"number":1,"repository":{"nameWithOwner":"owner/repo"}}}}}' ;;
                    PRRT_other)        payload='{"data":{"node":{"pullRequest":{"number":2,"repository":{"nameWithOwner":"owner/repo"}}}}}' ;;
                    PRRT_elsewhere)    payload='{"data":{"node":{"pullRequest":{"number":1,"repository":{"nameWithOwner":"someone/else"}}}}}' ;;
                    PRRT_offline)      echo "HTTP 502" >&2; exit 1 ;;
                    *)                 payload='{"data":{"node":null}}' ;;
                esac
                ;;
            *) payload='{"data":{}}' ;;
        esac
        ;;
    *)
        echo "unexpected gh endpoint: $endpoint" >&2
        exit 1
        ;;
esac

if [[ -n "$filter" ]]; then
    printf '%s' "$payload" | jq -r "$filter"
else
    printf '%s\n' "$payload"
fi
BASH
    chmod +x "$BIN_DIR/gh"
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
        "GH_TOKEN=dummy-token" \
        "WS_FOOTER_DISABLE=1" \
        ${WS_REVIEW_EXTRA_ENV[@]+"${WS_REVIEW_EXTRA_ENV[@]}"} \
        bash "$WS_BIN" review "$@"
}

@test "checks lists every check with its state and exits non-zero on a failure" {
    run_ws_review app checks 1

    [ "$status" -ne 0 ]
    [[ "$output" == *"=== Checks: CR #1 (owner/repo) ==="* ]]
    [[ "$output" == *"✓ pass     Full suite"* ]]
    [[ "$output" == *"✗ fail     lint"* ]]
    [[ "$output" == *"✓ pass     CodeRabbit"* ]]
    [[ "$output" == *"Checks: 2 pass, 1 fail, 0 pending"* ]]
}

@test "checks exits zero when everything passed" {
    WS_REVIEW_EXTRA_ENV=("CHECKS_ALL_GREEN=1")
    run_ws_review app checks 1

    [ "$status" -eq 0 ]
    [[ "$output" == *"Checks: 2 pass, 0 fail, 0 pending"* ]]
}

@test "the review header carries the checks summary" {
    run_ws_review app 1 --compact

    [ "$status" -eq 0 ]
    [[ "$output" == *"Title: Checks PR"* ]]
    [[ "$output" == *"Checks: 2 pass, 1 fail, 0 pending"* ]]
}

@test "resolve-all leaves a thread opened after the last push alone" {
    run_ws_review app threads 1 --resolve-all

    [ "$status" -eq 0 ]
    [[ "$output" == *"Left 1 thread(s) opened after the last push (2026-09-30T12:00:00Z) unresolved"* ]]
    [[ "$output" == *"Resolved 1 threads"* ]]
    run grep -c 'resolveReviewThread' "$API_LOG"
    [ "$output" = "1" ]
    # The mutation is the only call in this flow that names a thread id, so
    # the ids in the log are exactly the ones resolved.
    run grep -c 'id=PRRT_old' "$API_LOG"
    [ "$output" = "1" ]
    run grep -c 'id=PRRT_new' "$API_LOG"
    [ "$output" = "0" ]
}

@test "resolve-all sweeps everything, with a note, when no push time can be found" {
    WS_REVIEW_EXTRA_ENV=("NO_PUSH_INFO=1")
    run_ws_review app threads 1 --resolve-all

    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTE: no push time available"* ]]
    [[ "$output" == *"Resolved 2 threads"* ]]
}

@test "reply refuses an id that is not a thread id, before posting" {
    run_ws_review app reply 1 inline-501 "looks fine"

    [ "$status" -ne 0 ]
    [[ "$output" == *"'inline-501' is not a thread id"* ]]
    [[ "$output" == *"ws review app threads 1"* ]]
    run grep -c 'addPullRequestReviewThreadReply' "$API_LOG"
    [ "$output" = "0" ]
}

@test "reply refuses a thread that belongs to another CR, before posting" {
    run_ws_review app reply 1 PRRT_other "looks fine"

    [ "$status" -ne 0 ]
    [[ "$output" == *"belongs to owner/repo#2, not owner/repo#1. Nothing was posted."* ]]
    run grep -c 'addPullRequestReviewThreadReply' "$API_LOG"
    [ "$output" = "0" ]
}

@test "reply refuses a same-numbered thread from another repository" {
    # Thread ids are global, so another repository's #1 is not this #1.
    run_ws_review app reply 1 PRRT_elsewhere "looks fine"

    [ "$status" -ne 0 ]
    [[ "$output" == *"belongs to someone/else#1, not owner/repo#1"* ]]
    run grep -c 'addPullRequestReviewThreadReply' "$API_LOG"
    [ "$output" = "0" ]
}

@test "reply fails closed when the thread's location cannot be confirmed" {
    run_ws_review app reply 1 PRRT_offline "looks fine"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not confirm that thread PRRT_offline is on CR #1"* ]]
    run grep -c 'addPullRequestReviewThreadReply' "$API_LOG"
    [ "$output" = "0" ]
}

@test "checks fails rather than reporting a partial answer when an endpoint is down" {
    WS_REVIEW_EXTRA_ENV=("CHECKS_API_DOWN=1")
    run_ws_review app checks 1

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not fetch checks"* ]]
    [[ "$output" != *"Checks: 0 pass"* ]]
}

@test "the review header says checks are unavailable when an endpoint is down" {
    WS_REVIEW_EXTRA_ENV=("CHECKS_API_DOWN=1")
    run_ws_review app 1 --compact

    [ "$status" -eq 0 ]
    [[ "$output" == *"Checks: unavailable"* ]]
}

@test "reply posts to a thread that is on this CR" {
    run_ws_review app reply 1 PRRT_old "looks fine"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Replied to thread on CR #1"* ]]
    run grep -c 'addPullRequestReviewThreadReply' "$API_LOG"
    [ "$output" = "1" ]
}
