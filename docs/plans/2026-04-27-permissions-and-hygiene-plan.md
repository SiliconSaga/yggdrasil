# Permissions Documentation + Workspace Tooling Hygiene — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the 9 hygiene-pass items from `docs/plans/2026-04-27-permissions-and-hygiene-design.md` — three small bash-script defects, one workspace-tooling extension, one cross-repo doc relocation, one new GDD-specific reference doc, one new operational skill, two skill updates.

**Architecture:** Eight sequential phases that each land in a working state. Phase A clears the small bash defects (independent, fastest to verify). Phase B extends `ws status` (independent, dependency for Phase F). Phase C does the cross-repo doc move (independent, two-repo coordination). Phases D and E ship the new permissions doc and skill (loosely coupled). Phases F and G update the existing skills with the cadence nudge and housekeeping hook (depend on Phase B's `ws status` extension and Phase E's new skill being in place). Phase H is final verification + push.

**Tech Stack:** Bash (ws CLI scripts), `yq` v4 (Mike Farah), `gh` CLI, markdown documentation, git.

---

## Conventions for executing this plan

- The repo lives at `D:/Dev/GitWS/yggdrasil`. The user has `<workspace>/scripts/` on PATH; **use bare `ws <cmd>`** (not `bash scripts/ws`).
- Always commit via `ws commit yggdrasil <bodyfile>` — never raw `git add` / `git commit`. Bodyfiles live in `.commits/<name>.md` (gitignored). After PR #45's `feat(ws-commit)!` change, `ws commit` is bodyfile-only — every commit declares its `add:`/`remove:` frontmatter.
- Don't chain `ws commit && ws push` — run separately so each can be reviewed and approved independently.
- **Holding pushes to GitHub for now.** The user noted GitHub instability; commit locally throughout the plan but **don't push** until the user gives the all-clear at the end of Phase H. Realm-side push in Phase C is a separate gate (different repo, may be subject to the same hold).
- **Issue #46 is provisional.** The permission-testing regression issue is drafted at `.issues/permission-testing.md` but has not been filed yet (held by the same GitHub instability that's blocking pushes). Several phases reference "issue #46" in doc bodies, skill content, and the CR body. At Phase H — once GitHub is healthy — file the issue first, capture its actual number, and grep+replace if it landed somewhere other than #46:

  ```bash
  grep -rn '#46' D:/Dev/GitWS/yggdrasil/docs/gdd/permissions.md \
                  D:/Dev/GitWS/yggdrasil/.agent/skills/permissions-management/SKILL.md \
                  D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-permissions-doc.md \
                  D:/Dev/GitWS/yggdrasil/.crs/permissions-and-hygiene.md
  ```

  If the issue landed at a different number, fix-up commit the doc and skill before opening the CR (the bodyfiles and CR body are not yet committed).
- Stay on branch `design/permissions-and-hygiene` for the duration. The design spec is already committed at `3d54fec`.
- For all file edits use Edit/Write tools with absolute Windows-style paths (`D:/Dev/GitWS/yggdrasil/...`).
- yggdrasil has no shell-test framework. Verification is `bash -n` syntax checks + runtime smoke tests on synthetic fixtures — same pattern as the realms-and-hoards landing.

---

## Files Changed Overview

### Phase A — Tooling fixes

- **Modify** `scripts/ws-realm.sh` — move `set -euo pipefail` after the source-vs-execute guard.
- **Modify** `scripts/ws-hoard.sh` — same.
- **Modify** `scripts/ws-component.sh` — same.
- **Modify** `scripts/ws-commit.sh` — bump stale `Co-Authored-By` model default.
- **Modify** `scripts/ws` — switch four env-var assignments to `:=` form.

### Phase B — `ws status` walks realms + hoards

- **Modify** `scripts/ws-status.sh` — add realm + hoard walk loops mirroring the existing components walk.

### Phase C — Doc relocation

- **Realm side**: copy nine files into `realms/realm-siliconsaga/docs/agent-security/`; commit + push the realm.
- **Yggdrasil side**: `remove:` the same nine files via the hygiene-pass commit's frontmatter.

### Phase D — New permissions doc

- **Create** `docs/gdd/permissions.md` (~250-400 lines, seven sections).

### Phase E — New permissions-management skill

- **Create** `.agent/skills/permissions-management/SKILL.md` (~80-150 lines, six sections).

### Phase F — `gdd-orientation` updates

- **Modify** `.agent/skills/gdd-orientation/SKILL.md` — add commit-cadence-nudge logic + permissions-management pointer.
- **Modify** `templates/thalamus.md` — add `commit_staleness_days: 2` to the example frontmatter block with an inline comment.

### Phase G — `gdd-housekeeping` update

- **Modify** `.agent/skills/gdd-housekeeping/SKILL.md` — add per-item permissions hook.

### Phase H — Final verification + push

- No file changes; runs e2e smoke tests, confirms working tree clean, gates the push.

---

# Phase A — Tooling fixes

Three small mechanical fixes. Each is a few lines.

### Task A1: Move `set -euo pipefail` after the source-vs-execute guard in three sibling scripts

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws-realm.sh`
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws-hoard.sh`
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh`

- [ ] **Step 1: Find the lines in each script.**

For each of the three scripts:
- The `set -euo pipefail` line is near the top (typically lines 10-20).
- The source-vs-execute guard `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` is near the bottom, just before the dispatch logic. Use `grep -n` to find both:

```bash
grep -n 'set -euo pipefail\|BASH_SOURCE\[0\]' D:/Dev/GitWS/yggdrasil/scripts/ws-realm.sh
grep -n 'set -euo pipefail\|BASH_SOURCE\[0\]' D:/Dev/GitWS/yggdrasil/scripts/ws-hoard.sh
grep -n 'set -euo pipefail\|BASH_SOURCE\[0\]' D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh
```

Note the line numbers for both anchors in each file.

- [ ] **Step 2: For each script, delete the existing `set -euo pipefail` and re-insert it immediately after the guard.**

Use Edit (NOT replace_all — there should be exactly one occurrence per file):

For `ws-realm.sh`:
- Remove the existing top-of-file `set -euo pipefail` line (and its trailing blank line if any).
- Locate the guard: `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`
- Insert `set -euo pipefail` immediately AFTER that line, on its own.

The new shape is:

```bash
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
set -euo pipefail

# (dispatch logic continues)
```

Repeat for `ws-hoard.sh` and `ws-component.sh`.

- [ ] **Step 3: Syntax-check each script.**

```bash
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-realm.sh && echo "ws-realm.sh ok"
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-hoard.sh && echo "ws-hoard.sh ok"
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-component.sh && echo "ws-component.sh ok"
```

Expected: three "ok" lines.

- [ ] **Step 4: Verify sourcing doesn't leak strict mode.**

```bash
# Open a parent shell with permissive flags
bash -c 'set +e; source D:/Dev/GitWS/yggdrasil/scripts/ws-realm.sh; set | grep -E "^(errexit|nounset|pipefail)" | sort'
```

Expected: lines showing `errexit=off`, `nounset=off`, `pipefail=off` (or none of those — depending on bash version's default reporting). The point: sourcing did NOT set strict mode in the parent shell.

(If the parent shell shows `errexit=on` etc. after sourcing, the fix didn't take. Re-check that `set -euo pipefail` is below the guard, not above.)

### Task A2: Bump stale `Co-Authored-By` model default in `ws-commit.sh`

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws-commit.sh`

- [ ] **Step 1: Find the model default line.**

```bash
grep -n 'Opus 4\|CLAUDE_MODEL' D:/Dev/GitWS/yggdrasil/scripts/ws-commit.sh
```

Expected to find a line like `co_authored_by="Claude ${CLAUDE_MODEL:-Opus 4.6}"` near line 95-100.

- [ ] **Step 2: Edit the line.**

Find:

```bash
    co_authored_by="Claude ${CLAUDE_MODEL:-Opus 4.6}"
```

Replace with:

```bash
    co_authored_by="Claude ${CLAUDE_MODEL:-Opus 4.7}"
```

- [ ] **Step 3: Update the help text default mention.**

```bash
grep -n 'default: Opus' D:/Dev/GitWS/yggdrasil/scripts/ws-commit.sh
```

If found (likely in `commit_help()` near line 44), update the same `Opus 4.6` → `Opus 4.7`.

- [ ] **Step 4: Smoke test (no actual commit needed — just verify the trailer text would be right).**

```bash
cd D:/Dev/GitWS/yggdrasil
unset CLAUDE_MODEL
grep "Opus 4" scripts/ws-commit.sh
```

Expected: shows `4.7` in both the runtime default and any help text. No `4.6` left.

### Task A3: Switch router env-var assignments to `:=` defaults

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws`

- [ ] **Step 1: Find the assignments.**

```bash
grep -n '^ECOSYSTEM=\|^REALMS_DIR=\|^COMPONENTS_DIR=\|^OVERLAYS_DIR=' D:/Dev/GitWS/yggdrasil/scripts/ws
```

Expected: three assignments near lines 54-58 (after the realm rename, `OVERLAYS_DIR` should be gone).

- [ ] **Step 2: Edit each assignment to use the `:=` form.**

Find:

```bash
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
REALMS_DIR="$ROOT_DIR/realms"
COMPONENTS_DIR="$ROOT_DIR/components"
```

Replace with:

```bash
: "${ECOSYSTEM:="$ROOT_DIR/ecosystem.yaml"}"
: "${REALMS_DIR:="$ROOT_DIR/realms"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"
```

(`ROOT_DIR` itself stays as-is — it's derived from the script's own location and shouldn't be overridable.)

- [ ] **Step 3: Syntax-check.**

```bash
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws && echo "ws ok"
```

- [ ] **Step 4: Smoke test that env override now works through the router.**

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/components" "$tmpdir/templates/components/dummy"
echo "# Dummy" > "$tmpdir/templates/components/dummy/README.md"
cat > "$tmpdir/ecosystem.yaml" << 'EOF'
identity:
  human_account: testuser
EOF

# Run via the router. Before the fix, this would have written into the
# real workspace. After the fix, env overrides land it in $tmpdir.
COMPONENTS_DIR="$tmpdir/components" \
ROOT_DIR="$tmpdir" \
ECOSYSTEM="$tmpdir/ecosystem.yaml" \
TEMPLATES_DIR="$tmpdir/templates" \
  ws component init dummy testfix 2>&1 | tail -5

# Verify the scaffold landed in the temp dir, not the real workspace
ls "$tmpdir/components/testfix/" && echo "scaffold in temp dir — fix works"
ls D:/Dev/GitWS/yggdrasil/components/testfix/ 2>&1 | head -2 || echo "no leak to real workspace — fix works"

rm -rf "$tmpdir"
```

Expected: scaffold visible in the temp dir; the real workspace's `components/` does NOT contain a `testfix/` directory.

### Task A4: Commit Phase A

- [ ] **Step 1: Write the bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-tooling-fixes.md`:

```markdown
---
message: "fix(ws): tooling hygiene — strict-mode placement, model default, env-var clobber"
add:
  - scripts/ws-realm.sh
  - scripts/ws-hoard.sh
  - scripts/ws-component.sh
  - scripts/ws-commit.sh
  - scripts/ws
---

Three small fixes from the post-#45 hygiene pass:

- `set -euo pipefail` placement: moved below the source-vs-execute
  guard in `ws-realm.sh` / `ws-hoard.sh` / `ws-component.sh`. Sourcing
  these scripts (e.g. `ws-component.sh` sources `ws-realm.sh` for
  `ws_resolve_ecosystem`) no longer leaks strict mode into the parent
  shell.
- `Co-Authored-By` default in `ws-commit.sh`: bumped the stale
  `Claude Opus 4.6` baseline to `Claude Opus 4.7` to match the
  current model. The `$CLAUDE_MODEL` env-override path is unchanged.
- `scripts/ws` env-var clobber: switched `ECOSYSTEM`, `REALMS_DIR`,
  and `COMPONENTS_DIR` to `: "${VAR:=default}"` so caller-provided
  overrides survive the router. Mirrors the pattern the sub-scripts
  already use; makes synthetic-fixture smoke tests work uniformly
  whether you direct-invoke the sub-script or go through `ws`.

See `docs/plans/2026-04-27-permissions-and-hygiene-design.md` for the
broader hygiene-pass scope.
```

- [ ] **Step 2: Commit.**

```bash
ws commit yggdrasil .commits/hygiene-pass-tooling-fixes.md
```

- [ ] **Step 3: Verify the commit.**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 5 files modified, totals around 10-15 line-changes.

---

# Phase B — `ws status` walks realms + hoards

Single-script extension. Adds two new walk-loops mirroring the existing components walk.

### Task B1: Read the current `ws-status.sh` to understand its loop pattern

**Files:**
- Read-only: `D:/Dev/GitWS/yggdrasil/scripts/ws-status.sh`

- [ ] **Step 1: Read the current script.**

```bash
cat D:/Dev/GitWS/yggdrasil/scripts/ws-status.sh
```

Locate:
- The components walk-loop (probably near the bottom, after yggdrasil-root status).
- The function (if any) that prints a single repo's status (branch + dirty flag + listing). This will be reused for realms and hoards.

Note the pattern. Keep the existing yggdrasil-root and components-walk as-is.

### Task B2: Add the realm walk-loop

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/scripts/ws-status.sh`

- [ ] **Step 1: Identify the insertion point.**

The new realm walk should sit AFTER the components walk (so output order is yggdrasil → components → realms → hoards). Find the end of the components-walk loop's `done` line.

- [ ] **Step 2: Add the realm walk after the components-walk's `done`.**

Insert this block (adapting variable names as needed to match the existing components-walk style):

```bash
# Walk realms/ — directories with a .git/ subfolder, regardless of
# active-realm selection. We want to show ALL cloned realms' status,
# not just the active one.
realms_dir="${REALMS_DIR:-$ROOT_DIR/realms}"
if [[ -d "$realms_dir" ]]; then
    realm_count=0
    for realm_path in "$realms_dir"/*/; do
        [[ -d "$realm_path/.git" ]] || continue
        realm_count=$((realm_count + 1))
    done
    if [[ "$realm_count" -gt 0 ]]; then
        echo ""
        echo "=== realms ==="
        for realm_path in "$realms_dir"/*/; do
            [[ -d "$realm_path/.git" ]] || continue
            realm_name="$(basename "$realm_path")"
            echo ""
            echo "=== $realm_name ==="
            print_repo_status "$realm_path"   # name TBD — match the function used by the components walk
        done
    fi
fi
```

**IMPORTANT**: replace `print_repo_status` with the actual function name used by the components walk. If the components walk inlines the status logic instead of calling a helper, either:
- Extract the inline logic into a helper function first, then call it from all three walks; OR
- Inline the same logic in the new realm/hoard walks.

Pick whichever matches the script's existing style. If the script is short and inlines everything, inlining is fine.

- [ ] **Step 3: Add the hoard walk after the realm walk.**

Mirror the same shape:

```bash
# Walk hoards/ — same shape as realms walk
hoards_dir="${HOARDS_DIR:-$ROOT_DIR/hoards}"
if [[ -d "$hoards_dir" ]]; then
    hoard_count=0
    for hoard_path in "$hoards_dir"/*/; do
        [[ -d "$hoard_path/.git" ]] || continue
        hoard_count=$((hoard_count + 1))
    done
    if [[ "$hoard_count" -gt 0 ]]; then
        echo ""
        echo "=== hoards ==="
        for hoard_path in "$hoards_dir"/*/; do
            [[ -d "$hoard_path/.git" ]] || continue
            hoard_name="$(basename "$hoard_path")"
            echo ""
            echo "=== $hoard_name ==="
            print_repo_status "$hoard_path"   # same helper / inlined logic as realm walk
        done
    fi
fi
```

- [ ] **Step 4: Syntax check.**

```bash
bash -n D:/Dev/GitWS/yggdrasil/scripts/ws-status.sh && echo "syntax ok"
```

### Task B3: Smoke test

- [ ] **Step 1: Run `ws status` from a clean workspace.**

```bash
cd D:/Dev/GitWS/yggdrasil
ws status 2>&1 | head -40
```

Expected:

```text
=== yggdrasil ===
  branch: design/permissions-and-hygiene  (dirty — N file(s))
  ...

=== components ===
=== nordri ===
  ...
=== mimir ===
  ...

=== realms ===
=== realm-siliconsaga ===
  branch: main  (clean)

=== hoards ===
=== thalami-cervator ===
  branch: main  (dirty — 1 file(s))
   M Dionysus-thalamus.md
```

- [ ] **Step 2: Verify the new sections appear and don't break the existing output.**

If realms or hoards aren't cloned locally, the corresponding section should be SUPPRESSED (not shown as empty). The `realm_count`/`hoard_count` guard handles this. Verify by spot-checking the `ws status` output for any `=== realms ===` followed immediately by another `===` header (which would indicate empty). There shouldn't be any.

### Task B4: Commit Phase B

- [ ] **Step 1: Write the bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-ws-status.md`:

```markdown
---
message: "feat(ws): ws status walks realms/ and hoards/ in addition to components/"
add:
  - scripts/ws-status.sh
---

Extends `ws status` to walk `realms/*/.git/` and `hoards/*/.git/`
directories on disk, not via ecosystem-config declaration. Reports
branch + dirty state + changed-file listing for each, mirroring the
existing components walk.

Sections suppressed when empty (no realms or hoards cloned). Active
realm/active thalami selection is irrelevant — we show all cloned
ones since users want full workspace dirty-state visibility from a
single command.

Lays the groundwork for `gdd-orientation`'s commit-cadence nudge
(coming in this same PR) — orientation calls `ws status` to detect
dirty thalami-hoard state, then layers the temporal logic
(commit_staleness_days threshold) on top.
```

- [ ] **Step 2: Commit.**

```bash
ws commit yggdrasil .commits/hygiene-pass-ws-status.md
```

- [ ] **Step 3: Verify.**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 1 file modified, ~30-40 line additions.

---

# Phase C — Doc relocation (`docs/agent-security/` → realm)

Two-repo coordination. Realm side first (so the content is in its new home before being removed from yggdrasil). Yggdrasil-side commit follows. **Don't push either side until Phase H.**

### Task C1: Verify no internal links to `docs/agent-security/`

**Files:**
- Read-only sweep across yggdrasil

- [ ] **Step 1: Grep for any links.**

```bash
grep -rn 'agent-security/' D:/Dev/GitWS/yggdrasil/ \
  --include='*.md' \
  --exclude-dir=hoards \
  --exclude-dir=realms \
  --exclude-dir=components 2>&1 | head -30
```

Expected (per design-time check): no hits other than within `docs/agent-security/` itself or within design plans referencing the relocation. If any unexpected hits appear (e.g. `AGENTS.md` linking to one of the files), capture them — they need to be updated to point at the new realm path or removed.

If hits found beyond the design plan itself: pause and report to the controller before continuing.

### Task C2: Realm-side — copy files in, commit, and prepare push

**Files:**
- Create: `realms/realm-siliconsaga/docs/agent-security/{advanced-capability-model,implementation-phases,openclaw-security,pattern-calendar,pattern-chat-segmentation,pattern-contact-management,pattern-email,pattern-gitops-staging,pattern-voice-pipeline}.md`

- [ ] **Step 1: Make the destination directory and copy the files.**

```bash
mkdir -p D:/Dev/GitWS/yggdrasil/realms/realm-siliconsaga/docs/agent-security
cp -v D:/Dev/GitWS/yggdrasil/docs/agent-security/*.md \
      D:/Dev/GitWS/yggdrasil/realms/realm-siliconsaga/docs/agent-security/
```

Expected: 9 files copied.

- [ ] **Step 2: Verify the copy.**

```bash
ls D:/Dev/GitWS/yggdrasil/realms/realm-siliconsaga/docs/agent-security/ | sort
```

Expected output:

```text
advanced-capability-model.md
implementation-phases.md
openclaw-security.md
pattern-calendar.md
pattern-chat-segmentation.md
pattern-contact-management.md
pattern-email.md
pattern-gitops-staging.md
pattern-voice-pipeline.md
```

- [ ] **Step 3: Write the realm-side bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/realm-relocate-agent-security.md`:

```markdown
---
message: "docs: relocate agent-security/ from upstream yggdrasil"
add:
  - docs/agent-security/advanced-capability-model.md
  - docs/agent-security/implementation-phases.md
  - docs/agent-security/openclaw-security.md
  - docs/agent-security/pattern-calendar.md
  - docs/agent-security/pattern-chat-segmentation.md
  - docs/agent-security/pattern-contact-management.md
  - docs/agent-security/pattern-email.md
  - docs/agent-security/pattern-gitops-staging.md
  - docs/agent-security/pattern-voice-pipeline.md
---

These nine files predate GDD and reflect general AI-tooling-sandboxing
exploration that's been substantially superseded (Nvidia OpenShell /
NemoClaw addresses the same concerns more concretely). Keeping them in
upstream yggdrasil's `docs/` competed with a new GDD-specific
permissions doc landing in the same hygiene PR (PR #TBD against
SiliconSaga/yggdrasil) and confused the boundary between "GDD
methodology" (yggdrasil) and "personal exploration / community-specific
notes" (this realm).

Moving here keeps them findable for whoever picks up the security thread
later — the work itself is still useful as a starting point, just not
on yggdrasil's `docs/` shelf.

The yggdrasil-side companion commit references this commit's SHA in its
message body.
```

- [ ] **Step 4: Commit on the realm side.**

```bash
ws commit realm-siliconsaga .commits/realm-relocate-agent-security.md
```

- [ ] **Step 5: Note the realm commit SHA for the yggdrasil-side bodyfile.**

```bash
git -C D:/Dev/GitWS/yggdrasil/realms/realm-siliconsaga log -1 --format=%H
```

Save this SHA. The yggdrasil-side commit (Task C3) references it.

- [ ] **Step 6: DO NOT push the realm.** Hold for Phase H.

### Task C3: Yggdrasil-side — remove the files

**Files:**
- Remove: nine files under `docs/agent-security/`

- [ ] **Step 1: Get the realm commit SHA from C2 Step 5.**

(Carry it forward to the bodyfile body.)

- [ ] **Step 2: Write the yggdrasil-side bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-relocate-agent-security.md`:

```markdown
---
message: "docs: relocate agent-security/ to realm-siliconsaga"
remove:
  - docs/agent-security/advanced-capability-model.md
  - docs/agent-security/implementation-phases.md
  - docs/agent-security/openclaw-security.md
  - docs/agent-security/pattern-calendar.md
  - docs/agent-security/pattern-chat-segmentation.md
  - docs/agent-security/pattern-contact-management.md
  - docs/agent-security/pattern-email.md
  - docs/agent-security/pattern-gitops-staging.md
  - docs/agent-security/pattern-voice-pipeline.md
---

These files predate GDD and reflect general AI-tooling-sandboxing
exploration that's been substantially superseded (Nvidia OpenShell /
NemoClaw work). They competed for shelf space with the new GDD-specific
permissions doc (`docs/gdd/permissions.md`, also in this hygiene PR).

Relocated to `realms/realm-siliconsaga/docs/agent-security/` —
SiliconSaga-realm commit <REALM_SHA> mirrors this directory structure
with no content edits, just a path change.

A Thalamus pointer captures the new location for security-oriented
follow-up work.

See `docs/plans/2026-04-27-permissions-and-hygiene-design.md` §
"Doc relocation" for the rationale.
```

Replace `<REALM_SHA>` with the SHA you noted in C2 Step 5.

- [ ] **Step 3: Commit on yggdrasil.**

```bash
ws commit yggdrasil .commits/hygiene-pass-relocate-agent-security.md
```

- [ ] **Step 4: Verify the deletes.**

```bash
ls D:/Dev/GitWS/yggdrasil/docs/agent-security/ 2>&1 | head -3
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: `ls` shows directory not found OR empty; `git log --stat` shows 9 deletions totaling 0 line-additions.

- [ ] **Step 5: Add a Thalamus pointer.**

Edit the active thalami-hoard's per-machine thalamus file (e.g. `D:/Dev/GitWS/yggdrasil/hoards/thalami-Cervator/Dionysus-thalamus.md`). Under "## Observations", add:

```markdown
- **Old `docs/agent-security/` content lives in `realms/realm-siliconsaga/docs/agent-security/`** (relocated 2026-04-27). The nine files (capability model, implementation phases, openclaw-security, several pattern-*) predate GDD and reflect general AI-tooling-sandboxing exploration that's been substantially superseded by Nvidia OpenShell / NemoClaw work. Moved out of upstream yggdrasil's `docs/` to clear shelf space for the new GDD-specific permissions doc, but kept findable here for any future security-oriented thread that wants to revisit them.
```

Don't commit the Thalamus yet — batched per the cadence preference.

---

# Phase D — New permissions doc

Single new file at `docs/gdd/permissions.md`. Content per the design spec's §5 ("Permission system documentation"). Length target ~250-400 lines, seven sections.

### Task D1: Confirm `docs/gdd/` exists

**Files:**
- Read-only check

- [ ] **Step 1: Verify the directory.**

```bash
ls D:/Dev/GitWS/yggdrasil/docs/gdd/ 2>&1 | head -10
```

Expected: directory exists, has some content (e.g. `samples/`, `index.md`, etc.). If absent, `mkdir -p` it before D2.

### Task D2: Write `docs/gdd/permissions.md`

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/docs/gdd/permissions.md`

- [ ] **Step 1: Write the doc with all 7 sections.**

Use the design spec's §5 as the structural guide. Each section's content:

````markdown
# GDD Permissions Reference

How `.claude/settings.json` works in a GDD workspace, what makes a
pattern safe, and how to verify the safety claims for yourself.

This doc is the source of truth for the permission system's behavior
and the empirical findings it relies on. The `permissions-management`
skill (`.agent/skills/permissions-management/`) is the operational
companion — agents invoke it for live decisions; this doc is what they
(and humans, and automated review tools) read for reference.

---

## 1. What `.claude/settings.json` is and how it loads

Claude Code reads two settings files for each workspace:

- **`.claude/settings.json`** — project-level, committed to the repo.
  Shared across everyone working in the workspace.
- **`.claude/settings.local.json`** — per-user, gitignored. Not shared.

Both are merged at startup. Where they conflict on a single key, local
wins. The relevant top-level structure is:

```json
{
  "permissions": {
    "allow": [ "Bash(...)", "..." ],
    "deny":  [ "Bash(...)", "..." ]
  },
  "enableAllProjectMcpServers": false
}
```

`permissions.allow` and `permissions.deny` are lists of pattern strings.
A command is checked against `deny` first; if it matches, it's blocked
regardless of `allow`. Otherwise, if it matches any `allow`, it's
auto-approved. Otherwise the user is prompted.

`enableAllProjectMcpServers: false` means MCP servers declared by the
project don't auto-enable; users opt in per server via `/mcp`.

---

## 2. Pattern shapes

Three shapes appear in this workspace's `.claude/settings.json`:

### Exact-form

```text
Bash(ws status)
Bash(ws status --verbose)
Bash(git -C * branch --show-current)
```

The literal string after the command name must match exactly. The `*`
inside `git -C * branch --show-current` is a wildcard for the path
slot only; the trailing `branch --show-current` is a literal. A
command of `git -C . branch --list` does NOT match — `--list` ≠
`--show-current`. The matcher is honest about this; non-matches
produce a permission prompt.

### Prefix wildcards

```text
Bash(git -C * show *)
Bash(git -C * log *)
Bash(ws push *)
Bash(bash scripts/ws review * --since *)
```

Each `*` is a wildcard slot. The matcher binds each slot to a single
argument-shaped sequence. The space before `*` matters: `Bash(foo*)`
without the space matches `foo` followed by anything (including
`foobar`); `Bash(foo *)` requires a space, then any single argument.
For prefix matching of arguments, always include the space.

### MCP tool names

```text
mcp__slack__slack_read_thread
mcp__github__list_pull_requests
```

Full tool names, no wildcard. MCP names are already specific enough.

---

## 3. The two-layer defense

Every allow pattern in `.claude/settings.json` should be safe even if a
single layer fails. We rely on two:

### Layer 1: subcommand-level

The chosen subcommand for each pattern is read-only at the porcelain
level. `git show`, `git log`, `git diff`, `git status`, `git ls-tree`,
`git grep` — all read-only. There is no flag combination that mutates
state. We deliberately don't grant a wildcard pattern to subcommands
that DO have mutating flag-forms — `git branch -d` (deletes branches),
`git remote add` (adds a remote), `git push` (writes to a remote).
For those, we either pin to an exact safe form (`git -C * branch
--show-current`, `git -C * remote -v`) or don't grant at all.

### Layer 2: matcher-level

The matcher scopes wildcards correctly:

- **Compound commands** (`|`, `&&`, `||`, `;`) are validated
  per-segment. `git -C . show HEAD | xxd` is two segments: the left
  matches `Bash(git -C * show *)` and is allowed; the right is `xxd`
  alone and prompts. The wildcards in the left side don't extend
  across the pipe.
- **Command substitution** (`$(...)` and backticks) is rejected by the
  matcher. `git -C $(echo .) show HEAD --stat` does NOT match
  `Bash(git -C * show *)` — the matcher prompts and offers no
  "don't ask again" option. Substitution is too dynamic for any
  static pattern to safely allowlist.
- **Exact-form pinning is literal.** `git -C . branch --list` does
  not match `Bash(git -C * branch --show-current)` because the
  trailing literals differ.

Both layers must hold. If Claude Code's matcher behavior changes —
for instance, if compound commands stopped being per-segment validated
— a "safe" pattern could become unsafe. That's the case for
automated regression testing tracked at issue #46.

---

## 4. Empirical matcher findings

Verified in interactive testing. Each row is a (pattern, attempted
command, expected outcome) triple:

| Pattern | Command | Expected outcome | Notes |
|---------|---------|------------------|-------|
| `Bash(git -C * show *)` | `git -C . show HEAD --stat` | Allowed silently | Baseline |
| `Bash(git -C * show *)` | `git -C . show HEAD --stat \| xxd` | Right side prompts; left is allowed | Per-segment |
| `Bash(git -C * show *)` | `git -C $(echo .) show HEAD --stat` | Prompted; no don't-ask offer | Substitution rejected |
| `Bash(git -C * branch --show-current)` | `git -C . branch --list` | Prompted; don't-ask offer is the exact command | Exact-form pinning honored |
| `Bash(git -C * remote -v)` | `git -C . remote` | Prompted; don't-ask offer is the exact command | Same — exact-form |

When you add a new allow pattern, also add at least one positive case
(matches → allowed) and one negative case (close-but-not-quite →
prompts) to this table. Mismatches between the table and observed
behavior are PR-blocking — they indicate either a stale doc or a
matcher behavior change.

---

## 5. When to widen vs narrow patterns

A decision tree for adding a new `Bash(...)` pattern:

1. **Is the command already auto-allowed by Claude Code?** (`cat`, `ls`,
   `pwd`, `git status`, `git log` without `-C`, `gh pr view`, etc.) If
   yes, don't add a pattern — it's redundant.
2. **Does the command's subcommand have any mutating flag-form?**
   - No (e.g. `git show`, `git diff`, `git ls-tree`): a prefix-wildcard
     pattern (`Bash(<command> <subcommand> *)`) is fine.
   - Yes (e.g. `git branch -d`, `git remote add`): pin to the exact
     safe form (`Bash(git -C * branch --show-current)`).
3. **Is the command an arbitrary-execution shell?** (`bash *`,
   `python *`, `node *`, `npx *`, `bunx *`, `uvx *`, `make *`,
   `npm run *`, `bun run *`, `gh api *`.)  Never widen these. An exact
   `Bash(bash -n some-specific-script.sh)` is fine; wildcards aren't.
4. **Does the command write to a shared system?** (push, deploy,
   publish, send). These are Side-effect tier in
   `docs/ws-cli-guide.md` — never auto-allow; let the user decide
   case-by-case.

When in doubt, narrower wins. You can always widen later. Narrowing
post-hoc is harder (you've already trained yourself to expect the
wide form).

---

## 6. Cross-reference rule

When you modify `.claude/settings.json`'s `permissions.allow` (or
`permissions.deny`), also update §4 above to reflect the new pattern
with at least one positive and one negative case.

The two artifacts are paired:
- `.claude/settings.json` is what Claude Code enforces.
- `docs/gdd/permissions.md` (this file) is what humans, automated
  reviewers, and the agent reason against.

Drift between them is a real bug — humans trust the doc, agents trust
the doc, and a stale doc gives false confidence. PR review for
`.claude/settings.json` changes should call out a missing doc update
as blocking.

The `permissions-management` skill enforces this rule operationally:
when an agent adds a pattern, the skill includes the doc update as
part of the same change.

---

## 7. Future Directions

- **Cross-framework porting.** Other agent frameworks (Codex, Gemini
  CLI, Cursor, etc.) have their own permission-style configs. The
  semantics differ — some are tool-name-only, some have richer
  per-tool argument matching, some have no analogue to the
  `permissions.deny` override layer. Mapping Claude Code's allowlist
  to each framework's equivalent is a future arc; the skill points
  at this thread but doesn't carry the porting guidance in v1.

- **Automated regression testing** (issue #46). Today the empirical
  findings table in §4 is the source of truth, but there's no test
  harness that re-asserts those findings against new Claude Code
  versions. The future regression suite will execute each (pattern,
  command, expected) triple and flag matcher-behavior changes.

- **Sandboxing tooling.** Personal exploration of AI-tooling
  sandboxing patterns lives in
  `realms/realm-siliconsaga/docs/agent-security/` (relocated from
  this repo's `docs/` in the same hygiene PR that introduced this
  doc). Some of that work — particularly Nvidia's OpenShell /
  NemoClaw lineage — could inform a future GDD security category
  that sits next to permissions.
````

(Approximate length: ~340 lines. The exact line count depends on
final prose.)

- [ ] **Step 2: Verify the doc renders cleanly.**

```bash
# Markdown linter check (if markdownlint-cli2 is on PATH; otherwise skip)
markdownlint-cli2 D:/Dev/GitWS/yggdrasil/docs/gdd/permissions.md 2>&1 | head -10 || echo "markdownlint-cli2 not on PATH; skipping"
```

If `markdownlint-cli2` is on PATH, expect zero issues. If not, skip — it's not blocking.

- [ ] **Step 3: Spot-check that the empirical-findings table content matches the patterns in `.claude/settings.json`.**

```bash
grep -E '^\s*"Bash\(git -C' D:/Dev/GitWS/yggdrasil/.claude/settings.json | head -10
```

Confirm that each pattern in the doc's §4 table has a corresponding entry in `.claude/settings.json`.

### Task D3: Commit Phase D

- [ ] **Step 1: Write the bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-permissions-doc.md`:

```markdown
---
message: "docs: add GDD permissions reference (docs/gdd/permissions.md)"
add:
  - docs/gdd/permissions.md
---

New reference doc for the GDD permission system. Sits at
`docs/gdd/permissions.md` (next to GDD methodology), audience is
security-paranoid yggdrasil users + automated review tools (CodeRabbit
et al.) + agents reading on-demand + future maintainers.

Seven sections: how `.claude/settings.json` loads, pattern shapes
(exact / prefix wildcard / MCP), two-layer defense, empirical matcher
findings table, when to widen vs narrow, the cross-reference rule
(modifying allowlist → also update this doc), Future Directions.

The empirical-findings table is the seed for issue #46's automated
regression test suite — each row is a (pattern, command, expected
outcome) triple already in shape for the future test harness.

See `docs/plans/2026-04-27-permissions-and-hygiene-design.md` § 5.
```

- [ ] **Step 2: Commit.**

```bash
ws commit yggdrasil .commits/hygiene-pass-permissions-doc.md
```

- [ ] **Step 3: Verify.**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 1 file added, ~340 lines.

---

# Phase E — New permissions-management skill

Single new file at `.agent/skills/permissions-management/SKILL.md`. Content per the design spec's §6. Length target ~80-150 lines.

### Task E1: Write the skill

**Files:**
- Create: `D:/Dev/GitWS/yggdrasil/.agent/skills/permissions-management/SKILL.md`

- [ ] **Step 1: Make the directory.**

```bash
mkdir -p D:/Dev/GitWS/yggdrasil/.agent/skills/permissions-management
```

- [ ] **Step 2: Write the skill file.**

Content with all six sections per the design spec:

```markdown
---
name: permissions-management
description: >
  Use when adding or editing permission patterns, considering a "don't
  ask again" offer at a permission prompt, explaining the permission
  system to a user, or reviewing .claude/settings.json changes during
  code review. Operational companion to docs/gdd/permissions.md.
---

# Permissions Management

Operational guidance for working with `.claude/settings.json` allowlist
and deny rules. The reference content (how the system works, the
two-layer defense model, the empirical matcher findings) lives in
`docs/gdd/permissions.md`. This skill is what to *do* with that
knowledge.

## When to Use

Invoke this skill when:

- About to **add or edit** a pattern in `.claude/settings.json` — sister
  to `fewer-permission-prompts` (which does the bulk-from-transcripts
  case); this skill handles per-pattern safety analysis.
- At a **permission prompt** that's offering a "don't ask again" choice
  with a wide pattern — judgment guidance below.
- A **user asks** how the permission system works, or what a specific
  pattern means.
- **Reviewing `.claude/settings.json` changes** during code review.

For the bulk case (scanning recent transcripts and proposing many
patterns at once), invoke `fewer-permission-prompts` instead.

## Pattern-form decision tree

Before adding any pattern:

1. **Already auto-allowed?** Many commands are auto-allowed by Claude
   Code without an explicit pattern (`cat`, `ls`, `pwd`, plain `git
   status`, plain `git log`, `gh pr view`, etc.). If yes: don't add a
   pattern — it's redundant.
2. **Subcommand has mutating flag-forms?**
   - **No** (e.g. `git show`, `git diff`, `git ls-tree`): a prefix
     wildcard is fine: `Bash(git -C * show *)`.
   - **Yes** (e.g. `git branch -d`, `git remote add`): pin to the
     exact safe form: `Bash(git -C * branch --show-current)`,
     `Bash(git -C * remote -v)`.
3. **Arbitrary-execution shell?** (`bash *`, `python *`, `node *`,
   `npx *`, `bunx *`, `uvx *`, `make *`, `npm run *`, `gh api *`.)
   Never widen. Exact forms only, if at all.
4. **Writes to a shared system?** (push, deploy, publish, send.)
   Don't allow at all. Side-effect-tier per `docs/ws-cli-guide.md`.

When in doubt, narrower wins.

## "Don't ask again" judgment guidance

Claude Code prompts on unmatched commands. The prompt offers a
"don't ask again" with a suggested pattern (often wide). Decision
criteria for whether to accept:

| Offered pattern | Read-only command? | Pattern admits non-read-only forms? | Decision |
|-----------------|--------------------|-------------------------------------|----------|
| Wide (`Bash(xxd*)`, `Bash(python *)`) | Doesn't matter | Yes — wildcards admit anything | **Decline.** Suggest a narrower pattern manually if it's worth allowlisting at all. |
| Exact form (`Bash(git -C . status --porcelain)`) | Yes | No — pinned to one specific safe form | **Accept** — equivalent to adding the pattern via this skill anyway. |
| Prefix on a non-mutating subcommand (`Bash(git -C * show *)`) | Yes | No — subcommand is read-only | **Accept**, but verify the subcommand has no mutating flag-forms first (decision tree #2). |
| Anything wrapping `bash`, `python`, `node`, `make`, etc. | Doesn't matter | Yes — any of these is arbitrary code execution | **Always decline.** |

When declining, take a moment to either suggest a narrower pattern
inline (using this skill's decision tree), capture a Thalamus
observation about the prompt for later batch review, or just let the
user decide.

## Scope-narrowing checklist

Before committing any new pattern:

- [ ] Could this pattern match a mutating subcommand? (Re-read the
  command's `--help` and look for any flag that writes/deletes/sends.)
- [ ] Does the wildcard admit shell metacharacters that change the
  command's semantics? (Almost never; the matcher rejects substitution
  and validates compound commands per-segment, but corner cases exist.)
- [ ] Is there an existing auto-allowed form that covers this without
  a custom pattern? (See `docs/gdd/permissions.md` § 1.)
- [ ] Does the pattern align with `docs/gdd/permissions.md` § 5
  (when-to-widen-vs-narrow)? If you're departing from the doc's
  guidance, document the reason in the commit body.

## Cross-reference rule

When you modify `.claude/settings.json`'s `permissions.allow` (or
`permissions.deny`):

1. **Add the pattern.**
2. **Add empirical test cases to `docs/gdd/permissions.md` § 4.**
   Minimum: one positive case (matches → allowed) and one negative
   case (close-but-not-quite → prompts).
3. **Commit both files together.** A commit that touches the allowlist
   without updating the doc is review-blocking.

The doc and the config are paired artifacts. Drift gives false
confidence — humans and agents both trust the doc.

## Pointers

- `fewer-permission-prompts` — Claude Code-native skill for the
  bulk-from-transcripts case (sister to this one).
- `docs/gdd/permissions.md` — full reference content; consult for
  matcher details, pattern shapes, and the empirical findings table.
- Issue #46 — automated regression testing of allowlist patterns
  (future arc; not in v1's scope).

## Future scope

Cross-framework porting (mapping Claude Code's allowlist semantics to
Codex / Gemini / Cursor / etc.) is a known future direction. Not
covered by v1 of this skill — when picking it up, design as its own
arc.
```

(Approximate length: ~120 lines.)

- [ ] **Step 3: Verify the skill is well-formed.**

```bash
# Check the frontmatter is valid (just verify the file starts and ends correctly)
head -5 D:/Dev/GitWS/yggdrasil/.agent/skills/permissions-management/SKILL.md
tail -5 D:/Dev/GitWS/yggdrasil/.agent/skills/permissions-management/SKILL.md
```

Expected: starts with `---\nname: permissions-management\n...` frontmatter; ends with the "Future scope" section.

### Task E2: Commit Phase E

- [ ] **Step 1: Write the bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-permissions-skill.md`:

```markdown
---
message: "feat(skill): add permissions-management for per-pattern decisions"
add:
  - .agent/skills/permissions-management/SKILL.md
---

Operational companion to `docs/gdd/permissions.md`. Triggered when
adding/editing patterns, considering a "don't ask again" offer,
explaining the permission system to a user, or reviewing
.claude/settings.json changes.

Six sections: triggers, pattern-form decision tree, "don't ask again"
judgment table, scope-narrowing checklist, cross-reference rule
(allowlist edits paired with doc updates), and pointers/future scope.

Sister to the Claude Code-native `fewer-permission-prompts` skill —
that one handles the bulk-from-transcripts case; this one handles
per-pattern safety analysis when you already know what you want to
add.

Loading discipline: on-demand only. The `gdd-orientation` update in
this same PR adds a one-line pointer at the skill so the agent knows
it exists; actual content loads only when invoked. Avoids preloading
substantial content into every session's baseline.

See `docs/plans/2026-04-27-permissions-and-hygiene-design.md` § 6.
```

- [ ] **Step 2: Commit.**

```bash
ws commit yggdrasil .commits/hygiene-pass-permissions-skill.md
```

- [ ] **Step 3: Verify.**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 1 file added, ~120 lines.

---

# Phase F — `gdd-orientation` updates

Two additions to the existing skill: pointer at permissions-management, plus the commit-cadence nudge logic. Plus updating the thalamus template's frontmatter example.

### Task F1: Read the current `gdd-orientation/SKILL.md` to find insertion points

**Files:**
- Read-only: `D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-orientation/SKILL.md`

- [ ] **Step 1: Read the skill.**

```bash
cat D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-orientation/SKILL.md | head -100
```

Identify:
- The startup-sequence section (where Step 0 / Step 1 are).
- A natural place for a one-paragraph "available skills for this session" note (likely near the end of the startup sequence or in a "Skills you might invoke during the session" sidebar).

### Task F2: Add the permissions-management pointer

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-orientation/SKILL.md`

- [ ] **Step 1: Add a short paragraph in the orientation flow.**

Find an appropriate spot near the end of the startup sequence (after the existing Steps 0-7), and insert a paragraph like:

```markdown
## Skills available during this session

The session has several specialized skills that are NOT loaded by
default at startup but are worth knowing about:

- **`permissions-management`** — invoke when handling permission prompts
  during the session, especially when offered a "don't ask again"
  choice. See `docs/gdd/permissions.md` for the underlying reference
  content. The skill carries the operational decision-making
  guidance.

- **`fewer-permission-prompts`** (Claude Code-native) — invoke when
  permission prompts are piling up and you want to scan recent
  transcripts to propose a batch of safe additions to
  `.claude/settings.json`.

These skills load on-demand. Don't preload them; just remember they
exist.
```

(Adapt the section heading and prose style to match the existing skill — this is a guide, not verbatim required.)

### Task F3: Add the commit-cadence-nudge logic

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-orientation/SKILL.md`

- [ ] **Step 1: Add a new sub-step in the startup sequence.**

The natural placement is just after the existing Step 0 (Resolve the active thalamus file) — the cadence check happens once we know which thalami hoard is active.

Insert content like:

```markdown
### Step 0a: Thalamus commit-cadence nudge

If a thalami hoard is active (Step 0 resolved one), check whether the
per-machine thalamus file has uncommitted changes that have been
sitting around longer than `commit_staleness_days` (frontmatter
field; defaults to 2 if unset).

Mechanism:

1. Detect dirty state via `ws status` output for the active thalami
   hoard. (`ws status` walks `hoards/*/.git/` and reports per-hoard
   dirty state.)
2. If dirty: get the last-commit timestamp for the per-machine file:
   ```
   git -C hoards/<thalami-hoard> log -1 --format=%ct <machine>-thalamus.md
   ```
   This returns a Unix timestamp.
3. Compute elapsed time:
   ```
   elapsed_seconds = $(date +%s) - last_commit_timestamp
   threshold_seconds = commit_staleness_days * 86400
   ```
4. If `elapsed_seconds > threshold_seconds`: surface a nudge.

Wording:

> "Thalamus: <N> uncommitted observations. Last commit was <X> days,
> <Y> hours ago (threshold: commit_staleness_days = <Z>). Want me to
> commit these before we start, or save for later?"

Where `<N>` is dirty-line count from `ws status`, `<X>` and `<Y>` are
the elapsed time formatted as days/hours, and `<Z>` is the threshold
value.

If the user says "commit now," walk them through writing a bodyfile
and run `ws commit thalami-<user> <bodyfile>` (do NOT auto-stage; the
bodyfile's `add:` list is explicit per the cadence-preference
elsewhere in the Thalamus). If they say "save for later" or
equivalent, proceed silently.

Below threshold or clean: silent. No mention at all in orientation.
The threshold is the only signal; no nudge means no need to think
about it.
```

- [ ] **Step 2: Verify the skill still parses (no broken markdown).**

```bash
head -50 D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-orientation/SKILL.md | grep -c '^#'
```

Expected: a reasonable count of headers — hard to be precise without seeing the existing structure, but should NOT be zero (would indicate something broke).

### Task F4: Update the thalamus template frontmatter

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/templates/thalamus.md`

- [ ] **Step 1: Read the template.**

```bash
head -15 D:/Dev/GitWS/yggdrasil/templates/thalamus.md
```

Find the YAML frontmatter block (between the leading `---` markers).

- [ ] **Step 2: Add the new field.**

Find a line like:

```yaml
staleness_days: 14  # suggest housekeeping after this many days without audit
```

Add immediately after:

```yaml
commit_staleness_days: 2  # nudge to commit thalamus if uncommitted changes are older than this
```

### Task F5: Smoke-test the cadence nudge

This requires a real workspace with an active thalami hoard. If the test workspace doesn't have one, skip the live test and just verify the skill text is well-formed.

- [ ] **Step 1: If the user has a thalami hoard, check the timestamp manually.**

```bash
# Get the last commit timestamp for the per-machine thalamus file
hoard_path="$(ls -d D:/Dev/GitWS/yggdrasil/hoards/thalami-*/ 2>/dev/null | head -1)"
if [[ -n "$hoard_path" ]]; then
    machine_thalamus="$(ls "$hoard_path"*-thalamus.md 2>/dev/null | head -1)"
    if [[ -n "$machine_thalamus" ]]; then
        last_commit_ts="$(git -C "$hoard_path" log -1 --format=%ct -- "$(basename "$machine_thalamus")" 2>/dev/null)"
        now_ts="$(date +%s)"
        elapsed=$((now_ts - last_commit_ts))
        days=$((elapsed / 86400))
        hours=$(( (elapsed % 86400) / 3600 ))
        echo "Last commit: $days days, $hours hours ago"
    fi
fi
```

This reproduces the orientation skill's elapsed-time calculation. Verify the output is sensible (not negative, not absurdly large).

### Task F6: Commit Phase F

- [ ] **Step 1: Write the bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-orientation.md`:

```markdown
---
message: "feat(orientation): commit-cadence nudge + permissions-management pointer"
add:
  - .agent/skills/gdd-orientation/SKILL.md
  - templates/thalamus.md
---

Two additions to gdd-orientation:

- **Skills-available pointer** (one paragraph) listing
  `permissions-management` and `fewer-permission-prompts` as
  on-demand skills the agent should remember exist for the session.
  Doesn't preload either; just primes awareness.

- **Step 0a: Thalamus commit-cadence nudge.** After resolving the
  active thalami hoard, if the per-machine thalamus file is dirty AND
  its last commit is older than `commit_staleness_days` frontmatter
  threshold (default 2): surface a one-line nudge with the actual
  elapsed time ("2 days, 4 hours ago") and the threshold value, and
  offer to commit on the spot or defer. Below threshold or clean:
  silent.

Companion change: `templates/thalamus.md` frontmatter gets a new
`commit_staleness_days: 2` example field with an inline comment.
Existing thalami without the field get the default-2-days behavior.

The cadence-detection mechanism uses `ws status` (extended in this
PR to walk `hoards/`) for dirty-state detection plus
`git log -1 --format=%ct` for the timestamp, then computes
elapsed-seconds against threshold-seconds. Honest about elapsed time
— not rounded to "calendar days," which would false-positive across
midnight.

See `docs/plans/2026-04-27-permissions-and-hygiene-design.md` § 7.
```

- [ ] **Step 2: Commit.**

```bash
ws commit yggdrasil .commits/hygiene-pass-orientation.md
```

- [ ] **Step 3: Verify.**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 2 files modified.

---

# Phase G — `gdd-housekeeping` update

Single skill update: add a per-item permissions-related hook to the existing housekeeping flow.

### Task G1: Read the current housekeeping skill

**Files:**
- Read-only: `D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-housekeeping/SKILL.md`

- [ ] **Step 1: Read the skill.**

```bash
cat D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-housekeeping/SKILL.md
```

Identify the per-item review section. Each housekeeping item gets reviewed; we want to add a hook.

### Task G2: Add the permissions-management hook

**Files:**
- Modify: `D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-housekeeping/SKILL.md`

- [ ] **Step 1: Find the per-item review section.**

It's likely a section like "## Per-item review" or similar. The pattern: for each Thalamus observation/concern, decide what to do (keep, archive, file as issue, etc.).

- [ ] **Step 2: Add a single bullet within that flow.**

Insert content like:

```markdown
- **If the item mentions permissions, `.claude/settings.json`, a
  permission prompt the user wants to follow up on, or "don't ask
  again" decisions:** prompt the user to walk through it via
  `permissions-management`. Example:

  > "This observation mentions a permission prompt for `xxd` you got
  > last session. Want me to invoke `permissions-management` to think
  > through whether it's worth allowlisting?"

  This routes permissions-related work through the dedicated skill
  rather than handling it ad hoc during housekeeping.
```

- [ ] **Step 3: Verify the skill still parses (no broken markdown).**

```bash
head -50 D:/Dev/GitWS/yggdrasil/.agent/skills/gdd-housekeeping/SKILL.md | grep -c '^#'
```

Expected: a reasonable count of headers.

### Task G3: Commit Phase G

- [ ] **Step 1: Write the bodyfile.**

Create `D:/Dev/GitWS/yggdrasil/.commits/hygiene-pass-housekeeping.md`:

```markdown
---
message: "feat(housekeeping): hook permissions-management for permission-related items"
add:
  - .agent/skills/gdd-housekeeping/SKILL.md
---

Adds a single bullet to the per-item review flow: when a Thalamus
observation/concern mentions permissions, `.claude/settings.json`,
a permission prompt the user wants to follow up on, or
"don't ask again" decisions, prompt the user to walk it through via
`permissions-management`.

Routes permissions-related housekeeping work through the dedicated
skill rather than handling it ad hoc. Doesn't change the rest of the
housekeeping flow.

See `docs/plans/2026-04-27-permissions-and-hygiene-design.md` § 8.
```

- [ ] **Step 2: Commit.**

```bash
ws commit yggdrasil .commits/hygiene-pass-housekeeping.md
```

- [ ] **Step 3: Verify.**

```bash
git -C D:/Dev/GitWS/yggdrasil log --stat -1
```

Expected: 1 file modified.

---

# Phase H — Final verification + push

### Task H1: Final verification — syntax + smoke

- [ ] **Step 1: Syntax-check all touched scripts.**

```bash
cd D:/Dev/GitWS/yggdrasil
for f in scripts/ws scripts/ws-realm.sh scripts/ws-hoard.sh scripts/ws-component.sh scripts/ws-commit.sh scripts/ws-status.sh; do
    bash -n "$f" && echo "$f ok" || echo "$f FAILED"
done
```

Expected: six "ok" lines, no FAILED.

- [ ] **Step 2: Smoke-test `ws status` shows realms + hoards.**

```bash
ws status 2>&1 | head -50
```

Expected: shows `=== components ===`, `=== realms ===` (if any cloned), `=== hoards ===` (if any cloned) sections.

- [ ] **Step 3: Smoke-test the env-var override fix.**

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/components" "$tmpdir/templates/components/dummy"
echo "# Dummy" > "$tmpdir/templates/components/dummy/README.md"
cat > "$tmpdir/ecosystem.yaml" << 'EOF'
identity:
  human_account: testuser
EOF
COMPONENTS_DIR="$tmpdir/components" ROOT_DIR="$tmpdir" ECOSYSTEM="$tmpdir/ecosystem.yaml" TEMPLATES_DIR="$tmpdir/templates" \
    ws component init dummy testfix 2>&1 | tail -3
ls "$tmpdir/components/testfix/" 2>&1 | head -3
rm -rf "$tmpdir"
```

Expected: scaffold lands in the temp dir without leaking into the real workspace.

- [ ] **Step 4: Verify the docs and skills exist.**

```bash
ls D:/Dev/GitWS/yggdrasil/docs/gdd/permissions.md \
   D:/Dev/GitWS/yggdrasil/.agent/skills/permissions-management/SKILL.md \
   2>&1
```

Expected: both files exist.

- [ ] **Step 5: Verify the agent-security relocation.**

```bash
ls D:/Dev/GitWS/yggdrasil/docs/agent-security/ 2>&1 | head -3
ls D:/Dev/GitWS/yggdrasil/realms/realm-siliconsaga/docs/agent-security/ 2>&1 | head -10
```

Expected: yggdrasil-side directory empty or absent; realm-side has the 9 files.

- [ ] **Step 6: Confirm clean working tree (apart from gitignored bodyfiles).**

```bash
git -C D:/Dev/GitWS/yggdrasil status --short
```

Expected: nothing tracked-and-modified. Untracked `.commits/*.md` bodyfiles are fine.

### Task H2: Push the branch (gated on user authorization)

- [ ] **Step 1: Wait for user clearance.**

The user noted GitHub instability and asked us to hold pushes. Before pushing, confirm with the user that GitHub is healthy.

- [ ] **Step 2: Push the realm-side commit.**

```bash
ws push realm-siliconsaga main
```

Expected: push succeeds.

- [ ] **Step 3: Push the yggdrasil branch.**

```bash
ws push yggdrasil design/permissions-and-hygiene
```

Expected: push succeeds; output shows the branch URL on GitHub.

### Task H3: Open the CR

- [ ] **Step 1: Write the CR body.**

Create `D:/Dev/GitWS/yggdrasil/.crs/permissions-and-hygiene.md` with content summarizing:
- The 9 items
- The two-repo coordination (link to the realm-siliconsaga commit SHA)
- Test plan (every smoke test from Phase H Task H1)
- Reference to the design spec `docs/plans/2026-04-27-permissions-and-hygiene-design.md`

```markdown
> **AI-assisted change proposal.** Filed by agent driven by @Cervator via [GDD](https://github.com/SiliconSaga/yggdrasil).

## Summary

Post-#45 hygiene pass — bundles 9 items from the realms-and-hoards review cycle:

1. `set -euo pipefail` placement in the three sourceable `ws-*.sh` scripts (move below the source-vs-execute guard so sourcing doesn't leak strict mode).
2. Stale `Co-Authored-By: Claude Opus 4.6` default in `ws-commit.sh` bumped to 4.7.
3. Router env-var clobber in `scripts/ws` switched to `:=` defaults so caller env overrides survive.
4. `docs/agent-security/` relocated to `realms/realm-siliconsaga/docs/agent-security/` (companion realm commit: <REALM_SHA>).
5. New `docs/gdd/permissions.md` — reference doc for the GDD permission system, audience is security-paranoid users + automated review tools + agents reading on-demand.
6. New `.agent/skills/permissions-management/SKILL.md` — operational companion to the doc; agents invoke for per-pattern decisions and "don't ask again" judgments.
7. `gdd-orientation` adds a Thalamus commit-cadence nudge (configurable threshold; default 2 days) and a one-line pointer at the new skill.
8. `gdd-housekeeping` adds a per-item permission-related hook.
9. `ws status` walks `realms/*/.git/` and `hoards/*/.git/` in addition to `components/`.

Net diff: ~7 commits on `design/permissions-and-hygiene`, plus 1 commit on `realm-siliconsaga`'s `main` for the relocation.

## Commits

(Add the 7 commit SHAs and one-line summaries here once committed.)

## Test plan

- [x] `bash -n` clean on `scripts/ws`, `scripts/ws-realm.sh`, `scripts/ws-hoard.sh`, `scripts/ws-component.sh`, `scripts/ws-commit.sh`, `scripts/ws-status.sh`.
- [x] Sourcing `ws-realm.sh` / `ws-hoard.sh` / `ws-component.sh` does not leak strict mode into the parent shell.
- [x] Env-var override smoke test: `COMPONENTS_DIR=/tmp/test ws component init dummy ...` lands in the temp dir without leaking into the real workspace.
- [x] `ws status` shows new `=== realms ===` and `=== hoards ===` sections (suppressed when no cloned realms / hoards).
- [x] `docs/gdd/permissions.md` exists with all 7 sections, including the empirical findings table.
- [x] `.agent/skills/permissions-management/SKILL.md` exists with all 6 sections.
- [x] `gdd-orientation` skill mentions the new commit-cadence nudge; `templates/thalamus.md` has the new `commit_staleness_days` field.
- [x] `gdd-housekeeping` mentions the new permissions-management hook.
- [x] `docs/agent-security/` no longer present in yggdrasil; `realms/realm-siliconsaga/docs/agent-security/` has all 9 files.
- [ ] CodeRabbit review.

## Notes for reviewers

- Two-repo move: the `docs/agent-security/` content was relocated to `realm-siliconsaga` (commit <REALM_SHA>) BEFORE the yggdrasil-side delete, so the content was never untracked anywhere live (git history preserves it on yggdrasil's side regardless).
- Loading discipline: `permissions-management` is on-demand only. `gdd-orientation` adds a one-line pointer so the agent knows it exists; baseline context is unchanged.
- Cross-framework porting (Codex / Gemini / Cursor permission semantics) is explicitly Future Direction in the new doc and the new skill — not in v1.

## Related

- Predecessors: PRs #43, #44, #45 (realms-and-hoards arc); issue #46 (automated regression testing for allowlist patterns — future).
- Design: `docs/plans/2026-04-27-permissions-and-hygiene-design.md`.
- Plan: `docs/plans/2026-04-27-permissions-and-hygiene-plan.md`.
```

Replace `<REALM_SHA>` with the commit SHA from Task C2 Step 5.

- [ ] **Step 2: Open the PR.**

```bash
ws cr yggdrasil "Permissions doc + workspace tooling hygiene pass" .crs/permissions-and-hygiene.md
```

Expected: PR URL printed; capture for the user.

### Task H4: Triage initial review

- [ ] **Step 1: Wait for CodeRabbit / Copilot review to land.**

- [ ] **Step 2: Use `gdd-review-triage` skill** to fetch and consolidate findings.

- [ ] **Step 3: Address findings, push fix commits, repeat until clean.**

This task is open-ended; cap at 3 review rounds before pausing to consult the user about whether to keep iterating or merge.
