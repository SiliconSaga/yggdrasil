REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_BIN="$REPO_ROOT/scripts/ws"

run_ws() {
    run bash "$WS_BIN" "$@"
}

make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config core.autocrlf false
    git -C "$dir" config user.email "test@example.invalid"
    git -C "$dir" config user.name "Test"
    printf 'seed\n' > "$dir/seed.txt"
    git -C "$dir" add seed.txt
    git -C "$dir" commit -qm "seed"
}

# A bare repository that clones and fetches like a hosted one: its HEAD names
# the branch that was pushed, so a clone checks something out.
make_bare() { # <path> <branch>
    git init -q --bare "$1"
    git -C "$1" symbolic-ref HEAD "refs/heads/$2"
}

# A real repo on <branch> whose origin is a bare repo already holding it, with
# origin/HEAD recorded the way git clone records it. The bare repo lives under
# $REMOTES, outside every working tree a reset will clean.
make_remote_repo() { # <dir> <branch>
    local dir="$1" branch="$2" bare="$REMOTES/$(basename "$1").git"
    make_repo "$dir"
    git -C "$dir" branch -q -m main "$branch"
    make_bare "$bare" "$branch"
    git -C "$dir" remote add origin "$bare"
    git -C "$dir" push -q -u origin "$branch"
    git -C "$dir" remote set-head origin --auto >/dev/null
}

# The parent workspace: a clone of a stub yggdrasil whose scripts/ws records
# every call with the ROOT_DIR it saw and fakes realm, clone and hoard by
# making what they would make; one active realm checkout with a
# Terasology-shaped adapter; an empty bays/.
init_parent() {
    WORK="$BATS_TEST_TMPDIR/work"
    REMOTES="$BATS_TEST_TMPDIR/remotes"
    mkdir -p "$REMOTES"
    export BAY_WS_LOG="$BATS_TEST_TMPDIR/bay-ws.log"
    : > "$BAY_WS_LOG"

    local src="$BATS_TEST_TMPDIR/ygg-src"
    make_repo "$src"
    mkdir -p "$src/scripts" "$src/components" "$src/realms" "$src/hoards" "$src/bays"
    cat > "$src/scripts/ws" <<'EOF'
#!/usr/bin/env bash
# A stand-in for a bay's ws: records every call with the ROOT_DIR it saw and
# the directory it ran from, and fakes the verbs bay add relies on.
here="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s|root=%s|cwd=%s\n' "$*" "${ROOT_DIR:-unset}" "$PWD" >> "$BAY_WS_LOG"
case "$1" in
  realm)
    case "$2" in
      use) ;;
      *) git clone -q "$2" "$here/realms/$(basename "${2%.git}")" ;;
    esac ;;
  clone)
    mkdir -p "$here/components/$2"
    git -C "$here/components/$2" init -q -b main
    printf 'c\n' > "$here/components/$2/c.txt"
    git -C "$here/components/$2" add c.txt
    git -C "$here/components/$2" -c user.email=t@example.invalid -c user.name=T commit -qm c ;;
  hoard) mkdir -p "$here/hoards/$(basename "${2%.git}")" ;;
esac
EOF
    chmod +x "$src/scripts/ws"
    touch "$src/components/.gitkeep" "$src/realms/.gitkeep" "$src/hoards/.gitkeep" "$src/bays/.gitkeep"
    printf '/components/*\n!/components/.gitkeep\n/realms/*\n!/realms/.gitkeep\n/hoards/*\n!/hoards/.gitkeep\n/bays/*\n!/bays/.gitkeep\n/ecosystem.local.yaml\n/.tmp/\n/.outputs/\n' > "$src/.gitignore"
    git -C "$src" add -A
    git -C "$src" commit -qm "ws stub"
    make_bare "$REMOTES/ygg.git" main
    git -C "$src" remote add origin "$REMOTES/ygg.git"
    git -C "$src" push -q origin main

    git clone -q "$REMOTES/ygg.git" "$WORK"
    export ROOT_DIR="$WORK" COMPONENTS_DIR="$WORK/components" REALMS_DIR="$WORK/realms" HOARDS_DIR="$WORK/hoards" BAYS_DIR="$WORK/bays"
    export ECOSYSTEM="$WORK/ecosystem.yaml" ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml" WS_FOOTER_DISABLE=1
    printf 'identity: {}\ncomponents: {}\n' > "$ECOSYSTEM"
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: tester
realm: community
machine: Parent
_gdd:
  realmTrust:
    realm: community
    fingerprint: deadbeef
YAML

    local rsrc="$BATS_TEST_TMPDIR/realm-src"
    make_repo "$rsrc"
    mkdir -p "$rsrc/adapters"
    printf 'components: {}\n' > "$rsrc/ecosystem.yaml"
    cat > "$rsrc/adapters/terasology.yaml" <<'YAML'
nested:
  - "modules/*"
provision:
  init: "touch provisioned.marker"
  runtime_dirs: [logs, saves]
YAML
    git -C "$rsrc" add -A
    git -C "$rsrc" commit -qm adapter
    make_bare "$REMOTES/community.git" main
    git -C "$rsrc" remote add origin "$REMOTES/community.git"
    git -C "$rsrc" push -q origin main
    git clone -q "$REMOTES/community.git" "$REALMS_DIR/community"
}

# Change the realm's Terasology adapter at its source, so a bay's realm reset
# picks it up rather than reverting it.
realm_adapter_append() { # <text>
    local rsrc="$BATS_TEST_TMPDIR/realm-src"
    printf '%s\n' "$1" >> "$rsrc/adapters/terasology.yaml"
    git -C "$rsrc" add -A
    git -C "$rsrc" commit -qm "adapter change"
    git -C "$rsrc" push -q origin main
    git -C "$REALMS_DIR/community" pull -q
}

# A bay built by hand, the shape `ws bay add` leaves: a clone of the stub
# yggdrasil, the realm cloned in, a real component with a real nested module,
# each tracking its own bare remote.
make_bay() { # <name>
    local dir="$BAYS_DIR/$1"
    git clone -q "$REMOTES/ygg.git" "$dir"
    printf 'realm: community\nmachine: Parent-%s\n' "$1" > "$dir/ecosystem.local.yaml"
    git clone -q "$REMOTES/community.git" "$dir/realms/community"
    make_remote_repo "$dir/components/terasology" develop
    printf '/build/\n/logs/\n/saves/\n/modules/\n' > "$dir/components/terasology/.gitignore"
    git -C "$dir/components/terasology" add .gitignore
    git -C "$dir/components/terasology" commit -qm gitignore
    git -C "$dir/components/terasology" push -q origin develop
    make_remote_repo "$dir/components/terasology/modules/Cooking" develop
    BAY="$dir"
}
