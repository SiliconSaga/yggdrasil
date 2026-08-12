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

# Help is informational and needs no auth — let `--help`/`-h` (at any position,
# e.g. `ws gh pr --help`) pass straight through to gh's own help, matching the
# usage text above and avoiding a pointless token-gate failure.
for _a in "$@"; do
    case "$_a" in --help|-h) exec gh "$@" ;; esac
done

# `ws gh` takes no target, so it runs at the workspace root. Most gh subcommands
# are remote API calls and do not care, but a few mutate whatever repo they are
# standing in — and from here that repo is yggdrasil itself. `ws gh pr checkout
# <n> --repo <other/repo>` reads as though --repo scopes it; it does not, and it
# has already replaced this workspace's own working tree once, silently.
#
# The PreToolUse hook denies these too, but only for Claude Code. This wrapper is
# the harness-independent half: it protects Codex, other agents, and a human
# typing the same line into their own terminal.
# Read the command group and subcommand. gh has no value-taking global flags —
# only --help and --version, both handled above — so the first two non-flag args
# are the command path. Flags after the subcommand (--repo, -R) are skipped.
_WS_GH_GROUP=""
_WS_GH_SUB=""
for _a in "$@"; do
    [[ "$_a" == -* ]] && continue
    if [[ -z "$_WS_GH_GROUP" ]]; then
        _WS_GH_GROUP="$_a"
    else
        _WS_GH_SUB="$_a"
        break
    fi
done

case "$_WS_GH_GROUP${_WS_GH_SUB:+ $_WS_GH_SUB}" in
    "pr checkout"|"co"|"co "*)
        echo "ERROR: 'gh pr checkout' rewrites the working tree of whatever repo it runs in." >&2
        echo "  'ws gh' has no target, so that repo is the workspace root — not the one --repo names." >&2
        echo "  Run it inside the intended repo instead:" >&2
        echo "    ws exec <comp> gh pr checkout <number>" >&2
        echo "  Use component 'yggdrasil' if you really did mean the workspace repo." >&2
        exit 1
        ;;
    "repo sync")
        echo "ERROR: 'gh repo sync' mutates the repo it runs in, which here is the workspace root." >&2
        echo "  Use 'ws pull <comp>', or 'ws exec <comp> gh repo sync …' to scope it." >&2
        exit 1
        ;;
    "repo clone")
        echo "ERROR: 'gh repo clone' would clone into the workspace root." >&2
        echo "  Use 'ws clone <comp>' (or 'ws clone-fork <comp>' to work on a fork) so the" >&2
        echo "  clone lands in components/ with its remotes wired." >&2
        exit 1
        ;;
esac

# gh reads GH_TOKEN, then GITHUB_TOKEN. Require one rather than letting gh prompt.
if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: no GitHub token in the environment (GH_TOKEN / GITHUB_TOKEN)." >&2
    echo "  Add 'export GH_TOKEN=<token>' to .env (see docs/git-provider-setup.md)," >&2
    echo "  then retry. 'ws diagnose <comp>' shows which token covers a remote." >&2
    exit 1
fi

exec gh "$@"
