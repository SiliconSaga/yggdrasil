#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$WORK/scripts" "$WORK/realms/realm-fixture"
    cp "$REPO_ROOT/scripts/ws-mcp-setup.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-realm.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/ws-env.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-auth.sh" "$WORK/scripts/"
    cp "$REPO_ROOT/scripts/git-remote.sh" "$WORK/scripts/"
    printf 'components: {}\n' > "$WORK/ecosystem.yaml"
    printf 'realm: realm-fixture\n' > "$WORK/ecosystem.local.yaml"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
}

write_realm_mcp() {
    local url="$1"
    cat > "$WORK/realms/realm-fixture/ecosystem.yaml" <<YAML
components: {}
mcp:
  servers:
    fixture:
      transport: http
      url: $url
YAML
}

run_mcp() {
    run bash "$WORK/scripts/ws-mcp-setup.sh" --dry-run
}

@test "mcp setup rejects a relative endpoint" {
    write_realm_mcp /relative/mcp

    run_mcp

    [ "$status" -ne 0 ]
    [[ "$output" == *"absolute HTTP(S) URL"* ]]
}

@test "mcp setup rejects a non-HTTP endpoint" {
    write_realm_mcp ftp://mcp.example.com/service

    run_mcp

    [ "$status" -ne 0 ]
    [[ "$output" == *"absolute HTTP(S) URL"* ]]
}

@test "mcp setup warns for nonlocal plain HTTP" {
    write_realm_mcp http://mcp.example.com/service

    run_mcp

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"*"plain HTTP"*"mcp.example.com"* ]]
    [[ "$output" == *'"url": "http://mcp.example.com/service"'* ]]
}

@test "mcp setup allows loopback HTTP without the remote warning" {
    write_realm_mcp http://127.0.0.1:8080/service

    run_mcp

    [ "$status" -eq 0 ]
    [[ "$output" != *"plain HTTP"* ]]
}

@test "mcp setup does not mistake loopback-looking userinfo for a local host" {
    write_realm_mcp http://127.0.0.1@evil.example/service

    run_mcp

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"*"plain HTTP"*"evil.example"* ]]
}

@test "mcp setup treats bracketed IPv6 loopback as local" {
    write_realm_mcp http://[::1]:8080/service

    run_mcp

    [ "$status" -eq 0 ]
    [[ "$output" != *"plain HTTP"* ]]
}

@test "mcp setup rejects whitespace inside an endpoint URL" {
    write_realm_mcp "https://mcp.example.com/path with spaces"

    run_mcp

    [ "$status" -ne 0 ]
    [[ "$output" == *"absolute HTTP(S) URL"* ]]
}

@test "mcp setup flags embedded credentials in an endpoint" {
    write_realm_mcp https://svc-user:sekret@mcp.example.com/service

    run_mcp

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"*"embeds credentials"* ]]
}

@test "mcp setup accepts HTTPS endpoints" {
    write_realm_mcp https://mcp.example.com/service

    run_mcp

    [ "$status" -eq 0 ]
    [[ "$output" == *'"url": "https://mcp.example.com/service"'* ]]
}
