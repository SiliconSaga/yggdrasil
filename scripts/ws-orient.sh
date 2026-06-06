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

# Header. The backticked literal is asserted by tests/ws-orient/orient.bats
# so a future rename surfaces the doc/help drift here first.
echo "Workspace toolset (\`ws orient\`)"

emit_subcommand_survey

echo ""
echo "(Phase 1 Task 4 in progress — active realm, adapter enumeration,"
echo "and skill index land in sub-steps 4c-4e.)"
