#!/usr/bin/env bash
# ws-pull.sh — Pull latest changes for cloned components, realms, and hoards
# ws:use-when refreshing every cloned component from its remote
#
# Usage:
#   ws-pull.sh             Pull all cloned components/realms/hoards (skips dirty repos)
#   ws-pull.sh <name>      Pull a single component, realm, or hoard

set -euo pipefail

# Help short-circuit BEFORE any dependency check — fresh machines
# without yq still need to be able to read the help text. Detect
# --help/-h ANYWHERE in args so `ws pull <name> --help` works the
# same as `ws pull --help`, matching ws push / ws actions style.
for _arg in "$@"; do
    if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
        cat <<'HELP'
Usage:
  ws pull             Pull all cloned components, realms, and hoards (skips dirty repos)
  ws pull <name>      Pull a single component, realm, or hoard

Skips repos with an unclean working tree — commit or stash first.
Walks ecosystem-declared components plus on-disk realms/ and hoards/
(parallel to `ws status`).
HELP
        exit 0
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$ROOT_DIR/components"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

if ! type -P yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

# Highlight a same-named branch on a NON-tracking remote that is ahead of what
# we just pulled.
#
# Why this exists: a fork-cloned component tracks its fork, so `ws pull` follows
# the fork and can legitimately report "Already up to date" while the canonical
# upstream has moved on. The silence is the failure — the checkout looks current
# and isn't, which is exactly the state that makes someone cut a release from
# stale source. Only `ws clone-fork` syncs a fork from its upstream.
#
# Best-effort throughout: an unreachable remote, a missing branch, or a failed
# fetch is not an error, because this is advisory on top of a pull that already
# succeeded.
report_ahead_siblings() {
    local name="$1"
    local target="$2"
    local branch="$3"
    local tracking_remote="$4"
    local remote url ahead

    while IFS= read -r remote; do
        [[ -z "$remote" || "$remote" == "$tracking_remote" ]] && continue

        url=$(git -C "$target" remote get-url "$remote" 2>/dev/null || echo "")
        [[ -n "$url" ]] || continue

        local -a GIT_AUTH_ENV=()
        local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
        git_auth_env_for_url "$url"
        # Explicit refspec: fetch only this one branch, and guarantee the
        # remote-tracking ref updates so the comparison below isn't stale.
        git_auth_run git -C "$target" fetch --quiet "$remote" \
            "+refs/heads/$branch:refs/remotes/$remote/$branch" 2>/dev/null || continue

        ahead=$(git -C "$target" rev-list --count "HEAD..refs/remotes/$remote/$branch" 2>/dev/null || echo "")
        [[ "$ahead" =~ ^[0-9]+$ ]] || continue
        [[ "$ahead" -gt 0 ]] || continue

        echo "  AHEAD: $remote/$branch is $ahead commit(s) ahead of the '$branch' this pull followed."
        echo "         '$name' tracks '$tracking_remote'. If '$remote' is canonical, reconcile before"
        echo "         trusting this checkout — for a fork-based component: ws clone-fork $name"
    done < <(git -C "$target" remote 2>/dev/null)
}

pull_repo() {
    local name="$1"
    local target="$2"

    if [[ ! -d "$target/.git" ]]; then
        echo "SKIP: $name (not cloned)"
        return 0
    fi

    local dirty
    dirty=$(git -C "$target" status --porcelain 2>/dev/null | head -1)
    if [[ -n "$dirty" ]]; then
        echo "SKIP: $name (dirty working tree — commit or stash first)"
        return 0
    fi

    local branch
    branch=$(git -C "$target" branch --show-current 2>/dev/null)
    if [[ -z "$branch" ]]; then
        echo "SKIP: $name (detached HEAD)"
        return 0
    fi

    if ! git -C "$target" rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
        echo "SKIP: $name (no upstream tracking branch)"
        return 0
    fi

    echo "PULL: $name ($branch)"
    # Inject the .env token for the tracking remote so private HTTPS pulls
    # don't fall through to the OS credential manager (mirrors ws push).
    local upstream_ref remote_name remote_url
    upstream_ref=$(git -C "$target" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    remote_name="${upstream_ref%%/*}"
    remote_url=$(git -C "$target" remote get-url "$remote_name" 2>/dev/null || echo "")
    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    [[ -n "$remote_url" ]] && git_auth_env_for_url "$remote_url"
    if ! git_auth_run git -C "$target" pull --rebase 2>&1 | sed 's/^/  /'; then
        echo "  CONFLICT: aborting rebase — resolve manually in $target"
        git -C "$target" rebase --abort 2>/dev/null
        HAD_FAILURES=1
    fi

    report_ahead_siblings "$name" "$target" "$branch" "$remote_name"
}

HAD_FAILURES=0

if [[ -n "${1:-}" ]]; then
    # Single named arg — could be component, realm, or hoard.
    # ws_resolve_target handles all three (sets COMPONENT_DIR).
    if ! ws_resolve_target "$1"; then
        exit 1
    fi
    pull_repo "$1" "$COMPONENT_DIR"
else
    # No arg — walk all three families. Components are config-driven
    # (yq over ecosystem.yaml); realms and hoards are disk-driven
    # (any directory with a .git/ subfolder). Mirrors ws-status.sh.
    # `// {}` guards the fresh-workspace case (null/missing components map).
    ECO="$(ws_resolve_ecosystem)"
    ws_validate_component_keys "$ECO" || exit 1
    while IFS= read -r name; do
        pull_repo "$name" "$COMPONENTS_DIR/$name"
    done < <(yq -r '.components // {} | keys | .[]' "$ECO")

    realms_dir="${REALMS_DIR:-$ROOT_DIR/realms}"
    if [[ -d "$realms_dir" ]]; then
        for realm_path in "$realms_dir"/*/; do
            [[ -d "${realm_path}.git" ]] || continue
            pull_repo "$(basename "$realm_path")" "$realm_path"
        done
    fi

    hoards_dir="${HOARDS_DIR:-$ROOT_DIR/hoards}"
    if [[ -d "$hoards_dir" ]]; then
        for hoard_path in "$hoards_dir"/*/; do
            [[ -d "${hoard_path}.git" ]] || continue
            pull_repo "$(basename "$hoard_path")" "$hoard_path"
        done
    fi
fi

# Pulling a realm is the recovery path when its approved trust inputs have
# drifted, so do not require current trust before the pull. Afterward, surface
# the state without updating the operator-owned approval fingerprint.
active_realm=""
if active_realm="$(ws_detect_realm 2>/dev/null)" && [[ -n "$active_realm" ]]; then
    trust_state="$(ws_realm_trust_state "$active_realm")"
    if [[ "$trust_state" != "current" ]]; then
        echo ""
        echo "Realm trust reapproval required for '$active_realm' after pull (state: $trust_state)."
        echo "  Review the current trust summary, then run: ws realm use $active_realm"
    fi
fi

if [[ "$HAD_FAILURES" -ne 0 ]]; then
    echo ""
    echo "Some repos had conflicts. Resolve manually, then re-run."
    exit 1
fi
