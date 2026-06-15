#!/usr/bin/env bash
# ws-commit.sh — Commit with Co-Authored-By trailer (bodyfile-driven)
# ws:use-when finalizing a change — must use bodyfile from commit.md template
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

# Auto-source .env so agent attribution and other env are available
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
        echo "Model attribution:"
        echo "  The trailer identity resolves as: identity.co_authored_by"
        echo "  (if set in merged ecosystem config), else GDD_CO_AUTHOR,"
        echo "  else legacy \"Claude \$CLAUDE_MODEL\"."
        echo "  GDD_CO_AUTHOR is the full trailer identity, for example:"
        echo "    GDD_CO_AUTHOR=\"Codex GPT-5 <noreply@openai.com>\""
        echo "  GDD_CO_AUTHOR and CLAUDE_MODEL are auto-sourced from .env."
        echo "  Legacy CLAUDE_MODEL effective value now: \"${CLAUDE_MODEL:-Opus 4.8}\"."
        echo "  SUB-AGENTS: if you commit while running on a non-default model"
        echo "  (e.g. Sonnet vs the workspace default), prepend identity inline:"
        echo "    GDD_CO_AUTHOR=\"Claude Sonnet 4.6 <noreply@anthropic.com>\" ws commit <comp> <bodyfile>"
        echo "  Inline is correct for sub-agents — a shared .env rewrite from"
        echo "  parallel sub-agents would race."
        echo ""
        echo "Bodyfile frontmatter (YAML between --- markers):"
        echo "  message:      Commit subject line (required)"
        echo "  add:          Paths to stage. Each is passed to \`git add\`."
        echo "                Accepts files (new, modified, OR already-deleted-"
        echo "                from-disk-but-tracked) and directories (stages new"
        echo "                + modified files within recursively)."
        echo "                FAILS FAST if a path doesn't exist on disk AND"
        echo "                isn't a tracked deletion."
        echo "                NOTE: a directory you've fully \`rm -rf\`'d won't"
        echo "                stage via add: — git add on a missing dir errors."
        echo "                Pre-stage with \`git add -A <dir>\` (or \`git rm -r"
        echo "                --cached <dir>\` if also tracked-only) before the"
        echo "                ws commit, then list new + modified files in add:."
        echo "  remove:       Paths to delete via \`git rm\` (touches index AND"
        echo "                working tree). Use only for files still on disk;"
        echo "                for paths already removed from disk, list them in"
        echo "                add: so git add detects the deletion instead."
        echo "  Frontmatter is stripped from the commit body automatically."
        echo ""
        echo "See templates/commit.md for a ready-to-copy bodyfile template."
        echo ""
        echo "Flags:"
        echo "  --dry-run    Validate the bodyfile, simulate staging via"
        echo "               \`git add --dry-run\`, print the full commit"
        echo "               message that would land — but DO NOT touch"
        echo "               the index, working tree, or git history."
        echo ""
        echo "Examples:"
        echo "  ws commit yggdrasil .commits/fix-store-race.md"
        echo "  ws commit mimir .commits/race-fix.md"
        echo "  ws commit yggdrasil --dry-run .commits/preview-me.md"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    commit_help 1
    exit 0
fi

# Scan for --dry-run anywhere in args (positional-friendly). Collect
# the remaining positionals; their meaning is fixed (component +
# bodyfile) regardless of where the flag appeared.
dry_run=false
_positional=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        *)         _positional+=("$1"); shift ;;
    esac
done
set -- "${_positional[@]}"

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
    if [[ -n "${GDD_CO_AUTHOR:-}" ]]; then
        co_authored_by="$GDD_CO_AUTHOR"
    else
        # Legacy Claude default. CLAUDE_MODEL does not override a configured
        # identity or the agent-neutral GDD_CO_AUTHOR value.
        co_authored_by="Claude ${CLAUDE_MODEL:-Opus 4.8} <noreply@anthropic.com>"
    fi
elif [[ "$co_authored_by" != *"<"* ]]; then
    co_authored_by="$co_authored_by <noreply@anthropic.com>"
fi
# Sanitize — newlines would break the trailer format
co_authored_by="${co_authored_by%%$'\n'*}"
if [[ "$co_authored_by" != *"<"* || "$co_authored_by" != *">"* ]]; then
    echo "ERROR: Co-Authored-By identity must include an email in angle brackets." >&2
    echo "  Set GDD_CO_AUTHOR like: Codex GPT-5 <noreply@openai.com>" >&2
    exit 1
fi
trailer="Co-Authored-By: $co_authored_by"

# Ensure .commits/ exists for the normal-commit path (first use on a
# fresh clone may not have it yet). Skip in dry-run mode — dry-run
# promises not to touch the working tree, and creating an untracked
# directory (even one that's gitignored) is still a working-tree
# change a user might be surprised by on a brand-new clone.
if ! $dry_run; then
    mkdir -p "$ROOT_DIR/.commits"
fi

ws_resolve_target "$comp"
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

            # Track whether ANY add: or remove: entry would actually
            # change the index. Dry-run uses this to surface the
            # "no staged changes" case the real-commit path already
            # catches at line ~287 — without this, dry-run would
            # happily print a successful preview for a bodyfile that
            # references only unchanged files, which the real commit
            # would then reject with "No staged changes to commit."
            would_stage_any=0
            if [[ -n "$add_files" ]]; then
                if $dry_run; then
                    echo "DRY RUN — would stage files from bodyfile frontmatter:"
                else
                    echo "Staging files from bodyfile frontmatter..."
                fi
                add_fail=0
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    # Accept if the path exists on disk OR is a tracked path
                    # whose file has been deleted (git add -A stages such
                    # deletions). Only reject when both conditions fail —
                    # that's the real misspelled-path / phantom-entry case.
                    if [[ ! -e "$f" ]] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
                        echo "ERROR: file not found: $f (from bodyfile add: list)" >&2
                        add_fail=1
                    fi
                done <<< "$add_files"
                if [[ "$add_fail" -eq 1 ]]; then
                    exit 1
                fi
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    # `-A` so a tracked-but-deleted path stages as a
                    # deletion. Plain `git add <path>` errors on a
                    # missing file with "pathspec did not match any
                    # files" — which under `set -e` would abort the
                    # dry-run preview before the user sees what else
                    # was in the bodyfile. With `-A`, the same
                    # invocation handles modifications, new files,
                    # AND tracked-deleted uniformly.
                    if $dry_run; then
                        # --dry-run reports what git WOULD do without
                        # touching the index. Capture the output so we
                        # can both display it AND detect whether any
                        # actual staging would occur — `git add
                        # --dry-run` is silent for unchanged paths.
                        add_output=$(git add --dry-run -A "$f")
                        [[ -n "$add_output" ]] && printf '%s\n' "$add_output"
                        [[ -n "$add_output" ]] && would_stage_any=1
                    else
                        git add -A "$f"
                        would_stage_any=1
                    fi
                done <<< "$add_files"
            fi

            # Stage deleted files from remove: list
            if [[ -n "$remove_files" ]]; then
                if $dry_run; then
                    echo "DRY RUN — would remove files from bodyfile frontmatter:"
                else
                    echo "Staging removals from bodyfile frontmatter..."
                fi
                rm_fail=0
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    # `git rm` (no --cached) so removal applies to BOTH the
                    # index and the working tree. Index-only removal would
                    # leave dangling untracked files behind and surprise the
                    # next `git status` reader. If the file has uncommitted
                    # changes, git refuses — we surface the error rather
                    # than swallowing it, so the operator can decide whether
                    # `git rm -f` was actually intended.
                    #
                    # Dry-run uses `git rm --dry-run` which validates the
                    # path (same error surface) but doesn't modify the
                    # index or working tree.
                    rm_args=()
                    $dry_run && rm_args+=("--dry-run")
                    if ! git rm "${rm_args[@]}" "$f"; then
                        if $dry_run; then
                            # Promote to ERROR in dry-run mode — dry-run's
                            # whole point is "would this commit succeed?"
                            # Returning 0 with a warning on a stageable
                            # path the operator listed would be a
                            # misleading preview.
                            echo "ERROR: could not stage removal of $f (from bodyfile remove: list)" >&2
                            rm_fail=1
                        else
                            echo "WARNING: could not stage removal of $f" >&2
                            echo "  (file may have uncommitted changes — use 'git rm -f $f' if intended)" >&2
                        fi
                    else
                        # rm succeeded — index would change.
                        would_stage_any=1
                    fi
                done <<< "$remove_files"
                if $dry_run && [[ "$rm_fail" -eq 1 ]]; then
                    exit 1
                fi
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
#
# Dry-run uses a different signal: $would_stage_any was set whenever an
# add: or remove: entry produced actual `git add --dry-run` output OR a
# successful `git rm --dry-run`. If neither happened, the real commit
# would fail with "No staged changes" — surface that in the preview so
# dry-run fidelity matches real-commit behavior.
if $dry_run; then
    # Mirror real-mode's "is the index actually committable?" gate.
    # Dry-run fails only if BOTH (a) the bodyfile's add:/remove: list
    # produced no would-be-staged changes AND (b) the index has no
    # pre-staged changes from the operator's own `git add` ahead of
    # `ws commit --dry-run`. The pre-staged case is legitimate — the
    # operator may have manually staged something and is using the
    # bodyfile just for the message + trailer; real-mode happily
    # commits that, so dry-run should preview happily too.
    if [[ "${would_stage_any:-0}" -eq 0 ]] && git diff --cached --quiet 2>/dev/null; then
        echo "ERROR: dry-run found no stageable changes for this bodyfile." >&2
        echo "  The real commit would fail with 'No staged changes to commit'." >&2
        echo "  Likely cause: every add: path is unchanged from HEAD AND nothing is pre-staged." >&2
        exit 1
    fi
else
    if git diff --cached --quiet 2>/dev/null; then
        echo "ERROR: No staged changes to commit in $comp." >&2
        echo "  Add files to the bodyfile's 'add:' frontmatter list." >&2
        exit 1
    fi
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

# Build the final commit message — used for the real commit OR for
# the dry-run preview. Same shape either way so the user previews
# exactly what would land.
if [[ -n "$body_content" ]]; then
    full_message="$message

$body_content

$trailer"
else
    full_message="$message

$trailer"
fi

if $dry_run; then
    # Dry-run preview: print the commit message that WOULD land, plus
    # a marker so it's unambiguous that nothing happened. The earlier
    # `git add --dry-run` / `git rm --dry-run` invocations have already
    # surfaced any staging issues; reach this block only when the
    # bodyfile is internally consistent.
    echo ""
    echo "DRY RUN — would commit to $comp (HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo "none yet")):"
    echo ""
    # printf, not echo: a message body starting with `-n` or containing
    # backslash escapes would be interpreted as flags / escape sequences
    # by some echo implementations, mangling the preview. printf '%s\n'
    # treats the whole variable as literal content.
    printf '%s\n' "$full_message" | sed 's/^/    /'
    echo ""
    echo "No changes were made to the index or working tree."
else
    git commit -m "$full_message"
fi
