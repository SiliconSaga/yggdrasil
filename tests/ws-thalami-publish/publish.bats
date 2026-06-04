#!/usr/bin/env bats
load test_helper

setup() { init_publish_workspace; }

@test "ws thalami help lists the publish subcommand" {
    run bash "$WS_THALAMI_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"publish"* ]]
}

@test "publish resolves host/user/team/vault from the fixture" {
    run_publish --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"host=testhost"* ]]
    [[ "$output" == *"user=Cervator"* ]]
    [[ "$output" == *"team=team-thalami-cfr"* ]]
    [[ "$output" == *"vault=$HOARDS_DIR/obsidian-Cervator"* ]]
}

@test "publish errors clearly when no team hoard exists" {
    rm -rf "$HOARDS_DIR/team-thalami-cfr"
    run_publish --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"no hoards/team-thalami-*"* ]]
}

@test "publish --user overrides the frontmatter user" {
    run_publish --user Borgr --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"user=Borgr"* ]]
}
