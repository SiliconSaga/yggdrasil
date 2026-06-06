#!/usr/bin/env bats

# Tests for `ws orient` — the deterministic discovery menu (Phase 1,
# Task 4 of the GDD orientation + capability index arc).
#
# Task 4a scope (this file initially): scaffold + dispatch + header.
# Sub-steps 4b-4e bolt on additional assertions as those sections
# land:
#   4b — subcommand survey rows
#   4c — active realm detection
#   4d — per-component adapter enumeration with resolved-command surfacing
#   4e — skill index
#
# Reuses the ws-smoke test_helper so the dispatcher and timeout
# behavior match the rest of the smoke suite — `ws orient` is a
# read-only discovery command, same shape as `ws status` / `ws list`.

load ../ws-smoke/test_helper

setup() {
    init_workspace
}

# ─── 4a — scaffold + dispatch + header ─────────────────────────────

@test "ws orient: runs and prints a titled header" {
    run_ws orient
    [ "$status" -eq 0 ]
    # Header pins the literal command name in backticks so a future
    # rename surfaces here and forces the doc/help update alongside.
    [[ "$output" == *"Workspace toolset (\`ws orient\`)"* ]]
}

@test "ws orient: dispatcher routes the subcommand (no 'unknown command' error)" {
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unknown command"* ]]
    [[ "$output" != *"unknown command"* ]]
}

@test "ws orient: completes well under the smoke timeout (read-only)" {
    run_ws orient
    # 124 = `timeout` killed the process. Catches a future regression
    # where orient grows expensive (e.g. tree-walks every component).
    [ "$status" -ne 124 ]
}

# ─── 4b — subcommand survey ─────────────────────────────────────────

@test "ws orient: prints a subcommand survey with the 'use when' phrase" {
    run_ws orient
    [ "$status" -eq 0 ]
    # The plan specifies the 'use when' framing for each row — pin
    # the literal so a future cosmetic rephrase surfaces here first.
    [[ "$output" == *"use when"* ]]
}

@test "ws orient: subcommand survey lists the headline verbs (commit, test, lint, orient)" {
    # Plan-mandated rows (Task 4b assertions). Other rows live in
    # the authored survey table and can drift; these four are
    # pinned because they're the verbs the surrounding plan tasks
    # (5/6/7/8) revolve around.
    run_ws orient
    [ "$status" -eq 0 ]
    for verb in commit test lint orient; do
        [[ "$output" == *"$verb"* ]] || { echo "missing survey row: $verb"; return 1; }
    done
}

# ─── 4c — active realm detection ────────────────────────────────────

@test "ws orient: prints 'Active realm: none' when no realm is present" {
    # init_workspace creates an empty realms/ directory, so the
    # detect helper returns empty. The empty case must still
    # produce a clear status line — silence would be ambiguous.
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm: none"* ]]
}

@test "ws orient: surfaces the active realm name when one is present" {
    # Drop a fixture realm; auto-detection picks the single
    # non-template realm-* directory under realms/.
    mkdir -p "$WORK/realms/realm-fixture"
    cat > "$WORK/realms/realm-fixture/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    cat > "$WORK/realms/realm-fixture/AGENTS.md" <<'MD'
# realm-fixture
MD
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm: realm-fixture"* ]]
    # Pointer to the realm's AGENTS.md so the agent can navigate
    # to the canonical realm guide without further discovery.
    [[ "$output" == *"AGENTS.md"* ]]
}

# ─── 4d — per-component adapters with resolved command ──────────────

# Helper: drop a fixture realm + a cloned component dir. Used by the
# adapter tests below so each test can opt into wiring an adapter
# (or not).
_seed_realm_and_component() {
    local comp="$1"
    mkdir -p "$WORK/realms/realm-fixture/adapters"
    cat > "$WORK/realms/realm-fixture/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    # .git as a real dir marks the component as cloned for orient's
    # enumeration. No actual git operations happen — orient is
    # read-only and never invokes git on the component.
    mkdir -p "$WORK/components/$comp/.git"
}

@test "ws orient: wired adapter surfaces 'ws test [runs: …]' with the resolved command" {
    _seed_realm_and_component knarrlike
    cat > "$WORK/realms/realm-fixture/adapters/knarrlike.yaml" <<'YAML'
commands:
  test: "python3 -m pytest --ignore=tests/features"
  lint: "python3 -m ruff check src/ tests/"
YAML
    run_ws orient
    [ "$status" -eq 0 ]
    # Adapter-trust mitigation per design § Adapter trust: the
    # executed command must be visible from `ws orient` output, not
    # hidden behind the ws wrapper. Pin both the `runs:` token and
    # the actual command tail so an agent can verify what fires.
    [[ "$output" == *"ws test"* ]]
    [[ "$output" == *"runs: python3 -m pytest --ignore=tests/features"* ]]
    [[ "$output" == *"ws lint"* ]]
    [[ "$output" == *"runs: python3 -m ruff check"* ]]
}

@test "ws orient: cloned component without an adapter prints the wire-it hint" {
    _seed_realm_and_component bareclone
    # No adapter file. The orient output should call this out
    # explicitly so the unwired state is discoverable, not silent.
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"bareclone"* ]]
    [[ "$output" == *"no test/lint adapter"* ]]
    [[ "$output" == *"realm-fixture/adapters/bareclone.yaml"* ]]
}

@test "ws orient: components section is present even when no clones exist" {
    # init_workspace alone — no components cloned. Section must
    # still be emitted with a clear "(no components cloned)"
    # status so agents can distinguish "section was rendered but
    # empty" from "section is missing because of a regression."
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Components"* ]]
    [[ "$output" == *"no components cloned"* ]]
}

# ─── 4e — skill index ───────────────────────────────────────────────

# Helper: drop a SKILL.md with the given name + description into the
# target dir. Mirrors the on-disk convention every workspace +
# realm skill uses (`.agent/skills/<slug>/SKILL.md` with a YAML
# frontmatter carrying `name:` and `description:`).
_seed_skill() {
    local skills_root="$1" slug="$2" description="$3"
    mkdir -p "$skills_root/$slug"
    cat > "$skills_root/$slug/SKILL.md" <<MD
---
name: $slug
description: $description
---

# $slug
MD
}

@test "ws orient: surfaces a workspace skill name and its description" {
    _seed_skill "$WORK/.agent/skills" fixture-skill "Use when running the orient skill-index test."
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"fixture-skill"* ]]
    [[ "$output" == *"orient skill-index test"* ]]
}

@test "ws orient: surfaces an active-realm skill alongside workspace skills" {
    mkdir -p "$WORK/realms/realm-fixture"
    cat > "$WORK/realms/realm-fixture/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    _seed_skill "$WORK/.agent/skills" ws-skill "Workspace-tier skill"
    _seed_skill "$WORK/realms/realm-fixture/.agent/skills" realm-skill "Realm-tier skill"
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"ws-skill"* ]]
    [[ "$output" == *"realm-skill"* ]]
}

@test "ws orient: skills section is present even when no skills exist" {
    # init_workspace alone has no .agent/skills/ dirs anywhere.
    # Section header must still render so a future regression that
    # silently drops the whole index is visible.
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills"* ]]
    [[ "$output" == *"no skills"* ]]
}

# ─── resilience: ambiguous realm + malformed YAML survive ───────────

@test "ws orient: ambiguous realm renders a clear status, not a hard exit" {
    # ws_detect_realm exits 1 when multiple non-template realm-*
    # dirs are present and no ecosystem.local.yaml `realm:` selector
    # picks one. Orient should catch that, render an "ambiguous"
    # status with the resolution hint, and continue rendering the
    # rest of the output — not die mid-section.
    mkdir -p "$WORK/realms/realm-alpha" "$WORK/realms/realm-beta"
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm: ambiguous"* ]]
    [[ "$output" == *"ecosystem.local.yaml"* ]]
    # Subsequent sections must still render — Skills header proves
    # we didn't bail at the realm step.
    [[ "$output" == *"Skills"* ]]
}

@test "ws orient: malformed adapter YAML does not abort orient" {
    _seed_realm_and_component badyaml
    # Garbage YAML — yq will fail to parse. With strict mode, an
    # unguarded yq call would propagate the failure and kill orient
    # mid-render. The component should still appear with a clear
    # diagnostic, and following sections must still render.
    cat > "$WORK/realms/realm-fixture/adapters/badyaml.yaml" <<'YAML'
commands:
  test: "missing close quote
YAML
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"badyaml"* ]]
    # Pin the diagnostic text so a regression that silently swallows
    # the parse failure (returning empty commands and rendering "no
    # commands wired") instead of surfacing the actual problem fails
    # this test. Per CodeRabbit on PR #89.
    [[ "$output" == *"adapter present but YAML parse failed"* ]]
    [[ "$output" == *"badyaml.yaml"* ]]
    [[ "$output" == *"Skills"* ]]
}

@test "ws orient --help works when yq is not on PATH" {
    # Fresh-machine contract: --help must short-circuit before the
    # yq dependency check so a newcomer can discover the command
    # before installing every prerequisite. Per Copilot finding on
    # PR #89.
    #
    # Strip yq from PATH by pointing to system bin dirs only. If
    # those happen to contain yq on this host (rare — most installs
    # land in /usr/local/bin or ~/.local/bin), skip rather than
    # produce a false positive.
    local minimal_path="/usr/bin:/bin"
    if PATH="$minimal_path" command -v yq >/dev/null 2>&1; then
        skip "yq is in /usr/bin or /bin on this host — cannot simulate missing-yq"
    fi
    run env "PATH=$minimal_path" "$TIMEOUT_BIN" 10 bash "$WS_BIN" orient --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ws orient: ecosystem.local.yaml parse failure renders 'error' (not 'ambiguous')" {
    # Per Copilot finding on PR #89: a YAML parse failure in
    # ecosystem.local.yaml shouldn't be misreported as multi-realm
    # ambiguity — that sends the user down the wrong fix path.
    # Distinguish via the stderr content from ws_detect_realm.
    cat > "$WORK/ecosystem.local.yaml" <<'YAML'
identity:
  human_account: "broken
  unterminated: scalar
realm: "missing close
YAML
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"Active realm: error"* ]]
    # No misleading multi-realm guidance — that'd be the
    # wrong-fix-path Copilot warned about.
    [[ "$output" != *"Active realm: ambiguous"* ]]
    # Subsequent sections must still render.
    [[ "$output" == *"Skills"* ]]
}

@test "ws orient: malformed skill frontmatter does not abort orient" {
    # SKILL.md with broken frontmatter — yq fails on the parse.
    # Orient should fall back to the dir name (already done) and
    # keep walking; other skills must still appear.
    mkdir -p "$WORK/.agent/skills/broken-skill"
    cat > "$WORK/.agent/skills/broken-skill/SKILL.md" <<'MD'
---
name: broken-skill
description: "unterminated quote
---

# broken-skill
MD
    _seed_skill "$WORK/.agent/skills" sibling-skill "Should still appear despite the sibling's broken frontmatter."
    run_ws orient
    [ "$status" -eq 0 ]
    # The broken skill must still render via the dir-name fallback —
    # not just "didn't abort". Per CodeRabbit on PR #89: pin the
    # fallback path explicitly so a regression that silently drops
    # broken skills (e.g. via `continue` instead of `name=basename`)
    # would fail this test.
    [[ "$output" == *"broken-skill"* ]]
    # The good skill's description must still render — proves orient
    # didn't abort mid-walk over the broken sibling.
    [[ "$output" == *"sibling-skill"* ]]
    [[ "$output" == *"Should still appear"* ]]
}
