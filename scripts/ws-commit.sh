#!/usr/bin/env bash
# ws-commit.sh — Commit with Co-Authored-By trailer
#
# Usage:
#   ws-commit.sh <component> <bodyfile>
#   ws-commit.sh <component> <message> [bodyfile]
#
# Two modes: bodyfile (preferred) or inline message. See `ws commit --help`
# for full documentation. Uses shared functions from ws-overlay.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Auto-source .env so CLAUDE_MODEL and other env are available
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

# shellcheck source=ws-overlay.sh
source "$SCRIPT_DIR/ws-overlay.sh"

commit_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws commit <component> <bodyfile>"
        echo "       ws commit <component> <message> [bodyfile]"
        echo ""
        echo "Commit with a Co-Authored-By trailer. Two modes:"
        echo ""
        echo "  Bodyfile mode (preferred):"
        echo "    ws commit <component> .commits/my-change.md"
        echo "    The bodyfile contains everything: message, files to stage, body text."
        echo ""
        echo "  Inline mode:"
        echo "    ws commit <component> 'commit subject' [bodyfile]"
        echo "    Message on the command line, optional bodyfile for extended body."
        echo ""
        echo "Arguments:"
        echo "  component   Component name (or 'yggdrasil' for workspace root)"
        echo "  bodyfile    Commit file from .commits/ (detected by .md extension)"
        echo "  message     Commit subject line (inline mode)"
        echo ""
        echo "The Co-Authored-By trailer is appended automatically."
        echo "Set CLAUDE_MODEL to control the model name (default: Opus 4.6)."
        echo ""
        echo "Bodyfile frontmatter (YAML between --- markers):"
        echo "  message:      Commit subject line (required in bodyfile mode)"
        echo "  add:          List of files to stage before committing"
        echo "  remove:       List of deleted files to stage for removal"
        echo "  Frontmatter is stripped from the commit body automatically."
        echo ""
        echo "See .agent/commit-template.md for a ready-to-copy bodyfile template."
        echo ""
        echo "Examples:"
        echo "  ws commit yggdrasil .commits/fix-store-race.md"
        echo "  ws commit mimir 'fix: resolve store race condition'"
        echo "  ws commit yggdrasil 'feat(ws): add feature' .commits/details.md"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    commit_help 1
    exit 0
fi

if [[ $# -lt 2 ]]; then
    commit_help 2
    exit 1
fi

if [[ $# -gt 3 ]]; then
    echo "ERROR: Too many arguments." >&2
    echo "  Usage: ws commit <component> <bodyfile>" >&2
    echo "  Usage: ws commit <component> <message> [bodyfile]" >&2
    exit 1
fi

# Detect mode: if second arg is a path to an existing .md file, it's bodyfile mode.
# This avoids misclassifying messages like 'docs: update README.md' as bodyfiles.
comp="$1"
message=""
bodyfile=""
resolved_arg2="$2"
[[ "$resolved_arg2" != /* ]] && resolved_arg2="$ROOT_DIR/$resolved_arg2"
if [[ "$2" == *.md ]]; then
    # Looks like a bodyfile path — verify it exists
    if [[ ! -f "$resolved_arg2" ]]; then
        echo "ERROR: bodyfile not found: $2" >&2
        echo "  If this was meant as a commit message, note that arguments" >&2
        echo "  ending in .md are treated as bodyfile paths." >&2
        exit 1
    fi
    # Bodyfile mode: ws commit <comp> <bodyfile>
    bodyfile="$2"
    if [[ $# -gt 2 ]]; then
        echo "ERROR: Too many arguments for bodyfile mode." >&2
        echo "  Usage: ws commit <component> <bodyfile>" >&2
        echo "  Put the commit message in the bodyfile frontmatter (message: field)." >&2
        exit 1
    fi
else
    # Inline mode: ws commit <comp> <message> [bodyfile]
    message="$2"
    bodyfile="${3:-}"
fi

# --- Build Co-Authored-By trailer from identity config ---

eco="$(ws_resolve_ecosystem)"
co_authored_by=$(yq '.identity.co_authored_by // ""' "$eco" 2>/dev/null)
if [[ -z "$co_authored_by" || "$co_authored_by" == "null" ]]; then
    co_authored_by="Claude ${CLAUDE_MODEL:-Opus 4.6}"
fi
# Environment variable overrides config
if [[ -n "${CLAUDE_MODEL:-}" ]]; then
    co_authored_by="Claude $CLAUDE_MODEL"
fi
# Sanitize — newlines would break the trailer format
co_authored_by="${co_authored_by%%$'\n'*}"
trailer="Co-Authored-By: $co_authored_by <noreply@anthropic.com>"

# Ensure .commits/ exists (may be first use on a fresh clone)
mkdir -p "$ROOT_DIR/.commits"

# Resolve bodyfile path before cd (relative paths are from workspace root)
if [[ -n "$bodyfile" ]]; then
    if [[ "$bodyfile" != /* ]]; then
        bodyfile="$ROOT_DIR/$bodyfile"
    fi
    if [[ ! -f "$bodyfile" ]]; then
        echo "ERROR: body file not found: $bodyfile" >&2
        exit 1
    fi
fi

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

            # Parse message: from frontmatter if not provided on command line
            if [[ -z "$message" ]]; then
                message="$(echo "$frontmatter" | yq -r '.message // ""' 2>/dev/null)"
                if [[ -z "$message" ]]; then
                    echo "ERROR: No commit message. Provide message: in bodyfile frontmatter or as a command-line argument." >&2
                    exit 1
                fi
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
                    git rm --cached "$f" 2>/dev/null || git rm "$f" 2>/dev/null || {
                        echo "WARNING: could not stage removal of $f" >&2
                    }
                done <<< "$remove_files"
            fi
        fi
    else
        # No frontmatter — entire file is the body
        body_content="$file_content"
    fi
fi

# Verify we have a commit message at this point
if [[ -z "$message" ]]; then
    echo "ERROR: No commit message. Provide message: in bodyfile frontmatter or as a command-line argument." >&2
    exit 1
fi

# Verify there are staged changes (--quiet exits 0 when clean, 1 when dirty)
if git diff --cached --quiet 2>/dev/null; then
    echo "ERROR: No staged changes to commit in $comp." >&2
    echo "  Stage files first with git add, or use a bodyfile with add: frontmatter." >&2
    exit 1
fi

# Trim leading/trailing blank lines from body (portable awk)
if [[ -n "$body_content" ]]; then
    body_content="$(echo "$body_content" | awk 'NF{found=1} found' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--)if(lines[i]~/[^ \t]/){last=i;break} for(i=1;i<=last;i++)print lines[i]}')"
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
