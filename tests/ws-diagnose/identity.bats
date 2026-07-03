#!/usr/bin/env bats

# `ws diagnose` must flag an unedited identity.human_account placeholder
# ('your-github-username' from ecosystem.local.yaml.example) before it leaks
# into a CR/issue body via @HUMAN_ACCOUNT, and confirm a real value.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

setup() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"
    git init -q "$WORK"
    git -C "$WORK" config user.name "T"
    git -C "$WORK" config user.email "t@example.local"
    git -C "$WORK" commit -q --allow-empty -m seed
    printf 'components: {}\n' > "$WORK/ecosystem.yaml"
    export ROOT_DIR="$WORK"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    export WS_FOOTER_DISABLE=1
}

run_diagnose() {
    run env -u GH_TOKEN -u GITHUB_TOKEN bash "$WS_BIN" diagnose yggdrasil --no-api-check
}

@test "ws diagnose flags the placeholder human_account" {
    printf 'identity:\n  human_account: your-github-username\n' > "$WORK/ecosystem.local.yaml"
    run_diagnose
    [ "$status" -eq 0 ]
    [[ "$output" == *"identity.human_account is your-github-username"* ]]
}

@test "ws diagnose confirms a real human_account" {
    printf 'identity:\n  human_account: realdev\n' > "$WORK/ecosystem.local.yaml"
    run_diagnose
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ human_account: realdev"* ]]
}
