#!/usr/bin/env bash
# ws-gh.sh — GitHub CLI (gh) passthrough that injects the workspace token.
# ws:use-when running a one-off gh command (PR/issue/api) in an agent session
#
# The dispatcher auto-sources .env before reaching here, so GH_TOKEN is already
# in the environment — gh reads it natively. The value of routing through `ws`:
# a raw `gh` in an agent's Bash tool runs in a fresh shell that never sourced
# the workspace .env, so it falls through to an interactive `gh auth login` and
# fails. This wrapper gives agents one auditable entry point that fails fast
# with a useful message instead — or, with no token but a valid stored login,
# lets gh use that. It never prints the token (cf. the
# never-print-the-auth-header lesson). Mirror of ws-glab.sh.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    cat <<'HELP'
Usage: ws gh [<component>] <gh args...>

Runs the GitHub CLI (gh) with the workspace .env token (GH_TOKEN or
GITHUB_TOKEN) injected if set, otherwise gh's own already-valid stored login
for the target host (GH_HOST, default github.com) — so agent/non-interactive
sessions don't fall through to `gh auth login`. Pass any gh args through, e.g.:
  ws gh pr list --limit 5
  ws gh api /repos/{owner}/{repo}/pulls

With a component first, --repo is filled in from that component's remote,
so the form matches every other verb and nobody has to know the slug:
  ws gh nordri pr list --limit 5
  ws gh nordri run view 123 --log-failed
A component with both a fork remote and a source remote targets the source
(defaults.upstreamRemote, or the one that is not identity.forkRemote).
Still runs at the workspace ROOT: gh subcommands that rewrite the working
tree they stand in (pr checkout, repo sync, repo clone) are refused either way.

`ws gh --help` and `ws gh <cmd> --help` pass through to gh's own help.
HELP
    exit 0
fi

# Component-first form: `ws gh <comp> <gh args…>`. The first word is a
# workspace target when it resolves as one and is not a gh command group; the
# slug is read from the component's remotes and passed as --repo. Every other
# ws verb takes the component first, and `ws gh refrhus pr checks 3` failing
# with "unknown command refrhus" was how the gap was found.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WS_GH_COMP=""
case "${1:-}" in
    -*|pr|issue|repo|api|run|release|workflow|gist|auth|browse|codespace|label|project|search|secret|variable|cache|ruleset|org|ssh-key|gpg-key|config|extension|alias|status|completion|attestation|co|help) ;;
    *)
        # shellcheck source=ws-realm.sh
        source "$SCRIPT_DIR/ws-realm.sh"
        # Probed in a subshell first: resolution exits on an unknown name
        # rather than returning, and an unknown first word here is simply a
        # gh command group this list does not know, to be passed through.
        if (ws_resolve_target "$1" >/dev/null 2>&1); then
            ws_resolve_target "$1" >/dev/null 2>&1
            _WS_GH_COMP="$1"
            shift
        fi
        ;;
esac
if [[ -n "$_WS_GH_COMP" ]]; then
    _ws_gh_has_repo=""
    for _a in "$@"; do
        case "$_a" in --repo|--repo=*|-R) _ws_gh_has_repo=1 ;; esac
    done
    if [[ -z "$_ws_gh_has_repo" ]]; then
        # shellcheck source=git-provider.sh
        source "$SCRIPT_DIR/git-provider.sh"
        _ws_gh_eco="$(ws_resolve_ecosystem 2>/dev/null)" || _ws_gh_eco=""
        _ws_gh_fork="$(yq -r '.identity.forkRemote // ""' "$_ws_gh_eco" 2>/dev/null)"; [[ "$_ws_gh_fork" != "null" ]] || _ws_gh_fork=""
        _ws_gh_upstream="$(yq -r '.defaults.upstreamRemote // ""' "$_ws_gh_eco" 2>/dev/null)"; [[ "$_ws_gh_upstream" != "null" ]] || _ws_gh_upstream=""
        _ws_gh_pick=""
        _ws_gh_remotes=()
        while IFS= read -r _r; do
            [[ -n "$_r" ]] || continue
            _url="$(git -C "$COMPONENT_DIR" remote get-url "$_r" 2>/dev/null)" || continue
            _prov="$(gp_detect "$_url" "$_ws_gh_eco" 2>/dev/null)" || continue
            [[ "$_prov" == "github" ]] || continue
            _ws_gh_remotes+=("$_r")
        done < <(git -C "$COMPONENT_DIR" remote 2>/dev/null)
        if [[ ${#_ws_gh_remotes[@]} -eq 1 ]]; then
            _ws_gh_pick="${_ws_gh_remotes[0]}"
        elif [[ ${#_ws_gh_remotes[@]} -gt 1 ]]; then
            for _r in "${_ws_gh_remotes[@]}"; do
                [[ -n "$_ws_gh_upstream" && "$_r" == "$_ws_gh_upstream" ]] && { _ws_gh_pick="$_r"; break; }
            done
            if [[ -z "$_ws_gh_pick" ]]; then
                _ws_gh_nonfork=()
                for _r in "${_ws_gh_remotes[@]}"; do
                    [[ -n "$_ws_gh_fork" && "$_r" == "$_ws_gh_fork" ]] || _ws_gh_nonfork+=("$_r")
                done
                [[ ${#_ws_gh_nonfork[@]} -eq 1 ]] && _ws_gh_pick="${_ws_gh_nonfork[0]}"
            fi
        fi
        if [[ -z "$_ws_gh_pick" ]]; then
            echo "ERROR: cannot pick a GitHub remote for '$_WS_GH_COMP' (found: ${_ws_gh_remotes[*]:-none})." >&2
            echo "  Set defaults.upstreamRemote, or pass --repo <owner/name> explicitly." >&2
            exit 1
        fi
        gp_load github 2>/dev/null || true
        _ws_gh_slug="$(gp_extract_slug "$(git -C "$COMPONENT_DIR" remote get-url "$_ws_gh_pick")")"
        if [[ -z "$_ws_gh_slug" || "$_ws_gh_slug" != */* ]]; then
            echo "ERROR: could not read an owner/name slug from remote '$_ws_gh_pick' of '$_WS_GH_COMP'." >&2
            exit 1
        fi
        set -- "$@" --repo "$_ws_gh_slug"
    fi
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
# Read the command group and subcommand.
#
# Options are skipped, and a value-taking one takes its value with it: without
# that, `gh --repo owner/repo pr checkout` hands the scanner "owner/repo" as the
# group and "pr" as the subcommand, so the guard below never matches and the
# mutating form runs anyway. The separated spelling is the dangerous one; the
# `--repo=value` form keeps the value in the same word and needs no lookahead.
_WS_GH_GROUP=""
_WS_GH_SUB=""
_ws_gh_skip_value=0
for _a in "$@"; do
    if [[ "$_ws_gh_skip_value" -eq 1 ]]; then
        _ws_gh_skip_value=0
        continue
    fi
    case "$_a" in
        --repo|-R|--hostname|--jq|--template|--method|-X|--field|-F|--raw-field|-f|--header|-H)
            _ws_gh_skip_value=1
            continue
            ;;
    esac
    [[ "$_a" == -* ]] && continue
    if [[ -z "$_WS_GH_GROUP" ]]; then
        _WS_GH_GROUP="$_a"
    else
        _WS_GH_SUB="$_a"
        break
    fi
done

case "$_WS_GH_GROUP${_WS_GH_SUB:+ $_WS_GH_SUB}" in
    "pr checkout"|"pr co"|"co"|"co "*)
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

# Use .env token if set, else gh's own stored login (same fallback ws cr uses).
# Scoped to one host: unscoped `gh auth status` exits 1 when ANY known host has
# a stale account, so an old login on an unrelated host would block a valid one
# here. GH_HOST is what gh itself reads to pick the host.
if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
    _ws_gh_host="${GH_HOST:-github.com}"
    if ! gh auth status --hostname "$_ws_gh_host" >/dev/null 2>&1; then
        echo "ERROR: no GitHub token in the environment (GH_TOKEN / GITHUB_TOKEN)," >&2
        echo "  and 'gh' has no valid stored login for $_ws_gh_host either." >&2
        echo "  Add 'export GH_TOKEN=<token>' to .env (see docs/git-provider-setup.md)," >&2
        echo "  or run 'gh auth login' interactively, then retry." >&2
        echo "  'ws diagnose <comp>' shows which token covers a remote." >&2
        exit 1
    fi
fi

exec gh "$@"
