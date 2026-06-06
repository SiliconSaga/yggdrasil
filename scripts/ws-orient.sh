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

# Header. The backticked literal is asserted by tests/ws-orient/orient.bats
# so a future rename surfaces the doc/help drift here first.
echo "Workspace toolset (\`ws orient\`)"
echo ""
echo "(Phase 1 Task 4 scaffold — subcommand survey, active realm,"
echo "adapter enumeration, and skill index land in sub-steps 4b-4e.)"
