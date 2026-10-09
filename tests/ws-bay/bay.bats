#!/usr/bin/env bats
load test_helper

setup() { init_parent; }

@test "add clones the workspace, names its machine, gives it the realm and the components" {
    run_ws bay add bay-1 --with terasology

    [ "$status" -eq 0 ]
    [ -f "$BAYS_DIR/bay-1/scripts/ws" ]
    [ "$(yq -r '.machine' "$BAYS_DIR/bay-1/ecosystem.local.yaml")" = "Parent-bay-1" ]
    [ "$(yq -r '.realm' "$BAYS_DIR/bay-1/ecosystem.local.yaml")" = "community" ]
    [ "$(yq -r '.identity.human_account' "$BAYS_DIR/bay-1/ecosystem.local.yaml")" = "tester" ]
    [ "$(yq -r '._gdd // "gone"' "$BAYS_DIR/bay-1/ecosystem.local.yaml")" = "gone" ]
    grep -q '^realm .*community.git|' "$BAY_WS_LOG"     # the URL's path form differs by OS; the repo does not
    grep -q '^realm use community --trust|' "$BAY_WS_LOG"
    grep -q '^clone terasology|' "$BAY_WS_LOG"
    [ -f "$BAYS_DIR/bay-1/realms/community/adapters/terasology.yaml" ]
    [ -f "$BAYS_DIR/bay-1/components/terasology/provisioned.marker" ]
}

@test "the bay's ws runs from the bay with none of the parent's roots" {
    run_ws bay add bay-1
    [ "$status" -eq 0 ]
    run_ws bay exec bay-1 status --nested
    [ "$status" -eq 0 ]
    grep -q '^status --nested|root=unset|cwd=.*/bay-1$' "$BAY_WS_LOG"
    grep -q '^realm use community --trust|root=unset|' "$BAY_WS_LOG"
}

@test "add refuses an existing bay and a bad name" {
    mkdir -p "$BAYS_DIR/bay-1"
    run_ws bay add bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
    run_ws bay add "../x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid bay name"* ]]
}

@test "add takes --hoard and --from" {
    make_bare "$REMOTES/thalami.git" main
    run_ws bay add bay-1 --hoard "$REMOTES/thalami.git" --from "$REMOTES/ygg.git"
    [ "$status" -eq 0 ]
    grep -q "^hoard $REMOTES/thalami.git|" "$BAY_WS_LOG"
}

@test "add needs --from when the parent has several remotes and no upstreamRemote" {
    git -C "$WORK" remote add other "$REMOTES/ygg.git"
    run_ws bay add bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"--from"* ]]
    printf 'defaults:\n  upstreamRemote: other\n' >> "$ECOSYSTEM_LOCAL"
    run_ws bay add bay-1
    [ "$status" -eq 0 ]
}

@test "reset returns root, realm, component and module to their remotes' default branches, clean" {
    make_bay bay-1
    comp="$BAY/components/terasology"
    git -C "$comp" switch -q -c cr/7
    printf 'x\n' > "$comp/cr.txt"; git -C "$comp" add cr.txt; git -C "$comp" commit -qm cr
    printf 'edited\n' >> "$comp/seed.txt"
    printf 'stray\n' > "$comp/stray.txt"
    mkdir -p "$comp/logs/run1" "$comp/build/classes"; touch "$comp/logs/run1/a.log" "$comp/build/classes/A.class"
    printf 'lb\n' > "$comp/modules/Cooking/src.txt"
    printf 'local\n' >> "$BAY/realms/community/ecosystem.yaml"
    printf 'hack\n' >> "$BAY/scripts/ws"

    run_ws bay reset bay-1

    [ "$status" -eq 0 ]
    [ "$(git -C "$comp" rev-parse --abbrev-ref HEAD)" = "develop" ]
    [ "$(git -C "$comp" rev-parse HEAD)" = "$(git -C "$comp" rev-parse origin/develop)" ]
    [ -z "$(git -C "$comp" status --porcelain)" ]
    [ ! -e "$comp/stray.txt" ]
    [ ! -e "$comp/logs" ]
    [ -e "$comp/build/classes/A.class" ]                  # Gradle output survives a plain reset
    [ -z "$(git -C "$comp/modules/Cooking" status --porcelain)" ]
    [ -z "$(git -C "$BAY/realms/community" status --porcelain)" ]
    [ -z "$(git -C "$BAY" status --porcelain)" ]
    [ -d "$BAY/components/terasology/.git" ]
    [ -d "$BAY/realms/community/.git" ]
    [[ "$output" == *"clean in"* ]]
}

@test "reset --deep drops ignored output in components and never touches the bay's own clones" {
    make_bay bay-1
    comp="$BAY/components/terasology"
    mkdir -p "$comp/build/classes"; touch "$comp/build/classes/A.class"
    run_ws bay reset bay-1 --deep
    [ "$status" -eq 0 ]
    [ ! -e "$comp/build" ]
    [ -d "$BAY/components/terasology/.git" ]
    [ -d "$BAY/components/terasology/modules/Cooking/.git" ]
    [ -d "$BAY/realms/community/.git" ]
}

@test "reset fails and names the repository when a nested fetch fails" {
    make_bay bay-1
    git -C "$BAY/components/terasology/modules/Cooking" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
    run_ws bay reset bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"FAILED in "*"modules/Cooking"* ]]
}

@test "reset needs provision.remote when a component has several remotes" {
    make_bay bay-1
    comp="$BAY/components/terasology"
    make_bare "$REMOTES/fork.git" develop
    git -C "$comp" remote add fork "$REMOTES/fork.git"
    git -C "$comp" push -q fork develop
    run_ws bay reset bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"remotes and none is named"* ]]
    realm_adapter_append $'  remote: origin\n  branch: develop'
    run_ws bay reset bay-1
    [ "$status" -eq 0 ]
    [ "$(git -C "$comp" rev-parse --abbrev-ref HEAD)" = "develop" ]
}

@test "list and dir" {
    make_bay bay-1
    run_ws bay list
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = $'bay-1\tcommunity\tterasology' ]
    run_ws bay dir bay-1
    [ "$status" -eq 0 ]
    [ "$output" = "$BAYS_DIR/bay-1" ]
}

@test "rm treats a repository whose status cannot be read as dirty" {
    make_bay bay-1
    # A corrupt index makes git status fail outright. (A corrupt HEAD would
    # not: git then treats the module as not-a-repo and reports the enclosing
    # engine checkout's status, which is clean.)
    printf 'garbage\n' > "$BAY/components/terasology/modules/Cooking/.git/index"
    run_ws bay rm bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot read the status"* ]]
    [ -d "$BAY" ]
}

@test "rm refuses uncommitted work unless forced" {
    make_bay bay-1
    printf 'wip\n' > "$BAY/components/terasology/wip.txt"
    run_ws bay rm bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"uncommitted work"* ]]
    [ -d "$BAY" ]
    run_ws bay rm bay-1 --force
    [ "$status" -eq 0 ]
    [ ! -e "$BAY" ]
}
