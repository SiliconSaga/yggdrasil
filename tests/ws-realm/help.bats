#!/usr/bin/env bats

# `ws realm init --help` must print usage and return, NOT start cloning the
# template realm. Regression for the dispatcher dropping args before
# ws_realm_init (so --help fell through and ran the command).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

@test "ws realm init --help prints usage and does not run" {
    run bash "$WS_BIN" realm init --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws realm init"* ]]
}

@test "ws realm init -h prints usage too" {
    run bash "$WS_BIN" realm init -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ws realm init"* ]]
}

@test "ws realm use writes active realm through yq env interpolation" {
    work="$BATS_TEST_TMPDIR/work"
    mkdir -p "$work/realms/realm.test" "$work/components" "$work/hoards"
    cat > "$work/ecosystem.yaml" <<'YAML'
components: {}
YAML
    cat > "$work/ecosystem.local.yaml" <<'YAML'
notes: keep
YAML
    printf 'components: {}\n' > "$work/realms/realm.test/ecosystem.yaml"

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm set to: realm.test"* ]]
    [ "$(yq '.realm' "$work/ecosystem.local.yaml")" = "realm.test" ]
    [ "$(yq '.notes' "$work/ecosystem.local.yaml")" = "keep" ]
}

@test "ws realm use requires explicit trust in a non-interactive session" {
    work="$BATS_TEST_TMPDIR/work-trust"
    mkdir -p "$work/realms/realm.test" "$work/components" "$work/hoards"
    printf 'components: {}\n' > "$work/ecosystem.yaml"
    printf 'notes: keep\n' > "$work/ecosystem.local.yaml"
    printf 'components: {}\n' > "$work/realms/realm.test/ecosystem.yaml"

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use realm.test

    [ "$status" -ne 0 ]
    [[ "$output" == *"--trust"* ]]
    [ "$(yq '.realm // ""' "$work/ecosystem.local.yaml")" = "" ]
}

@test "ws realm use --trust summarizes the trust surface before selection" {
    work="$BATS_TEST_TMPDIR/work-summary"
    mkdir -p "$work/realms/realm.test/adapters" "$work/components" "$work/hoards"
    printf 'components: {}\n' > "$work/ecosystem.yaml"
    printf 'notes: keep\n' > "$work/ecosystem.local.yaml"
    cat > "$work/realms/realm.test/ecosystem.yaml" <<'YAML'
defaults:
  gddHome: https://docs.example.com/gdd
  upstreamRemote: upstream
  gitProviders:
    git.example.com: gitlab
  gitTokens:
    git.example.com/team: GITLAB_TEAM_TOKEN
components:
  app:
    repo: https://git.example.com/team/app.git
    forkRepo: https://git.example.com/operator/app.git
identity:
  forkRemote: operator
  homes:
    fork:
      namespace: git.example.com/operator
mcp:
  servers:
    assistant:
      transport: http
      url: https://mcp.example.com/api
YAML
    cat > "$work/realms/realm.test/adapters/app.yaml" <<'YAML'
commands:
  test: uv run pytest
YAML

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"Realm trust summary"* ]]
    [[ "$output" == *$'  Component repository routes:\n'* ]]
    [[ "$output" == *$'  Adapter commands:\n    app:\n      test  uv run pytest'* ]]
    # The repo URL itself, not just the host — the host string also appears in
    # the gitTokens line, which once let a broken repo enumeration pass unseen.
    [[ "$output" == *"https://git.example.com/team/app.git"* ]]
    [[ "$output" == *"uv run pytest"* ]]
    [[ "$output" == *"GITLAB_TEAM_TOKEN"* ]]
    [[ "$output" == *"defaults.gddHome"*"https://docs.example.com/gdd"* ]]
    [[ "$output" == *"defaults.upstreamRemote"*"upstream"* ]]
    [[ "$output" == *"defaults.gitProviders.git.example.com"*"gitlab"* ]]
    [[ "$output" == *"https://git.example.com/operator/app.git"* ]]
    [[ "$output" == *"git.example.com/operator"* ]]
    [[ "$output" == *"forkRemote"*"operator"* ]]
    [[ "$output" == *"https://mcp.example.com/api"* ]]
    [[ "$output" == *"transport=http"* ]]
    [ "$(yq '.realm' "$work/ecosystem.local.yaml")" = "realm.test" ]
}

@test "ws realm use refuses adoption when adapter command extraction fails" {
    work="$BATS_TEST_TMPDIR/work-broken-adapter"
    mkdir -p "$work/realms/realm.test/adapters" "$work/components" "$work/hoards"
    printf 'components: {}\n' > "$work/ecosystem.yaml"
    printf 'notes: keep\n' > "$work/ecosystem.local.yaml"
    printf 'components: {}\n' > "$work/realms/realm.test/ecosystem.yaml"
    cat > "$work/realms/realm.test/adapters/app.yaml" <<'YAML'
commands:
  test: uv run pytest
  metadata:
    hidden: value
YAML

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot safely render adapter commands"* ]]
    [ "$(yq '.realm // ""' "$work/ecosystem.local.yaml")" = "" ]
}

@test "ws realm use --trust redacts embedded credentials in the trust summary" {
    work="$BATS_TEST_TMPDIR/work-redact"
    mkdir -p "$work/realms/realm.test" "$work/components" "$work/hoards"
    printf 'components: {}\n' > "$work/ecosystem.yaml"
    printf 'notes: keep\n' > "$work/ecosystem.local.yaml"
    cat > "$work/realms/realm.test/ecosystem.yaml" <<'YAML'
components:
  app:
    repo: https://oauth2:sekret123@git.example.com/team/app.git
YAML

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -eq 0 ]
    [[ "$output" != *"sekret123"* ]]
    [[ "$output" == *"[redacted]@git.example.com"* ]]
}

@test "ws realm use --trust strips terminal control sequences from the summary" {
    work="$BATS_TEST_TMPDIR/work-ansi"
    mkdir -p "$work/realms/realm.test/adapters" "$work/components" "$work/hoards"
    printf 'components: {}\n' > "$work/ecosystem.yaml"
    printf 'notes: keep\n' > "$work/ecosystem.local.yaml"
    printf 'components: {}\n' > "$work/realms/realm.test/ecosystem.yaml"
    cat > "$work/realms/realm.test/adapters/app.yaml" <<'YAML'
commands:
  test: "safe \x1b[2K\x1b[1A spoofed"
YAML

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use --trust realm.test

    [ "$status" -eq 0 ]
    [[ "$output" == *"safe"*"spoofed"* ]]
    [[ "$output" != *$'\x1b'* ]]
}

@test "ws realm use avoids direct yq string interpolation" {
    run grep -Fq 'yq -i ".realm = \"$name\""' "$REPO_ROOT/scripts/ws-realm.sh"
    [ "$status" -ne 0 ]

    run grep -Fq "strenv(REALM_NAME)" "$REPO_ROOT/scripts/ws-realm.sh"
    [ "$status" -eq 0 ]
}

@test "ws realm use rejects injection-shaped names without changing local config" {
    work="$BATS_TEST_TMPDIR/injection-work"
    mkdir -p "$work/realms" "$work/components" "$work/hoards"
    cat > "$work/ecosystem.yaml" <<'YAML'
components: {}
YAML
    cat > "$work/ecosystem.local.yaml" <<'YAML'
realm: realm.safe
notes: keep
YAML

    run env \
        "ROOT_DIR=$work" \
        "REALMS_DIR=$work/realms" \
        "COMPONENTS_DIR=$work/components" \
        "HOARDS_DIR=$work/hoards" \
        "ECOSYSTEM=$work/ecosystem.yaml" \
        "ECOSYSTEM_LOCAL=$work/ecosystem.local.yaml" \
        bash "$WS_BIN" realm use --trust 'realm" | .notes = "changed'

    [ "$status" -ne 0 ]
    [ "$(yq '.realm' "$work/ecosystem.local.yaml")" = "realm.safe" ]
    [ "$(yq '.notes' "$work/ecosystem.local.yaml")" = "keep" ]
}
