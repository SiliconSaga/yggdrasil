#!/usr/bin/env bash
# ws-gh.sh — GitHub CLI (gh) passthrough that injects the workspace token.
# ws:use-when running a one-off gh command (PR/issue/api) in an agent session
#
# The dispatcher auto-sources .env before reaching here, so GH_TOKEN is already
# in the environment — gh reads it natively. The value of routing through `ws`:
# a raw `gh` in an agent's Bash tool runs in a fresh shell that never sourced
# the workspace .env, so it falls through to an interactive `gh auth login` and
# fails. This wrapper gives agents one auditable entry point that fails fast
# with a useful message instead. It never prints the token (cf. the
# never-print-the-auth-header lesson). Mirror of ws-glab.sh.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    cat <<'HELP'
Usage: ws gh <gh args...>

Runs the GitHub CLI (gh) with the workspace .env token (GH_TOKEN) injected,
so agent/non-interactive sessions don't fall through to `gh auth login`.
Pass any gh args through, e.g.:
  ws gh pr list --limit 5
  ws gh pr checks 123
  ws gh api /repos/{owner}/{repo}/pulls

`ws gh --help` and `ws gh <cmd> --help` pass through to gh's own help.
HELP
    exit 0
fi

# gh reads GH_TOKEN, then GITHUB_TOKEN. Require one rather than letting gh prompt.
if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: no GitHub token in the environment (GH_TOKEN / GITHUB_TOKEN)." >&2
    echo "  Add 'export GH_TOKEN=<token>' to .env (see docs/git-provider-setup.md)," >&2
    echo "  then retry. 'ws diagnose <comp>' shows which token covers a remote." >&2
    exit 1
fi

exec gh "$@"
