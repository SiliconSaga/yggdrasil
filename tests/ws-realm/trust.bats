#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"
REALM_LIB="$REPO_ROOT/scripts/ws-realm.sh"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    export ROOT_DIR="$WORK"
    export REALMS_DIR="$WORK/realms"
    export COMPONENTS_DIR="$WORK/components"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    mkdir -p "$REALMS_DIR/realm.test/adapters" "$REALMS_DIR/realm.test/tools" "$COMPONENTS_DIR/app" "$HOARDS_DIR"
    printf 'components: {}\n' > "$ECOSYSTEM"
    printf 'notes: keep\n' > "$ECOSYSTEM_LOCAL"
    cat > "$REALMS_DIR/realm.test/ecosystem.yaml" <<'YAML'
defaults:
  gitProviders:
    git.example.com: gitlab
  gitTokens:
    git.example.com/team: GITLAB_TEAM_TOKEN
components:
  app:
    tier: supporting
    repo: https://git.example.com/team/app.git
mcp:
  servers:
    assistant:
      transport: http
      url: https://mcp.example.com/api
YAML
    cat > "$REALMS_DIR/realm.test/adapters/app.yaml" <<'YAML'
commands:
  test: uv run pytest
  lint: uv run ruff check
YAML
    cat > "$REALMS_DIR/realm.test/adapters/tool.yaml" <<'YAML'
commands:
  test: go test ./...
YAML
}

approve_realm() {
    run bash "$WS_BIN" realm use --trust realm.test
    [ "$status" -eq 0 ]
}

run_trust_state() {
    run bash -c 'source "$1"; ws_realm_trust_state realm.test' _ "$REALM_LIB"
}

@test "realm approval stores the selected realm and semantic fingerprint" {
    approve_realm

    [ "$(yq '.realm' "$ECOSYSTEM_LOCAL")" = "realm.test" ]
    [ "$(yq '._gdd.realmTrust.realm' "$ECOSYSTEM_LOCAL")" = "realm.test" ]
    [ -n "$(yq '._gdd.realmTrust.fingerprint // ""' "$ECOSYSTEM_LOCAL")" ]

    run_trust_state
    [ "$status" -eq 0 ]
    [ "$output" = "current" ]
}

@test "realm trust summary identifies each component repository route" {
    run bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"app"*"git.example.com"*"https://git.example.com/team/app.git"* ]]
}

@test "realm approval rejects invalid component keys without rendering them" {
    cat > "$REALMS_DIR/realm.test/ecosystem.yaml" <<'YAML'
components:
  ../outside:
    repo: https://example.test/outside.git
YAML

    run bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid component name"* ]]
    [[ "$output" != *"../outside"* ]]
    [ "$(yq '.realm // ""' "$ECOSYSTEM_LOCAL")" = "" ]
}

@test "realm fingerprint ignores YAML comments formatting and mapping order" {
    approve_realm
    cat > "$REALMS_DIR/realm.test/ecosystem.yaml" <<'YAML'
# The same semantic trust values in a different presentation.
mcp: {servers: {assistant: {url: https://mcp.example.com/api, transport: http}}}
components:
  app: {repo: https://git.example.com/team/app.git, tier: supporting}
defaults:
  gitTokens: {git.example.com/team: GITLAB_TEAM_TOKEN}
  gitProviders: {git.example.com: gitlab}
YAML

    run_trust_state

    [ "$status" -eq 0 ]
    [ "$output" = "current" ]
}

@test "realm trust becomes stale when ecosystem semantics change" {
    approve_realm
    COMPONENT_REPO="https://git.example.com/other/app.git" yq -i \
        '.components.app.repo = strenv(COMPONENT_REPO)' \
        "$REALMS_DIR/realm.test/ecosystem.yaml"

    run_trust_state

    [ "$status" -eq 0 ]
    [ "$output" = "stale" ]
}

@test "realm trust becomes stale when an adapter command changes" {
    approve_realm
    ADAPTER_TEST="uv run pytest -q" yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm.test/adapters/app.yaml"

    run_trust_state

    [ "$status" -eq 0 ]
    [ "$output" = "stale" ]
}

@test "realm trust becomes stale when an adapter-referenced realm file changes" {
    printf '#!/usr/bin/env bash\necho original\n' > "$REALMS_DIR/realm.test/tools/run-tests.sh"
    ADAPTER_TEST='bash "../../realms/realm.test/tools/run-tests.sh"' yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm.test/adapters/app.yaml"
    approve_realm

    printf '#!/usr/bin/env bash\necho changed\n' > "$REALMS_DIR/realm.test/tools/run-tests.sh"
    run_trust_state

    [ "$status" -eq 0 ]
    [ "$output" = "stale" ]
}

@test "realm trust ignores unrelated documentation changes" {
    printf 'first\n' > "$REALMS_DIR/realm.test/README.md"
    approve_realm

    printf 'second\n' > "$REALMS_DIR/realm.test/README.md"
    run_trust_state

    [ "$status" -eq 0 ]
    [ "$output" = "current" ]
}

@test "realm approval rejects adapter-referenced symlinks" {
    printf '#!/usr/bin/env bash\necho original\n' > "$REALMS_DIR/realm.test/tools/run-tests.sh"
    ln -s run-tests.sh "$REALMS_DIR/realm.test/tools/run-tests-link.sh"
    ADAPTER_TEST='bash "../../realms/realm.test/tools/run-tests-link.sh"' yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm.test/adapters/app.yaml"

    run bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -ne 0 ]
    [[ "$output" == *"referenced realm trust input must not be a symlink"* ]]
}

@test "realm trust distinguishes missing and malformed approval state" {
    REALM_NAME="realm.test" yq -i '.realm = strenv(REALM_NAME)' "$ECOSYSTEM_LOCAL"

    run_trust_state
    [ "$status" -eq 0 ]
    [ "$output" = "missing" ]

    yq -i '._gdd.realmTrust = {"realm": "realm.test", "fingerprint": []}' "$ECOSYSTEM_LOCAL"
    run_trust_state
    [ "$status" -eq 0 ]
    [ "$output" = "error" ]
}

@test "ws list succeeds when an unselected realm template directory exists" {
    mkdir -p "$REALMS_DIR/realm-template"
    printf 'components: {}\n' > "$REALMS_DIR/realm-template/ecosystem.yaml"

    run bash "$WS_BIN" list

    [ "$status" -eq 0 ]
}

@test "explicitly selected realm without approval fails with activation guidance" {
    REALM_NAME="realm.test" yq -i '.realm = strenv(REALM_NAME)' "$ECOSYSTEM_LOCAL"

    run bash -c 'source "$1"; ws_resolve_ecosystem' _ "$REALM_LIB"

    [ "$status" -ne 0 ]
    [[ "$output" == *"reapproval"* ]]
    [[ "$output" == *"ws realm use realm.test"* ]]
}

@test "realm reapproval records changed trust and restores current state" {
    approve_realm
    ADAPTER_TEST="uv run pytest -q" yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm.test/adapters/app.yaml"
    run_trust_state
    [ "$output" = "stale" ]

    approve_realm
    run_trust_state

    [ "$status" -eq 0 ]
    [ "$output" = "current" ]
}

@test "realm approval refuses trust inputs that change while the summary is rendered" {
    local reviewed_fingerprint
    reviewed_fingerprint="$(bash -c 'source "$1"; ws_realm_trust_fingerprint realm.test' _ "$REALM_LIB")"
    ADAPTER_TEST="uv run pytest -q" yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm.test/adapters/app.yaml"

    run bash -c 'source "$1"; ws_realm_record_approval realm.test "$2"' \
        _ "$REALM_LIB" "$reviewed_fingerprint"

    [ "$status" -ne 0 ]
    [[ "$output" == *"changed while"*"reviewed"* ]]
    [ "$(yq '.realm // ""' "$ECOSYSTEM_LOCAL")" = "" ]
}

@test "realm ecosystem resolution fails closed after trust drift" {
    approve_realm
    run bash -c 'source "$1"; ws_resolve_ecosystem' _ "$REALM_LIB"
    [ "$status" -eq 0 ]

    ADAPTER_TEST="uv run pytest -q" yq -i \
        '.commands.test = strenv(ADAPTER_TEST)' \
        "$REALMS_DIR/realm.test/adapters/app.yaml"
    run bash -c 'source "$1"; ws_resolve_ecosystem' _ "$REALM_LIB"

    [ "$status" -ne 0 ]
    [[ "$output" == *"reapproval"* ]]
    [[ "$output" == *"ws realm use realm.test"* ]]
}
