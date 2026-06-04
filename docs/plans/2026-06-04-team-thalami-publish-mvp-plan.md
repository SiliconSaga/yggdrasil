# `ws thalami publish` MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a minimal `ws thalami publish` that mirrors a personal thalami's `published: true` arcs — plus their `#team/<arc-id>`-tagged Vault notes — into a team-thalami hoard, idempotently and repeatably, so a real arc can be dogfooded by editing and re-publishing.

**Architecture:** A new `scripts/ws-thalami.sh` handler (dispatched from `scripts/ws`) with one subcommand, `publish`. It reuses existing helpers in `scripts/ws-realm.sh` / `scripts/ws-hoard.sh` (ecosystem resolution, active-thalami detection, per-machine thalamus path). The frontmatter round-trip uses `awk` to extract the YAML block and `yq` (v4) to filter arcs and **regenerate** the team projection file (validated by a spike). Publishing is write-only (no commit/push) and confirm-before-write, with `--dry-run` and `--yes`.

**Tech Stack:** Bash, `yq` v4 (mikefarah), `awk`/`grep`/`find`/`cp`, bats-core (vendored).

**Scope note:** This is the **MVP slice of Plan 2** (design: [`2026-06-01-team-thalami-tier-design.md`](2026-06-01-team-thalami-tier-design.md); foundation: [`2026-06-01-team-thalami-foundation-plan.md`](2026-06-01-team-thalami-foundation-plan.md)). It deliberately implements: published-arc projection, team-hoard auto-detection, user/vault cascade resolution, tag sweep with a basic `#private`/`#noteam` denylist, per-arc idempotent replace, confirm/`--dry-run`/`--yes`, and a dogfood quickstart. It deliberately DEFERS (named in tasks, not built): realm-declared cloning, cross-arc `.publish-manifest.yaml` pruning (the MVP scopes deletes to each published arc's *own* `<arc-id>/` subfolder, which is inherently safe), auto-commit/push of the team hoard, orientation/housekeeping auto-surfacing, configurable allowlist/denylist beyond the two fixed exclusion tags, and GitLab Pages. Per-arc `vault:` override resolution is read but write-back of a confirmed `user:` is out of scope (resolve each run).

---

## Design decisions locked by the spike

The projection regen (validated in `.tmp/spike-publish.sh`) is:

1. Extract frontmatter: `awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f{print}' "$src"`.
2. Filter + clean via `yq`: `USER_VAL="$user" yq '{"user": strenv(USER_VAL), "arcs": (.arcs // [] | map(select(.published == true)))}'` — yields a doc with ONLY `user` + published arcs (personal prefs like `mode`/`role` and unpublished arcs are dropped).
3. Published arc ids for the sweep: `yq '.arcs // [] | map(select(.published == true)) | .[].id'`.
4. Note sweep per arc id: markdown files under the vault containing the literal `#team/<arc-id>`, minus any containing `#private` or `#noteam`.
5. Write `team/<user>/<host>-thalamus.md` = `---\n<projection>\n---\n<generated-banner>`; and for each arc, `rm -rf team/<user>/<arc-id>/` then copy each swept note preserving its vault-relative path.

---

## File Structure

**Create:**
- `scripts/ws-thalami.sh` — handler: two-level dispatch + `ws_thalami_publish` and its helpers.
- `tests/ws-thalami-publish/test_helper.bash` — builds an isolated fixture workspace (personal thalami hoard, obsidian-vault hoard with tagged/private notes, empty team hoard) and an env-propagating runner.
- `tests/ws-thalami-publish/publish.bats` — the test suite.
- `docs/gdd/team-thalami-quickstart.md` — the dogfood loop (setup + repeatable publish).

**Modify:**
- `scripts/ws` — add a `thalami)` dispatch case and a help-line entry.
- `.claude/settings.json` — allow `ws thalami publish *` / `ws thalami *` (side-effect tier; local file writes, repeatedly run).
- `docs/ws-cli-guide.md` — classify `ws thalami publish` in the permission-tier reference.

---

## Task 1: Handler skeleton + dispatch wiring + test harness

**Files:**
- Create: `scripts/ws-thalami.sh`
- Modify: `scripts/ws`
- Create: `tests/ws-thalami-publish/test_helper.bash`, `tests/ws-thalami-publish/publish.bats`

- [ ] **Step 1: Create `scripts/ws-thalami.sh` skeleton** (dispatch + help + a stub publish that parses flags and prints them). Model the sourcing/dispatch on `scripts/ws-hoard.sh`.

```bash
#!/usr/bin/env bash
# ws thalami — publish personal published:true arcs (+ tagged Vault notes)
# into a team-thalami hoard. See docs/gdd/team-thalami-quickstart.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"

# shared helpers (ws_resolve_ecosystem, ws_detect_thalami_hoard,
# ws_resolve_thalamus_path, etc.)
source "$SCRIPT_DIR/ws-realm.sh"
source "$SCRIPT_DIR/ws-hoard.sh"

ws_thalami_help() {
    cat <<'EOF'
Usage: ws thalami <subcommand>

Subcommands:
  publish [--to <hoard>] [--vault <path>] [--user <name>] [--dry-run] [--yes]
        Mirror this machine's published:true arcs (and their
        #team/<arc-id>-tagged Vault notes) into a team-thalami hoard.
        Write-only — review then commit the team hoard yourself.

  help  Show this help.
EOF
}

# Implemented in later steps.
ws_thalami_publish() {
    echo "ws thalami publish: not yet implemented" >&2
    return 1
}

SUBCMD="${1:-}"
shift 2>/dev/null || true
case "$SUBCMD" in
    ""|help|--help|-h) ws_thalami_help ;;
    publish)           ws_thalami_publish "$@" ;;
    *) echo "ERROR: Unknown thalami subcommand '$SUBCMD'. Run 'ws thalami help'." >&2; exit 1 ;;
esac
```

- [ ] **Step 2: Wire dispatch in `scripts/ws`.** Find the command `case` (it has entries like `hoard)`). Add, immediately before the `*)` catch-all:

```bash
    thalami)
        bash "$SCRIPT_DIR/ws-thalami.sh" "$@"
        ;;
```

Also add a one-line entry to the `ws help` output text alongside the other subcommands (locate the help heredoc/echo block listing `hoard`, `realm`, … and add `thalami` with a short blurb: `thalami publish  Publish published:true arcs to a team-thalami hoard`).

- [ ] **Step 3: Create `tests/ws-thalami-publish/test_helper.bash`** — isolated fixture. (Model env-propagation on `tests/ws-hoard-init/test_helper.bash`.)

```bash
# Shared fixture for ws-thalami-publish bats tests.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_THALAMI_BIN="$REPO_ROOT/scripts/ws-thalami.sh"

# Build an isolated workspace under $BATS_TEST_TMPDIR with:
#   hoards/thalami/<machine>-thalamus.md   (personal, 2 published + 1 unpublished arc)
#   hoards/obsidian-Cervator/...           (vault: tagged + private notes)
#   hoards/team-thalami-cfr/               (empty team hoard, just the dashboard)
# After this: $WORK, $HOARDS_DIR, $ROOT_DIR, $ECOSYSTEM, $ECOSYSTEM_LOCAL exported.
init_publish_workspace() {
    WORK="$BATS_TEST_TMPDIR/work"
    export ROOT_DIR="$WORK"
    export HOARDS_DIR="$WORK/hoards"
    mkdir -p "$HOARDS_DIR/thalami" "$HOARDS_DIR/obsidian-Cervator/notes" \
             "$HOARDS_DIR/team-thalami-cfr"
    export HOSTNAME="testhost"

    export ECOSYSTEM="$WORK/ecosystem.yaml"
    printf 'components: []\n' > "$ECOSYSTEM"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    printf 'identity:\n  human_account: testuser\n' > "$ECOSYSTEM_LOCAL"

    # Personal thalamus: vault points at the obsidian hoard; user: Cervator.
    cat > "$HOARDS_DIR/thalami/testhost-thalamus.md" <<EOF
---
mode: flow
user: Cervator
vault: $HOARDS_DIR/obsidian-Cervator
arcs:
  - id: observability-improvements
    name: Observability improvements
    status: active
    started: 2026-05-20
    last_touched: 2026-06-04
    next: "summarize meeting"
    published: true
  - id: private-spike
    name: Private spike
    status: active
    started: 2026-06-01
    last_touched: 2026-06-03
    next: "noodle"
---
# Thalamus
EOF

    # Vault notes: one tagged for the arc, one tagged but private, one untagged.
    printf '#team/observability-improvements\n\nMeeting notes 1\n' \
        > "$HOARDS_DIR/obsidian-Cervator/notes/meeting1.md"
    printf '#team/observability-improvements #private\n\nsecret\n' \
        > "$HOARDS_DIR/obsidian-Cervator/notes/secret.md"
    printf 'unrelated note\n' \
        > "$HOARDS_DIR/obsidian-Cervator/notes/other.md"
}

run_publish() { run bash "$WS_THALAMI_BIN" publish "$@"; }
```

- [ ] **Step 4: Create `tests/ws-thalami-publish/publish.bats` with the dispatch smoke test:**

```bash
#!/usr/bin/env bats
load test_helper

setup() { init_publish_workspace; }

@test "ws thalami help lists the publish subcommand" {
    run bash "$WS_THALAMI_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"publish"* ]]
}
```

- [ ] **Step 5: Run the test.** `bash tests/vendor/bats-core/bin/bats tests/ws-thalami-publish/publish.bats` — expected: PASS (1 test).

- [ ] **Step 6: Commit.** Bodyfile `.commits/ws-thalami-skeleton.md`:
```markdown
---
message: "feat(ws): scaffold ws thalami publish handler + dispatch"
add:
  - scripts/ws-thalami.sh
  - scripts/ws
  - tests/ws-thalami-publish/test_helper.bash
  - tests/ws-thalami-publish/publish.bats
---

Skeleton for the team-publish engine (Plan 2 MVP): ws-thalami.sh handler with a
publish stub, dispatch wiring in scripts/ws, and an isolated bats fixture
(personal thalami + obsidian vault + team hoard). The engine lands next.
```
Then: `ws commit yggdrasil .commits/ws-thalami-skeleton.md`

---

## Task 2: Resolve sources — thalamus, team hoard, user, vault

**Files:** Modify `scripts/ws-thalami.sh`; extend `tests/ws-thalami-publish/publish.bats`.

Implements flag parsing + the four resolutions. No mirroring yet — for testability, end the function by printing a resolved-context block and exiting 0.

- [ ] **Step 1: Replace the `ws_thalami_publish` stub** with flag parsing + resolution + a printed context. (Helper functions kept small and single-purpose.)

```bash
# --- resolution helpers -----------------------------------------------------

# Extract the YAML frontmatter block of a markdown file (between first two ---).
_wt_frontmatter() {
    awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f{print}' "$1"
}

# Auto-detect a single hoards/team-thalami-* dir; honor explicit name.
_wt_resolve_team_hoard() {
    local explicit="$1" d matches=()
    if [[ -n "$explicit" ]]; then
        [[ -d "$HOARDS_DIR/$explicit" ]] || { echo "ERROR: team hoard '$explicit' not found under hoards/." >&2; return 1; }
        echo "$explicit"; return 0
    fi
    for d in "$HOARDS_DIR"/team-thalami-*/; do
        [[ -d "$d" ]] || continue
        matches+=("$(basename "$d")")
    done
    case "${#matches[@]}" in
        1) echo "${matches[0]}" ;;
        0) echo "ERROR: no hoards/team-thalami-* found. Pass --to <hoard> or run 'ws hoard init team-thalami --name <n>'." >&2; return 1 ;;
        *) echo "ERROR: multiple team-thalami hoards (${matches[*]}). Pass --to <hoard>." >&2; return 1 ;;
    esac
}

ws_thalami_publish() {
    local to="" vault="" user="" dry=0 yes=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to) to="${2:?--to needs a value}"; shift 2 ;;
            --vault) vault="${2:?--vault needs a value}"; shift 2 ;;
            --user) user="${2:?--user needs a value}"; shift 2 ;;
            --dry-run) dry=1; shift ;;
            --yes|-y) yes=1; shift ;;
            *) echo "ERROR: unknown flag '$1'." >&2; return 1 ;;
        esac
    done

    # 1. Personal thalamus (the active per-machine file).
    local src; src="$(ws_resolve_thalamus_path)"
    [[ -n "$src" && -f "$src" ]] || { echo "ERROR: no active thalami thalamus file found." >&2; return 1; }
    local host; host="$(basename "$src" | sed 's/-thalamus\.md$//')"
    local fm; fm="$(_wt_frontmatter "$src")"

    # 2. Team hoard.
    local team; team="$(_wt_resolve_team_hoard "$to")" || return 1
    local team_dir="$HOARDS_DIR/$team"

    # 3. User: --user > frontmatter user > $USER.
    local fm_user; fm_user="$(printf '%s\n' "$fm" | yq '.user // ""')"
    user="${user:-${fm_user:-${USER:-unknown}}}"

    # 4. Vault: --vault > frontmatter vault. (Per-arc override handled in Task 4.)
    local fm_vault; fm_vault="$(printf '%s\n' "$fm" | yq '.vault // ""')"
    vault="${vault:-$fm_vault}"
    [[ -n "$vault" ]] || { echo "ERROR: no Vault source. Set 'vault:' in your thalamus frontmatter or pass --vault <path>." >&2; return 1; }
    [[ -d "$vault" ]] || { echo "ERROR: vault path '$vault' is not a directory." >&2; return 1; }

    echo "context: host=$host user=$user team=$team vault=$vault dry=$dry yes=$yes"
    # mirroring implemented in Tasks 3-5
}
```

- [ ] **Step 2: Add resolution tests** to `publish.bats`:

```bash
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
```

- [ ] **Step 3: Run** `bash tests/vendor/bats-core/bin/bats tests/ws-thalami-publish/publish.bats` — expected: PASS (4 tests). Note: `ws_resolve_thalamus_path` must resolve `hoards/thalami/testhost-thalamus.md` in the fixture; if it doesn't (e.g. it needs a selector), set `hoards.thalami: thalami` in the fixture's `ECOSYSTEM_LOCAL` in `test_helper.bash` and re-run. Fix the helper, not the test.

- [ ] **Step 4: Commit.** Bodyfile `.commits/ws-thalami-resolve.md`:
```markdown
---
message: "feat(ws): resolve thalamus/team-hoard/user/vault for thalami publish"
add:
  - scripts/ws-thalami.sh
  - tests/ws-thalami-publish/publish.bats
  - tests/ws-thalami-publish/test_helper.bash
---

Flag parsing + the resolution cascade: active personal thalamus, team-hoard
auto-detection (single hoards/team-thalami-*, --to override), user
(--user > frontmatter > $USER), and Vault path (--vault > frontmatter vault).
Mirroring follows.
```
(If Step 3 required editing the fixture, that's why test_helper.bash is in the list.) Then: `ws commit yggdrasil .commits/ws-thalami-resolve.md`

---

## Task 3: Regenerate the team projection file

**Files:** Modify `scripts/ws-thalami.sh`; extend `publish.bats`.

Builds the published-only projection and (on execute) writes `team/<user>/<host>-thalamus.md`. Gate the write behind `--dry-run`/confirm in Task 5; here, implement the projection-build helper and write it when not `--dry-run` (Task 5 adds the confirm prompt; for now treat absence of `--dry-run` as "write").

- [ ] **Step 1: Add the projection helper + wire it in** (replace the `# mirroring implemented…` comment).

```bash
# Build the team projection YAML (only user + published arcs) from frontmatter.
_wt_projection() {
    local fm="$1" user="$2"
    printf '%s\n' "$fm" | USER_VAL="$user" \
        yq '{"user": strenv(USER_VAL), "arcs": (.arcs // [] | map(select(.published == true)))}'
}

# List published arc ids, one per line.
_wt_published_ids() {
    printf '%s\n' "$1" | yq '.arcs // [] | map(select(.published == true)) | .[].id'
}
```

Wire after the context line:
```bash
    local projection ids
    projection="$(_wt_projection "$fm" "$user")"
    ids="$(_wt_published_ids "$fm")"
    if [[ -z "$ids" ]]; then echo "Nothing to publish: no arcs with 'published: true'."; return 0; fi

    local user_dir="$team_dir/$user"
    local out="$user_dir/$host-thalamus.md"

    if [[ "$dry" -eq 1 ]]; then
        echo "would write projection -> $out"
        printf '%s\n' "$projection"
        echo "published arcs: $(echo "$ids" | tr '\n' ' ')"
        return 0
    fi

    mkdir -p "$user_dir"
    { echo "---"; printf '%s\n' "$projection"; echo "---"; echo ""; \
      echo "# Team projection — generated by \`ws thalami publish\`, do not hand-edit"; } > "$out"
    echo "wrote $out"
```

- [ ] **Step 2: Tests** in `publish.bats`:

```bash
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
```

Note: `--yes` isn't a real gate yet (Task 5 adds the confirm prompt); for now any non-`--dry-run` run writes, and `--yes` is accepted as a no-op flag (already parsed in Task 2).

- [ ] **Step 3: Run** the suite — expected PASS (7 tests).

- [ ] **Step 4: Commit.** Bodyfile `.commits/ws-thalami-projection.md`:
```markdown
---
message: "feat(ws): regenerate team projection from published arcs"
add:
  - scripts/ws-thalami.sh
  - tests/ws-thalami-publish/publish.bats
---

Build the team <host>-thalamus.md from the personal frontmatter, keeping only
`user` + published:true arcs (personal prefs and unpublished arcs dropped).
Idempotent full-file regeneration — the "generated, never hand-edited"
invariant. --dry-run previews.
```
Then: `ws commit yggdrasil .commits/ws-thalami-projection.md`

---

## Task 4: Sweep + mirror the arc's tagged Vault notes (with denylist)

**Files:** Modify `scripts/ws-thalami.sh`; extend `publish.bats`.

For each published arc, copy `#team/<arc-id>`-tagged notes (excluding `#private`/`#noteam`) into `team/<user>/<arc-id>/`, preserving vault-relative paths, replacing the arc subfolder each run.

- [ ] **Step 1: Add the sweep + copy helper.**

```bash
# Echo the vault-relative paths of notes tagged for $arc_id, minus denylisted.
_wt_sweep() {
    local vault="$1" arc_id="$2" f rel
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        # denylist: skip notes carrying an exclusion tag
        grep -qE '#private|#noteam' "$f" && continue
        rel="${f#"$vault"/}"
        echo "$rel"
    done < <(grep -rlF "#team/$arc_id" "$vault" --include='*.md' 2>/dev/null | sort)
}
```

In the execute path (after writing the projection), add per-arc mirroring:
```bash
    local arc_id rel src_note dest_note
    while IFS= read -r arc_id; do
        [[ -n "$arc_id" ]] || continue
        local arc_dir="$user_dir/$arc_id"
        rm -rf "$arc_dir"
        local n=0
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            src_note="$vault/$rel"; dest_note="$arc_dir/$rel"
            mkdir -p "$(dirname "$dest_note")"
            cp "$src_note" "$dest_note"
            n=$((n+1))
        done < <(_wt_sweep "$vault" "$arc_id")
        echo "  $arc_id: mirrored $n note(s)"
    done <<< "$ids"
```

And in the `--dry-run` branch, list what WOULD be swept:
```bash
        while IFS= read -r arc_id; do
            [[ -n "$arc_id" ]] || continue
            echo "  $arc_id notes:"
            _wt_sweep "$vault" "$arc_id" | sed 's/^/    /'
        done <<< "$ids"
```

- [ ] **Step 2: Tests.**

```bash
@test "publish mirrors tagged notes and skips #private notes" {
    run_publish --yes
    [ "$status" -eq 0 ]
    local d="$HOARDS_DIR/team-thalami-cfr/Cervator/observability-improvements"
    [ -f "$d/notes/meeting1.md" ]
    [ ! -f "$d/notes/secret.md" ]
    [ ! -f "$d/notes/other.md" ]
}

@test "publish --dry-run lists the notes it would copy, excludes private" {
    run_publish --dry-run
    [[ "$output" == *"notes/meeting1.md"* ]]
    [[ "$output" != *"notes/secret.md"* ]]
}

@test "un-tagging a note removes it from the arc subfolder on re-publish" {
    run_publish --yes
    local d="$HOARDS_DIR/team-thalami-cfr/Cervator/observability-improvements"
    [ -f "$d/notes/meeting1.md" ]
    printf 'untagged now\n' > "$HOARDS_DIR/obsidian-Cervator/notes/meeting1.md"
    run_publish --yes
    [ ! -f "$d/notes/meeting1.md" ]
}
```

- [ ] **Step 3: Run** — expected PASS (10 tests).

- [ ] **Step 4: Commit.** Bodyfile `.commits/ws-thalami-sweep.md`:
```markdown
---
message: "feat(ws): sweep + mirror tagged Vault notes per published arc"
add:
  - scripts/ws-thalami.sh
  - tests/ws-thalami-publish/publish.bats
---

For each published arc, copy #team/<arc-id>-tagged Vault notes (excluding
#private/#noteam) into team/<user>/<arc-id>/, preserving vault-relative paths
and replacing the subfolder each run so un-tagging removes a note. Deletes are
scoped to the arc's own subfolder (no cross-arc manifest needed in the MVP).
```
Then: `ws commit yggdrasil .commits/ws-thalami-sweep.md`

---

## Task 5: Confirm-before-write + `--dry-run`/`--yes` gate

**Files:** Modify `scripts/ws-thalami.sh`; extend `publish.bats`.

Make the write path actually gated: build the plan, print it, and require confirmation unless `--yes`. `--dry-run` already previews and exits.

- [ ] **Step 1: Add the confirm gate** right before the first write (`mkdir -p "$user_dir"`):

```bash
    # Confirm before writing (skipped by --yes).
    if [[ "$yes" -ne 1 ]]; then
        echo "About to publish to: $user_dir"
        echo "  projection: $out  (arcs: $(echo "$ids" | tr '\n' ' '))"
        while IFS= read -r arc_id; do
            [[ -n "$arc_id" ]] || continue
            echo "  $arc_id notes:"; _wt_sweep "$vault" "$arc_id" | sed 's/^/    /'
        done <<< "$ids"
        printf 'Proceed? [y/N] '
        local reply; read -r reply
        [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted — nothing written."; return 0; }
    fi
```

- [ ] **Step 2: Tests** (drive the prompt via stdin with `run ... <<<`):

```bash
@test "publish without --yes aborts on 'n' and writes nothing" {
    run bash -c "printf 'n\n' | bash '$WS_THALAMI_BIN' publish"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aborted"* ]]
    [ ! -d "$HOARDS_DIR/team-thalami-cfr/Cervator" ]
}

@test "publish without --yes proceeds on 'y'" {
    run bash -c "printf 'y\n' | bash '$WS_THALAMI_BIN' publish"
    [ "$status" -eq 0 ]
    [ -f "$HOARDS_DIR/team-thalami-cfr/Cervator/testhost-thalamus.md" ]
}
```

(These invoke the bin directly with a piped reply; the fixture env is exported by `setup()`, so the child `bash` inherits `HOARDS_DIR` etc.)

- [ ] **Step 3: Run** — expected PASS (12 tests).

- [ ] **Step 4: Commit.** Bodyfile `.commits/ws-thalami-confirm.md`:
```markdown
---
message: "feat(ws): confirm-before-write gate for thalami publish"
add:
  - scripts/ws-thalami.sh
  - tests/ws-thalami-publish/publish.bats
---

Print the full publish plan (projection + per-arc note list) and require y/N
confirmation before writing; --yes skips it, --dry-run previews and exits. The
team hoard is written only on explicit consent.
```
Then: `ws commit yggdrasil .commits/ws-thalami-confirm.md`

---

## Task 6: Permissions, help, and the dogfood quickstart doc

**Files:** Modify `.claude/settings.json`, `docs/ws-cli-guide.md`; Create `docs/gdd/team-thalami-quickstart.md`.

- [ ] **Step 1: Allow the command** in `.claude/settings.json`. Read it first; under `permissions.allow`, add (matching the existing string style, both bare and verbose forms):
```
"Bash(ws thalami publish *)",
"Bash(ws thalami *)",
"Bash(bash scripts/ws thalami publish *)"
```
(It writes only local files and never pushes, but it mutates the team hoard, so it's side-effect tier — allowed for the dogfood loop, no deny rule.)

- [ ] **Step 2: Document the tier** in `docs/ws-cli-guide.md` — add `ws thalami publish` to the side-effect/local-write row of the permission-tier reference (match the doc's existing table format; read it first).

- [ ] **Step 3: Create `docs/gdd/team-thalami-quickstart.md`** — the dogfood loop:

```markdown
# Team Thalami — Quickstart (dogfooding `ws thalami publish`)

A minimal loop for promoting a personal arc to a shared team-thalami hoard.

## One-time setup

1. **Team hoard:** `ws hoard init team-thalami --name team-thalami-cfr`
   (push it to a shared remote when you want teammates to clone it).
2. **Notes vault:** `ws hoard init obsidian-vault --name obsidian-<you>` — where meeting notes / tab dumps live.
3. **Point your thalamus at the vault:** in your active `hoards/thalami/<host>-thalamus.md` frontmatter, set `vault: hoards/obsidian-<you>` (absolute or workspace-relative).
4. **Create the arc:** add an arc to that frontmatter, e.g.
   ```yaml
   - id: observability-improvements
     name: Observability improvements
     status: active
     started: 2026-06-04
     last_touched: 2026-06-04
     next: "summarize last meeting"
     published: true
   ```

## The loop

1. Drop meeting notes as `.md` in the vault, each containing the tag line `#team/observability-improvements`. Mark anything sensitive `#private` (or `#noteam`) to keep it out.
2. Preview: `ws thalami publish --dry-run`.
3. Publish: `ws thalami publish` (review the file list, confirm), or `--yes` to skip the prompt.
4. Look: open the team hoard's `TeamArcDashboard.md` in Obsidian; browse `team-thalami-cfr/<you>/observability-improvements/` for the mirrored notes.
5. Edit notes or the arc's `next:`, re-publish, repeat. Re-publishing is idempotent (un-tagged notes drop off).
6. Share: `ws commit team-thalami-cfr <bodyfile>` and push when you want teammates to see the update. (Publish itself never commits or pushes.)

## Not yet (later plans)

- Auto-cloning the team hoard from a realm declaration.
- Orientation/housekeeping surfacing the team hoard or prompting to publish.
- GitLab Pages rendering of the dashboard.
```

- [ ] **Step 4: Verify** — `grep -n "ws thalami publish" .claude/settings.json` (expect the allow entries) and confirm the quickstart renders (eyeball headings). Re-run the full publish suite once more: `bash tests/vendor/bats-core/bin/bats tests/ws-thalami-publish/` — expect all PASS.

- [ ] **Step 5: Commit.** Bodyfile `.commits/ws-thalami-docs.md`:
```markdown
---
message: "docs(gdd): allow ws thalami publish + add team-thalami quickstart"
add:
  - .claude/settings.json
  - docs/ws-cli-guide.md
  - docs/gdd/team-thalami-quickstart.md
---

Allow the publish command (side-effect tier, local writes), document its tier,
and add the dogfood quickstart: scaffold team hoard + obsidian vault, mark an
arc published, tag notes, then dry-run/publish/look/edit/repeat.
```
Then: `ws commit yggdrasil .commits/ws-thalami-docs.md`

---

## Final verification

- [ ] `bash tests/vendor/bats-core/bin/bats tests/ws-thalami-publish/` — all PASS.
- [ ] `ws test yggdrasil` — full suite still green (no regression in the hook/permission tests from the settings.json change).
- [ ] Manual smoke (optional): in the real workspace, `ws thalami publish --dry-run` with a published arc + a `vault:` set — confirm the plan prints and nothing is written.

## Self-Review

**Spec coverage (MVP slice):** publish handler + dispatch (T1); resolution cascade incl. team-hoard auto-detect + user/vault (T2); published-only projection regen (T3); tag sweep + denylist + per-arc idempotent replace (T4); confirm/`--dry-run`/`--yes` (T5); permissions + tier doc + dogfood quickstart (T6). Deferred items (realm clone, cross-arc manifest prune, auto-commit, orientation, Pages) are named in the Scope note.

**Placeholder scan:** every step ships real bash/bats/markdown. The Task 2 Step 3 fallback (set `hoards.thalami` selector if detection needs it) is a concrete conditional, not a placeholder.

**Type/name consistency:** `_wt_frontmatter`, `_wt_resolve_team_hoard`, `_wt_projection`, `_wt_published_ids`, `_wt_sweep` are defined once and reused; `ws_thalami_publish` flags (`--to/--vault/--user/--dry-run/--yes`) are consistent across tasks and tests; fixture paths (`hoards/thalami/testhost-thalamus.md`, `hoards/obsidian-Cervator`, `hoards/team-thalami-cfr`, user `Cervator`) are consistent across all tests.
