#!/usr/bin/env bash
# ws thalami — publish personal published:true arcs (+ tagged Vault notes)
# into a team-thalami hoard. See docs/gdd/team-thalami-quickstart.md.
#
# Sourcing ws-hoard.sh transitively provides the ws-realm.sh helpers
# (ws_resolve_ecosystem, ws_detect_thalami_hoard, ws_resolve_thalamus_path, …):
# ws-hoard.sh already sources ws-realm.sh, so we do not source it again here.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"

source "$SCRIPT_DIR/ws-hoard.sh"

ws_thalami_help() {
    cat <<'EOF'
Usage: ws thalami <subcommand>

Subcommands:
  publish [--to <hoard>] [--vault <path>] [--user <name>] [--dry-run] [--yes]
        Mirror this machine's published:true arcs (and their
        #team/<arc-id>-tagged Vault notes) into a team-thalami hoard.
        Write-only — review then commit the team hoard yourself.

  help  Show this help.
EOF
}

# --- resolution helpers -----------------------------------------------------

# Extract the YAML frontmatter block of a markdown file (between first two ---).
_wt_frontmatter() {
    awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f{print}' "$1"
}

# Auto-detect a single hoards/team-thalami-* dir; honor an explicit name.
_wt_resolve_team_hoard() {
    local explicit="$1" d matches=()
    if [[ -n "$explicit" ]]; then
        [[ -d "$HOARDS_DIR/$explicit" ]] || { echo "ERROR: team hoard '$explicit' not found under hoards/." >&2; return 1; }
        echo "$explicit"; return 0
    fi
    for d in "$HOARDS_DIR"/team-thalami-*/; do
        [[ -d "$d" ]] || continue
        matches+=("$(basename "$d")")
    done
    case "${#matches[@]}" in
        1) echo "${matches[0]}" ;;
        0) echo "ERROR: no hoards/team-thalami-* found. Pass --to <hoard> or run 'ws hoard init team-thalami --name <n>'." >&2; return 1 ;;
        *) echo "ERROR: multiple team-thalami hoards (${matches[*]}). Pass --to <hoard>." >&2; return 1 ;;
    esac
}

# Build the team projection YAML (only user + published arcs) from frontmatter.
_wt_projection() {
    local fm="$1" user="$2"
    printf '%s\n' "$fm" | USER_VAL="$user" \
        yq '{"user": strenv(USER_VAL), "arcs": (.arcs // [] | map(select(.published == true)))}'
}

# List published arc ids, one per line.
_wt_published_ids() {
    printf '%s\n' "$1" | yq '.arcs // [] | map(select(.published == true)) | .[].id'
}

# Echo the vault-relative paths of notes tagged for $arc_id, minus denylisted.
_wt_sweep() {
    local vault="$1" arc_id="$2" f rel
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        # Denylist: skip notes carrying an exclusion tag — inline #private/#noteam,
        # or a frontmatter list item `- private` / `- noteam`. A bare prose word
        # like "private" must NOT trigger exclusion, so we require the # (inline)
        # or an exact YAML list-item line (frontmatter).
        grep -qE '(^|[^A-Za-z0-9_/-])#(private|noteam)([^A-Za-z0-9_/-]|$)|^[[:space:]]*-[[:space:]]*(private|noteam)[[:space:]]*$' "$f" && continue
        rel="${f#"$vault"/}"
        echo "$rel"
    done < <(grep -rlE "(^|[^A-Za-z0-9_/-])#?team/$arc_id([^A-Za-z0-9_/-]|\$)" "$vault" --include='*.md' 2>/dev/null | sort)
}

ws_thalami_publish() {
    command -v yq >/dev/null 2>&1 || { echo "ERROR: 'yq' (v4+) is required for 'ws thalami publish'." >&2; return 1; }
    local to="" vault="" user="" dry=0 yes=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to) to="${2:?--to needs a value}"; shift 2 ;;
            --vault) vault="${2:?--vault needs a value}"; shift 2 ;;
            --user) user="${2:?--user needs a value}"; shift 2 ;;
            --dry-run) dry=1; shift ;;
            --yes|-y) yes=1; shift ;;
            *) echo "ERROR: unknown flag '$1'." >&2; return 1 ;;
        esac
    done

    # 1. Personal thalamus (the active per-machine file).
    local src; src="$(ws_resolve_thalamus_path)"
    [[ -n "$src" && -f "$src" ]] || { echo "ERROR: no active thalami thalamus file found." >&2; return 1; }
    local host; host="$(basename "$src" | sed 's/-thalamus\.md$//')"
    local fm; fm="$(_wt_frontmatter "$src")"

    # 2. Team hoard.
    local team; team="$(_wt_resolve_team_hoard "$to")" || return 1
    local team_dir; team_dir="$HOARDS_DIR/$team"

    # 3. User identity: --user > frontmatter user: > identity.human_account > $USER.
    local fm_user; fm_user="$(printf '%s\n' "$fm" | yq '.user // ""')"
    local acct; acct="$(ws_resolve_human_account 2>/dev/null || true)"
    user="${user:-${fm_user:-${acct:-${USER:-unknown}}}}"

    # 4. Vault: --vault > frontmatter vault. (Per-arc override handled later.)
    local fm_vault; fm_vault="$(printf '%s\n' "$fm" | yq '.vault // ""')"
    vault="${vault:-$fm_vault}"
    [[ -n "$vault" ]] || { echo "ERROR: no Vault source. Set 'vault:' in your thalamus frontmatter or pass --vault <path>." >&2; return 1; }
    # A workspace-relative vault path is anchored to the workspace root.
    [[ "$vault" = /* ]] || vault="$ROOT_DIR/$vault"
    [[ -d "$vault" ]] || { echo "ERROR: vault path '$vault' is not a directory." >&2; return 1; }

    echo "context: host=$host user=$user team=$team vault=$vault dry=$dry yes=$yes"

    local projection ids
    projection="$(_wt_projection "$fm" "$user")"
    ids="$(_wt_published_ids "$fm")"
    if [[ -z "$ids" ]]; then echo "Nothing to publish: no arcs with 'published: true'."; return 0; fi

    local user_dir="$team_dir/$user"
    local out_name="$host-thalamus.md"
    local arc_id rel base dest reply count

    # --dry-run: preview the projection + the source notes that would be swept.
    if [[ "$dry" -eq 1 ]]; then
        echo "would publish to: $user_dir"
        echo "projection ($out_name):"
        printf '%s\n' "$projection" | sed 's/^/  /'
        echo "published arcs: $(echo "$ids" | tr '\n' ' ')"
        while IFS= read -r arc_id; do
            [[ -n "$arc_id" ]] || continue
            echo "  $arc_id notes:"
            _wt_sweep "$vault" "$arc_id" | sed 's/^/    /'
        done <<< "$ids"
        return 0
    fi

    # Stage the desired user-folder content in a temp dir, then compare to what is
    # already published — so we can report "No changes" and only write on a diff.
    # Notes are flattened to their basename under <arc-id>/ (a collision within an
    # arc is an error, not a silent clobber).
    local stage; stage="$(mktemp -d)"
    trap 'rm -rf "${stage:-}"' EXIT
    { echo "---"; printf '%s\n' "$projection"; echo "---"; echo ""; \
      echo "# Team projection — generated by \`ws thalami publish\`, do not hand-edit"; } > "$stage/$out_name"

    while IFS= read -r arc_id; do
        [[ -n "$arc_id" ]] || continue
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            base="$(basename "$rel")"
            dest="$stage/$arc_id/$base"
            if [[ -e "$dest" ]]; then
                echo "ERROR: two notes flatten to the same name in arc '$arc_id': '$base'. Rename one." >&2
                rm -rf "$stage"
                return 1
            fi
            mkdir -p "$stage/$arc_id"
            cp "$vault/$rel" "$dest"
        done < <(_wt_sweep "$vault" "$arc_id")
    done <<< "$ids"

    # No-changes short-circuit.
    if [[ -d "$user_dir" ]] && diff -rq "$user_dir" "$stage" >/dev/null 2>&1; then
        echo "No changes since last publish."
        rm -rf "$stage"
        return 0
    fi

    # Confirm before writing (skipped by --yes).
    if [[ "$yes" -ne 1 ]]; then
        echo "About to publish to: $user_dir"
        echo "  projection: $user_dir/$out_name  (arcs: $(echo "$ids" | tr '\n' ' '))"
        while IFS= read -r arc_id; do
            [[ -n "$arc_id" ]] || continue
            echo "  $arc_id notes:"; _wt_sweep "$vault" "$arc_id" | sed 's/^/    /'
        done <<< "$ids"
        printf 'Proceed? [y/N] '
        reply=""; read -r reply || reply=""
        [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted — nothing written."; rm -rf "$stage"; return 0; }
    fi

    # Apply: replace the user folder with the staged content.
    trap - EXIT
    rm -rf "$user_dir"
    mkdir -p "$(dirname "$user_dir")"
    mv "$stage" "$user_dir"
    echo "Published to $user_dir"
    while IFS= read -r arc_id; do
        [[ -n "$arc_id" ]] || continue
        count="$(find "$user_dir/$arc_id" -type f 2>/dev/null | wc -l | tr -d ' ')"
        echo "  $arc_id: $count note(s)"
    done <<< "$ids"
}

# When sourced for its function definitions, stop before dispatch.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

SUBCMD="${1:-}"
shift 2>/dev/null || true
case "$SUBCMD" in
    ""|help|--help|-h) ws_thalami_help ;;
    publish)           ws_thalami_publish "$@" ;;
    *) echo "ERROR: Unknown thalami subcommand '$SUBCMD'. Run 'ws thalami help'." >&2; exit 1 ;;
esac
