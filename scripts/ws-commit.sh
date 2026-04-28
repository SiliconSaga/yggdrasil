#!/usr/bin/env bash
# ws-commit.sh — Commit with Co-Authored-By trailer (bodyfile-driven)
#
# Usage:
#   ws-commit.sh <component> <bodyfile>
#
# Bodyfile-only: every commit declares its `add:` frontmatter so staging
# is part of the bodyfile contract, never a hidden precondition. See
# `ws commit --help` for full documentation. Uses shared functions from
# ws-realm.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Auto-source .env so CLAUDE_MODEL and other env are available
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

commit_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws commit <component> <bodyfile>"
        echo ""
        echo "Commit with a Co-Authored-By trailer. Bodyfile-driven: every"
        echo "commit declares its files to stage in the bodyfile frontmatter,"
        echo "so there's no separate \`git add\` step and no implicit staging"
        echo "preconditions."
        echo ""
        echo "Arguments:"
        echo "  component   Component name (or 'yggdrasil' for workspace root)"
        echo "  bodyfile    Path (relative to workspace root) to a .md file"
        echo "              with YAML frontmatter — typically .commits/<name>.md"
        echo ""
        echo "The Co-Authored-By trailer is appended automatically."
        echo "Set CLAUDE_MODEL to control the model name (default: Opus 4.7)."
        echo ""
        echo "Bodyfile frontmatter (YAML between --- markers):"
        echo "  message:      Commit subject line (required)"
        echo "  add:          List of files to stage before committing"
        echo "  remove:       List of deleted files to stage for removal"
        echo "  Frontmatter is stripped from the commit body automatically."
        echo ""
        echo "See templates/commit.md for a ready-to-copy bodyfile template."
        echo ""
        echo "Examples:"
        echo "  ws commit yggdrasil .commits/fix-store-race.md"
        echo "  ws commit mimir .commits/race-fix.md"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    commit_help 1
    exit 0
fi

if [[ $# -ne 2 ]]; then
    commit_help 2
    exit 1
fi

comp="$1"
bodyfile="$2"
message=""

# The bodyfile arg should be a path to a .md file. Reject anything else
# loudly so a stray inline-message-style invocation doesn't silently
# misread.
if [[ "$bodyfile" != *.md ]]; then
    echo "ERROR: ws commit is bodyfile-only — second arg must be a .md path." >&2
    echo "  Got: '$bodyfile'" >&2
    echo "  Usage: ws commit <component> <bodyfile>" >&2
    echo "  Write a bodyfile (see templates/commit.md) under .commits/ first." >&2
    exit 1
fi

# Resolve to an absolute path so later code (which cd's into the component
# dir) can still read the file. Validate existence here; no later check
# needed.
[[ "$bodyfile" != /* ]] && bodyfile="$ROOT_DIR/$bodyfile"
if [[ ! -f "$bodyfile" ]]; then
    echo "ERROR: bodyfile not found: $bodyfile" >&2
    exit 1
fi

# --- Build Co-Authored-By trailer from identity config ---

eco="$(ws_resolve_ecosystem)"
co_authored_by=$(yq -r '.identity.co_authored_by // ""' "$eco" 2>/dev/null)
if [[ -z "$co_authored_by" || "$co_authored_by" == "null" ]]; then
    # No custom identity configured — fall back to Claude, with CLAUDE_MODEL
    # selecting the model name. CLAUDE_MODEL does not override a configured
    # identity (e.g. "Human Dev" or a non-Claude AI should pass through).
    co_authored_by="Claude ${CLAUDE_MODEL:-Opus 4.7}"
fi
# Sanitize — newlines would break the trailer format
co_authored_by="${co_authored_by%%$'\n'*}"
trailer="Co-Authored-By: $co_authored_by <noreply@anthropic.com>"

# Ensure .commits/ exists (may be first use on a fresh clone)
mkdir -p "$ROOT_DIR/.commits"

ws_validate_component "$comp"
cd "$COMPONENT_DIR"

# --- Parse bodyfile frontmatter for files to stage ---

body_content=""
if [[ -n "$bodyfile" ]]; then
    file_content="$(cat "$bodyfile")"

    # Check if file starts with YAML frontmatter (--- on first line)
    if [[ "$file_content" == ---* ]]; then
        # Extract frontmatter (between first and second --- markers)
        frontmatter="$(echo "$file_content" | awk '/^---$/{n++; next} n==1')"

        # Verify we found a closing --- (n should reach 2)
        marker_count="$(echo "$file_content" | grep -c '^---$')"
        if [[ "$marker_count" -lt 2 ]]; then
            # No closing --- — treat entire file as body, no frontmatter
            body_content="$file_content"
        else
            # Extract body (everything after the second --- marker).
            # Only skip the first two --- delimiters; pass through any later
            # ones (e.g. markdown horizontal rules in the commit body).
            body_content="$(echo "$file_content" | awk 'BEGIN{n=0} /^---$/ && n<2 {n++; next} n>=2')"

            # Parse message: from frontmatter (required)
            message="$(echo "$frontmatter" | yq -r '.message // ""' 2>/dev/null)"
            if [[ -z "$message" ]]; then
                echo "ERROR: No commit message. Bodyfile frontmatter must include a 'message:' field." >&2
                exit 1
            fi

            # Parse add: list from frontmatter
            add_files="$(echo "$frontmatter" | yq -r '.add // [] | .[]' 2>/dev/null)"

            # Parse remove: list (for deleted files)
            remove_files="$(echo "$frontmatter" | yq -r '.remove // [] | .[]' 2>/dev/null)"

            if [[ -n "$add_files" ]]; then
                echo "Staging files from bodyfile frontmatter..."
                add_fail=0
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    if [[ ! -e "$f" ]]; then
                        echo "ERROR: file not found: $f (from bodyfile add: list)" >&2
                        add_fail=1
                    fi
                done <<< "$add_files"
                if [[ "$add_fail" -eq 1 ]]; then
                    exit 1
                fi
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    git add "$f"
                done <<< "$add_files"
            fi

            # Stage deleted files from remove: list
            if [[ -n "$remove_files" ]]; then
                echo "Staging removals from bodyfile frontmatter..."
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    # `git rm` (no --cached) so removal applies to BOTH the
                    # index and the working tree. Index-only removal would
                    # leave dangling untracked files behind and surprise the
                    # next `git status` reader. If the file has uncommitted
                    # changes, git refuses — we surface the error rather
                    # than swallowing it, so the operator can decide whether
                    # `git rm -f` was actually intended.
                    if ! git rm "$f"; then
                        echo "WARNING: could not stage removal of $f" >&2
                        echo "  (file may have uncommitted changes — use 'git rm -f $f' if intended)" >&2
                    fi
                done <<< "$remove_files"
            fi
        fi
    else
        # No frontmatter — entire file is the body
        body_content="$file_content"
    fi
fi

# Verify we have a commit message at this point. Reaches here only when
# the bodyfile had no YAML frontmatter (just body text) — in which case
# message: was never parsed and the bodyfile is malformed.
if [[ -z "$message" ]]; then
    echo "ERROR: No commit message. Bodyfile must start with --- delimited frontmatter containing 'message:'." >&2
    exit 1
fi

# Verify there are staged changes (--quiet exits 0 when clean, 1 when dirty).
# In bodyfile mode the add: list does the staging, so this check usually
# passes. Failure means the bodyfile had no add: list and the workspace
# had no pre-staged changes — point the user at the canonical fix.
if git diff --cached --quiet 2>/dev/null; then
    echo "ERROR: No staged changes to commit in $comp." >&2
    echo "  Add files to the bodyfile's 'add:' frontmatter list." >&2
    exit 1
fi

# Trim leading and trailing blank lines from the body (portable awk).
# Logic: buffer only once we've seen a non-blank line (skips leading blanks);
# track the index of the last non-blank line so trailing blanks are dropped;
# blank lines between content (NR after first non-blank, before last) are kept.
if [[ -n "$body_content" ]]; then
    body_content="$(echo "$body_content" | awk '
        NF    { buf[++n] = $0; last = n; next }
        n > 0 { buf[++n] = $0 }
        END   { for (i = 1; i <= last; i++) print buf[i] }
    ')"
fi

# Build and execute the commit
if [[ -n "$body_content" ]]; then
    full_message="$message

$body_content

$trailer"
    git commit -m "$full_message"
else
    git commit -m "$message" -m "$trailer"
fi
