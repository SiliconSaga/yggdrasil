#!/usr/bin/env bash
# ws-gh.sh — GitHub CLI (gh) passthrough that injects the workspace token.
# ws:use-when running a one-off gh command (PR/issue/api) in an agent session
#
# Mirror of ws-glab.sh.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    cat <<'HELP'
Usage: ws gh <gh args...>

Runs the GitHub CLI (gh) with the workspace .env token (GH_TOKEN) injected
if set, otherwise gh's own already-valid stored login — so agent/non-
interactive sessions don't fall through to `gh auth login`. Pass any gh args
through, e.g.:
  ws gh pr list --limit 5
  ws gh pr checks 123
  ws gh api /repos/{owner}/{repo}/pulls

`ws gh --help` and `ws gh <cmd> --help` pass through to gh's own help.
HELP
    exit 0
fi

# Help is informational and needs no auth — let `--help`/`-h` (at any position,
# e.g. `ws gh pr --help`) pass straight through to gh's own help, matching the
# usage text above and avoiding a pointless token-gate failure.
for _a in "$@"; do
    case "$_a" in --help|-h) exec gh "$@" ;; esac
done

# Use .env token if set, else gh's own stored login (same fallback ws cr uses).
if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "ERROR: no GitHub token in the environment (GH_TOKEN / GITHUB_TOKEN)," >&2
        echo "  and 'gh' has no valid stored login either." >&2
        echo "  Add 'export GH_TOKEN=<token>' to .env (see docs/git-provider-setup.md)," >&2
        echo "  or run 'gh auth login' interactively, then retry." >&2
        echo "  'ws diagnose <comp>' shows which token covers a remote." >&2
        exit 1
    fi
fi

exec gh "$@"
