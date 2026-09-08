#!/usr/bin/env bash
# ws-glab.sh — GitLab CLI (glab) passthrough that injects the workspace token.
# ws:use-when running a one-off glab command (MR/issue/api) in an agent session
#
# The dispatcher auto-sources .env before reaching here, so GITLAB_TOKEN (and
# GITLAB_HOST for self-hosted) are already in the environment — glab reads them
# natively. Routing through `ws` keeps a raw agent `glab` from falling through
# to an interactive `glab auth login` (a fresh Bash-tool shell never sourced the
# workspace .env). One auditable entry point, fails fast, never prints the token.
# Mirror of ws-gh.sh. For full self-hosted credential setup see `ws gitlab-auth`.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    cat <<'HELP'
Usage: ws glab <glab args...>

Runs the GitLab CLI (glab) with the workspace .env token (GITLAB_TOKEN)
injected, so agent/non-interactive sessions don't fall through to
`glab auth login`. Self-hosted instances also need GITLAB_HOST in .env.
Pass any glab args through, e.g.:
  ws glab mr list
  ws glab ci status

For full self-hosted auth + git credential setup, use `ws gitlab-auth`.
`ws glab --help` and `ws glab <cmd> --help` pass through to glab's own help.
HELP
    exit 0
fi

# Help needs no auth — let `--help`/`-h` (at any position) pass through to glab's
# own help, matching the usage text above and avoiding a token-gate failure.
for _a in "$@"; do
    case "$_a" in --help|-h) exec glab "$@" ;; esac
done

# Same root-directory hazard as ws-gh.sh — see the longer note there. `ws glab`
# has no target, so a subcommand that mutates the repo it stands in lands on the
# workspace root rather than the project --repo names.
_WS_GLAB_GROUP=""
_WS_GLAB_SUB=""
for _a in "$@"; do
    [[ "$_a" == -* ]] && continue
    if [[ -z "$_WS_GLAB_GROUP" ]]; then
        _WS_GLAB_GROUP="$_a"
    else
        _WS_GLAB_SUB="$_a"
        break
    fi
done

case "$_WS_GLAB_GROUP${_WS_GLAB_SUB:+ $_WS_GLAB_SUB}" in
    "mr checkout")
        echo "ERROR: 'glab mr checkout' rewrites the working tree of whatever repo it runs in." >&2
        echo "  'ws glab' has no target, so that repo is the workspace root." >&2
        echo "  Run it inside the intended repo instead:" >&2
        echo "    ws exec <comp> glab mr checkout <number>" >&2
        exit 1
        ;;
    "repo clone")
        echo "ERROR: 'glab repo clone' would clone into the workspace root." >&2
        echo "  Use 'ws clone <comp>' (or 'ws clone-fork <comp>') so the clone lands in" >&2
        echo "  components/ with its remotes wired." >&2
        exit 1
        ;;
esac

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    echo "ERROR: no GitLab token in the environment (GITLAB_TOKEN)." >&2
    echo "  Add 'export GITLAB_TOKEN=<token>' to .env (and 'export GITLAB_HOST=<host>'" >&2
    echo "  for self-hosted), then retry — or run 'ws gitlab-auth' for full setup." >&2
    exit 1
fi

exec glab "$@"
