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
injected if set, otherwise glab's own already-valid stored login for the
target host (GITLAB_HOST, default gitlab.com) — so agent/non-interactive
sessions don't fall through to `glab auth login`. Self-hosted instances
also need GITLAB_HOST in .env.
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
# Read the command group and subcommand.
#
# Options are skipped, and a value-taking one takes its value with it: without
# that, `glab -R owner/repo mr checkout` hands the scanner "owner/repo" as the
# group and "mr" as the subcommand, so the guard below never matches and the
# mutating form runs anyway. The separated spelling is the dangerous one; the
# `-R=value` form keeps the value in the same word and needs no lookahead.
# glab is the sharper case: `-R/--repo` really is a root-level option there, so
# `glab -R owner/repo mr checkout 1` is a spelling a user would reasonably type.
_WS_GLAB_GROUP=""
_WS_GLAB_SUB=""
_ws_glab_skip_value=0
for _a in "$@"; do
    if [[ "$_ws_glab_skip_value" -eq 1 ]]; then
        _ws_glab_skip_value=0
        continue
    fi
    case "$_a" in
        --repo|-R|--host|--token|--output|-o|--per-page|-P)
            _ws_glab_skip_value=1
            continue
            ;;
    esac
    [[ "$_a" == -* ]] && continue
    if [[ -z "$_WS_GLAB_GROUP" ]]; then
        _WS_GLAB_GROUP="$_a"
    else
        _WS_GLAB_SUB="$_a"
        break
    fi
done

case "$_WS_GLAB_GROUP${_WS_GLAB_SUB:+ $_WS_GLAB_SUB}" in
    "mr checkout"|"mr co")
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

# Use .env token if set, else glab's own stored login for the target host —
# the same fallback ws-gh.sh and the ws cr provider path use.
if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    _ws_glab_host="${GITLAB_HOST:-gitlab.com}"
    if ! glab auth status --hostname "$_ws_glab_host" >/dev/null 2>&1; then
        echo "ERROR: no GitLab token in the environment (GITLAB_TOKEN)," >&2
        echo "  and 'glab' has no valid stored login for $_ws_glab_host either." >&2
        echo "  Add 'export GITLAB_TOKEN=<token>' to .env (and 'export GITLAB_HOST=<host>'" >&2
        echo "  for self-hosted) — 'ws gitlab-auth' then registers it with glab and git —" >&2
        echo "  or run 'glab auth login --hostname $_ws_glab_host' interactively, then retry." >&2
        exit 1
    fi
fi

exec glab "$@"
