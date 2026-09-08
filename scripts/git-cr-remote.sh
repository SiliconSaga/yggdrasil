#!/usr/bin/env bash
# git-cr-remote.sh — fork/upstream remote resolution shared by the change-request create and edit paths
#
# Extracted from git-cr.sh with no behaviour change. The edit path needs the same answer to "which remote, which slug, which host" and must not carry a second copy: remote resolution is where --remote, GIT_CR_REMOTE and identity.forkRemote get reconciled, and two copies of that would drift the way the attribution check already had.
#
# Requires git-provider.sh (for git_remote_host) to be sourced first.

# Resolve the fork/head remote for a change request.
#
# Explicit override: match it. Single remote: use it. Multiple: match identity.forkRemote. No match: fail.
#
# Sets FORK_REMOTE, FORK_URL, FORK_HOST and the GDD_CR_ALL_REMOTES array in the caller's scope.
# Usage: gdd_cr_resolve_fork_remote <cr-remote-override-or-empty> <ecosystem-path-or-empty>
gdd_cr_resolve_fork_remote() {
    local cr_remote="$1" eco="$2" _r="" _fork_remote=""
    mapfile -t GDD_CR_ALL_REMOTES < <(git remote)

    FORK_REMOTE=""
    if [[ -n "$cr_remote" ]]; then
        for _r in "${GDD_CR_ALL_REMOTES[@]}"; do
            if [[ "${_r,,}" == "${cr_remote,,}" ]]; then
                FORK_REMOTE="$_r"
                break
            fi
        done
        if [[ -z "$FORK_REMOTE" ]]; then
            echo "ERROR: No remote matching '$cr_remote' (from --remote/GIT_CR_REMOTE)." >&2
            echo "  Available remotes: ${GDD_CR_ALL_REMOTES[*]:-(none)}" >&2
            return 1
        fi
    elif [[ ${#GDD_CR_ALL_REMOTES[@]} -eq 1 ]]; then
        FORK_REMOTE="${GDD_CR_ALL_REMOTES[0]}"
    elif [[ -n "$eco" ]]; then
        _fork_remote=$(yq '.identity.forkRemote // ""' "$eco" 2>/dev/null) || _fork_remote=""
        [[ "$_fork_remote" == "null" ]] && _fork_remote=""
        if [[ -n "$_fork_remote" ]]; then
            for _r in "${GDD_CR_ALL_REMOTES[@]}"; do
                if [[ "${_r,,}" == "${_fork_remote,,}" ]]; then
                    FORK_REMOTE="$_r"
                    break
                fi
            done
        fi
    fi
    if [[ -z "$FORK_REMOTE" ]]; then
        if [[ ${#GDD_CR_ALL_REMOTES[@]} -eq 0 ]]; then
            echo "ERROR: No remotes configured." >&2
        else
            echo "ERROR: Multiple remotes found — cannot determine fork remote." >&2
            echo "  Available remotes: ${GDD_CR_ALL_REMOTES[*]}" >&2
            echo "  Set identity.forkRemote in ecosystem.local.yaml." >&2
        fi
        return 1
    fi

    # Read the remote's RAW configured URL (not `git remote get-url`, which applies url.insteadOf rewrites): every consumer below is logical — provider detection, token mapping, slug/host extraction — and should see the canonical URL the operator configured. Transport operations address the remote by NAME, so git still applies any insteadOf rewrite where it belongs.
    # Take the FIRST url entry (--get-all | head): that is the URL git fetches from on a multi-URL remote, while --get would return the LAST — letting provider detection disagree with the remote git actually talks to.
    FORK_URL=$(git config --get-all "remote.$FORK_REMOTE.url" 2>/dev/null | head -n1) || true
    if [[ -z "$FORK_URL" ]]; then
        echo "ERROR: remote '$FORK_REMOTE' has no configured URL." >&2
        return 1
    fi
    FORK_HOST=$(git_remote_host "$FORK_URL") || {
        echo "ERROR: Cannot determine host for fork remote '$FORK_REMOTE'." >&2
        return 1
    }
}
