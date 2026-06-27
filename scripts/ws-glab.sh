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

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    echo "ERROR: no GitLab token in the environment (GITLAB_TOKEN)." >&2
    echo "  Add 'export GITLAB_TOKEN=<token>' to .env (and 'export GITLAB_HOST=<host>'" >&2
    echo "  for self-hosted), then retry — or run 'ws gitlab-auth' for full setup." >&2
    exit 1
fi

exec glab "$@"
