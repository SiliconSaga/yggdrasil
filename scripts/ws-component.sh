#!/usr/bin/env bash
# ws-component.sh — Component management
# ws:use-when scaffolding a new component from a template flavor
#
# Subcommands (called via ws component):
#   init <flavor> [name] [template-args]   Scaffold a new component locally
#                                          from templates/components/<flavor>/
#   list                                   Show known flavors
#
# Templates ship under templates/components/<flavor>/.
# Currently shipped: gh-pages.

# Apply strict mode only when executed directly, NOT when sourced —
# many callers don't want errexit/nounset/pipefail in their shell.
# When executed, strict mode is enabled before any top-level command
# (notably the `source ws-realm.sh` below) so a failed source
# fail-fasts instead of producing confusing downstream errors.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"
: "${TEMPLATES_DIR:="$ROOT_DIR/templates"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"   # for ws_resolve_ecosystem

# Resolve identity.human_account from merged ecosystem config.
# Errors with guidance if unset — required for the suggested gh repo create
# command and the inferred remote URL.
ws_resolve_human_account() {
    local eco
    eco="$(ws_resolve_ecosystem)"
    local who
    who="$(yq '.identity.human_account // ""' "$eco" 2>/dev/null)"
    if [[ -z "$who" || "$who" == "null" ]]; then
        echo "ERROR: identity.human_account is not set." >&2
        echo "  Set it in ecosystem.local.yaml so component names and remote" >&2
        echo "  URLs can be generated. Example:" >&2
        echo "    identity:" >&2
        echo "      human_account: cervator" >&2
        exit 1
    fi
    echo "$who"
}

# List the available component flavors (one per line) found in
# templates/components/.
ws_component_list_flavors() {
    if [[ ! -d "$TEMPLATES_DIR/components" ]]; then
        return
    fi
    for d in "$TEMPLATES_DIR/components"/*/; do
        [[ -d "$d" ]] || continue
        basename "$d"
    done
}

ws_component_help() {
    echo "Usage: ws component <subcommand> [args...]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init <flavor> [name] [template-args]" >&2
    echo "      Scaffold a new component into components/<name>/ from" >&2
    echo "      templates/components/<flavor>/. Auto-registers in" >&2
    echo "      ecosystem.local.yaml. Prompts for name if omitted on a tty." >&2
    echo "  list" >&2
    echo "      Show known flavors." >&2
}

ws_component_show_list() {
    echo "Known component flavors:"
    local found=0
    while IFS= read -r flavor; do
        [[ -z "$flavor" ]] && continue
        echo "  $flavor"
        found=1
    done < <(ws_component_list_flavors)
    if [[ "$found" -eq 0 ]]; then
        echo "  (none — templates/components/ is empty or absent)"
    fi
}

# Scaffold a new component from a template.
# Usage: ws_component_init <flavor> [name] [template-args...]
ws_component_init() {
    local flavor="${1:-}"
    if [[ -z "$flavor" ]]; then
        echo "ERROR: flavor is required." >&2
        ws_component_help
        exit 1
    fi
    shift

    # Validate flavor exists
    local template_dir="$TEMPLATES_DIR/components/$flavor"
    if [[ ! -d "$template_dir" ]]; then
        echo "ERROR: Unknown component flavor: '$flavor'." >&2
        echo "  Available flavors:" >&2
        local listed=0
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            echo "    $f" >&2
            listed=1
        done < <(ws_component_list_flavors)
        if [[ "$listed" -eq 0 ]]; then
            echo "    (none — templates/components/ is empty or absent)" >&2
        fi
        exit 1
    fi

    # Resolve name — first non-flag arg, prompt if missing on a tty
    local name="${1:-}"
    if [[ -n "$name" && "${name:0:1}" != "-" ]]; then
        shift
    else
        name=""
    fi
    if [[ -z "$name" ]]; then
        if [[ -t 0 ]]; then
            read -r -p "Component name: " name
        fi
        if [[ -z "$name" ]]; then
            echo "ERROR: component name required (no tty for prompt)." >&2
            echo "  Usage: ws component init $flavor <name>" >&2
            exit 1
        fi
    fi

    # Validate name
    if [[ "$name" == "yggdrasil" ]]; then
        echo "ERROR: 'yggdrasil' is the workspace root name; pick a different component name." >&2
        exit 1
    fi
    # Match the regex used by ws_validate_component in ws-realm.sh — allows
    # dotted segments (e.g. some.component) for parity with names already
    # accepted by the rest of the workspace's component handling.
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Invalid component name '$name'." >&2
        echo "  Must be lowercase alphanumeric with hyphens/dots (no trailing dots or consecutive dots)." >&2
        exit 1
    fi

    # Pre-flight checks
    local target="$COMPONENTS_DIR/$name"
    if [[ -d "$target" ]]; then
        echo "ERROR: components/$name already exists at $target." >&2
        exit 1
    fi

    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    if [[ -f "$local_file" ]]; then
        local existing
        # Capture yq's exit status explicitly — `existing="$(yq ...)"` swallows
        # the substitution's status under set -e, so a parse error would
        # silently yield an empty result and be misread as "no collision."
        if ! existing="$(yq ".components.\"$name\" // \"\"" "$local_file")"; then
            echo "ERROR: failed to parse $local_file. Check YAML syntax." >&2
            exit 1
        fi
        if [[ -n "$existing" && "$existing" != "null" ]]; then
            echo "ERROR: component '$name' is already declared in $local_file." >&2
            echo "  Edit the file or pick a different name." >&2
            exit 1
        fi
    fi

    # Warn if name shadows a realm-catalog component
    local eco realm_entry
    eco="$(ws_resolve_ecosystem)"
    if ! realm_entry="$(yq ".components.\"$name\" // \"missing\"" "$eco")"; then
        echo "ERROR: failed to parse merged ecosystem config." >&2
        exit 1
    fi
    if [[ "$realm_entry" != "missing" ]]; then
        echo "WARNING: '$name' is already declared in the merged ecosystem catalog." >&2
        echo "  Adding a local-layer entry will shadow it. This is allowed but unusual." >&2
        if [[ -t 0 ]]; then
            read -r -p "Continue? [y/N] " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 0
            fi
        else
            echo "  (non-tty; refusing to proceed without confirmation)" >&2
            exit 1
        fi
    fi

    # Resolve identity (errors if unset)
    local who
    who="$(ws_resolve_human_account)"

    # Per-template flag handling
    case "$flavor" in
        gh-pages)
            if [[ $# -gt 0 ]]; then
                echo "ERROR: gh-pages template does not accept extra args (got: $*)." >&2
                exit 2
            fi
            ;;
        *)
            if [[ $# -gt 0 ]]; then
                echo "ERROR: flavor '$flavor' does not accept extra args (got: $*)." >&2
                exit 2
            fi
            ;;
    esac

    # Track whether ecosystem.local.yaml exists already, so the rollback trap
    # can also remove a freshly-created (header-only) local file if a later
    # step fails. Without this, an init that fails between `printf header`
    # and `yq -i …` would leave a header-only file behind.
    local local_file_was_new=0
    if [[ ! -f "$local_file" ]]; then
        local_file_was_new=1
    fi

    # Install rollback trap BEFORE the destructive cp -R so a mid-copy
    # failure also cleans up the partial component dir (would otherwise
    # block the next init's pre-flight collision check).
    local rollback_target="$target"
    trap 'rm -rf "$rollback_target" 2>/dev/null; [[ "$local_file_was_new" == 1 ]] && rm -f "$local_file" 2>/dev/null' ERR

    # Copy template directory
    mkdir -p "$COMPONENTS_DIR"
    cp -R "$template_dir" "$target"

    # git init + initial commit
    local commit_name commit_email
    commit_name="$(git config --get user.name 2>/dev/null || echo "$who")"
    commit_email="$(git config --get user.email 2>/dev/null || echo "${who}@local")"
    (
        cd "$target"
        git init -q -b main
        git add .
        git -c user.name="$commit_name" -c user.email="$commit_email" \
            commit -q -m "Initial commit (${flavor} component for ${who})"
    )

    # Add ecosystem.local.yaml entry. Field name is `repo`, matching what
    # ws-clone.sh reads (.components.<name>.repo, with fallback to
    # defaults.gitOrg + name + ".git" when unset). Canonical HTTPS + .git
    # form so a downstream `ws clone <name>` from a fresh workspace gets
    # exactly the right URL without ambiguity.
    local repo_url="https://github.com/${who}/${name}.git"
    if [[ "$local_file_was_new" == 1 ]]; then
        printf '# ecosystem.local.yaml — per-developer overrides (gitignored)\n# Created by ws component init.\n' > "$local_file"
    fi
    yq -i ".components.\"$name\".repo = \"$repo_url\"" "$local_file"

    # Disarm rollback trap — past the danger zone
    trap - ERR

    # Per-flavor visibility default for the suggested gh command. `gh repo
    # create` requires one of --public/--private/--internal in non-interactive
    # mode, so fall back to --private for unknown flavors (safest default —
    # user can override if they want public). gh-pages is the special case
    # because free GH Pages on personal accounts requires public visibility.
    local visibility="--private"
    case "$flavor" in
        gh-pages) visibility="--public" ;;
    esac

    # Educational output
    echo ""
    echo "Component initialized: components/${name}"
    echo ""
    echo "Registered in ecosystem.local.yaml:"
    echo "  components:"
    echo "    ${name}:"
    echo "      repo: ${repo_url}"
    echo ""
    echo "This is the local-only layer of the three-layer config merge:"
    echo "  upstream ecosystem.yaml → realm/ecosystem.yaml → ecosystem.local.yaml"
    echo ""
    echo "The component is immediately usable from this workspace"
    echo "(ws status, ws push ${name}, etc.) without touching the realm."
    echo ""
    echo "When you're ready to share this component with the community:"
    echo "  1. Push the component to your remote (see suggested gh command below)"
    echo "  2. Move the entry from ecosystem.local.yaml into the realm's"
    echo "     ecosystem.yaml, with realm-appropriate fields added (tier, etc.)"
    echo "  3. Commit and push the realm"
    echo ""
    echo "Suggested next step — create and push the GitHub remote:"
    echo "  gh repo create ${who}/${name} ${visibility} \\"
    echo "    --source=components/${name} --remote=${who} --push"
    echo ""
    if [[ "$flavor" == "gh-pages" ]]; then
        echo "(--public is required for free GitHub Pages on personal accounts.)"
        echo ""
    fi
    echo "Then read components/${name}/README.md for the demo walkthrough."
}

# Guard: if sourced by another script, stop here. Strict mode is
# already on (from the conditional at top) when we reach this point
# during direct execution, so no second `set -euo pipefail` needed.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

SUBCMD="${1:-}"
shift 2>/dev/null || true

case "$SUBCMD" in
    ""|--help|-h)
        ws_component_help
        ;;
    init)
        ws_component_init "$@"
        ;;
    list)
        ws_component_show_list
        ;;
    *)
        echo "ERROR: Unknown subcommand '$SUBCMD'." >&2
        ws_component_help
        exit 1
        ;;
esac
