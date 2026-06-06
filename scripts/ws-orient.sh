#!/usr/bin/env bash
# ws-orient.sh — deterministic "what can I do here?" menu.
#
# `ws orient` is the L1 layer of the progressive-disclosure buffet
# documented in `docs/plans/2026-06-02-gdd-orientation-and-attribution-design.md`:
#
#   L0  slim AGENTS.md + reflex contract       — always-loaded reminder
#   L1  ws orient                              — this command
#   L2  ws <cmd> --help                        — per-subcommand depth
#
# The goal is one deterministic place an agent (or a human) can run
# to see: the workspace toolset + the active realm + per-component
# adapter wiring (with the resolved command surfaced) + the skill
# index. Phase 1 Task 4 of the gdd-orientation-capability-index arc.
#
# This file is the Task 4a scaffold: header only. Sub-steps 4b-4e
# layer additional sections on top (subcommand survey, active realm,
# adapters, skill index) — see the plan for the per-step interface
# contracts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Honor a pre-set ROOT_DIR (matches scripts/ws + ws-commit.sh) so the
# bats smoke suite can point ws-orient at an isolated $WORK without
# the script clobbering the test's exported override.
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

orient_help() {
    cat <<'HELP'
Usage: ws orient

Deterministic "what can I do here?" menu — workspace toolset, active
realm, per-component adapters (with resolved commands), and the
skill index. Run after compaction, on a fresh dispatch, or when
switching tasks. Pairs with the per-command `ws orient` footer
nudge that fires after every subcommand.

Read-only. No flags yet — Phase 1 Task 4 sub-steps fill in
sections incrementally.
HELP
    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
    orient_help
fi

# Explicit yq presence check matching ws-list / ws-test / ws-lint —
# under `set -euo pipefail` a missing yq would otherwise surface as
# a cryptic 127 from inside `_emit_one_adapter` rather than as a
# helpful diagnostic at startup. Deliberately AFTER the --help
# short-circuit so a fresh-machine user can still discover `ws orient`
# before installing every prerequisite (Copilot finding on PR #89).
if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    echo "  Install: see docs/dev-setup.md or 'ws preflight' for the platform-specific hint." >&2
    exit 1
fi

# Subcommand survey — authored per the plan (Task 4b). The "use when"
# phrasing is judgment that lives here, in one place, not scattered
# across each subcommand script. Format is `name|use-when` so the
# table stays trivially editable; a future `--json` or `--names-only`
# flag can re-emit the same rows in a different shape.
emit_subcommand_survey() {
    printf '\n%s\n' "Subcommands (name — use when …):"
    while IFS='|' read -r name use_when; do
        # Skip blank lines + comment rows so the heredoc can carry
        # section dividers without polluting output.
        [[ -z "$name" || "$name" == \#* ]] && continue
        printf '  %-18s — %s\n' "$name" "$use_when"
    done <<'SURVEY'
list|surveying what's declared in the ecosystem (clones, tiers, repos)
orient|starting a session, recovering from compaction, or switching tasks
status|checking git state across every cloned component at a glance
clone|materializing a component locally (clone-fork for cross-org forks)
pull|refreshing every cloned component from its remote
commit|finalizing a change — required to attach Co-Authored-By + bodyfile
test|running the component's test suite via its adapter
lint|running the component's linter via its adapter
push|sending a topic branch to your fork remote
cr|opening a code-review request (PR / MR) from the current branch
review|triaging review comments + resolving threads on an open CR
issue|filing a tracker issue with a bodyfile + labels
log|checking what commits are on the current branch versus main
clean|sweeping draft files from .commits/ .crs/ .issues/ .outputs/ .tmp/
exec|running a one-off command inside a component dir
actions|inspecting which adapter commands a component has wired
realm|adopting or switching the active community config
hoard|managing personal cross-workspace artifacts (thalami, vaults)
component|scaffolding a new component from a template flavor
preflight|verifying workspace prerequisites (bash, git, yq, jq, gh/glab)
diagnose|investigating push/cr failures — remote + token coverage
audit-permissions|reviewing your Bash allowlist for over-broad patterns
gitlab-auth|configuring glab + git credentials from .env tokens
resolve|generating ArgoCD Application manifests from declared components
SURVEY
}

# Resolve the active realm once for the whole orient run, classifying
# the result so each emit_* function consumes a stable state rather
# than re-invoking ws_detect_realm (which exits 1 on multi-realm —
# without this catch, the rest of orient never renders).
#
# Status values: ok | none | ambiguous | error
#   ok        — exactly one realm-* directory or selector picked one
#   none      — no realms present (and no selector pointing at one)
#   ambiguous — multiple realm-* dirs and no selector to disambiguate
#   error     — any OTHER detection failure (YAML parse, file I/O, …)
#
# `ambiguous` and `error` are split deliberately: ws_detect_realm
# exits 1 on both multi-realm AND on a malformed ecosystem.local.yaml.
# Conflating them would point the user at the wrong fix path
# (Copilot finding on PR #89). The split keys off the canonical
# "Multiple non-template realms" stderr message from
# ws_detect_realm; anything else is classified as a generic error
# and the actual stderr first line surfaces to the user.
_ORIENT_REALM=""
_ORIENT_REALM_STATUS="none"
_ORIENT_REALM_ERROR=""
_resolve_orient_realm() {
    local rc=0 stderr_file
    stderr_file="$(mktemp 2>/dev/null || echo "/tmp/orient.stderr.$$")"
    _ORIENT_REALM="$(ws_detect_realm 2>"$stderr_file")" || rc=$?
    local first_err=""
    if [[ -f "$stderr_file" ]]; then
        first_err="$(head -n1 "$stderr_file" 2>/dev/null || true)"
        rm -f "$stderr_file"
    fi
    if [[ $rc -ne 0 ]]; then
        _ORIENT_REALM=""
        if [[ "$first_err" == *"Multiple non-template realms"* ]]; then
            _ORIENT_REALM_STATUS="ambiguous"
        else
            _ORIENT_REALM_STATUS="error"
            _ORIENT_REALM_ERROR="$first_err"
        fi
        return
    fi
    if [[ -n "$_ORIENT_REALM" ]]; then
        _ORIENT_REALM_STATUS="ok"
    else
        _ORIENT_REALM_STATUS="none"
    fi
}

# Per-component adapter enumeration with the resolved command
# surfaced. The "runs:" form is the adapter-trust mitigation from
# the design (§ Adapter trust): when `ws test` runs, the actual
# command the wrapper dispatches must be auditable from `ws orient`
# output. Otherwise the wrapper hides the executable-config surface.
#
# Discovery: iterate $COMPONENTS_DIR/*/ that look cloned (any .git
# entry — handles both real .git dirs and worktree-pointer .git
# files). For each, look up the realm-side adapter at
# realms/<active>/adapters/<comp>.yaml and surface what's wired.
emit_component_adapters() {
    printf '\nComponents (cloned) — adapter wiring:\n'

    local found=0 comp_dir comp
    if [[ -d "$COMPONENTS_DIR" ]]; then
        for comp_dir in "$COMPONENTS_DIR"/*/; do
            [[ -d "$comp_dir" ]] || continue
            [[ -e "$comp_dir/.git" ]] || continue
            comp="$(basename "$comp_dir")"
            _emit_one_adapter "$comp" "$_ORIENT_REALM"
            found=1
        done
    fi
    if [[ $found -eq 0 ]]; then
        echo "  (no components cloned)"
    fi
}

# Render one component's adapter wiring. Walks the three plan-named
# verbs explicitly (test/lint/build) so a typo in the YAML doesn't
# silently swallow a missing slot — the diagnostic message stays
# loud either way.
_emit_one_adapter() {
    local comp="$1" active_realm="$2"
    echo "  $comp"
    local adapter_file=""
    if [[ -n "$active_realm" ]]; then
        adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    fi
    if [[ -z "$adapter_file" || ! -f "$adapter_file" ]]; then
        local hint="realms/${active_realm:-<active>}/adapters/$comp.yaml"
        echo "    no test/lint adapter (wire: $hint)"
        return
    fi
    local verb cmd rc=0 any=0 parse_failed=0
    for verb in test lint build; do
        rc=0
        cmd="$(yq -r ".commands.$verb // \"\"" "$adapter_file" 2>/dev/null)" || rc=$?
        if [[ $rc -ne 0 ]]; then
            # Don't let one malformed adapter file abort the whole
            # orient run — surface a diagnostic, keep walking.
            parse_failed=1
            continue
        fi
        if [[ -n "$cmd" && "$cmd" != "null" ]]; then
            printf '    ws %s [runs: %s]\n' "$verb" "$cmd"
            any=1
        fi
    done
    if [[ $parse_failed -eq 1 ]]; then
        echo "    (adapter present but YAML parse failed — fix $adapter_file)"
    elif [[ $any -eq 0 ]]; then
        echo "    (adapter present but no commands.{test,lint,build} wired)"
    fi
}

# Skill index — workspace + active-realm scopes only. Component
# skills are surfaced indirectly via the component's adapter rows
# above (the ai_context paths); listing them here would explode the
# section into noise. Frontmatter-only parsing — the SKILL.md body
# stays unread, so the index is cheap even on a workspace with
# dozens of skills.
emit_skill_index() {
    printf '\nSkills (workspace + active realm):\n'
    local any=0
    if [[ -d "$ROOT_DIR/.agent/skills" ]]; then
        _emit_skills_in "$ROOT_DIR/.agent/skills" "workspace" && any=1
    fi
    if [[ -n "$_ORIENT_REALM" && -d "$REALMS_DIR/$_ORIENT_REALM/.agent/skills" ]]; then
        _emit_skills_in "$REALMS_DIR/$_ORIENT_REALM/.agent/skills" "realm:$_ORIENT_REALM" && any=1
    fi
    if [[ $any -eq 0 ]]; then
        echo "  (no skills found in workspace or active realm)"
    fi
}

# Render every SKILL.md under the given dir. Returns 0 if at least
# one skill rendered, 1 if the dir was empty — lets the caller
# decide whether to surface the "no skills" fallback.
_emit_skills_in() {
    local skills_dir="$1" scope="$2"
    local skill_file rendered=0
    for skill_file in "$skills_dir"/*/SKILL.md; do
        [[ -f "$skill_file" ]] || continue
        local name description
        # Parse the frontmatter only — `yq` reads the first YAML
        # document in a multi-doc stream by default, which on
        # SKILL.md files (front-matter only at the top) yields the
        # frontmatter map directly without a body read.
        # Tolerate malformed frontmatter — fall back to the dir
        # name and an empty description rather than aborting the
        # whole walk over one broken SKILL.md.
        name="$(yq -r '.name // ""' "$skill_file" 2>/dev/null)" || name=""
        description="$(yq -r '.description // ""' "$skill_file" 2>/dev/null)" || description=""
        # Fallback to the dir name if the frontmatter is missing /
        # malformed so the row still surfaces something useful.
        [[ -z "$name" || "$name" == "null" ]] && name="$(basename "$(dirname "$skill_file")")"
        [[ "$description" == "null" ]] && description=""
        if [[ -n "$description" ]]; then
            printf '  [%s] %s — %s\n' "$scope" "$name" "$description"
        else
            printf '  [%s] %s\n' "$scope" "$name"
        fi
        rendered=1
    done
    [[ $rendered -eq 1 ]]
}

# Active realm — same detection logic gdd-orientation Step 0c uses
# (ecosystem.local.yaml `realm:` selector, else a single realm-*).
# Prints a status line + pointer to the realm's AGENTS.md guide; the
# realm's skill enumeration lands separately in 4e so the index
# duties stay in one place. Consumes the cached _ORIENT_REALM state
# resolved by _resolve_orient_realm so the multi-realm exit-1 case
# is rendered as a clear status, not propagated as a script crash.
emit_active_realm() {
    printf '\n'
    case "$_ORIENT_REALM_STATUS" in
        error)
            echo "Active realm: error (detection failed)"
            if [[ -n "$_ORIENT_REALM_ERROR" ]]; then
                echo "  $_ORIENT_REALM_ERROR"
            fi
            return
            ;;
        ambiguous)
            echo "Active realm: ambiguous (multiple non-template realms found)"
            echo "  Set \`realm: <name>\` in ecosystem.local.yaml to pick one."
            return
            ;;
        none)
            echo "Active realm: none"
            echo "  Adopt one with \`ws realm <git-url>\` or scaffold the tutorial via \`ws realm init\`."
            return
            ;;
    esac
    echo "Active realm: $_ORIENT_REALM"
    local realm_agents="$REALMS_DIR/$_ORIENT_REALM/AGENTS.md"
    if [[ -f "$realm_agents" ]]; then
        echo "  Guide: $realm_agents"
    fi
}

# Header. The backticked literal is asserted by tests/ws-orient/orient.bats
# so a future rename surfaces the doc/help drift here first.
echo "Workspace toolset (\`ws orient\`)"

# Resolve realm state once so emit_active_realm + emit_component_adapters
# + emit_skill_index can all consume the same answer without re-invoking
# ws_detect_realm (which exits 1 on multi-realm and would otherwise
# kill orient mid-render).
_resolve_orient_realm

emit_subcommand_survey
emit_active_realm
emit_component_adapters
emit_skill_index
