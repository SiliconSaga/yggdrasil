#!/usr/bin/env bash
# ws-hoard.sh — Hoard management
#
# Subcommands (called via ws hoard):
#   init [template] [args...]   Scaffold a new hoard locally
#                               (template defaults to 'thalami')
#   <git-url>                   Clone an existing hoard from a git URL
#   list                        Show hoards and which thalami hoard is active
#
# Templates ship under templates/hoards/<name>/.
# Currently shipped: thalami.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"
: "${TEMPLATES_DIR:="$ROOT_DIR/templates"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"   # for ws_resolve_ecosystem

# Resolve identity.human_account from merged ecosystem config.
# Errors with guidance if unset — required for hoard naming.
ws_resolve_human_account() {
    local eco
    eco="$(ws_resolve_ecosystem)"
    local who
    who="$(yq '.identity.human_account // ""' "$eco" 2>/dev/null)"
    if [[ -z "$who" || "$who" == "null" ]]; then
        echo "ERROR: identity.human_account is not set." >&2
        echo "  Set it in ecosystem.local.yaml so hoard names can be generated." >&2
        echo "  Example:" >&2
        echo "    identity:" >&2
        echo "      human_account: cervator" >&2
        exit 1
    fi
    echo "$who"
}

# Resolve the machine name. Defaults to the short hostname; override via
# `machine: <name>` in ecosystem.local.yaml.
#
# Portability: `hostname -s` works on Linux/macOS but not on Windows Git
# Bash, where `hostname` accepts no flags. Strip any domain suffix from
# the bash builtin $HOSTNAME instead — works on all platforms.
ws_resolve_machine_name() {
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    if [[ -f "$local_file" ]]; then
        local override
        override="$(yq '.machine // ""' "$local_file" 2>/dev/null)"
        if [[ -n "$override" && "$override" != "null" ]]; then
            echo "$override"
            return
        fi
    fi
    # ${HOSTNAME%%.*} keeps everything before the first dot.
    # If $HOSTNAME isn't set (rare), fall back to plain `hostname`.
    local h="${HOSTNAME:-$(hostname)}"
    echo "${h%%.*}"
}

# Detect the active thalami hoard.
# Returns the hoard directory name (not full path), or empty.
#
# Discovery rule:
#   1. ecosystem.local.yaml `hoards.thalami:` selector
#   2. Single thalami-* directory in hoards/
#   3. None
ws_detect_thalami_hoard() {
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    if [[ -f "$local_file" ]]; then
        local selector
        selector="$(yq '.hoards.thalami // ""' "$local_file" 2>/dev/null)"
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$HOARDS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi

    local candidates=()
    if [[ -d "$HOARDS_DIR" ]]; then
        for d in "$HOARDS_DIR"/thalami-*/; do
            [[ -d "$d" ]] || continue
            candidates+=("$(basename "$d")")
        done
    fi

    case "${#candidates[@]}" in
        0) echo "" ;;
        1) echo "${candidates[0]}" ;;
        *)
            echo "ERROR: Multiple thalami-* hoards found in hoards/: ${candidates[*]}." >&2
            echo "  Set 'hoards.thalami: <name>' in ecosystem.local.yaml to pick one." >&2
            exit 1
            ;;
    esac
}

# Resolve the path to the per-machine thalamus file in the active hoard.
# Echoes the absolute path or empty if no active hoard.
# (Path template is currently fixed; see design spec for the future
# config-driven override.)
ws_resolve_thalamus_path() {
    local hoard
    hoard="$(ws_detect_thalami_hoard)"
    [[ -z "$hoard" ]] && echo "" && return
    local machine
    machine="$(ws_resolve_machine_name)"
    echo "$HOARDS_DIR/$hoard/${machine}-thalamus.md"
}

ws_hoard_help() {
    echo "Usage: ws hoard <subcommand> [args...]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init [template] [args]   Scaffold a new hoard locally (default: thalami)" >&2
    echo "                           Per-template args:" >&2
    echo "                             thalami --from-thalamus" >&2
    echo "                                  Move root Thalamus.md into the new hoard" >&2
    echo "  <git-url>                Clone an existing hoard" >&2
    echo "  list                     Show hoards and which thalami hoard is active" >&2
}

# ws_hoard_init [template] [template-args...]
# Default template: thalami.
# Per-template args:
#   thalami --from-thalamus    Move root Thalamus.md into the new hoard
ws_hoard_init() {
    # First arg is the template name UNLESS it starts with `-` — that lets
    # `ws hoard init --from-thalamus` use the default thalami template
    # instead of being misread as a template name. Same shape works for
    # any future per-template flag.
    local template="thalami"
    if [[ -n "${1:-}" && "${1:0:1}" != "-" ]]; then
        template="$1"
        shift
    fi

    local template_dir="$TEMPLATES_DIR/hoards/$template"
    if [[ ! -d "$template_dir" ]]; then
        echo "ERROR: Unknown hoard template: '$template'." >&2
        echo "  Available templates:" >&2
        for d in "$TEMPLATES_DIR/hoards"/*/; do
            [[ -d "$d" ]] && echo "    $(basename "$d")"
        done >&2
        exit 1
    fi

    local who
    who="$(ws_resolve_human_account)"
    local target="$HOARDS_DIR/${template}-${who}"
    if [[ -d "$target" ]]; then
        echo "ERROR: Hoard already exists at $target." >&2
        echo "  Remove it first if you want to start over." >&2
        exit 1
    fi

    # Per-template arg handling
    local from_thalamus=false
    case "$template" in
        thalami)
            for arg in "$@"; do
                case "$arg" in
                    --from-thalamus) from_thalamus=true ;;
                    *)
                        echo "ERROR: unknown arg for thalami template: '$arg'." >&2
                        exit 2
                        ;;
                esac
            done
            ;;
        *)
            if [[ $# -gt 0 ]]; then
                echo "ERROR: template '$template' does not accept extra args (got: $*)." >&2
                exit 2
            fi
            ;;
    esac

    # Confirm before doing anything destructive
    if [[ "$from_thalamus" == true ]]; then
        local root_thalamus="$ROOT_DIR/Thalamus.md"
        if [[ ! -f "$root_thalamus" ]]; then
            echo "ERROR: --from-thalamus requested but $root_thalamus does not exist." >&2
            exit 1
        fi
        local machine
        machine="$(ws_resolve_machine_name)"
        echo "About to:"
        echo "  1. Copy template from: $template_dir → $target"
        echo "  2. Move:               $root_thalamus → $target/${machine}-thalamus.md"
        echo "  3. git init the new hoard with an initial commit"
        echo ""
        read -r -p "Proceed? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # Pre-flight check: confirm we have everything needed for the per-template
    # seeding step BEFORE creating $target. Without this, a missing template
    # asset would abort the script half-way through with $target left behind.
    if [[ "$template" == "thalami" && "$from_thalamus" != true ]]; then
        if [[ ! -f "$TEMPLATES_DIR/thalamus.md" ]]; then
            echo "ERROR: thalamus template not found at $TEMPLATES_DIR/thalamus.md." >&2
            echo "  This file ships with the upstream yggdrasil checkout — verify" >&2
            echo "  the workspace is intact, or restore it from upstream." >&2
            exit 1
        fi
    fi

    # Copy template directory
    mkdir -p "$HOARDS_DIR"
    cp -R "$template_dir" "$target"

    # Apply per-template seeding
    if [[ "$template" == "thalami" ]]; then
        local machine
        machine="$(ws_resolve_machine_name)"
        if [[ "$from_thalamus" == true ]]; then
            mv "$ROOT_DIR/Thalamus.md" "$target/${machine}-thalamus.md"
            echo "Moved Thalamus.md → $target/${machine}-thalamus.md"
        else
            # Seed an empty machine thalamus from the workspace template
            cp "$TEMPLATES_DIR/thalamus.md" "$target/${machine}-thalamus.md"
        fi
    fi

    # git init + initial commit. Honor the user's existing git config for
    # name/email when set (so the first commit looks like the user's other
    # work). Fall back to the resolved human_account + a generic email
    # otherwise — the hoard is a personal repo and the user can rebase /
    # amend the initial commit later if they prefer their own attribution.
    local commit_name commit_email
    commit_name="$(git config --get user.name 2>/dev/null || echo "$who")"
    commit_email="$(git config --get user.email 2>/dev/null || echo "hoard@local")"
    (
        cd "$target"
        # Init with explicit `main` so the printed push instructions are
        # correct regardless of the user's init.defaultBranch setting.
        git init -q -b main
        git add .
        git -c user.name="$commit_name" -c user.email="$commit_email" \
            commit -q -m "Initial commit (${template} hoard for ${who})"
    )

    echo ""
    echo "Hoard initialized: $target"
    echo ""
    echo "Push to your own remote when ready, e.g.:"
    echo "  gh repo create ${who}/${template}-${who} --private --source=${target#"$ROOT_DIR"/} --remote=${who} --push"
    echo ""
    echo "Or set up the remote manually (using ${who} as the remote name —"
    echo "the workspace convention is to avoid generic 'origin'):"
    echo "  cd $target"
    echo "  git remote add ${who} <your-url>"
    echo "  git push -u ${who} main"
}

ws_hoard_clone_url() {
    local url="$1"
    if [[ ! "$url" =~ ^(https?://|git@) ]]; then
        echo "ERROR: Unknown subcommand or invalid URL '$url'." >&2
        echo "  Run 'ws hoard' for usage." >&2
        exit 1
    fi

    # Derive hoard directory name from the URL's repo basename
    local repo_name
    repo_name="${url##*/}"
    repo_name="${repo_name%.git}"
    if [[ ! "$repo_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: hoard repo name must be a safe directory name (got: $repo_name)." >&2
        exit 1
    fi

    local target="$HOARDS_DIR/$repo_name"
    if [[ -d "$target" ]]; then
        echo "ERROR: Hoard '$repo_name' already exists at $target." >&2
        exit 1
    fi

    mkdir -p "$HOARDS_DIR"
    echo "CLONE: hoard -> $target"
    git clone "$url" "$target"
    echo ""
    echo "Hoard cloned. If this is a thalami hoard, the active machine's thalamus"
    echo "file is at $target/$(ws_resolve_machine_name)-thalamus.md (created on first session if absent)."
}

ws_hoard_list() {
    echo "=== Hoards ==="
    local active_thalami
    active_thalami="$(ws_detect_thalami_hoard)"
    local found=0
    if [[ -d "$HOARDS_DIR" ]]; then
        for d in "$HOARDS_DIR"/*/; do
            [[ -d "$d" ]] || continue
            local dname
            dname="$(basename "$d")"
            [[ "$dname" == ".gitkeep" ]] && continue
            found=1
            local marker="    "
            if [[ "$dname" == "$active_thalami" ]]; then
                marker="  * "
            fi
            local label=""
            if [[ "$dname" == thalami-* && "$dname" == "$active_thalami" ]]; then
                label=" (active thalami)"
            fi
            echo "${marker}${dname}${label}"
        done
    fi
    if [[ "$found" -eq 0 ]]; then
        echo "  (none)"
        echo ""
        echo "Run 'ws hoard init' to scaffold one, or 'ws hoard <git-url>' to clone."
    fi
}

# Guard: if sourced by another script, stop here
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
set -euo pipefail

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

SUBCMD="${1:-}"
shift 2>/dev/null || true

case "$SUBCMD" in
    ""|--help|-h)
        ws_hoard_help
        ;;
    init)
        ws_hoard_init "$@"
        ;;
    list)
        ws_hoard_list
        ;;
    *)
        ws_hoard_clone_url "$SUBCMD"
        ;;
esac
