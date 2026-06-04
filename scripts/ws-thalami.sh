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

    # 3. User: --user > frontmatter user > $USER.
    local fm_user; fm_user="$(printf '%s\n' "$fm" | yq '.user // ""')"
    user="${user:-${fm_user:-${USER:-unknown}}}"

    # 4. Vault: --vault > frontmatter vault. (Per-arc override handled later.)
    local fm_vault; fm_vault="$(printf '%s\n' "$fm" | yq '.vault // ""')"
    vault="${vault:-$fm_vault}"
    [[ -n "$vault" ]] || { echo "ERROR: no Vault source. Set 'vault:' in your thalamus frontmatter or pass --vault <path>." >&2; return 1; }
    [[ -d "$vault" ]] || { echo "ERROR: vault path '$vault' is not a directory." >&2; return 1; }

    echo "context: host=$host user=$user team=$team vault=$vault dry=$dry yes=$yes"
    # mirroring implemented in later tasks
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
