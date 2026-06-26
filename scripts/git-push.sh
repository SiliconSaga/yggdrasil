#!/usr/bin/env bash
# git-push.sh — push a branch or tag to a named remote
#
# Usage: git-push.sh [--force] [branch|tag]
#   --force    — force push a branch (for rebases). Refuses main/master and tags.
#   branch|tag — ref to push (default: current branch)
#
# Auth: for HTTPS GitHub/GitLab remotes, ws-provided env tokens are injected
# into this one git push process and credential helpers are disabled so IDE /
# OS keychain prompts do not fire. SSH remotes and tokenless HTTPS remotes use
# normal git behavior.
#
# Remote selection:
#   1 remote  → use it (no ambiguity, any name including origin)
#   N remotes → use GIT_PUSH_REMOTE to disambiguate (case-insensitive)
#   N remotes, no match → fail with clear error
#
# GIT_PUSH_REMOTE is typically set by ws from identity.forkRemote in ecosystem config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

# Auth-env injection is shared with clone/fetch/pull via git-auth.sh, which
# ws-realm.sh (sourced above) pulls in. This thin shim maps the shared
# GIT_AUTH_* outputs onto the GIT_PUSH_* names the push body already uses, so
# the rest of this script is unchanged.
git_push_auth_env_for_remote() {
  git_auth_env_for_url "$1"
  GIT_PUSH_AUTH_ENV=("${GIT_AUTH_ENV[@]}")
  GIT_PUSH_AUTH_LABEL="$GIT_AUTH_LABEL"
  GIT_PUSH_AUTH_PROVIDER="$GIT_AUTH_PROVIDER"
}

# Parse --force flag
FORCE=""
if [[ "${1:-}" == "--force" ]]; then
  FORCE="--force"
  shift
fi

TARGET="${1:-}"
TARGET_KIND="branch"
if [[ -z "$TARGET" ]]; then
  TARGET="$(git rev-parse --abbrev-ref HEAD)"
else
  HAS_LOCAL_BRANCH=""
  HAS_LOCAL_TAG=""
  if git show-ref --verify --quiet "refs/heads/$TARGET"; then
    HAS_LOCAL_BRANCH="1"
  fi
  if git show-ref --verify --quiet "refs/tags/$TARGET"; then
    HAS_LOCAL_TAG="1"
  fi

  if [[ -n "$HAS_LOCAL_BRANCH" && -n "$HAS_LOCAL_TAG" ]]; then
    echo "ERROR: Target '$TARGET' is ambiguous: both refs/heads/$TARGET and refs/tags/$TARGET exist." >&2
    echo "  Rename one ref, or push the tag manually with an explicit refspec if that is intentional." >&2
    exit 1
  elif [[ -n "$HAS_LOCAL_TAG" ]]; then
    TARGET_KIND="tag"
  fi
fi

# Find the push remote.
mapfile -t REMOTES < <(git remote)

if [[ ${#REMOTES[@]} -eq 0 ]]; then
  echo "ERROR: No remotes configured." >&2
  echo "  Add a remote: git remote add <orgname> <url>" >&2
  exit 1
fi

REMOTE_NAME=""
if [[ ${#REMOTES[@]} -eq 1 ]]; then
  REMOTE_NAME="${REMOTES[0]}"
  # Gentle nudge if using origin — not a blocker
  if [[ "$REMOTE_NAME" == "origin" ]]; then
    echo "TIP: Consider renaming 'origin' to your org name for clarity:" >&2
    echo "  git remote rename origin <orgname>" >&2
    echo "" >&2
  fi
elif [[ -n "${GIT_PUSH_REMOTE:-}" ]]; then
  # Case-insensitive match against available remotes
  REMOTE_NAME=""
  for _r in "${REMOTES[@]}"; do
    if [[ "${_r,,}" == "${GIT_PUSH_REMOTE,,}" ]]; then
      REMOTE_NAME="$_r"
      break
    fi
  done
  if [[ -z "$REMOTE_NAME" ]]; then
    echo "ERROR: No remote matching '$GIT_PUSH_REMOTE' (from identity.forkRemote)." >&2
    echo "  Available remotes: ${REMOTES[*]}" >&2
    echo "  Set identity.forkRemote in ecosystem.local.yaml or GIT_PUSH_REMOTE." >&2
    exit 1
  fi
else
  echo "ERROR: Multiple remotes found — cannot determine which to push to." >&2
  echo "  Available remotes: ${REMOTES[*]}" >&2
  echo "  Set identity.forkRemote in ecosystem.local.yaml or GIT_PUSH_REMOTE." >&2
  exit 1
fi

REMOTE_URL=$(git remote get-url "$REMOTE_NAME" 2>/dev/null || echo "")
ORG_REPO=$(echo "$REMOTE_URL" | sed 's|^ssh://[^/]*/||; s|^https://[^/]*/||; s|^http://[^/]*/||; s|^git@[^:]*:||; s|\.git$||')
GIT_PUSH_AUTH_ENV=()
GIT_PUSH_AUTH_LABEL=""
GIT_PUSH_AUTH_PROVIDER=""
git_push_auth_env_for_remote "$REMOTE_URL"

# Tags do not have upstream tracking branches. Use an explicit tag
# refspec so Git cannot reinterpret an ambiguous short name.
if [[ "$TARGET_KIND" == "tag" ]]; then
  if [[ -n "$FORCE" ]]; then
    echo "ERROR: Refusing to force-push tag $TARGET." >&2
    echo "  Tags are release markers; delete/recreate intentionally outside ws push if needed." >&2
    exit 1
  fi

  echo "Pushing tag $TARGET → $REMOTE_NAME ($ORG_REPO)"
  if [[ -n "$GIT_PUSH_AUTH_LABEL" ]]; then
    echo "Using $GIT_PUSH_AUTH_LABEL for HTTPS $GIT_PUSH_AUTH_PROVIDER push auth (no credential helper prompt)"
  fi
  env "${GIT_PUSH_AUTH_ENV[@]}" git push "$REMOTE_NAME" "refs/tags/$TARGET:refs/tags/$TARGET"
  exit 0
fi

BRANCH="$TARGET"

# Safety: refuse to force-push main or master
if [[ -n "$FORCE" ]] && [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Refusing to force-push to $BRANCH. This is almost certainly a mistake." >&2
  exit 1
fi

# Detect whether $BRANCH already has an upstream tracking ref pointing
# at the same remote we're about to push to. If not, add `-u` so the
# first push wires up tracking automatically — without this, a later
# `ws pull <name>` would skip the repo as "no upstream tracking
# branch." Caller can still re-push later without args because tracking
# is now set.
#
# Important: scope the upstream lookup to ${BRANCH}@{upstream}, not the
# bare @{upstream} (which is the *current* branch's upstream). When the
# caller passes an explicit branch name, those can differ.
SET_UPSTREAM=""
if ! current_upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "${BRANCH}@{upstream}" 2>/dev/null); then
  SET_UPSTREAM="--set-upstream"
elif [[ "$current_upstream" != "$REMOTE_NAME/$BRANCH" ]]; then
  # Tracking exists but points elsewhere (e.g. branch was created
  # tracking origin and we're now pushing to a fork remote). Re-aim
  # it so future `git pull` / `ws pull` flows the right way.
  SET_UPSTREAM="--set-upstream"
fi

if [[ -n "$FORCE" ]]; then
  echo "Force pushing $BRANCH → $REMOTE_NAME ($ORG_REPO)"
  if [[ -n "$GIT_PUSH_AUTH_LABEL" ]]; then
    echo "Using $GIT_PUSH_AUTH_LABEL for HTTPS $GIT_PUSH_AUTH_PROVIDER push auth (no credential helper prompt)"
  fi
  env "${GIT_PUSH_AUTH_ENV[@]}" git push --force ${SET_UPSTREAM:+$SET_UPSTREAM} "$REMOTE_NAME" "$BRANCH"
else
  echo "Pushing $BRANCH → $REMOTE_NAME ($ORG_REPO)"
  if [[ -n "$GIT_PUSH_AUTH_LABEL" ]]; then
    echo "Using $GIT_PUSH_AUTH_LABEL for HTTPS $GIT_PUSH_AUTH_PROVIDER push auth (no credential helper prompt)"
  fi
  env "${GIT_PUSH_AUTH_ENV[@]}" git push ${SET_UPSTREAM:+$SET_UPSTREAM} "$REMOTE_NAME" "$BRANCH"
fi
