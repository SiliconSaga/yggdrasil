# Attribution Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make placeholder substitution and the AI-attribution check run on every path that publishes agent-authored text to a tracker, and give editing a change request, an issue, or a comment a first-class `ws` verb.

**Architecture:** One new sourced module, `scripts/gdd-attribution.sh`, owns banner validation, placeholder substitution, and a publish-time guard that refuses an unsubstituted body. Existing creation scripts shed their duplicated copies and call it. Three new edit scripts and their provider functions reuse the same module plus a second extracted module, `scripts/git-cr-remote.sh`, carrying the fork/upstream remote resolution that `git-cr.sh` performs today.

**Tech Stack:** Bash 4 (`set -euo pipefail`), `yq` and `jq` for config and JSON, `gh` and `glab` behind the `gp_*` provider contract, `bats` for tests.

Design: [`2026-09-01-attribution-coverage-design.md`](2026-09-01-attribution-coverage-design.md).

## Global Constraints

- **No hard-wrapped prose** anywhere — comments, help text, docs, commit bodies. One line per paragraph and per bullet. `tests/templates/line-wrap.bats` enforces this for `templates/`, `docs/gdd/` and non-grandfathered skills.
- **Every commit goes through `ws commit yggdrasil <bodyfile>`** with a bodyfile copied from `templates/commit.md`. Never `git add` + `git commit`.
- **POSIX awk only** where awk is used (workspace convention; `scripts/ws-orient.sh` is the precedent).
- **Bash regex goes in a variable**, never inline on the right of `=~` — `local re='...'; [[ "$s" =~ $re ]]`.
- **`set -e` safety:** never write `cmd && var=x` as a bare statement; use `if cmd; then var=x; fi`. A failing `&&` list at statement level exits the script.
- The banner text for bodies is unchanged: `> **AI-assisted <kind>.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).`
- The banner text for replies and comments is new: `> _Agent-authored <label> — @<account> via [GDD](<home>)._`
- **`ws test yggdrasil`** is the verification command. This machine has fourteen pre-existing environment-shaped failures (absent `ln -s`, absent `rush`/`parallel`, a `kubectl` path containing a space); compare against a baseline run on `main`, and treat the CI Ubuntu job as authoritative.

---

### Task 1: The shared attribution module

**Files:**
- Create: `scripts/gdd-attribution.sh`
- Test: `tests/ws-cr/attribution.bats`

**Interfaces:**
- Consumes: `ws_resolve_ecosystem` from `scripts/ws-realm.sh` (must be sourced by the caller first).
- Produces: `gdd_attribution_human_account`, `gdd_attribution_gdd_home`, `gdd_attribution_check <bodyfile> [template-hint]`, `gdd_attribution_substitute <bodyfile> <human> <home>` (prints a temp path), `gdd_attribution_check_driver <resolved-bodyfile> <human>`, `gdd_attribution_assert_resolved <file>`.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-cr/attribution.bats`:

```bash
#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"

    export ROOT_DIR="$WORK"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
defaults:
  gddHome: https://example.test/gdd/
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/ws-realm.sh"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/gdd-attribution.sh"
}

write_body() {
    printf '%s\n' "$1" > "$WORK/body.md"
    printf '\nBody text.\n' >> "$WORK/body.md"
}

@test "the shipped change template banner passes the check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "the shipped issue template banner passes the check" {
    write_body '> **AI-assisted issue.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "the gdd-sandbox wording variant passes the check" {
    # The sandbox ships a template opening "— requested over chat." The old
    # exact-sentence grep rejected it, which is why the live instance carried a
    # host-side patch to templates/change.md.
    write_body '> **AI-assisted change proposal — requested over chat.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "a bold run that does not close on the first line fails the check" {
    write_body '> **AI-assisted change proposal. Filed by agent driven by @HUMAN_ACCOUNT.'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
}

@test "a first line that is not a blockquote fails the check" {
    write_body '**AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT.'
    run gdd_attribution_check "$WORK/body.md"
    [ "$status" -ne 0 ]
}

@test "a banner naming a different account fails the driver check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @someoneelse via [GDD](https://example.test/gdd/).'
    run gdd_attribution_check_driver "$WORK/body.md" testuser
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not name the driving human"* ]]
}

@test "a substituted banner passes the driver check" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    local resolved
    resolved=$(gdd_attribution_substitute "$WORK/body.md" testuser https://example.test/gdd/)
    run gdd_attribution_check_driver "$resolved" testuser
    [ "$status" -eq 0 ]
}

@test "substitution replaces both placeholders" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    local resolved
    resolved=$(gdd_attribution_substitute "$WORK/body.md" testuser https://example.test/gdd/)
    run cat "$resolved"
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" == *"https://example.test/gdd/"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "the resolved guard refuses a body still carrying @HUMAN_ACCOUNT" {
    # This is the yggdrasil#158 regression: the published body read
    # "driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" with both literal.
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](https://example.test/gdd/).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" == *"refusing to publish"* ]]
}

@test "the resolved guard refuses a body still carrying @GDD_HOME" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](@GDD_HOME).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"@GDD_HOME"* ]]
}

@test "the resolved guard names both placeholders when both leak" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"@HUMAN_ACCOUNT and @GDD_HOME"* ]]
}

@test "the resolved guard passes a fully substituted body" {
    write_body '> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](https://example.test/gdd/).'
    run gdd_attribution_assert_resolved "$WORK/body.md"
    [ "$status" -eq 0 ]
}

@test "human_account resolves from ecosystem config" {
    run gdd_attribution_human_account
    [ "$status" -eq 0 ]
    [ "$output" = "testuser" ]
}

@test "an unset human_account fails closed" {
    cat > "$ECOSYSTEM" <<'YAML'
identity: {}
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"
    run gdd_attribution_human_account
    [ "$status" -ne 0 ]
    [[ "$output" == *"identity.human_account not set"* ]]
}

@test "gddHome falls back to the GDD docs URL when unset" {
    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"
    run gdd_attribution_gdd_home
    [ "$status" -eq 0 ]
    [ "$output" = "https://siliconsaga.github.io/yggdrasil/gdd/" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/attribution.bats`

Expected: every test fails at `source .../scripts/gdd-attribution.sh` with "No such file or directory".

- [ ] **Step 3: Write the module**

Create `scripts/gdd-attribution.sh`:

```bash
#!/usr/bin/env bash
# gdd-attribution.sh — attribution banner and placeholder resolution for agent-authored text
#
# Sourced by git-cr.sh, git-issue.sh, git-cr-edit.sh, git-issue-edit.sh and ws-review.sh. Every path that publishes agent-authored text to a tracker goes through here, so the guarantees cannot diverge between the create path and the edit path — which is exactly how they diverged before: substitution and the banner check lived on creation only, and an edit through raw `gh pr edit --body-file` ran neither.
#
# Requires ws-realm.sh (for ws_resolve_ecosystem) to be sourced first.

GDD_ATTRIBUTION_HOME_DEFAULT="https://siliconsaga.github.io/yggdrasil/gdd/"

_gdd_attribution_no_account() {
    echo "ERROR: identity.human_account not set in ecosystem config." >&2
    echo "  Set it in ecosystem.local.yaml (see ecosystem.local.yaml.example)." >&2
}

# Resolve identity.human_account. Fails closed: a banner cannot be written, or meaningfully checked, without knowing who is driving.
gdd_attribution_human_account() {
    local eco="" human=""
    eco=$(ws_resolve_ecosystem 2>/dev/null) || eco=""
    if [[ -z "$eco" ]]; then
        _gdd_attribution_no_account
        return 1
    fi
    human=$(yq '.identity.human_account // ""' "$eco" 2>/dev/null) || human=""
    [[ "$human" == "null" ]] && human=""
    if [[ -z "$human" ]]; then
        _gdd_attribution_no_account
        return 1
    fi
    printf '%s\n' "$human"
}

# Resolve defaults.gddHome, falling back to the published GDD docs URL.
gdd_attribution_gdd_home() {
    local eco="" raw=""
    eco=$(ws_resolve_ecosystem 2>/dev/null) || eco=""
    if [[ -n "$eco" ]]; then
        raw=$(yq '.defaults.gddHome // ""' "$eco" 2>/dev/null) || raw=""
        if [[ -n "$raw" && "$raw" != "null" ]]; then
            printf '%s\n' "$raw"
            return 0
        fi
    fi
    printf '%s\n' "$GDD_ATTRIBUTION_HOME_DEFAULT"
}

# Validate the banner on a bodyfile's first line.
#
# The rule is a prefix match rather than the exact sentence it replaces, because the exact form rejected `> **AI-assisted change proposal — requested over chat.**` — a banner that carries the attribution perfectly well, shipped by gdd-sandbox's own template, and patched around by hand inside the live container. What the check exists to require is the attribution, not one sentence.
#
# It is nonetheless STRICTER than what it replaces, because gdd_attribution_check_driver below verifies the resolved account afterwards. The old check confirmed one sentence and never confirmed the driver reference resolved to anything.
#
# Usage: gdd_attribution_check <bodyfile> [template-hint]
gdd_attribution_check() {
    local bodyfile="$1" hint="${2:-templates/change.md}"
    local first="" re='^> \*\*AI-assisted [^*]+\*\*'
    first=$(head -n 1 "$bodyfile")
    if [[ ! "$first" =~ $re ]]; then
        echo "ERROR: body file is missing the AI attribution line." >&2
        echo "  The first line must be a blockquote whose bold run opens \"AI-assisted \" and closes on the same line, e.g." >&2
        echo "    > **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)." >&2
        echo "  Copy $hint rather than writing the line by hand — the template evolves." >&2
        return 1
    fi
}

# Verify the banner names the resolved driving human. Run on the SUBSTITUTED body, never the template.
# Usage: gdd_attribution_check_driver <resolved-bodyfile> <human-account>
gdd_attribution_check_driver() {
    local bodyfile="$1" human="$2" first=""
    first=$(head -n 1 "$bodyfile")
    if [[ "$first" != *"@${human}"* ]]; then
        echo "ERROR: the attribution line does not name the driving human." >&2
        echo "  After substitution the first line must contain '@${human}'." >&2
        echo "  Leave '@HUMAN_ACCOUNT' in the body — it is substituted for you." >&2
        return 1
    fi
}

# Substitute @HUMAN_ACCOUNT and @GDD_HOME into a temp copy and print its path. The caller owns cleanup.
# Usage: gdd_attribution_substitute <bodyfile> <human-account> <gdd-home>
gdd_attribution_substitute() {
    local bodyfile="$1" human="$2" gdd_home="$3"
    local out="" esc_human="" esc_home=""
    out=$(mktemp) || return 1
    esc_human=$(printf '%s' "$human" | sed 's/[&|\\]/\\&/g')
    esc_home=$(printf '%s' "$gdd_home" | sed 's/[&|\\]/\\&/g')
    sed -e "s|@HUMAN_ACCOUNT|@${esc_human}|g" \
        -e "s|@GDD_HOME|${esc_home}|g" \
        "$bodyfile" > "$out"
    printf '%s\n' "$out"
}

# Refuse to publish a body still carrying either placeholder.
#
# Deliberately separate from gdd_attribution_substitute rather than folded into it. Its value is catching bodies that were NEVER substituted — including ones written by tooling this workspace does not own — and a check that only runs inside the substituter cannot see those. yggdrasil#158 published "driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" with both literal; BOTH being unresolved is what proves the body never entered the substituter at all.
#
# Usage: gdd_attribution_assert_resolved <file>
gdd_attribution_assert_resolved() {
    local file="$1" human_leak="" home_leak="" found=""
    if grep -q '@HUMAN_ACCOUNT' "$file"; then human_leak=1; fi
    if grep -q '@GDD_HOME' "$file"; then home_leak=1; fi
    if [[ -n "$human_leak" && -n "$home_leak" ]]; then
        found="@HUMAN_ACCOUNT and @GDD_HOME"
    elif [[ -n "$human_leak" ]]; then
        found="@HUMAN_ACCOUNT"
    elif [[ -n "$home_leak" ]]; then
        found="@GDD_HOME"
    else
        return 0
    fi
    echo "ERROR: refusing to publish — the body still contains the unsubstituted placeholder $found." >&2
    echo "  An unsubstituted placeholder is valid Markdown, so nothing downstream would have noticed." >&2
    echo "  Publish through ws cr / ws issue (create or edit) so substitution runs." >&2
    return 1
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/attribution.bats`

Expected: 15 tests, all PASS.

- [ ] **Step 5: Commit**

Write `.commits/attribution-module.md`:

```markdown
---
message: "feat(ws): add shared attribution module for agent-authored bodies"

add:
  - scripts/gdd-attribution.sh
  - tests/ws-cr/attribution.bats
---

The banner check and placeholder substitution were duplicated between git-cr.sh and git-issue.sh and ran on the creation path only. One module so create and edit cannot diverge, which is how they diverged in the first place.

Two behaviour changes ride along. The banner check becomes a prefix match, accepting `— requested over chat.` and retiring the host-side patch the live gdd-sandbox carries against its own template. It gains a driver check the old exact-match form never had, so a banner whose `@HUMAN_ACCOUNT` failed to resolve now fails instead of passing.

`gdd_attribution_assert_resolved` is separate from the substituter on purpose: its value is catching bodies that were never substituted at all — #158 published both placeholders literal — and a check inside the substituter cannot see those.
```

Run: `bash scripts/ws commit yggdrasil .commits/attribution-module.md`

---

### Task 2: Wire the creation scripts onto the module

**Files:**
- Modify: `scripts/git-cr.sh:443-469` (the identity/attribution/substitution block)
- Modify: `scripts/git-issue.sh:54-80` (the same block)
- Test: `tests/ws-cr/attribution.bats` (extend), existing `tests/ws-cr/*.bats` must stay green

**Interfaces:**
- Consumes: everything Task 1 produced.
- Produces: no new names. `git-cr.sh` and `git-issue.sh` keep their existing CLI contracts exactly.

- [ ] **Step 1: Write the failing test**

Append to `tests/ws-cr/attribution.bats`:

```bash
@test "git-cr.sh accepts the gdd-sandbox banner variant end to end" {
    # Regression guard for the wiring, not the rule: Task 1's module accepts
    # this wording, and this asserts git-cr.sh actually calls the module rather
    # than keeping its own copy of the old exact-match grep.
    run grep -c 'AI-assisted change proposal\\\.' "$REPO_ROOT/scripts/git-cr.sh"
    [ "$output" = "0" ]
}

@test "git-issue.sh no longer carries its own attribution grep" {
    run grep -c 'AI-assisted issue\\\.' "$REPO_ROOT/scripts/git-issue.sh"
    [ "$output" = "0" ]
}

@test "git-cr.sh sources the attribution module" {
    run grep -q 'gdd-attribution.sh' "$REPO_ROOT/scripts/git-cr.sh"
    [ "$status" -eq 0 ]
}

@test "git-issue.sh sources the attribution module" {
    run grep -q 'gdd-attribution.sh' "$REPO_ROOT/scripts/git-issue.sh"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/attribution.bats`

Expected: the four new tests FAIL — the greps still find the old exact-match patterns and no module import.

- [ ] **Step 3: Rewrite the git-cr.sh block**

In `scripts/git-cr.sh`, after the `source "$SCRIPT_DIR/git-provider.sh"` line, add:

```bash
# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"
```

Then replace the whole block from `# Resolve @HUMAN_ACCOUNT, @GDD_HOME and enforce AI attribution line` through `BODYFILE="$_RESOLVED_BODY"` with:

```bash
# Attribution and placeholder resolution — see scripts/gdd-attribution.sh. The check runs on the template, the driver check on the substituted copy, and the leak guard immediately before the provider call at the bottom of this script.
_HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
_GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/change.md" || exit 1
_RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$_HUMAN_ACCOUNT" "$_GDD_HOME") || exit 1
trap 'rm -f "$_RESOLVED_BODY" 2>/dev/null' EXIT
gdd_attribution_check_driver "$_RESOLVED_BODY" "$_HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$_RESOLVED_BODY" || exit 1
BODYFILE="$_RESOLVED_BODY"
```

- [ ] **Step 4: Rewrite the git-issue.sh block**

In `scripts/git-issue.sh`, after `source "$SCRIPT_DIR/ws-realm.sh"`, add:

```bash
# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"
```

Replace the block from `# Resolve identity from merged ecosystem config` through the closing `> "$RESOLVED_BODY"` with:

```bash
# Attribution and placeholder resolution — see scripts/gdd-attribution.sh.
ECO=$(ws_resolve_ecosystem)
HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/issue.md" || exit 1
RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$HUMAN_ACCOUNT" "$GDD_HOME") || exit 1
trap 'rm -f "$RESOLVED_BODY" "$_RESOLVED_ECOSYSTEM" 2>/dev/null' EXIT
gdd_attribution_check_driver "$RESOLVED_BODY" "$HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$RESOLVED_BODY" || exit 1
```

Note: `ECO` is still read directly because `gp_detect_and_load "$REMOTE_URL" "$ECO"` further down needs it. The trap keeps `$_RESOLVED_ECOSYSTEM` in its cleanup list exactly as before — that variable belongs to `ws_resolve_ecosystem`, not to this block.

- [ ] **Step 5: Run the full change-request and issue test suites**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/`

Expected: all PASS, including the four new wiring tests and every pre-existing `remote-override.bats` test.

- [ ] **Step 6: Commit**

Write `.commits/attribution-wire-creation.md`:

```markdown
---
message: "refactor(ws): route ws cr and ws issue through the attribution module"

add:
  - scripts/git-cr.sh
  - scripts/git-issue.sh
  - tests/ws-cr/attribution.bats
---

Both scripts carried their own copy of the same twenty lines. The copies had already drifted in one respect that mattered — each hardcoded a different exact sentence — and a third copy was about to be written for the edit path.

Behaviour changes in exactly one direction: a body whose `@HUMAN_ACCOUNT` failed to substitute used to pass the exact-match check and now fails the driver check.
```

Run: `bash scripts/ws commit yggdrasil .commits/attribution-wire-creation.md`

---

### Task 3: Move and reshape the reply banner

**Files:**
- Modify: `scripts/ws-realm.sh` (delete `ws_gdd_attribution_line`, lines 680-700)
- Modify: `scripts/gdd-attribution.sh` (add it back, compact form)
- Modify: `scripts/ws-review.sh` (source the module)
- Modify: `tests/ws-review/review-remote.bats:159-170` (the banner assertion)
- Test: `tests/ws-cr/attribution.bats` (extend)

**Interfaces:**
- Consumes: `gdd_attribution_human_account`, `gdd_attribution_gdd_home` from Task 1.
- Produces: `ws_gdd_attribution_line <label>` at its new home, emitting `> _Agent-authored <label> — @<account> via [GDD](<home>)._`

- [ ] **Step 1: Write the failing test**

Append to `tests/ws-cr/attribution.bats`:

```bash
@test "the reply banner uses the compact italic form" {
    run ws_gdd_attribution_line reply
    [ "$status" -eq 0 ]
    [ "$output" = '> _Agent-authored reply — @testuser via [GDD](https://example.test/gdd/)._' ]
}

@test "the comment banner carries its own label" {
    run ws_gdd_attribution_line comment
    [ "$status" -eq 0 ]
    [[ "$output" == '> _Agent-authored comment — '* ]]
}

@test "the reply banner is shorter than the body banner" {
    # Not cosmetic: replies stack down a thread while a body is read once at the
    # top of a review. If a future edit re-lengthens it, this fails loudly.
    local reply body
    reply=$(ws_gdd_attribution_line reply)
    body='> **AI-assisted change proposal.** Filed by agent driven by @testuser via [GDD](https://example.test/gdd/).'
    [ "${#reply}" -lt "${#body}" ]
}

@test "the reply banner fails closed with no human_account" {
    cat > "$ECOSYSTEM" <<'YAML'
identity: {}
components: {}
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"
    run ws_gdd_attribution_line reply
    [ "$status" -ne 0 ]
}

@test "ws-realm.sh no longer defines the attribution line" {
    run grep -c 'ws_gdd_attribution_line()' "$REPO_ROOT/scripts/ws-realm.sh"
    [ "$output" = "0" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/attribution.bats`

Expected: the five new tests FAIL. The first three fail on the old wording (the function is still reachable, since `ws-realm.sh` is sourced in setup); the last fails because the definition is still there.

- [ ] **Step 3: Move the function**

Delete the `ws_gdd_attribution_line()` definition and its comment block from `scripts/ws-realm.sh`. Append to `scripts/gdd-attribution.sh`:

```bash
# Generate the attribution banner for agent-authored text that has no template to copy from — review replies and top-level comments.
#
# Deliberately shorter than the banner a change-request or issue body carries. A body banner is read once, at the top of a review; a reply banner repeats on every reply and a dozen of them down one thread reads as shouting. It stays a marked, translatable sentence rather than being dropped: the machine account it might otherwise lean on is legible as a robot only to a reader who parses English bot-naming conventions, which is the reader an international project most needs the banner for.
#
# Usage: ws_gdd_attribution_line <label>   (label e.g. "reply", "comment")
ws_gdd_attribution_line() {
    local label="$1" human="" gdd_home=""
    human=$(gdd_attribution_human_account) || return 1
    gdd_home=$(gdd_attribution_gdd_home)
    printf '> _Agent-authored %s — @%s via [GDD](%s)._\n' "$label" "$human" "$gdd_home"
}
```

- [ ] **Step 4: Source the module from ws-review.sh**

In `scripts/ws-review.sh`, immediately after `source "$SCRIPT_DIR/ws-realm.sh"`, add:

```bash
# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"
```

- [ ] **Step 5: Update the ws-review banner assertion**

In `tests/ws-review/review-remote.bats`, in the test named `reply preserves a message that begins with --remote`, replace the two banner assertions with:

```bash
    [[ "$(cat "$BODY_LOG")" == *$'\n\n'"--remote=spoof" ]]
    [[ "$(cat "$BODY_LOG")" == "> _Agent-authored reply"* ]]
```

- [ ] **Step 6: Run both suites**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/ tests/ws-review/`

Expected: all PASS.

- [ ] **Step 7: Commit**

Write `.commits/attribution-compact-banner.md`:

```markdown
---
message: "refactor(ws): move the reply banner into the attribution module and shorten it"

add:
  - scripts/gdd-attribution.sh
  - scripts/ws-realm.sh
  - scripts/ws-review.sh
  - tests/ws-cr/attribution.bats
  - tests/ws-review/review-remote.bats
---

`ws_gdd_attribution_line` landed in ws-realm.sh in #141 for want of a better home, with a comment naming this convergence. ws-realm.sh resolves realms and tokens; attribution is not that.

The reply form shortens to `> _Agent-authored reply — @user via [GDD](…)._` A body banner is read once at the top of a review; a reply banner repeats on every reply. Considered and rejected: suppressing it entirely for machine accounts. The account name is legible as a robot only to a reader who parses English bot-naming, which is the reader the banner most exists for.
```

Run: `bash scripts/ws commit yggdrasil .commits/attribution-compact-banner.md`

---

### Task 4: Extract the fork-remote resolution

**Files:**
- Create: `scripts/git-cr-remote.sh`
- Modify: `scripts/git-cr.sh:476-533` (replace the inline block with a call)
- Test: existing `tests/ws-cr/remote-override.bats` is the regression suite; no new tests

**Interfaces:**
- Consumes: `git_remote_host` from `scripts/git-remote.sh` (already sourced via `git-provider.sh`).
- Produces: `gdd_cr_resolve_fork_remote <cr-remote-override> <ecosystem-path>` setting globals `FORK_REMOTE`, `FORK_URL`, `FORK_HOST`, and `GDD_CR_ALL_REMOTES` (array).

This task is a pure extraction with no behaviour change. The edit scripts in Tasks 6 and 7 need exactly this resolution and must not be given a second copy of it.

- [ ] **Step 1: Capture the baseline**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/remote-override.bats`

Record the pass count. This suite is the contract; it must be identical after the extraction.

- [ ] **Step 2: Write the module**

Create `scripts/git-cr-remote.sh`:

```bash
#!/usr/bin/env bash
# git-cr-remote.sh — fork/upstream remote resolution shared by the change-request create and edit paths
#
# Extracted from git-cr.sh unchanged. The edit path needs the same answer to "which remote, which slug, which host" and must not carry a second copy: the two would drift, and the resolution is where --remote, --upstream and identity.forkRemote are reconciled.
#
# Requires git-provider.sh (for git_remote_host) to be sourced first.

# Resolve the fork/head remote for a change request.
#
# Explicit override: match it. Single remote: use it. Multiple: match identity.forkRemote. No match: fail.
#
# Sets FORK_REMOTE, FORK_URL, FORK_HOST and the GDD_CR_ALL_REMOTES array in the caller's scope.
# Usage: gdd_cr_resolve_fork_remote <cr-remote-override-or-empty> <ecosystem-path-or-empty>
gdd_cr_resolve_fork_remote() {
    local cr_remote="$1" eco="$2" _r="" _fork_remote=""
    mapfile -t GDD_CR_ALL_REMOTES < <(git remote)

    FORK_REMOTE=""
    if [[ -n "$cr_remote" ]]; then
        for _r in "${GDD_CR_ALL_REMOTES[@]}"; do
            if [[ "${_r,,}" == "${cr_remote,,}" ]]; then
                FORK_REMOTE="$_r"
                break
            fi
        done
        if [[ -z "$FORK_REMOTE" ]]; then
            echo "ERROR: No remote matching '$cr_remote' (from --remote/GIT_CR_REMOTE)." >&2
            echo "  Available remotes: ${GDD_CR_ALL_REMOTES[*]:-(none)}" >&2
            return 1
        fi
    elif [[ ${#GDD_CR_ALL_REMOTES[@]} -eq 1 ]]; then
        FORK_REMOTE="${GDD_CR_ALL_REMOTES[0]}"
    elif [[ -n "$eco" ]]; then
        _fork_remote=$(yq '.identity.forkRemote // ""' "$eco" 2>/dev/null) || _fork_remote=""
        [[ "$_fork_remote" == "null" ]] && _fork_remote=""
        if [[ -n "$_fork_remote" ]]; then
            for _r in "${GDD_CR_ALL_REMOTES[@]}"; do
                if [[ "${_r,,}" == "${_fork_remote,,}" ]]; then
                    FORK_REMOTE="$_r"
                    break
                fi
            done
        fi
    fi
    if [[ -z "$FORK_REMOTE" ]]; then
        if [[ ${#GDD_CR_ALL_REMOTES[@]} -eq 0 ]]; then
            echo "ERROR: No remotes configured." >&2
        else
            echo "ERROR: Multiple remotes found — cannot determine fork remote." >&2
            echo "  Available remotes: ${GDD_CR_ALL_REMOTES[*]}" >&2
            echo "  Set identity.forkRemote in ecosystem.local.yaml." >&2
        fi
        return 1
    fi

    # Read the remote's RAW configured URL (not `git remote get-url`, which applies url.insteadOf rewrites): every consumer here is logical — provider detection, token mapping, slug/host extraction — and should see the canonical URL the operator configured. Transport operations address the remote by NAME, so git still applies any insteadOf rewrite where it belongs.
    # Take the FIRST url entry (--get-all | head): that is the URL git fetches from on a multi-URL remote, while --get would return the LAST — letting provider detection disagree with the remote git actually talks to.
    FORK_URL=$(git config --get-all "remote.$FORK_REMOTE.url" 2>/dev/null | head -n1) || true
    if [[ -z "$FORK_URL" ]]; then
        echo "ERROR: remote '$FORK_REMOTE' has no configured URL." >&2
        return 1
    fi
    FORK_HOST=$(git_remote_host "$FORK_URL") || {
        echo "ERROR: Cannot determine host for fork remote '$FORK_REMOTE'." >&2
        return 1
    }
}
```

- [ ] **Step 3: Call it from git-cr.sh**

Add after the `git-provider.sh` source in `scripts/git-cr.sh`:

```bash
# shellcheck source=git-cr-remote.sh
source "$SCRIPT_DIR/git-cr-remote.sh"
```

Replace everything from `# Find the fork remote.` through the closing brace of the `FORK_HOST=$(git_remote_host "$FORK_URL") || { … }` block with:

```bash
gdd_cr_resolve_fork_remote "$CR_REMOTE" "$_ECO" || exit 1
mapfile -t _ALL_REMOTES < <(printf '%s\n' "${GDD_CR_ALL_REMOTES[@]}")
```

The `_ALL_REMOTES` copy keeps the `--upstream` block below working unchanged; it reads that array to find the non-fork remote.

- [ ] **Step 4: Run the regression suite**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/`

Expected: identical pass count to Step 1. A behaviour change here is a bug, not a feature.

- [ ] **Step 5: Commit**

Write `.commits/extract-cr-remote.md`:

```markdown
---
message: "refactor(ws): extract change-request remote resolution into git-cr-remote.sh"

add:
  - scripts/git-cr-remote.sh
  - scripts/git-cr.sh
---

Pure extraction, no behaviour change — `tests/ws-cr/remote-override.bats` is the contract and its pass count is unchanged. The edit path needs the same answer to "which remote, which slug, which host", and remote resolution is where --remote, --upstream and identity.forkRemote get reconciled: two copies of that would drift.
```

Run: `bash scripts/ws commit yggdrasil .commits/extract-cr-remote.md`

---

### Task 5: Provider update functions

**Files:**
- Modify: `scripts/providers/github.sh` (after `gp_create_issue`)
- Modify: `scripts/providers/gitlab.sh` (after `gp_create_issue`)
- Test: `tests/ws-cr/provider-update.bats`

**Interfaces:**
- Consumes: `ws_native_path` (github.sh already uses it), `_gl_encode` (gitlab.sh internal).
- Produces: `gp_update_pr --repo SLUG --number N --body-file PATH [--title TEXT]` and `gp_update_issue --repo SLUG --number N --body-file PATH [--title TEXT]`, in both providers.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-cr/provider-update.bats`:

```bash
#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"
    BODY="$WORK/body.md"
    printf 'Updated body text.\n' > "$BODY"

    STUB_DIR="$BATS_TEST_TMPDIR/stub"
    API_LOG="$BATS_TEST_TMPDIR/api.log"
    mkdir -p "$STUB_DIR"
    for tool in gh glab; do
        cat > "$STUB_DIR/$tool" <<'SH'
#!/usr/bin/env bash
{
  printf '%s:' "$(basename "$0")"
  printf ' %q' "$@"
  printf '\n'
} >> "$API_LOG"
exit 0
SH
        chmod +x "$STUB_DIR/$tool"
    done
    export API_LOG
    export PATH="$STUB_DIR:$PATH"

    ws_native_path() { printf '%s\n' "$1"; }
    export -f ws_native_path
}

@test "github gp_update_pr PATCHes the pulls endpoint with the body" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number 42 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"--method"*"PATCH"* ]]
    [[ "$output" == *"repos/owner/repo/pulls/42"* ]]
    [[ "$output" == *"Updated body text."* ]]
}

@test "github gp_update_pr omits title when not given" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number 42 --body-file "$BODY"
    run cat "$API_LOG"
    [[ "$output" != *"title="* ]]
}

@test "github gp_update_pr sends title when given" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number 42 --body-file "$BODY" --title "New title"
    run cat "$API_LOG"
    [[ "$output" == *"title=New title"* ]]
}

@test "github gp_update_issue PATCHes the issues endpoint" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_issue --repo owner/repo --number 7 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"repos/owner/repo/issues/7"* ]]
}

@test "gitlab gp_update_pr PUTs the merge_requests endpoint with description" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_pr --repo group/project --number 42 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"--method"*"PUT"* ]]
    [[ "$output" == *"group%2Fproject/merge_requests/42"* ]]
    [[ "$output" == *"description=Updated body text."* ]]
}

@test "gitlab gp_update_issue PUTs the issues endpoint" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/gitlab.sh"
    run gp_update_issue --repo group/project --number 7 --body-file "$BODY"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"group%2Fproject/issues/7"* ]]
}

@test "a non-numeric number is rejected before any API call" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_update_pr --repo owner/repo --number "1;rm" --body-file "$BODY"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/provider-update.bats`

Expected: all FAIL with "gp_update_pr: command not found".

- [ ] **Step 3: Add the GitHub implementations**

Append to `scripts/providers/github.sh`, after `gp_create_issue`:

```bash
# Shared argument parser for the update functions. Sets _up_repo, _up_number, _up_body_file, _up_title.
_gp_parse_update_args() {
    _up_repo=""; _up_number=""; _up_body_file=""; _up_title=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      _up_repo="$2"; shift 2 ;;
            --number)    _up_number="$2"; shift 2 ;;
            --body-file) _up_body_file="$2"; shift 2 ;;
            --title)     _up_title="$2"; shift 2 ;;
            *) echo "ERROR: update: unknown arg '$1'" >&2; return 1 ;;
        esac
    done
    # The number reaches an API path, so it is validated rather than trusted — the same discipline _gl_validate_discussion_id applies to thread ids.
    if [[ ! "$_up_number" =~ ^[0-9]+$ ]]; then
        echo "ERROR: update: number must be numeric, got '$_up_number'" >&2
        return 1
    fi
    if [[ ! -f "$_up_body_file" ]]; then
        echo "ERROR: update: body file not found: $_up_body_file" >&2
        return 1
    fi
}

# Update a pull request's body, and its title when given.
# Usage: gp_update_pr --repo SLUG --number N --body-file PATH [--title TEXT]
gp_update_pr() {
    local _up_repo _up_number _up_body_file _up_title body
    _gp_parse_update_args "$@" || return 1
    body=$(cat "$_up_body_file")
    if [[ -n "$_up_title" ]]; then
        gh api --method PATCH "repos/$_up_repo/pulls/$_up_number" \
            -f body="$body" -f title="$_up_title" >/dev/null
    else
        gh api --method PATCH "repos/$_up_repo/pulls/$_up_number" \
            -f body="$body" >/dev/null
    fi
}

# Update an issue's body, and its title when given.
# Usage: gp_update_issue --repo SLUG --number N --body-file PATH [--title TEXT]
gp_update_issue() {
    local _up_repo _up_number _up_body_file _up_title body
    _gp_parse_update_args "$@" || return 1
    body=$(cat "$_up_body_file")
    if [[ -n "$_up_title" ]]; then
        gh api --method PATCH "repos/$_up_repo/issues/$_up_number" \
            -f body="$body" -f title="$_up_title" >/dev/null
    else
        gh api --method PATCH "repos/$_up_repo/issues/$_up_number" \
            -f body="$body" >/dev/null
    fi
}
```

- [ ] **Step 4: Add the GitLab implementations**

Append to `scripts/providers/gitlab.sh`, after `gp_create_issue`. Copy `_gp_parse_update_args` verbatim from Step 3 — the two provider files are loaded exclusively of one another, so a shared helper would have to move to `git-provider.sh` and neither file currently reaches across that way.

```bash
# Shared argument parser for the update functions. Sets _up_repo, _up_number, _up_body_file, _up_title.
_gp_parse_update_args() {
    _up_repo=""; _up_number=""; _up_body_file=""; _up_title=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      _up_repo="$2"; shift 2 ;;
            --number)    _up_number="$2"; shift 2 ;;
            --body-file) _up_body_file="$2"; shift 2 ;;
            --title)     _up_title="$2"; shift 2 ;;
            *) echo "ERROR: update: unknown arg '$1'" >&2; return 1 ;;
        esac
    done
    if [[ ! "$_up_number" =~ ^[0-9]+$ ]]; then
        echo "ERROR: update: number must be numeric, got '$_up_number'" >&2
        return 1
    fi
    if [[ ! -f "$_up_body_file" ]]; then
        echo "ERROR: update: body file not found: $_up_body_file" >&2
        return 1
    fi
}

# Update a merge request's description, and its title when given.
# GitLab calls the field `description`; the gp_* contract calls it a body, matching the create side.
# Usage: gp_update_pr --repo SLUG --number N --body-file PATH [--title TEXT]
gp_update_pr() {
    local _up_repo _up_number _up_body_file _up_title body encoded
    _gp_parse_update_args "$@" || return 1
    body=$(cat "$_up_body_file")
    encoded=$(_gl_encode "$_up_repo")
    if [[ -n "$_up_title" ]]; then
        glab api --method PUT "projects/$encoded/merge_requests/$_up_number" \
            -f description="$body" -f title="$_up_title" >/dev/null
    else
        glab api --method PUT "projects/$encoded/merge_requests/$_up_number" \
            -f description="$body" >/dev/null
    fi
}

# Update an issue's description, and its title when given.
# Usage: gp_update_issue --repo SLUG --number N --body-file PATH [--title TEXT]
gp_update_issue() {
    local _up_repo _up_number _up_body_file _up_title body encoded
    _gp_parse_update_args "$@" || return 1
    body=$(cat "$_up_body_file")
    encoded=$(_gl_encode "$_up_repo")
    if [[ -n "$_up_title" ]]; then
        glab api --method PUT "projects/$encoded/issues/$_up_number" \
            -f description="$body" -f title="$_up_title" >/dev/null
    else
        glab api --method PUT "projects/$encoded/issues/$_up_number" \
            -f description="$body" >/dev/null
    fi
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/provider-update.bats`

Expected: 7 tests, all PASS.

- [ ] **Step 6: Commit**

Write `.commits/provider-update-fns.md`:

```markdown
---
message: "feat(ws): add gp_update_pr and gp_update_issue to both providers"

add:
  - scripts/providers/github.sh
  - scripts/providers/gitlab.sh
  - tests/ws-cr/provider-update.bats
---

The number reaches an API path, so it is validated numeric before any call — the discipline `_gl_validate_discussion_id` already applies to thread ids.

`_gp_parse_update_args` is duplicated across the two provider files rather than shared. They are loaded exclusively of one another and neither reaches across today; hoisting it to git-provider.sh is the alternative and is a larger change than this one earns.
```

Run: `bash scripts/ws commit yggdrasil .commits/provider-update-fns.md`

---

### Task 6: `ws cr <comp> edit`

**Files:**
- Create: `scripts/git-cr-edit.sh`
- Modify: `scripts/ws:226-320` (`ws_cr` — dispatch, `--title`, help)
- Test: `tests/ws-cr/edit.bats`

**Interfaces:**
- Consumes: `gdd_cr_resolve_fork_remote` (Task 4), the attribution module (Task 1), `gp_update_pr` (Task 5).
- Produces: `ws cr <comp> edit <cr#> [--title <t>] <bodyfile>`; script `scripts/git-cr-edit.sh [--remote R] [--upstream] [--title T] <cr#> <bodyfile>`.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-cr/edit.bats`:

```bash
#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WS_BIN="$REPO_ROOT/scripts/ws"

    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/components/app" "$WORK/realms" "$WORK/hoards" "$WORK/.crs"

    export ROOT_DIR="$WORK"
    export COMPONENTS_DIR="$WORK/components"
    export REALMS_DIR="$WORK/realms"
    export HOARDS_DIR="$WORK/hoards"
    export ECOSYSTEM="$WORK/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$WORK/ecosystem.local.yaml"

    cat > "$ECOSYSTEM" <<'YAML'
identity:
  human_account: testuser
  forkRemote: fork
defaults:
  gddHome: https://example.test/gdd/
components:
  app:
    repo: https://github.com/example/fork.git
YAML
    cp "$ECOSYSTEM" "$ECOSYSTEM_LOCAL"

    BODYFILE="$WORK/.crs/edit.md"
    cat > "$BODYFILE" <<'MD'
> **AI-assisted change proposal.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).

Revised summary.
MD

    git init -q "$WORK/components/app"
    git -C "$WORK/components/app" config user.name "Test User"
    git -C "$WORK/components/app" config user.email "test@example.local"
    echo seed > "$WORK/components/app/f.txt"
    git -C "$WORK/components/app" add f.txt
    git -C "$WORK/components/app" commit -q -m seed
    git -C "$WORK/components/app" remote add fork https://github.com/example/fork.git

    GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$GH_STUB_DIR"
    cat > "$GH_STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
esac
{
  printf 'gh:'
  printf ' %q' "$@"
  printf '\n'
} >> "$GH_LOG"
exit 0
SH
    chmod +x "$GH_STUB_DIR/gh"
    export GH_LOG
    export PATH="$GH_STUB_DIR:$PATH"
}

@test "edit substitutes placeholders before sending the body" {
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" == *"https://example.test/gdd/"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "edit targets the pulls endpoint with the given number" {
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"repos/example/fork/pulls/42"* ]]
}

@test "edit rejects a body with no attribution line" {
    printf 'No banner here.\n' > "$WORK/.crs/edit.md"
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
    [ ! -s "$GH_LOG" ]
}

@test "no placeholder reaches the provider" {
    # End-to-end counterpart to the unit tests on gdd_attribution_assert_resolved
    # in attribution.bats. The guard itself cannot be provoked through this path
    # — substitution always runs first — so what this asserts is the wiring: the
    # body that reaches the API is the substituted one, which is the property
    # #158 lacked.
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "the edit path calls the leak guard" {
    # The guard's job is bodies that never entered the substituter at all, which
    # this path cannot produce. Assert it is wired rather than leaving the only
    # coverage at unit level, where a dropped call would go unnoticed.
    run grep -q 'gdd_attribution_assert_resolved' "$REPO_ROOT/scripts/git-cr-edit.sh"
    [ "$status" -eq 0 ]
}

@test "edit rejects a non-numeric CR number" {
    run "$WS_BIN" cr app edit abc .crs/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"numeric"* ]]
    [ ! -s "$GH_LOG" ]
}

@test "edit passes a title through when given" {
    run "$WS_BIN" cr app edit 42 --title "fix: revised title" .crs/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"title=fix: revised title"* ]]
}

@test "edit sends no title when none is given" {
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    run cat "$GH_LOG"
    [[ "$output" != *"title="* ]]
}

@test "edit does not run the stale-base preflight" {
    # The stale-base check, the source-branch verification and the changelog
    # reminder are all statements about a branch being proposed. None of them
    # mean anything when only a description is changing, and running them would
    # make editing a description fail because a branch drifted.
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
    [[ "$output" != *"has moved"* ]]
    [[ "$output" != *"CHANGELOG"* ]]
}

@test "edit works from a branch named main" {
    # Creation refuses main because a CR cannot be opened from it. An edit is
    # about a CR that already exists, so the branch you happen to stand on is
    # irrelevant — refusing here would be inherited nonsense.
    git -C "$WORK/components/app" checkout -q -b main 2>/dev/null || git -C "$WORK/components/app" checkout -q main
    run "$WS_BIN" cr app edit 42 .crs/edit.md
    [ "$status" -eq 0 ]
}

@test "create still requires exactly a title and a bodyfile" {
    run "$WS_BIN" cr app "just a title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/edit.bats`

Expected: all FAIL — `ws cr app edit 42 …` currently treats `edit` as the CR title and reaches `git-cr.sh`.

- [ ] **Step 3: Write the edit script**

Create `scripts/git-cr-edit.sh`:

```bash
#!/usr/bin/env bash
# git-cr-edit.sh — update an existing change request's body, and its title when given
#
# Usage: git-cr-edit.sh [--remote REMOTE] [--upstream] [--title TITLE] CR_NUMBER BODYFILE
#
# Exists because editing a description through raw `gh pr edit --body-file` runs neither the placeholder substitution nor the attribution check, both of which lived on the creation path only. yggdrasil#158 published a body reading "driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME)" for exactly that reason, and failed silently, because an unsubstituted placeholder is valid Markdown.
#
# Deliberately does NOT run the creation preflights. The stale-base check, the source-branch verification and the changelog reminder are all statements about a branch being proposed for review; none of them are meaningful when only a description changes, and the branch-is-not-main guard would refuse an edit for standing in the wrong directory.
#
# Run from the repo the change request belongs to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"
# shellcheck source=git-cr-remote.sh
source "$SCRIPT_DIR/git-cr-remote.sh"

_ECO=""
_AUTH_ECO=""
if [[ -f "$SCRIPT_DIR/ws-realm.sh" ]]; then
  source "$SCRIPT_DIR/ws-realm.sh"
  _ECO=$(ws_resolve_ecosystem 2>/dev/null) || _ECO=""
  _AUTH_ECO=$(ws_resolve_local_ecosystem 2>/dev/null) || _AUTH_ECO=""
fi

# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"

UPSTREAM=""
CR_REMOTE="${GIT_CR_REMOTE:-}"
TITLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) UPSTREAM="1"; shift ;;
    --remote)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "ERROR: --remote requires a git remote name" >&2
        exit 1
      fi
      CR_REMOTE="$2"; shift 2 ;;
    --remote=*)
      CR_REMOTE="${1#--remote=}"
      if [[ -z "$CR_REMOTE" || "$CR_REMOTE" == -* ]]; then
        echo "ERROR: --remote requires a git remote name" >&2
        exit 1
      fi
      shift ;;
    --title)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --title requires a title" >&2
        exit 1
      fi
      TITLE="$2"; shift 2 ;;
    --title=*)
      TITLE="${1#--title=}"
      if [[ -z "$TITLE" ]]; then
        echo "ERROR: --title requires a title" >&2
        exit 1
      fi
      shift ;;
    --) shift; break ;;
    -*) echo "ERROR: unknown option '$1'" >&2; exit 1 ;;
    *) break ;;
  esac
done

CR_NUMBER="${1:-}"
BODYFILE="${2:-}"

if [[ -z "$CR_NUMBER" || -z "$BODYFILE" || $# -ne 2 ]]; then
  echo "Usage: $0 [--remote REMOTE] [--upstream] [--title TITLE] CR_NUMBER BODYFILE" >&2
  exit 1
fi

if [[ ! "$CR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: CR number must be numeric, got '$CR_NUMBER'" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

_HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
_GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/change.md" || exit 1
_RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$_HUMAN_ACCOUNT" "$_GDD_HOME") || exit 1
trap 'rm -f "$_RESOLVED_BODY" 2>/dev/null' EXIT
gdd_attribution_check_driver "$_RESOLVED_BODY" "$_HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$_RESOLVED_BODY" || exit 1

gdd_cr_resolve_fork_remote "$CR_REMOTE" "$_ECO" || exit 1

TARGET_URL="$FORK_URL"
TARGET_LABEL="$FORK_REMOTE"
if [[ -n "$UPSTREAM" ]]; then
  UPSTREAM_REMOTES=()
  for remote in "${GDD_CR_ALL_REMOTES[@]}"; do
    if [[ "$remote" != "$FORK_REMOTE" ]]; then
      UPSTREAM_REMOTES+=("$remote")
    fi
  done
  if [[ ${#UPSTREAM_REMOTES[@]} -eq 0 ]]; then
    echo "ERROR: No upstream remote found (only '$FORK_REMOTE' exists)." >&2
    exit 1
  elif [[ ${#UPSTREAM_REMOTES[@]} -gt 1 ]]; then
    _DEFAULT_UPSTREAM=""
    if [[ -n "$_ECO" ]]; then
      _DEFAULT_UPSTREAM=$(yq '.defaults.upstreamRemote // ""' "$_ECO" 2>/dev/null) || _DEFAULT_UPSTREAM=""
      [[ "$_DEFAULT_UPSTREAM" == "null" ]] && _DEFAULT_UPSTREAM=""
    fi
    if [[ -n "$_DEFAULT_UPSTREAM" ]] && printf '%s\n' "${UPSTREAM_REMOTES[@]}" | grep -qx "$_DEFAULT_UPSTREAM"; then
      UPSTREAM_REMOTES=("$_DEFAULT_UPSTREAM")
    else
      echo "ERROR: Multiple upstream remotes found: ${UPSTREAM_REMOTES[*]}" >&2
      echo "  Set defaults.upstreamRemote in your realm or ecosystem.local.yaml." >&2
      exit 1
    fi
  fi
  TARGET_LABEL="${UPSTREAM_REMOTES[0]}"
  TARGET_URL=$(git config --get-all "remote.$TARGET_LABEL.url" 2>/dev/null | head -n1) || true
  if [[ -z "$TARGET_URL" ]]; then
    echo "ERROR: remote '$TARGET_LABEL' has no configured URL." >&2
    exit 1
  fi
fi

gp_detect_and_load "$TARGET_URL" "$_ECO"
gp_set_token_for_url "$TARGET_URL" "$_AUTH_ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$TARGET_URL")

echo "Updating CR #$CR_NUMBER on $TARGET_SLUG (via remote '$TARGET_LABEL')"
if [[ -n "$TITLE" ]]; then
  echo "  Title: $TITLE"
fi
echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

if [[ -n "$TITLE" ]]; then
  gp_update_pr --repo "$TARGET_SLUG" --number "$CR_NUMBER" --body-file "$_RESOLVED_BODY" --title "$TITLE"
else
  gp_update_pr --repo "$TARGET_SLUG" --number "$CR_NUMBER" --body-file "$_RESOLVED_BODY"
fi

echo "✓ CR updated: #$CR_NUMBER on $TARGET_SLUG"
```

- [ ] **Step 4: Dispatch `edit` from `ws_cr`**

In `scripts/ws`, inside `ws_cr`, add `--title` to the flag-parsing `while` loop, next to the `--remote` cases:

```bash
            --title)
                if [[ $# -lt 2 || -z "${2:-}" ]]; then
                    echo "ERROR: --title requires a title" >&2
                    exit 1
                fi
                cr_title="$2"
                shift 2
                ;;
            --title=*)
                cr_title="${1#--title=}"
                if [[ -z "$cr_title" ]]; then
                    echo "ERROR: --title requires a title" >&2
                    exit 1
                fi
                shift
                ;;
```

Also add an explicit `--upstream` case to the same loop, so the flag never lands in `args` where the `edit` positional test would have to see past it:

```bash
            --upstream)
                cr_upstream="1"
                shift
                ;;
```

Declare `local cr_title=""` and `local cr_upstream=""` alongside `local cr_remote=""`. Then replace the arity check and the final dispatch line with:

```bash
    # `edit` as the first positional after the component selects the edit path. Unambiguous against create, which takes exactly a title and a bodyfile — matching `ws review <comp> threads <cr#>` rather than reserving a word ahead of component resolution.
    if [[ "${args[0]:-}" == "edit" ]]; then
        if [[ ${#args[@]} -ne 3 ]]; then
            echo "Usage: ws cr <component> edit <cr#> [--title <title>] <bodyfile>" >&2
            exit 1
        fi
        local cr_number="${args[1]}"
        local cr_body="${args[2]}"
        if [[ "$cr_body" != /* ]]; then
            cr_body="$ROOT_DIR/$cr_body"
        fi
        local edit_args=()
        [[ -n "$cr_remote" ]] && edit_args+=(--remote "$cr_remote")
        [[ -n "$cr_title" ]] && edit_args+=(--title "$cr_title")
        [[ -n "$cr_upstream" ]] && edit_args+=(--upstream)
        cd "$COMPONENT_DIR" && bash "$SCRIPT_DIR/git-cr-edit.sh" "${edit_args[@]}" "$cr_number" "$cr_body"
        return 0
    fi

    # Create path: --upstream was consumed above, so hand it back to git-cr.sh, which still parses it itself.
    if [[ -n "$cr_upstream" ]]; then
        args=(--upstream "${args[@]}")
    fi

    if [[ ${#args[@]} -lt 2 || ${#args[@]} -gt 4 ]]; then
        echo "Usage: ws cr <component> [--remote <remote>] [--source-branch <branch>] [--upstream] [--stale-base-ok] <title> <bodyfile>" >&2
        exit 1
    fi
```

Careful with the bodyfile-path resolution that already exists above this point: it rewrites `args[last]` to an absolute path. Move that rewrite to AFTER the `--upstream` re-prepend, or the index it computed no longer names the bodyfile. The edit branch does its own path resolution and returns before reaching it either way.

- [ ] **Step 5: Update the help text**

In `ws_cr`'s heredoc, add after the existing usage line:

```
       ws cr <component> edit <cr#> [--remote <remote>] [--upstream] [--title <title>] <bodyfile>
```

and, after the closing prose paragraph:

```
Editing an existing CR reuses creation's placeholder substitution and attribution
check — the guarantees that raw `gh pr edit --body-file` runs none of. The creation
preflights (stale base, source-branch verification, changelog reminder) are skipped:
they are statements about a branch being proposed, not about a description.
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/`

Expected: `edit.bats` 10 tests PASS; every pre-existing `ws-cr` test still passes.

- [ ] **Step 7: Commit**

Write `.commits/ws-cr-edit.md`:

```markdown
---
message: "feat(ws): add ws cr <comp> edit for updating an existing CR body"

add:
  - scripts/git-cr-edit.sh
  - scripts/ws
  - tests/ws-cr/edit.bats
---

There was no `ws` verb for editing a description, so an update went out through raw `gh pr edit --body-file` and ran neither the substitution nor the attribution check. #158 published both placeholders literal for exactly that reason.

The creation preflights are deliberately absent. Stale base, source-branch verification and the changelog reminder are statements about a branch being proposed; the branch-is-not-main guard would refuse an edit for standing in the wrong directory.
```

Run: `bash scripts/ws commit yggdrasil .commits/ws-cr-edit.md`

---

### Task 7: `ws issue <comp> edit`

**Files:**
- Create: `scripts/git-issue-edit.sh`
- Modify: `scripts/ws:597-636` (`ws_issue`)
- Test: `tests/ws-cr/issue-edit.bats`

**Interfaces:**
- Consumes: the attribution module (Task 1), `gp_update_issue` (Task 5).
- Produces: `ws issue <comp> edit <issue#> [--title <t>] <bodyfile>`; script `scripts/git-issue-edit.sh COMPONENT_DIR REMOTE ISSUE_NUMBER BODYFILE [TITLE]`.

`git-issue.sh` takes positional `COMPONENT_DIR REMOTE …` rather than running inside the component, so the edit script mirrors that shape instead of `git-cr-edit.sh`'s.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-cr/issue-edit.bats`. Reuse the `setup()` from `tests/ws-cr/edit.bats` verbatim, changing only `BODYFILE` to `$WORK/.issues/edit.md`, the `mkdir -p` to include `"$WORK/.issues"`, and the banner to the issue form:

```bash
    cat > "$BODYFILE" <<'MD'
> **AI-assisted issue.** Filed by agent driven by @HUMAN_ACCOUNT via [GDD](@GDD_HOME).

Revised problem statement.
MD
```

Then the tests:

```bash
@test "issue edit substitutes placeholders before sending" {
    run "$WS_BIN" issue app edit 7 .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"@testuser"* ]]
    [[ "$output" != *"@HUMAN_ACCOUNT"* ]]
    [[ "$output" != *"@GDD_HOME"* ]]
}

@test "issue edit targets the issues endpoint" {
    run "$WS_BIN" issue app edit 7 .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"repos/example/fork/issues/7"* ]]
}

@test "issue edit rejects a body with no attribution line" {
    printf 'No banner.\n' > "$WORK/.issues/edit.md"
    run "$WS_BIN" issue app edit 7 .issues/edit.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing the AI attribution line"* ]]
    [ ! -s "$GH_LOG" ]
}

@test "issue edit rejects a non-numeric issue number" {
    run "$WS_BIN" issue app edit abc .issues/edit.md
    [ "$status" -ne 0 ]
    [ ! -s "$GH_LOG" ]
}

@test "issue edit passes a title through" {
    run "$WS_BIN" issue app edit 7 --title "revised title" .issues/edit.md
    [ "$status" -eq 0 ]
    run cat "$GH_LOG"
    [[ "$output" == *"title=revised title"* ]]
}

@test "issue create still requires title, label and bodyfile" {
    run "$WS_BIN" issue app "a title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/issue-edit.bats`

Expected: all FAIL — `ws issue app edit 7 .issues/edit.md` is currently read as four positionals and reaches `git-issue.sh` with `edit` as the remote.

- [ ] **Step 3: Write the edit script**

Create `scripts/git-issue-edit.sh`:

```bash
#!/usr/bin/env bash
# git-issue-edit.sh — update an existing issue's body, and its title when given
#
# Usage: git-issue-edit.sh COMPONENT_DIR REMOTE ISSUE_NUMBER BODYFILE [TITLE]
#
# Same reason as git-cr-edit.sh: substitution and the attribution check lived on the creation path only, so an edit through the raw provider CLI ran neither. Mirrors git-issue.sh's positional shape (it takes COMPONENT_DIR rather than running inside the component) rather than git-cr-edit.sh's.

set -euo pipefail

COMPONENT_DIR="${1:-}"
REMOTE="${2:-}"
ISSUE_NUMBER="${3:-}"
BODYFILE="${4:-}"
TITLE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=git-provider.sh
source "$SCRIPT_DIR/git-provider.sh"
source "$SCRIPT_DIR/ws-realm.sh"
# shellcheck source=gdd-attribution.sh
source "$SCRIPT_DIR/gdd-attribution.sh"

if [[ -z "$COMPONENT_DIR" || -z "$ISSUE_NUMBER" || -z "$BODYFILE" ]]; then
  echo "Usage: $0 COMPONENT_DIR [REMOTE] ISSUE_NUMBER BODYFILE [TITLE]" >&2
  exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: issue number must be numeric, got '$ISSUE_NUMBER'" >&2
  exit 1
fi

if [[ ! -f "$BODYFILE" ]]; then
  echo "ERROR: body file not found: $BODYFILE" >&2
  exit 1
fi

ECO=$(ws_resolve_ecosystem)
AUTH_ECO=$(ws_resolve_local_ecosystem 2>/dev/null) || AUTH_ECO=""

HUMAN_ACCOUNT=$(gdd_attribution_human_account) || exit 1
GDD_HOME=$(gdd_attribution_gdd_home)
gdd_attribution_check "$BODYFILE" "templates/issue.md" || exit 1
RESOLVED_BODY=$(gdd_attribution_substitute "$BODYFILE" "$HUMAN_ACCOUNT" "$GDD_HOME") || exit 1
trap 'rm -f "$RESOLVED_BODY" 2>/dev/null' EXIT
gdd_attribution_check_driver "$RESOLVED_BODY" "$HUMAN_ACCOUNT" || exit 1
gdd_attribution_assert_resolved "$RESOLVED_BODY" || exit 1

mapfile -t _REMOTES < <(cd "$COMPONENT_DIR" && git remote)
REMOTE_NAME=""
if [[ ${#_REMOTES[@]} -eq 0 ]]; then
  echo "ERROR: No remotes configured in $COMPONENT_DIR." >&2
  exit 1
elif [[ ${#_REMOTES[@]} -eq 1 ]]; then
  REMOTE_NAME="${_REMOTES[0]}"
elif [[ -n "$REMOTE" ]]; then
  REMOTE_NAME=$(cd "$COMPONENT_DIR" && git remote | grep -i "^${REMOTE}$" | head -1 || true)
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$REMOTE' found in $COMPONENT_DIR." >&2
    echo "  Available remotes: ${_REMOTES[*]}" >&2
    exit 1
  fi
else
  echo "ERROR: Multiple remotes in $COMPONENT_DIR — specify which one." >&2
  echo "  Available remotes: ${_REMOTES[*]}" >&2
  exit 1
fi
REMOTE_URL=$(cd "$COMPONENT_DIR" && git remote get-url "$REMOTE_NAME")

gp_detect_and_load "$REMOTE_URL" "$ECO"
gp_set_token_for_url "$REMOTE_URL" "$AUTH_ECO"
gp_check_cli

TARGET_SLUG=$(gp_extract_slug "$REMOTE_URL")
if [[ -z "$TARGET_SLUG" || "$TARGET_SLUG" != */* ]]; then
  echo "ERROR: Could not resolve org/repo from remote URL: $REMOTE_URL" >&2
  exit 1
fi

echo "Updating issue #$ISSUE_NUMBER on $TARGET_SLUG (via remote '$REMOTE_NAME')"
if [[ -n "$TITLE" ]]; then
  echo "  Title: $TITLE"
fi
echo "  Body : $BODYFILE ($(wc -l < "$BODYFILE") lines)"
echo ""

if [[ -n "$TITLE" ]]; then
  gp_update_issue --repo "$TARGET_SLUG" --number "$ISSUE_NUMBER" --body-file "$RESOLVED_BODY" --title "$TITLE"
else
  gp_update_issue --repo "$TARGET_SLUG" --number "$ISSUE_NUMBER" --body-file "$RESOLVED_BODY"
fi

echo "✓ Issue updated: #$ISSUE_NUMBER on $TARGET_SLUG"
```

- [ ] **Step 4: Dispatch `edit` from `ws_issue`**

In `scripts/ws`, in `ws_issue`, immediately after `ws_resolve_target "$comp"`, insert:

```bash
    # `edit` as the first positional after the component selects the edit path, matching ws cr.
    if [[ "${1:-}" == "edit" ]]; then
        shift
        local issue_title=""
        local edit_positional=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --title)
                    if [[ $# -lt 2 || -z "${2:-}" ]]; then
                        echo "ERROR: --title requires a title" >&2
                        exit 1
                    fi
                    issue_title="$2"; shift 2 ;;
                --title=*)
                    issue_title="${1#--title=}"
                    if [[ -z "$issue_title" ]]; then
                        echo "ERROR: --title requires a title" >&2
                        exit 1
                    fi
                    shift ;;
                *) edit_positional+=("$1"); shift ;;
            esac
        done
        if [[ ${#edit_positional[@]} -ne 2 ]]; then
            echo "Usage: ws issue <component> edit <issue#> [--title <title>] <bodyfile>" >&2
            exit 1
        fi
        local issue_number="${edit_positional[0]}"
        local issue_body="${edit_positional[1]}"
        if [[ "$issue_body" != /* ]]; then
            issue_body="$ROOT_DIR/$issue_body"
        fi
        bash "$SCRIPT_DIR/git-issue-edit.sh" "$COMPONENT_DIR" "$(ws_resolve_fork_remote)" \
            "$issue_number" "$issue_body" "$issue_title"
        return 0
    fi
```

The `$# -lt 4` arity check below it stays as is; the early return means the edit form never reaches it.

- [ ] **Step 5: Update the help text**

In `ws_issue`'s heredoc, add after the usage line:

```
       ws issue <component> edit <issue#> [--title <title>] <bodyfile>
```

and after the closing sentence:

```
Editing an existing issue reuses creation's placeholder substitution and attribution
check, which raw `gh issue edit --body-file` runs none of.
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/ws-cr/`

Expected: `issue-edit.bats` 6 tests PASS; all pre-existing tests still pass.

- [ ] **Step 7: Commit**

Write `.commits/ws-issue-edit.md`:

```markdown
---
message: "feat(ws): add ws issue <comp> edit for updating an existing issue body"

add:
  - scripts/git-issue-edit.sh
  - scripts/ws
  - tests/ws-cr/issue-edit.bats
---

Mirrors `ws cr edit`. Takes git-issue.sh's positional shape rather than git-cr-edit.sh's, because the issue scripts receive COMPONENT_DIR instead of running inside the component.
```

Run: `bash scripts/ws commit yggdrasil .commits/ws-issue-edit.md`

---

### Task 8: Comment ids in `ws review` output

**Files:**
- Modify: `scripts/providers/github.sh` (`gp_review_list_comments`, `gp_review_list_notes`)
- Modify: `scripts/providers/gitlab.sh` (the same two)
- Test: `tests/ws-review/comment-ids.bats`

**Interfaces:**
- Produces: comment ids rendered in `ws review` output as `[user] (note) id:issue-<n>` and `[user] path:line id:inline-<n>` for GitHub, `id:note-<n>` for GitLab.

The `issue-` / `inline-` prefix is load-bearing: GitHub edits a top-level note and an inline review comment through different endpoints, so Task 9 reads the kind off the id rather than probing both.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-review/comment-ids.bats`:

```bash
#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    STUB_DIR="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$STUB_DIR"
    cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
# The functions under test build their output entirely inside a --jq filter, so
# a stub that only returns JSON would test nothing. Apply the filter with real
# jq, the way gh does — otherwise these tests pass against a broken filter.
endpoint=""
filter=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) filter="$2"; shift 2 ;;
    api) shift ;;
    -*) shift ;;
    *) [[ -z "$endpoint" ]] && endpoint="$1"; shift ;;
  esac
done
case "$endpoint" in
  *"/pulls/1/comments") payload='[{"id":501,"user":{"login":"rev"},"path":"a.sh","line":10,"body":"inline text"}]' ;;
  *"/issues/1/comments") payload='[{"id":601,"user":{"login":"rev"},"body":"note text"}]' ;;
  *) payload='[]' ;;
esac
if [[ -n "$filter" ]]; then
  printf '%s' "$payload" | jq -r "$filter"
else
  printf '%s\n' "$payload"
fi
SH
    chmod +x "$STUB_DIR/gh"
    export PATH="$STUB_DIR:$PATH"
}

@test "github inline comments render an inline- prefixed id" {
    run grep -q 'id:inline-' "$REPO_ROOT/scripts/providers/github.sh"
    [ "$status" -eq 0 ]
}

@test "github notes render an issue- prefixed id" {
    run grep -q 'id:issue-' "$REPO_ROOT/scripts/providers/github.sh"
    [ "$status" -eq 0 ]
}

@test "gitlab notes render a note- prefixed id" {
    run grep -q 'id:note-' "$REPO_ROOT/scripts/providers/gitlab.sh"
    [ "$status" -eq 0 ]
}

@test "github inline comment output carries the id" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_review_list_comments owner/repo 1
    [[ "$output" == *"id:inline-501"* ]]
    [[ "$output" == *"inline text"* ]]
}

@test "github note output carries the id" {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/providers/github.sh"
    run gp_review_list_notes owner/repo 1
    [[ "$output" == *"id:issue-601"* ]]
    [[ "$output" == *"note text"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-review/comment-ids.bats`

Expected: all FAIL — the `--jq` filters render no ids.

- [ ] **Step 3: Add ids to the GitHub filters**

In `scripts/providers/github.sh`, change `gp_review_list_comments`'s jq string from:

```
".[] | $filter | \"---\n[\(.user.login)] \(.path):\(.line // .original_line)\n\(.body)\n\""
```

to:

```
".[] | $filter | \"---\n[\(.user.login)] \(.path):\(.line // .original_line) id:inline-\(.id)\n\(.body)\n\""
```

and `gp_review_list_notes`'s from:

```
".[] | $filter | \"---\n[\(.user.login)] (note)\n\(.body)\n\""
```

to:

```
".[] | $filter | \"---\n[\(.user.login)] (note) id:issue-\(.id)\n\(.body)\n\""
```

- [ ] **Step 4: Add ids to the GitLab filters**

Make the equivalent change in `scripts/providers/gitlab.sh`'s `gp_review_list_comments` and `gp_review_list_notes`, using `id:note-\(.id)` for both. GitLab edits every note through one endpoint, so it needs no kind distinction — but it keeps a prefix so the argument shape is identical across providers.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/ws-review/`

Expected: `comment-ids.bats` 5 tests PASS; every pre-existing `ws-review` test still passes.

- [ ] **Step 6: Commit**

Write `.commits/review-comment-ids.md`:

```markdown
---
message: "feat(ws): surface comment ids in ws review output"

add:
  - scripts/providers/github.sh
  - scripts/providers/gitlab.sh
  - tests/ws-review/comment-ids.bats
---

`ws review` printed ids for threads but not for notes or inline comments, so a reader could see a comment and had no way to name it. That is a gap on its own — and the prerequisite for editing one.

The `inline-` / `issue-` prefix is load-bearing on GitHub, which edits a top-level note and an inline review comment through different endpoints. Reading the kind off the id beats probing both.
```

Run: `bash scripts/ws commit yggdrasil .commits/review-comment-ids.md`

---

### Task 9: `ws review <comp> edit`

**Files:**
- Modify: `scripts/providers/github.sh`, `scripts/providers/gitlab.sh` (add `gp_update_comment`)
- Modify: `scripts/ws-review.sh` (`review_edit`, help, `_PEEK_CR`, routing)
- Test: `tests/ws-review/comment-edit.bats`

**Interfaces:**
- Consumes: `ws_gdd_attribution_line` (Task 3), the id format from Task 8.
- Produces: `gp_update_comment SLUG CR_NUM COMMENT_ID MESSAGE`; `ws review <comp> edit <cr#> <comment-id> <bodyfile>`.

- [ ] **Step 1: Write the failing test**

Create `tests/ws-review/comment-edit.bats`, reusing the fixture shape of `tests/ws-review/review-remote.bats` (component `app`, a single `fork` remote on github.com, a `gh` stub logging to `$BODY_LOG`):

```bash
@test "edit rewrites an inline comment through the pulls endpoint" {
    printf 'Corrected text.\n' > "$WORK/.crs/note.md"
    run run_ws_review app edit 1 inline-501 "$WORK/.crs/note.md"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"pulls/comments/501"* ]]
    [[ "$output" == *"--method"*"PATCH"* ]]
}

@test "edit rewrites a top-level note through the issues endpoint" {
    printf 'Corrected text.\n' > "$WORK/.crs/note.md"
    run run_ws_review app edit 1 issue-601 "$WORK/.crs/note.md"
    [ "$status" -eq 0 ]
    run cat "$API_LOG"
    [[ "$output" == *"issues/comments/601"* ]]
}

@test "an edited comment carries the attribution banner" {
    printf 'Corrected text.\n' > "$WORK/.crs/note.md"
    run run_ws_review app edit 1 issue-601 "$WORK/.crs/note.md"
    run cat "$API_LOG"
    [[ "$output" == *"Agent-authored comment"* ]]
    [[ "$output" == *"@testuser"* ]]
}

@test "an unprefixed comment id is rejected" {
    printf 'Corrected text.\n' > "$WORK/.crs/note.md"
    run run_ws_review app edit 1 601 "$WORK/.crs/note.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"comment id"* ]]
}

@test "a comment id with a non-numeric tail is rejected" {
    printf 'Corrected text.\n' > "$WORK/.crs/note.md"
    run run_ws_review app edit 1 "issue-6;rm" "$WORK/.crs/note.md"
    [ "$status" -ne 0 ]
    [ ! -s "$API_LOG" ]
}

@test "a missing bodyfile is rejected before any API call" {
    run run_ws_review app edit 1 issue-601 "$WORK/.crs/absent.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"body file not found"* ]]
    [ ! -s "$API_LOG" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/ws-review/comment-edit.bats`

Expected: all FAIL — `edit` is not a routed subcommand, so `review_comments` receives it and errors on a non-numeric CR number.

- [ ] **Step 3: Add `gp_update_comment` to GitHub**

Append to `scripts/providers/github.sh`:

```bash
# Update an existing comment. The id carries its kind, because GitHub edits a top-level note and an inline review comment through different resources: `inline-<n>` is a pull-request review comment, `issue-<n>` is a PR/issue conversation comment.
# The CR number is accepted for contract symmetry with GitLab, whose notes are nested under the merge request; GitHub does not need it.
# Usage: gp_update_comment SLUG CR_NUM COMMENT_ID MESSAGE
gp_update_comment() {
    local slug="$1" cr_num="$2" comment_id="$3" message="$4"
    local kind="${comment_id%%-*}" num="${comment_id#*-}"
    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: comment id must be <kind>-<number>, got '$comment_id'" >&2
        return 1
    fi
    case "$kind" in
        inline) gh api --method PATCH "repos/$slug/pulls/comments/$num" -f body="$message" >/dev/null ;;
        issue)  gh api --method PATCH "repos/$slug/issues/comments/$num" -f body="$message" >/dev/null ;;
        *)
            echo "ERROR: unknown comment id kind '$kind' — expected inline- or issue-." >&2
            return 1
            ;;
    esac
}
```

- [ ] **Step 4: Add `gp_update_comment` to GitLab**

Append to `scripts/providers/gitlab.sh`:

```bash
# Update an existing merge-request note. GitLab edits every note through one endpoint, so the id kind is always `note`; the prefix is kept so the argument shape matches GitHub's.
# Usage: gp_update_comment SLUG MR_NUM COMMENT_ID MESSAGE
gp_update_comment() {
    local slug="$1" mr_num="$2" comment_id="$3" message="$4"
    local kind="${comment_id%%-*}" num="${comment_id#*-}"
    if [[ "$kind" != "note" ]]; then
        echo "ERROR: unknown comment id kind '$kind' — expected note-." >&2
        return 1
    fi
    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: comment id must be note-<number>, got '$comment_id'" >&2
        return 1
    fi
    local encoded
    encoded=$(_gl_encode "$slug")
    glab api --method PUT "projects/$encoded/merge_requests/$mr_num/notes/$num" \
        -f body="$message" >/dev/null
}
```

- [ ] **Step 5: Add `review_edit` to ws-review.sh**

Insert after `review_comment()`:

```bash
# Rewrite an existing comment, reattaching the attribution banner. Bodyfile-based like review_comment: an edited comment is usually the long one that needed correcting.
#
# The banner is regenerated rather than carried over from the old body, so a comment whose banner was missing or hand-typed gains a correct one on its first edit — which is the case that motivated this verb. #141 reported that missing attribution "required hand-patching both comments afterward".
review_edit() {
    if [[ $# -ne 3 ]]; then
        echo "Usage: ws review <comp> edit <cr#> <comment-id> <bodyfile> [--remote <name>]" >&2
        exit 1
    fi

    local cr_num="$1" comment_id="$2" bodyfile="$3"

    if [[ ! "$cr_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: CR number must be numeric, got '$cr_num'" >&2
        exit 1
    fi

    if [[ ! "$comment_id" =~ ^[a-z]+-[0-9]+$ ]]; then
        echo "ERROR: comment id must be <kind>-<number> as printed by ws review, got '$comment_id'" >&2
        echo "  Run 'ws review <comp> $cr_num' and copy the id: field from the comment." >&2
        exit 1
    fi

    if [[ ! -f "$bodyfile" ]]; then
        echo "ERROR: body file not found: $bodyfile" >&2
        exit 1
    fi

    local banner
    banner=$(ws_gdd_attribution_line "comment") || exit 1
    local message
    message="${banner}"$'\n\n'"$(cat "$bodyfile")"

    gp_update_comment "$REPO_SLUG" "$cr_num" "$comment_id" "$message" || {
        echo "ERROR: Failed to update comment $comment_id on CR #$cr_num." >&2
        exit 1
    }
    echo "Updated comment $comment_id on CR #$cr_num ($REPO_SLUG)."
}
```

- [ ] **Step 6: Route it**

In the `_PEEK_CR` chain, add:

```bash
elif [[ "${1:-}" == "edit" && "${2:-}" =~ ^[0-9]+$ ]]; then
    _PEEK_CR="$2"
```

In the routing block at the bottom, add before the `else`:

```bash
elif [[ "${1:-}" == "edit" ]]; then
    shift
    review_edit "$@"
```

In `review_help`, add the usage line and a description entry:

```bash
    echo "       ws review <comp> edit <cr#> <comment-id> <bodyfile> [--remote <name>]"
```

```bash
    echo "  edit <cr#> <comment-id> <bodyfile>"
    echo "                             Rewrite an existing comment. The comment-id is the"
    echo "                             id: field printed beside each comment. The GDD"
    echo "                             attribution banner is reattached, so a comment that"
    echo "                             was missing one gains it on first edit."
    echo ""
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/ws-review/`

Expected: `comment-edit.bats` 6 tests PASS; every pre-existing `ws-review` test still passes.

- [ ] **Step 8: Commit**

Write `.commits/ws-review-edit.md`:

```markdown
---
message: "feat(ws): add ws review <comp> edit for rewriting an existing comment"

add:
  - scripts/providers/github.sh
  - scripts/providers/gitlab.sh
  - scripts/ws-review.sh
  - tests/ws-review/comment-edit.bats
---

#141's own body records the gap: missing attribution on two comments "required hand-patching both comments afterward" through the raw CLI.

The banner is regenerated on every edit rather than carried over, so a comment that was posted without one gains it on its first edit — which is the case that motivated the verb.
```

Run: `bash scripts/ws commit yggdrasil .commits/ws-review-edit.md`

---

### Task 10: Hook redirects

**Files:**
- Modify: `.claude/hooks/hook-rules` (the `[redirect-commands]` section, after the `gh-pr-comments*` rows)
- Test: `tests/hook/edit-redirect.bats`

**Interfaces:**
- Consumes: the verbs from Tasks 6, 7 and 9. This task lands only after them — a redirect pointing at a verb that does not exist is the failure the section's own header warns about.

- [ ] **Step 1: Write the failing test**

Create `tests/hook/edit-redirect.bats`, following the fixture shape of the existing hook tests (they invoke `.claude/hooks/gdd-permission-hook.sh` with a JSON payload on stdin and assert on the decision):

```bash
@test "gh pr edit --body-file redirects at ws cr edit" {
    run run_hook 'gh pr edit 42 --body-file .crs/x.md'
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"ws cr <comp> edit"* ]]
}

@test "gh pr edit --title redirects at ws cr edit" {
    run run_hook 'gh pr edit 42 --title "new"'
    [[ "$output" == *"deny"* ]]
}

@test "gh issue edit --body-file redirects at ws issue edit" {
    run run_hook 'gh issue edit 7 --body-file .issues/x.md'
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"ws issue <comp> edit"* ]]
}

@test "glab mr update --description redirects at ws cr edit" {
    run run_hook 'glab mr update 42 --description "x"'
    [[ "$output" == *"deny"* ]]
}

@test "glab issue update --description redirects at ws issue edit" {
    run run_hook 'glab issue update 7 --description "x"'
    [[ "$output" == *"deny"* ]]
}

@test "gh pr edit --add-label is NOT redirected" {
    # Denying a capability with no replacement manufactures bypass requests —
    # the failure this section's own header warns about. ws cr edit rewrites a
    # body and a title; it does not touch labels, so labels stay reachable.
    run run_hook 'gh pr edit 42 --add-label enhancement'
    [[ "$output" != *"ws cr <comp> edit"* ]]
}

@test "gh pr edit --add-reviewer is NOT redirected" {
    run run_hook 'gh pr edit 42 --add-reviewer someone'
    [[ "$output" != *"ws cr <comp> edit"* ]]
}

@test "the ws exec spellings redirect too" {
    # Whenever a wrapper exists, check both spellings reach the same verdict:
    # `ws exec <comp> git commit` once merely ASKED where the raw form denied.
    run run_hook 'ws exec app gh pr edit 42 --body-file .crs/x.md'
    [[ "$output" == *"deny"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/ws test yggdrasil -- tests/hook/edit-redirect.bats`

Expected: the five deny tests FAIL (no rule matches); the two "NOT redirected" tests pass vacuously.

- [ ] **Step 3: Add the rules**

Insert into `.claude/hooks/hook-rules`, in `[redirect-commands]` after the `gh-pr-reviews-api-raw` row:

```
# Editing a description used to lose everything ws cr guarantees: substitution and the attribution check both lived on the CREATION path, so an update through the raw CLI ran neither and failed silently — an unsubstituted @HUMAN_ACCOUNT is valid Markdown. yggdrasil#158 published exactly that. Scoped to the body- and title-writing flags: label, reviewer, milestone and assignee edits have no ws equivalent and stay reachable, because denying a capability with no replacement is the failure this section's header warns about.
gh-pr-edit-body      | gh pr edit*--body*      | Use `ws cr <comp> edit <cr#> [--title <t>] <bodyfile>` — applies the identity substitutions and the attribution check that `gh pr edit` skips. `ws hook-bypass gh-pr-edit-body` for a session-scoped bypass.
gh-pr-edit-title     | gh pr edit*--title*     | Use `ws cr <comp> edit <cr#> --title <t> <bodyfile>` — keeps title and body on one reviewed path. `ws hook-bypass gh-pr-edit-title` for a session-scoped bypass.
gh-pr-edit-body-exec | ws exec * gh pr edit*--body* | Use `ws cr <comp> edit <cr#> <bodyfile>` — wrapping it in `ws exec` skips the substitutions and the attribution check just as the raw form does. `ws hook-bypass gh-pr-edit-body-exec` for a session-scoped bypass.
gh-issue-edit-body   | gh issue edit*--body*   | Use `ws issue <comp> edit <issue#> [--title <t>] <bodyfile>` — applies the identity substitutions and the attribution check that `gh issue edit` skips. `ws hook-bypass gh-issue-edit-body` for a session-scoped bypass.
gh-issue-edit-title  | gh issue edit*--title*  | Use `ws issue <comp> edit <issue#> --title <t> <bodyfile>`. `ws hook-bypass gh-issue-edit-title` for a session-scoped bypass.
gh-issue-edit-body-exec | ws exec * gh issue edit*--body* | Use `ws issue <comp> edit <issue#> <bodyfile>` — `ws exec` is not a way to reach past the wrapper. `ws hook-bypass gh-issue-edit-body-exec` for a session-scoped bypass.
glab-mr-update       | glab mr update*--description* | Use `ws cr <comp> edit <cr#> <bodyfile>` — applies the identity substitutions and the attribution check. `ws hook-bypass glab-mr-update` for a session-scoped bypass.
glab-mr-update-title | glab mr update*--title* | Use `ws cr <comp> edit <cr#> --title <t> <bodyfile>`. `ws hook-bypass glab-mr-update-title` for a session-scoped bypass.
glab-issue-update    | glab issue update*--description* | Use `ws issue <comp> edit <issue#> <bodyfile>` — applies the identity substitutions and the attribution check. `ws hook-bypass glab-issue-update` for a session-scoped bypass.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/ws test yggdrasil -- tests/hook/`

Expected: `edit-redirect.bats` 8 tests PASS; every pre-existing hook test still passes.

- [ ] **Step 5: Commit**

Write `.commits/edit-redirect-rules.md`:

```markdown
---
message: "feat(hook): redirect raw PR/issue body edits at the new ws edit verbs"

add:
  - .claude/hooks/hook-rules
  - tests/hook/edit-redirect.bats
---

Lands only now that the verbs exist. Redirecting before there is an alternative is the failure this section's own header warns about.

Scoped to the body- and title-writing flags. Label, reviewer, milestone and assignee edits have no ws equivalent and stay reachable. Each raw form has its `ws exec` twin, since `ws exec <comp> git commit` once merely ASKED where the raw form denied — a softer path around a redirect is a hole.
```

Run: `bash scripts/ws commit yggdrasil .commits/edit-redirect-rules.md`

---

### Task 11: Documentation and changelog

**Files:**
- Modify: `docs/gdd/agent-communication.md` — only if PR #161 has merged by now; skip this file otherwise and note it in the CR body
- Modify: `docs/ws-cli-guide.md`
- Modify: `.agent/skills/gdd-review-triage/SKILL.md`
- Modify: `.agent/skills/gdd-branch-workflow/SKILL.md`
- Modify: `CHANGELOG.md`
- Test: `tests/templates/line-wrap.bats` must stay green

- [ ] **Step 1: Update the review-triage skill**

In `.agent/skills/gdd-review-triage/SKILL.md`, in the command block added by #141, add:

```
bash scripts/ws review <comp> edit <cr#> <comment-id> <bodyfile>   # rewrite a comment you already posted
```

and after the existing attribution sentence:

```
Comment ids print beside each comment as `id:<kind>-<n>` — copy one to edit that comment. Never edit a comment through raw `gh`/`glab`: the banner and the identity substitutions do not run there.
```

- [ ] **Step 2: Update the branch-workflow skill**

In `.agent/skills/gdd-branch-workflow/SKILL.md`, in the Workspace CLI Commands table, add two rows:

```
| `ws cr <comp> edit <cr#> [--title <t>] <bodyfile>` | Update an open CR's body (and title) with substitutions applied |
| `ws issue <comp> edit <issue#> [--title <t>] <bodyfile>` | Update an open issue's body (and title) |
```

Note: this skill is on the `GRANDFATHERED` hard-wrap list, so its existing wrapped prose stays wrapped. Table rows are exempt regardless.

- [ ] **Step 3: Update the CLI guide's permission-tier table**

`docs/ws-cli-guide.md` is the contributor guide and the permission-tier classification, not a per-command reference — `ws <cmd> --help` is the reference, and Tasks 6, 7 and 9 already updated those. What needs saying here is a permissions fact, at `docs/ws-cli-guide.md:184-185`.

The existing allowlist patterns are `Bash(ws cr *)` and `Bash(ws issue *)`, so **the new edit forms are already covered by them** — `ws cr app edit 42 body.md` matches `ws cr *` and publishes without a prompt, exactly as creation does. That is the intended tier and it is consistent with the create path, but it is not obvious from the pattern, so record it. Amend the two table rows:

```markdown
| `Bash(ws cr *)` | CR creation and body/title edits, including rare remote overrides | `ws cr mimir --remote siliconsaga "feat: add X" .crs/x.md` · `ws cr mimir edit 42 .crs/x.md` |
| `Bash(ws issue *)` | Issue creation and body/title edits with label and bodyfile | `ws issue mimir "fix: Y" bug .issues/y.md` · `ws issue mimir edit 7 .issues/y.md` |
```

Add one sentence below the table:

```markdown
The edit forms sit in the same tier as creation deliberately: both publish agent-authored text to a tracker, and both now run the identity substitutions and the attribution check. It is the raw provider CLI — which runs neither — that is denied, not the edit itself.
```

- [ ] **Step 4: Update agent-communication.md if #161 has merged**

Check first: `bash scripts/ws gh pr view 161 --repo SiliconSaga/yggdrasil --json state`.

If merged, the "What GDD already does, and where it stops" section claims "The disclaimer covers bodies, not replies. `ws review reply` enforces nothing today." Both halves are now false — #141 closed replies and comments, and this change closes edits. Replace that bullet with an accurate statement of the coverage that exists, and keep the honesty of the section by naming what still is not covered: issue comments outside a change request have no verb.

If #161 is still open, do not touch the file — it does not exist on main yet. Record in the CR body that the line needs updating when #161 lands, so it is not lost.

- [ ] **Step 5: Write the changelog entries**

In `CHANGELOG.md`, under `## [Unreleased]`, add an `### Added` and a `### Changed` section:

```markdown
### Added

- **`ws cr <comp> edit` and `ws issue <comp> edit`** — update an open change request's or issue's body and title through the wrapper, so the identity substitutions and the AI-attribution check run on edits the way they already ran on creation. Raw `gh pr edit --body` and its siblings now redirect here.
- **`ws review <comp> edit <cr#> <comment-id> <bodyfile>`** — rewrite a comment you already posted, reattaching the attribution banner. Comment ids now print beside each comment in `ws review` output.
- **`ws review <comp> comment`** — post a top-level comment on a change request, with the attribution banner attached; `ws review reply` gained the same banner (#141).

### Changed

- **Publishing refuses a body carrying an unsubstituted `@HUMAN_ACCOUNT` or `@GDD_HOME`.** Previously a body that never passed through substitution published as-is, because an unsubstituted placeholder is valid Markdown and nothing looked at the body afterwards.
- **The attribution-line check accepts wording variants** that still carry the attribution, instead of one exact sentence — and now verifies the driving account actually resolved, which the exact-match check never did.
- **The banner on review replies and comments is shorter** than the one on a change-request body: a body banner is read once at the top of a review, a reply banner repeats down the thread.
```

Note that the `ws review comment` entry covers #141, which merged without a changelog entry of its own.

- [ ] **Step 6: Verify the wrap guard and the full suite**

Run: `bash scripts/ws test yggdrasil`

Expected: `tests/templates/line-wrap.bats` green; the rest matching the `main` baseline plus the new tests. Compare failures against the baseline recorded at Task 4 Step 1 — this box's fourteen environment failures are expected and unrelated.

- [ ] **Step 7: Commit**

Write `.commits/attribution-docs.md`:

```markdown
---
message: "docs(ws): document the edit verbs and start the v1.2 changelog"

add:
  - CHANGELOG.md
  - docs/ws-cli-guide.md
  - .agent/skills/gdd-review-triage/SKILL.md
  - .agent/skills/gdd-branch-workflow/SKILL.md
---

The `ws review comment` entry covers #141, which merged without a changelog entry.
```

Run: `bash scripts/ws commit yggdrasil .commits/attribution-docs.md`

---

## Finalizing

- [ ] **Push:** `bash scripts/ws push yggdrasil`
- [ ] **Draft the CR body:** `cp templates/change.md .crs/attribution-coverage.md` and fill it in. Name three things the diff cannot show: that #141's `ws review comment` entry is folded into this changelog, that `docs/gdd/agent-communication.md` needs a line updated when #161 lands if it had not merged in time, and that `comms.identity` was considered and rejected with the reasoning recorded in the design doc.
- [ ] **Open the CR:** `bash scripts/ws cr yggdrasil "feat(ws): attribution coverage across outbound writing surfaces" .crs/attribution-coverage.md`
- [ ] **Budget 3–4 review rounds.** This branch carries a substantial doc surface and a security-adjacent hook change; per the branch-workflow skill, use the round-by-round fix-bodyfile commit pattern so each rebuttal is auditable.
