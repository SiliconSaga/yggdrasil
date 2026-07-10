#!/usr/bin/env bash
# ws-realm.sh — Realm management and shared config merge functions
# ws:use-when:realm adopting or switching the active community config
# ws:use-when:actions inspecting which adapter commands a component has wired
#
# Subcommands (called via ws realm):
#   init            Clone template realm for tutorials
#   <git-url>       Clone community realm from a git URL
#   use <name>      Set active realm in ecosystem.local.yaml
#   list            Show available realms and which is active
#   actions <comp>  List adapter commands for a component
#
# Also provides shared functions sourced by other ws-* scripts:
#   ws_detect_realm       — detect active realm directory name
#   ws_resolve_ecosystem  — three-layer config merge (upstream + realm + local)
#                           (Inheritance reservation: the merge generalizes to
#                           N layers if multi-realm chains land later.)

# Apply strict mode only when executed directly, NOT when sourced —
# this script is sourced by ws-hoard.sh and ws-component.sh for its
# helper functions, and many callers don't want errexit/nounset/
# pipefail in their shell. When executed, strict mode is enabled
# before any top-level command so failures fail-fast.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${ECOSYSTEM:="$ROOT_DIR/ecosystem.yaml"}"
: "${REALMS_DIR:="$ROOT_DIR/realms"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"

# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"

# shellcheck source=git-remote.sh
source "$SCRIPT_DIR/git-remote.sh"

# Shared HTTPS token-injection helpers (git_auth_env_for_url). Sourcing here
# means every script that sources ws-realm.sh — clone, hoard, pull, realm,
# push — can inject .env tokens into raw git operations instead of falling
# through to the OS credential manager. git-auth.sh sources nothing, so there
# is no circular dependency with this file (it uses ws_resolve_token_var,
# defined below, only at call time).
# shellcheck source=git-auth.sh
source "$SCRIPT_DIR/git-auth.sh"

_RESOLVED_ECOSYSTEM=""
_LOCAL_ECOSYSTEM=""
# Initialize only if unset so callers that set COMPONENT_DIR before sourcing
# this file (e.g. git-issue.sh) keep their value. Without :=, sourcing this
# file from such callers wiped COMPONENT_DIR and broke downstream validation.
: "${COMPONENT_DIR:=""}"  # Set by ws_resolve_target

# ---------------------------------------------------------------------------
# Shared functions (used by ws-clone.sh, ws-list.sh, ws, etc.)
# ---------------------------------------------------------------------------

# Resolve a workspace target name to its directory.
# Usage: ws_resolve_target <name>
# Sets: COMPONENT_DIR to the resolved path.
# Accepts "yggdrasil" (workspace root), realm directory names, hoard
# directory names, and components declared in the merged ecosystem config.
# Exits non-zero with a kind-neutral message when nothing resolves.
ws_resolve_target() {
    local name="$1"

    # "yggdrasil" refers to the workspace root, not a component
    if [[ "$name" == "yggdrasil" ]]; then
        COMPONENT_DIR="$ROOT_DIR"
        return 0
    fi

    # Check if name is a realm directory (uses broader name pattern)
    if [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ -d "$REALMS_DIR/$name/.git" ]]; then
        COMPONENT_DIR="$REALMS_DIR/$name"
        return 0
    fi

    # Check if name is a hoard directory (same broader name pattern as realms,
    # since hoards are personal containers cloned with arbitrary repo names).
    if [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ -d "$HOARDS_DIR/$name/.git" ]]; then
        COMPONENT_DIR="$HOARDS_DIR/$name"
        return 0
    fi

    # Reject component names that don't match safe pattern.
    # Use bash regex directly — grep matches per-line and would pass
    # newline-injected names like "mimir\nevil" (CVE-style bypass).
    if [[ ! "$name" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Invalid target name '$name'. Components must be lowercase alphanumeric with hyphens/dots (no trailing dots or consecutive dots); no realm or hoard dir matched it either." >&2
        exit 1
    fi

    # Check yq is available
    if ! command -v yq &>/dev/null; then
        echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
        exit 1
    fi

    # Check component exists in merged ecosystem config
    local eco
    eco="$(ws_resolve_ecosystem)"
    local exists
    exists=$(yq ".components[\"$name\"] // \"missing\"" "$eco")
    if [[ "$exists" == "missing" ]]; then
        echo "ERROR: no such target '$name' (looked for a component, realm, or hoard)." >&2
        echo "  Components must be declared in ecosystem config — run 'ws list'." >&2
        echo "  Realms live under realms/, hoards under hoards/ (must be cloned)." >&2
        exit 1
    fi

    COMPONENT_DIR="$COMPONENTS_DIR/$name"

    # Check if cloned locally
    if [[ ! -d "$COMPONENT_DIR" ]]; then
        echo "ERROR: '$name' is not cloned locally." >&2
        echo "  Run 'ws clone $name' to clone it." >&2
        exit 1
    fi
}

# Detect the active realm directory name.
# Returns the realm directory name (not the full path) or empty string.
#
# Discovery rule:
#   1. ecosystem.local.yaml `realm:` selector, if set and dir exists
#   2. Single non-template realm in realms/ (matches realm-* but not realm-template)
#   3. realm-template, if present
#   4. Empty (no realm active)
#
# Errors if step 2 finds multiple non-template realms (ambiguous).
ws_detect_realm() {
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    if [[ -f "$local_file" ]]; then
        local selector
        if ! selector="$(yq '.realm // ""' "$local_file")"; then
            echo "ERROR: Failed to parse $local_file. Check YAML syntax." >&2
            exit 1
        fi
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$REALMS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi

    # Auto-detect: a single realm-* that is not realm-template
    local candidates=()
    if [[ -d "$REALMS_DIR" ]]; then
        for d in "$REALMS_DIR"/realm-*/; do
            [[ -d "$d" ]] || continue
            local dname
            dname="$(basename "$d")"
            [[ "$dname" == "realm-template" ]] && continue
            candidates+=("$dname")
        done
    fi

    case "${#candidates[@]}" in
        0)
            if [[ -d "$REALMS_DIR/realm-template" ]]; then
                echo "realm-template"
                return
            fi
            echo ""
            ;;
        1)
            echo "${candidates[0]}"
            ;;
        *)
            echo "ERROR: Multiple non-template realms found in realms/: ${candidates[*]}." >&2
            echo "  Set 'realm: <name>' in ecosystem.local.yaml to pick one." >&2
            exit 1
            ;;
    esac
}

# Produce a merged ecosystem config (upstream + realm + local).
# Returns the path to a temp file. Cleanup happens at script exit.
ws_resolve_ecosystem() {
    if [[ -n "$_RESOLVED_ECOSYSTEM" && -f "$_RESOLVED_ECOSYSTEM" ]]; then
        echo "$_RESOLVED_ECOSYSTEM"
        return
    fi

    # Inheritance reservation: today the merge is upstream + realm + local
    # (three layers). When multi-realm inheritance lands, this generalizes
    # to N layers with child-wins semantics — no new identifier needed.

    local base="${ECOSYSTEM:-$ROOT_DIR/ecosystem.yaml}"
    local realm_file=""
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"

    local active_realm
    active_realm="$(ws_detect_realm)"
    if [[ -n "$active_realm" ]]; then
        realm_file="$REALMS_DIR/$active_realm/ecosystem.yaml"
        if [[ ! -f "$realm_file" ]]; then
            echo "ERROR: Active realm '$active_realm' has no ecosystem.yaml." >&2
            echo "  The realm may be incomplete or corrupted." >&2
            exit 1
        fi
    fi

    local merged
    merged="$(mktemp)"
    if [[ -n "$realm_file" ]]; then
        yq eval-all 'select(fileIndex == 0) *d select(fileIndex == 1)' \
            "$base" "$realm_file" > "$merged"
    else
        cp "$base" "$merged"
    fi
    if [[ -f "$local_file" ]]; then
        local tmp
        tmp="$(mktemp)"
        yq eval-all 'select(fileIndex == 0) *d select(fileIndex == 1)' \
            "$merged" "$local_file" > "$tmp"
        mv "$tmp" "$merged"
    fi

    _RESOLVED_ECOSYSTEM="$merged"
    echo "$merged"
}

# Produce the credential/bootstrap authority view: committed workspace config
# plus the operator-owned local override, deliberately excluding realm data.
# Realms may choose repositories and providers after trust, but cannot attach
# the operator's secrets or replace the realm bootstrap source by themselves.
ws_resolve_local_ecosystem() {
    if [[ -n "$_LOCAL_ECOSYSTEM" && -f "$_LOCAL_ECOSYSTEM" ]]; then
        echo "$_LOCAL_ECOSYSTEM"
        return
    fi

    local base="${ECOSYSTEM:-$ROOT_DIR/ecosystem.yaml}"
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    local merged
    merged="$(mktemp)"
    cp "$base" "$merged"
    if [[ -f "$local_file" ]]; then
        local tmp
        tmp="$(mktemp)"
        yq eval-all 'select(fileIndex == 0) *d select(fileIndex == 1)' \
            "$merged" "$local_file" > "$tmp"
        mv "$tmp" "$merged"
    fi
    _LOCAL_ECOSYSTEM="$merged"
    echo "$merged"
}

trap 'rm -f "$_RESOLVED_ECOSYSTEM" "$_LOCAL_ECOSYSTEM" 2>/dev/null' EXIT

# Resolve the gitTokens env-var name for a normalized "host/path" target.
#
# Walks .defaults.gitTokens in the root-plus-local authority config looking for
# the longest-prefix match against $1, and prints the configured env
# var name on stdout. Prints nothing (and exits 0) if no entry matches —
# callers branch on $? or on output emptiness.
#
# Args:
#   $1  Normalized path-like target: "<host>/<group>[/<sub-group>...]/<repo>"
#       — no scheme prefix, no credentials, no port, no .git suffix.
#       Callers that have a raw git URL should normalize it first (see
#       the sed pipeline in ws_diagnose for a reference normalization).
#
# Used by ws_diagnose (token coverage per remote) and ws-clone-fork.sh
# (upstream-read + fork-write token resolution).
ws_resolve_token_var() {
    local target="$1"
    local eco
    eco="$(ws_resolve_local_ecosystem)" || return 0
    [[ -f "$eco" ]] || return 0
    local best_key="" best_len=0
    while IFS= read -r key; do
        [[ -z "$key" || "$key" == "null" ]] && continue
        local key_len=${#key}
        if [[ ( "$target" == "${key}/"* || "$target" == "$key" ) && $key_len -gt $best_len ]]; then
            best_len=$key_len
            best_key="$key"
        fi
    done < <(yq '.defaults.gitTokens | keys | .[]' "$eco" 2>/dev/null)
    [[ -z "$best_key" ]] && return 0
    local token_var
    token_var=$(KEY="$best_key" yq '.defaults.gitTokens[strenv(KEY)] // ""' "$eco" 2>/dev/null)
    [[ -z "$token_var" || "$token_var" == "null" ]] && return 0
    ws_require_provider_token_var "$token_var" || return 1
    printf '%s\n' "$token_var"
}

# ---------------------------------------------------------------------------
# Subcommands — only run when called directly (not when sourced)
# ---------------------------------------------------------------------------

# Guard: if sourced by another script, stop here — don't parse $1 as
# a command. Strict mode is already on (from the conditional at top)
# when we reach this point during direct execution.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

ws_realm_help() {
    echo "Usage: ws realm <subcommand>" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init            Clone the template realm for tutorials" >&2
    echo "  <git-url>       Clone a community realm" >&2
    echo "  use <name>      Set active realm in ecosystem.local.yaml" >&2
    echo "  list            Show available realms and which is active" >&2
    echo "" >&2
    echo "Also available via ws:" >&2
    echo "  ws actions <comp>   List adapter commands for a component" >&2
}

ws_realm_init() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<'HELP'
Usage: ws realm init

Clone the shared template realm (realm-template) into realms/ for the
tutorial flow, creating ecosystem.local.yaml from the example if it is
absent. Takes no arguments.

After it runs you can either try the quick tutorial
('ws component init gh-pages <name>') or make the realm your own — fork it
on GitHub, rename to realm-<your-community>, then 'ws realm <your-fork-url>'.
HELP
        return 0
    fi
    # Copy ecosystem.local.yaml.example if no local config exists.
    # Must happen BEFORE ws_resolve_ecosystem — the example file contains
    # defaults.templateRealm which the merge needs to find.
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    local example_file="$ROOT_DIR/ecosystem.local.yaml.example"
    if [[ ! -f "$local_file" && -f "$example_file" ]]; then
        cp "$example_file" "$local_file"
        echo "Created ecosystem.local.yaml from example."
        echo "  Edit it to set your identity.human_account."
        echo ""
    fi

    local eco
    eco="$(ws_resolve_local_ecosystem)"
    local template_url
    template_url=$(yq '.defaults.templateRealm // ""' "$eco" 2>/dev/null)
    if [[ -z "$template_url" || "$template_url" == "null" ]]; then
        echo "ERROR: No template realm URL configured." >&2
        echo "  Set defaults.templateRealm in ecosystem.local.yaml." >&2
        exit 1
    fi
    git_remote_validate "$template_url" remote

    local target="$REALMS_DIR/realm-template"
    if [[ -d "$target" ]]; then
        echo "SKIP: Template realm already exists at $target"
        return 0
    fi
    mkdir -p "$REALMS_DIR"
    echo "CLONE: template realm -> $target"
    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    git_auth_env_for_url "$template_url"
    env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git clone -- "$template_url" "$target"
    echo ""
    echo "Template realm ready — you're on the shared 'realm-template' starter."
    echo ""
    echo "New to GDD? Fastest first loop:  ws component init gh-pages my-page   (edit -> PR -> live site)"
    echo "Make it your own:                fork this repo on GitHub, rename it realm-<your-community>,"
    echo "                                 then adopt your fork:  ws realm <your-fork-url>"
    echo "Or browse the example projects:  ws clone --all   (clones the realm's suggested repos as-is)"
}

ws_realm_use() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: ws realm use <name>" >&2
        exit 1
    fi
    local name="$1"
    # Validate realm name — prevent path traversal
    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid realm name '$name'. Must be alphanumeric with dots, dashes, underscores." >&2
        exit 1
    fi
    if [[ ! -d "$REALMS_DIR/$name" ]]; then
        echo "ERROR: Realm '$name' not found in realms/." >&2
        echo "  Available realms:" >&2
        for d in "$REALMS_DIR"/*/; do
            [[ -d "$d" ]] && echo "    $(basename "$d")"
        done
        exit 1
    fi
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    if [[ -f "$local_file" ]]; then
        REALM_NAME="$name" yq -i '.realm = strenv(REALM_NAME)' "$local_file"
    else
        echo "realm: \"$name\"" > "$local_file"
    fi
    echo "Active realm set to: $name"
}

ws_realm_list() {
    echo "=== Realms ==="
    local active
    active="$(ws_detect_realm)"
    local found=0
    for d in "$REALMS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local dname
        dname="$(basename "$d")"
        [[ "$dname" == ".gitkeep" ]] && continue
        found=1
        if [[ "$dname" == "$active" ]]; then
            echo "  * $dname (active)"
        else
            echo "    $dname"
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo "  (none)"
        echo ""
        echo "Run 'ws realm init' for tutorials, or 'ws realm <url>' for your community."
    fi
}

ws_realm_clone_url() {
    local url="$1"
    if ! git_remote_validate "$url" remote; then
        echo "ERROR: Unknown subcommand or invalid URL '$url'." >&2
        echo "  Run 'ws realm' for usage." >&2
        exit 1
    fi

    # Derive realm directory name from the URL's repo basename
    local repo_name
    repo_name="${url##*/}"
    repo_name="${repo_name%.git}"
    if [[ ! "$repo_name" =~ ^realm-[A-Za-z0-9._-]+$ ]]; then
        echo "ERROR: realm repo name must match 'realm-<community>' (got: $repo_name)." >&2
        echo "  Rename the repo on the host or fork it under a compliant name." >&2
        exit 1
    fi
    # Reserve realm-template for the upstream tutorial slot (cloned via 'ws realm init').
    # Block community realms from shadowing it via URL.
    if [[ "$repo_name" == "realm-template" ]]; then
        echo "ERROR: 'realm-template' is reserved for the upstream tutorial realm." >&2
        echo "  Use 'ws realm init' to clone the template, or rename the URL's repo." >&2
        exit 1
    fi

    local target="$REALMS_DIR/$repo_name"
    if [[ -d "$target" ]]; then
        echo "ERROR: Realm '$repo_name' already exists at $target." >&2
        echo "  Remove it first or use 'ws realm use' to switch." >&2
        exit 1
    fi
    mkdir -p "$REALMS_DIR"
    echo "CLONE: community realm -> $target"
    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    git_auth_env_for_url "$url"
    env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git clone -- "$url" "$target"
    echo ""
    echo "Community realm ready. Run 'ws clone --all' to clone components."
}

ws_actions() {
    # Detect --help / -h anywhere in args, not just $1, so
    # `ws actions <comp> --help` works as expected.
    for _arg in "$@"; do
        if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
            cat <<'HELP'
Usage: ws actions <component>

List adapter commands declared for a component (test runners,
build commands, etc.). Source of truth is
`realms/<active>/adapters/<comp>.yaml` in the active realm — the
realm-side adapter file lists test/build/lint/etc. commands the
workspace can invoke. Falls back to auto-detection from the
component directory when no adapter file exists.
HELP
            return 0
        fi
    done
    if [[ $# -ne 1 ]]; then
        echo "Usage: ws actions <component>" >&2
        exit 1
    fi
    local comp="$1"

    # Validate component name (safe pattern, exists in config)
    if [[ ! "$comp" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$ ]]; then
        echo "ERROR: Invalid component name '$comp'." >&2
        exit 1
    fi

    # Workspace root is not an ecosystem component, but ws-test.sh treats
    # `yggdrasil` as one whose suite is the vendored-bats files under tests/.
    # Surface that self-test instead of erroring on "not declared in config".
    if [[ "$comp" == "yggdrasil" ]]; then
        echo "=== yggdrasil (workspace root) ==="
        if [[ -n "$(LC_ALL=C find "$ROOT_DIR/tests" -path "$ROOT_DIR/tests/vendor" -prune -o -type f -name '*.bats' -print -quit 2>/dev/null)" ]]; then
            echo "Self-test (vendored bats):"
            echo "  test    ws test yggdrasil   [bats tests/**/*.bats]"
        else
            echo "  (no .bats files under tests/)"
        fi
        return 0
    fi

    local eco
    eco="$(ws_resolve_ecosystem)"
    local exists
    exists=$(yq ".components[\"$comp\"] // \"missing\"" "$eco")
    if [[ "$exists" == "missing" ]]; then
        echo "ERROR: '$comp' is not declared in ecosystem config." >&2
        exit 1
    fi

    echo "=== $comp ==="

    # Check for adapter file in active realm
    local active_realm
    active_realm="$(ws_detect_realm)"
    local adapter_file=""
    if [[ -n "$active_realm" ]]; then
        adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    fi

    local has_configured=0
    if [[ -n "$adapter_file" && -f "$adapter_file" ]]; then
        echo "Configured (from realm):"
        local commands
        commands=$(yq -r '.commands // {} | to_entries | .[] | "  " + .key + "    " + .value' "$adapter_file" 2>/dev/null)
        if [[ -n "$commands" ]]; then
            echo "$commands"
            has_configured=1
        fi
    fi

    # Auto-detection check
    local comp_dir="$COMPONENTS_DIR/$comp"
    if [[ -d "$comp_dir" ]]; then
        echo "Auto-detected:"
        local has_auto=0
        if [[ -f "$comp_dir/gradlew" ]]; then
            echo "  build    ./gradlew build"
            echo "  test     ./gradlew test"
            has_auto=1
        elif [[ -f "$comp_dir/Makefile" ]]; then
            echo "  build    make build (if target exists)"
            echo "  test     make test (if target exists)"
            has_auto=1
        elif [[ -f "$comp_dir/go.mod" ]]; then
            echo "  test     go test ./..."
            has_auto=1
        elif [[ -f "$comp_dir/pyproject.toml" ]]; then
            echo "  test     uv run pytest"
            has_auto=1
        elif [[ -f "$comp_dir/package.json" ]]; then
            echo "  test     npm test"
            has_auto=1
        fi
        if [[ "$has_auto" -eq 0 ]]; then
            if [[ "$has_configured" -eq 1 ]]; then
                echo "  (none - realm commands take precedence)"
            else
                echo "  (none detected)"
                echo ""
                echo "Configure an adapter file: realms/<realm>/adapters/$comp.yaml"
            fi
        fi
    else
        echo "(not cloned locally — run 'ws clone $comp')"
    fi
}

# ---------------------------------------------------------------------------
# Command dispatch (when called directly)
# ---------------------------------------------------------------------------

SUBCMD="${1:-}"
shift 2>/dev/null || true

case "$SUBCMD" in
    ""|help|--help|-h)
        ws_realm_help
        ;;
    init)
        ws_realm_init "$@"
        ;;
    use)
        ws_realm_use "$@"
        ;;
    list)
        ws_realm_list
        ;;
    actions)
        ws_actions "$@"
        ;;
    *)
        ws_realm_clone_url "$SUBCMD"
        ;;
esac
