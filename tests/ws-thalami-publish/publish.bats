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

@test "publish --dry-run shows the published-only projection, excludes unpublished" {
    run_publish --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"observability-improvements"* ]]
    [[ "$output" != *"private-spike"* ]]
}

@test "publish writes a regenerated team thalamus with only published arcs" {
    run_publish --yes
    [ "$status" -eq 0 ]
    local f="$HOARDS_DIR/team-thalami-cfr/Cervator/testhost-thalamus.md"
    [ -f "$f" ]
    grep -q "observability-improvements" "$f"
    run grep -c "private-spike" "$f"
    [ "$output" -eq 0 ]
    grep -q "do not hand-edit" "$f"
}

@test "publish is idempotent — re-running yields the same projection file" {
    run_publish --yes
    local f="$HOARDS_DIR/team-thalami-cfr/Cervator/testhost-thalamus.md"
    cp "$f" "$BATS_TEST_TMPDIR/first"
    run_publish --yes
    run diff "$f" "$BATS_TEST_TMPDIR/first"
    [ "$status" -eq 0 ]
}
