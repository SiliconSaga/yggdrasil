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
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
    local active_realm
    active_realm="$(ws_detect_realm)"

    local found=0 comp_dir comp
    if [[ -d "$COMPONENTS_DIR" ]]; then
        for comp_dir in "$COMPONENTS_DIR"/*/; do
            [[ -d "$comp_dir" ]] || continue
            [[ -e "$comp_dir/.git" ]] || continue
            comp="$(basename "$comp_dir")"
            _emit_one_adapter "$comp" "$active_realm"
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
    local verb cmd any=0
    for verb in test lint build; do
        cmd="$(yq -r ".commands.$verb // \"\"" "$adapter_file" 2>/dev/null)"
        if [[ -n "$cmd" && "$cmd" != "null" ]]; then
            printf '    ws %s [runs: %s]\n' "$verb" "$cmd"
            any=1
        fi
    done
    if [[ $any -eq 0 ]]; then
        echo "    (adapter present but no commands.{test,lint,build} wired)"
    fi
}

# Active realm — same detection logic gdd-orientation Step 0c uses
# (ecosystem.local.yaml `realm:` selector, else a single realm-*).
# Prints a status line + pointer to the realm's AGENTS.md guide; the
# realm's skill enumeration lands separately in 4e so the index
# duties stay in one place.
emit_active_realm() {
    printf '\n'
    local active_realm
    active_realm="$(ws_detect_realm)"
    if [[ -z "$active_realm" ]]; then
        echo "Active realm: none"
        echo "  Adopt one with \`ws realm <git-url>\` or scaffold the tutorial via \`ws realm init\`."
        return
    fi
    echo "Active realm: $active_realm"
    local realm_agents="$REALMS_DIR/$active_realm/AGENTS.md"
    if [[ -f "$realm_agents" ]]; then
        echo "  Guide: $realm_agents"
    fi
}

# Header. The backticked literal is asserted by tests/ws-orient/orient.bats
# so a future rename surfaces the doc/help drift here first.
echo "Workspace toolset (\`ws orient\`)"

emit_subcommand_survey
emit_active_realm
emit_component_adapters

echo ""
echo "(Phase 1 Task 4 in progress — skill index lands in sub-step 4e.)"
