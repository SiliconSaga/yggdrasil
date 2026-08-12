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
# Native-path yq wrapper — makes ws immune to MSYS path-conversion state.
# ---------------------------------------------------------------------------
# On Git Bash (Windows), MSYS may or may not auto-convert Unix-style paths
# (/d/…, /tmp/…) into Windows paths (D:\…) when handing arguments to native
# executables like yq.exe. With MSYS_NO_PATHCONV=1 set (e.g. to keep docker
# volume paths intact) the conversion is OFF, so yq.exe cannot open a
# "/d/…/ecosystem.yaml" argument — which breaks every ws command that reads
# config. Defend at the boundary: convert any file-path argument with
# `cygpath -m` (yields D:/… with forward slashes, which yq accepts regardless
# of the env state) before invoking the real binary. Off Windows there is no
# cygpath, so this is a transparent pass-through.
ws_native_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m -- "$1"
    else
        printf '%s' "$1"
    fi
}

# yq() shadows the binary: absolute Unix-style arguments that name existing
# files are converted for the native binary; expressions, flags, and relative
# paths pass through untouched. Native Windows processes resolve relative paths
# from the same working directory, while restricting conversion to absolute
# paths avoids mistaking an expression for a file merely because a same-named
# relative file exists. stdin-based calls (echo … | yq '…') carry no file
# argument and are unaffected. Callers use `type -P yq` to probe for the real
# binary.
yq() {
    local _arg
    local -a _args=()
    for _arg in "$@"; do
        if [[ "$_arg" == /* && -f "$_arg" ]]; then
            _args+=("$(ws_native_path "$_arg")")
        else
            _args+=("$_arg")
        fi
    done
    command yq "${_args[@]}"
}
export -f ws_native_path yq

# ---------------------------------------------------------------------------
# Shared functions (used by ws-clone.sh, ws-list.sh, ws, etc.)
# ---------------------------------------------------------------------------

WS_COMPONENT_NAME_REGEX='^[a-z]([a-z0-9-]*[a-z0-9])?(\.[a-z]([a-z0-9-]*[a-z0-9])?)*$'

ws_component_name_is_valid() {
    [[ "${1:-}" =~ $WS_COMPONENT_NAME_REGEX ]]
}

# Nested repos are independent upstreams that live inside a component's working
# tree (Terasology's modules/, for one). They are not components: they are not
# declared in ecosystem config, they churn far too fast to enumerate, and their
# names are upstream-controlled — CamelCase, unlike the strict component rule.
#
# So the segment rule below is deliberately broader than WS_COMPONENT_NAME_REGEX,
# and the safety it gives up there is recovered two ways: the component segment
# before the slash still obeys the strict rule, and every resolved path is
# containment-checked against the host component's real path.
#
# Anchored bash regex, not grep: `$` here ends the string rather than a line, so
# a newline-injected name cannot present a valid-looking first segment.
WS_NESTED_SEGMENT_REGEX='^[A-Za-z0-9][A-Za-z0-9._-]*$'

# Validate a nested subpath: one or more slash-separated segments. Rejects empty
# segments (leading, trailing, or doubled slashes), absolute paths, and both `.`
# and `..` — so traversal cannot be spelled at all, before any path is touched.
ws_nested_subpath_is_valid() {
    local subpath="${1:-}" segment
    [[ -n "$subpath" ]] || return 1
    while [[ "$subpath" == */* ]]; do
        segment="${subpath%%/*}"
        subpath="${subpath#*/}"
        [[ "$segment" =~ $WS_NESTED_SEGMENT_REGEX ]] || return 1
        [[ "$segment" != "." && "$segment" != ".." ]] || return 1
    done
    [[ "$subpath" =~ $WS_NESTED_SEGMENT_REGEX ]] || return 1
    [[ "$subpath" != "." && "$subpath" != ".." ]] || return 1
}

# Glob patterns come from a realm adapter, which is trusted but still config.
# Whitespace is rejected because the expansion below relies on the pattern being
# a single shell word, and `..` because a pattern must not be able to climb out.
WS_NESTED_GLOB_REGEX='^[A-Za-z0-9._*?/-]+$'

ws_nested_glob_is_valid() {
    local glob="${1:-}"
    [[ "$glob" =~ $WS_NESTED_GLOB_REGEX ]] || return 1
    [[ "$glob" != /* ]] || return 1
    [[ "$glob" != *".."* ]] || return 1
}

# Emit the `nested:` globs declared for a component by the active realm adapter,
# one per line. Silent non-zero when there is no active realm, no adapter, or no
# declaration — "this component has no nested repos" is the common case, not an
# error worth narrating from here.
#
# Trust is required at the same bar as adapter commands: a realm that has not
# been approved must not be able to steer where a write verb lands.
# Memoized per process. The trust check fingerprints every adapter in the realm,
# and ws status / ws pull ask this once per component — without the cache that is
# a full re-fingerprint per component, which on a workspace with a couple dozen
# components is seconds of yq for an answer that cannot change mid-run.
_WS_NESTED_REALM_CHECKED=""
_WS_NESTED_REALM=""
ws_nested_trusted_realm() {
    if [[ -z "$_WS_NESTED_REALM_CHECKED" ]]; then
        _WS_NESTED_REALM_CHECKED="yes"
        _WS_NESTED_REALM=""
        local active_realm=""
        if active_realm="$(ws_detect_realm 2>/dev/null)" && [[ -n "$active_realm" ]]; then
            if [[ "$(ws_realm_trust_state "$active_realm")" == "current" ]]; then
                _WS_NESTED_REALM="$active_realm"
            fi
        fi
    fi
    [[ -n "$_WS_NESTED_REALM" ]] || return 1
    printf '%s' "$_WS_NESTED_REALM"
}

ws_nested_globs_for_component() {
    local comp="$1" active_realm="" adapter_file=""
    active_realm="$(ws_nested_trusted_realm)" || return 1
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    [[ -f "$adapter_file" && ! -L "$adapter_file" ]] || return 1
    yq -r '.nested // [] | .[] | select(tag == "!!str")' "$adapter_file" 2>/dev/null
}

# Validate the complete key set inside yq so embedded newlines cannot turn one
# invalid mapping key into multiple apparently valid shell input lines.
ws_validate_component_keys() {
    local eco="$1" invalid_count
    if ! invalid_count="$(WS_COMPONENT_NAME_REGEX="$WS_COMPONENT_NAME_REGEX" yq -r '[.components // {} | keys | .[] | select(test(strenv(WS_COMPONENT_NAME_REGEX)) | not)] | length' "$eco" 2>/dev/null)"; then
        echo "ERROR: Cannot validate component names in ecosystem config." >&2
        return 1
    fi
    if [[ ! "$invalid_count" =~ ^[0-9]+$ ]] || [[ "$invalid_count" -ne 0 ]]; then
        echo "ERROR: Invalid component name in ecosystem config; expected lowercase alphanumeric segments with hyphens or dots." >&2
        return 1
    fi
}

# Classify every workspace target kind matched by a name before choosing a
# directory. Callers use the flags and ordered kind list below to reject
# ambiguity instead of silently applying resolver precedence.
WS_TARGET_MATCH_WORKSPACE=false
WS_TARGET_MATCH_REALM=false
WS_TARGET_MATCH_HOARD=false
WS_TARGET_MATCH_COMPONENT=false
WS_TARGET_MATCH_KINDS=()

# Read configuration layers without granting authority from them. This helper
# is only for detecting namespace collisions; executable component resolution
# still goes through ws_resolve_ecosystem and its realm-trust gate.
ws_component_name_is_declared_for_collision() {
    local name="$1" active_realm="" local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    local file="" realm_file="" realm_trust_state="missing" declared="false"
    local -a layer_files=("${ECOSYSTEM:-$ROOT_DIR/ecosystem.yaml}")

    active_realm="$(ws_detect_realm)" || return 2
    if [[ -n "$active_realm" ]]; then
        realm_file="$REALMS_DIR/$active_realm/ecosystem.yaml"
        realm_trust_state="$(ws_realm_trust_state "$active_realm")"
        layer_files+=("$realm_file")
    fi
    layer_files+=("$local_file")

    for file in "${layer_files[@]}"; do
        [[ -f "$file" ]] || continue
        if ! yq '.' "$file" >/dev/null 2>&1; then
            echo "ERROR: Cannot inspect component declarations in malformed ecosystem config: $file" >&2
            return 2
        fi
        if COMPONENT_NAME="$name" yq -e '(((.components // {}) | select(kind == "map") | has(strenv(COMPONENT_NAME))) // false)' "$file" >/dev/null 2>&1; then
            if COMPONENT_NAME="$name" yq -e '.components[strenv(COMPONENT_NAME)] != null' "$file" >/dev/null 2>&1; then
                declared="true"
            elif [[ "$file" == "$realm_file" && "$realm_trust_state" != "current" ]]; then
                # Untrusted realm additions count as possible collisions, but
                # removals cannot erase a trusted declaration before the
                # executable resolver reaches the realm-trust gate.
                continue
            else
                declared="false"
            fi
        fi
    done

    [[ "$declared" == "true" ]]
}

ws_classify_target_name() {
    local name="$1" declaration_status=0

    WS_TARGET_MATCH_WORKSPACE=false
    WS_TARGET_MATCH_REALM=false
    WS_TARGET_MATCH_HOARD=false
    WS_TARGET_MATCH_COMPONENT=false
    WS_TARGET_MATCH_KINDS=()

    if [[ "$name" == "yggdrasil" ]]; then
        WS_TARGET_MATCH_WORKSPACE=true
        WS_TARGET_MATCH_KINDS+=("workspace")
    fi

    if [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        if [[ -d "$REALMS_DIR/$name/.git" ]]; then
            WS_TARGET_MATCH_REALM=true
            WS_TARGET_MATCH_KINDS+=("realm")
        fi
        if [[ -d "$HOARDS_DIR/$name/.git" ]]; then
            WS_TARGET_MATCH_HOARD=true
            WS_TARGET_MATCH_KINDS+=("hoard")
        fi
    fi

    if ws_component_name_is_valid "$name"; then
        if ! type -P yq &>/dev/null; then
            echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
            return 1
        fi
        if ws_component_name_is_declared_for_collision "$name"; then
            WS_TARGET_MATCH_COMPONENT=true
            WS_TARGET_MATCH_KINDS+=("component")
        else
            declaration_status=$?
            [[ "$declaration_status" -eq 1 ]] || return 1
        fi
    fi
}

# Expand a component's declared nested globs and echo every match that is itself
# a git repo, as "<relative-path>\t<absolute-path>". A `.git` file counts as well
# as a directory — worktrees and submodules both present that way.
ws_nested_candidates() {
    local comp="$1" comp_dir="$2" glob candidate relative
    local -a matches=()

    while IFS= read -r glob; do
        [[ -n "$glob" ]] || continue
        if ! ws_nested_glob_is_valid "$glob"; then
            echo "ERROR: Invalid nested glob '$glob' in the adapter for '$comp'." >&2
            echo "  Patterns are relative, may not contain '..', and may not contain whitespace." >&2
            return 1
        fi
        shopt -s nullglob
        # $glob unquoted so it globs; comp_dir quoted so spaces in it stay intact.
        matches=("$comp_dir"/$glob)
        shopt -u nullglob
        for candidate in "${matches[@]}"; do
            [[ -d "$candidate" ]] || continue
            [[ -e "$candidate/.git" ]] || continue
            relative="${candidate#"$comp_dir"/}"
            printf '%s\t%s\n' "$relative" "$candidate"
        done
    done < <(ws_nested_globs_for_component "$comp")
}

# Resolve "<component>/<subpath>" to a nested repo inside the component.
# Sets COMPONENT_DIR, WS_TARGET_NESTED_HOST and WS_TARGET_NESTED_PATH.
#
# The subpath matches either a full relative path ("modules/Health") or a bare
# repo name ("Health"). The bare form is what makes this usable — nobody should
# have to remember which typed subdirectory a given module lives under.
ws_resolve_nested_target() {
    local host="$1" subpath="$2" comp_dir="$3"
    local relative candidate line
    local -a hits=()

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        relative="${line%%$'\t'*}"
        candidate="${line#*$'\t'}"
        if [[ "$subpath" == */* ]]; then
            [[ "$relative" == "$subpath" ]] || continue
        else
            [[ "${relative##*/}" == "$subpath" ]] || continue
        fi
        hits+=("$candidate")
    done < <(ws_nested_candidates "$host" "$comp_dir")

    if [[ "${#hits[@]}" -eq 0 ]]; then
        echo "ERROR: No nested repo '$subpath' inside component '$host'." >&2
        if ws_nested_globs_for_component "$host" >/dev/null 2>&1; then
            echo "  The component declares nested repos, but none matched. Run 'ws status $host' to list them." >&2
        else
            echo "  Component '$host' does not declare nested repos." >&2
            echo "  Add a 'nested:' list of globs (e.g. 'modules/*') to realms/<realm>/adapters/$host.yaml," >&2
            echo "  then re-approve the realm with 'ws realm use --trust <realm>' so the adapter change is trusted." >&2
        fi
        return 1
    fi

    if [[ "${#hits[@]}" -gt 1 ]]; then
        echo "ERROR: Ambiguous nested target '$host/$subpath' matches ${#hits[@]} repos:" >&2
        for candidate in "${hits[@]}"; do
            echo "    ${candidate#"$comp_dir"/}" >&2
        done
        echo "  Qualify it with the full relative path, e.g. 'ws <cmd> $host/${hits[0]#"$comp_dir"/}'." >&2
        return 1
    fi

    candidate="${hits[0]}"

    # Containment check. The segment and glob rules above already forbid spelling
    # a traversal, so this is aimed at what they cannot see: a symlink inside the
    # component pointing somewhere else entirely. Compare resolved real paths.
    local real_candidate real_comp
    if ! real_candidate="$(cd "$candidate" 2>/dev/null && pwd -P)"; then
        echo "ERROR: Cannot resolve nested repo path for '$host/$subpath'." >&2
        return 1
    fi
    if ! real_comp="$(cd "$comp_dir" 2>/dev/null && pwd -P)"; then
        echo "ERROR: Cannot resolve component path for '$host'." >&2
        return 1
    fi
    if [[ "$real_candidate" != "$real_comp"/* ]]; then
        echo "ERROR: Nested repo '$host/$subpath' resolves outside component '$host'." >&2
        echo "  Resolved: $real_candidate" >&2
        echo "  Refusing to operate on it — a nested target must stay inside its host component." >&2
        return 1
    fi

    COMPONENT_DIR="$candidate"
    WS_TARGET_NESTED_HOST="$host"
    WS_TARGET_NESTED_PATH="${candidate#"$comp_dir"/}"
}

# Resolve a workspace target name to its directory.
# Usage: ws_resolve_target <name>
# Sets: COMPONENT_DIR to the resolved path.
# Accepts "yggdrasil" (workspace root), realm directory names, hoard
# directory names, components declared in the merged ecosystem config, and
# "<component>/<nested>" for a repo nested inside a component's working tree.
# Exits non-zero with a kind-neutral message when nothing resolves.
#
# Every repo-touching verb funnels through here, so nested support is added once
# and inherited rather than taught to each verb separately.
WS_TARGET_NESTED_HOST=""
WS_TARGET_NESTED_PATH=""
ws_resolve_target() {
    local name="$1"

    WS_TARGET_NESTED_HOST=""
    WS_TARGET_NESTED_PATH=""

    # Nested form. Resolved before classification because a name containing a
    # slash can never be a component, realm, or hoard directory name.
    if [[ "$name" == */* ]]; then
        local nested_host="${name%%/*}" nested_subpath="${name#*/}"
        if ! ws_component_name_is_valid "$nested_host"; then
            echo "ERROR: Invalid component '$nested_host' in nested target '$name'." >&2
            echo "  The part before the first slash must be a declared component." >&2
            exit 1
        fi
        if ! ws_nested_subpath_is_valid "$nested_subpath"; then
            echo "ERROR: Invalid nested path '$nested_subpath' in target '$name'." >&2
            echo "  Expected slash-separated names, e.g. 'terasology/Health' or 'terasology/modules/Health'." >&2
            exit 1
        fi
        # Resolve the host component through the normal path first, so a nested
        # target inherits declaration and clone checks rather than bypassing them.
        ws_resolve_target "$nested_host"
        local nested_comp_dir="$COMPONENT_DIR"
        ws_resolve_nested_target "$nested_host" "$nested_subpath" "$nested_comp_dir" || exit 1
        return 0
    fi

    ws_classify_target_name "$name" || exit 1

    if [[ "${#WS_TARGET_MATCH_KINDS[@]}" -gt 1 ]]; then
        local kind kinds=""
        for kind in "${WS_TARGET_MATCH_KINDS[@]}"; do
            [[ -z "$kinds" ]] || kinds+=", "
            kinds+="$kind"
        done
        echo "ERROR: Ambiguous target name '$name' matches: $kinds." >&2
        echo "  Rename or remove one of the colliding targets before running a target command." >&2
        exit 1
    fi

    if [[ "$WS_TARGET_MATCH_WORKSPACE" == "true" ]]; then
        COMPONENT_DIR="$ROOT_DIR"
        return 0
    fi

    if [[ "$WS_TARGET_MATCH_REALM" == "true" ]]; then
        COMPONENT_DIR="$REALMS_DIR/$name"
        return 0
    fi

    if [[ "$WS_TARGET_MATCH_HOARD" == "true" ]]; then
        COMPONENT_DIR="$HOARDS_DIR/$name"
        return 0
    fi

    # Reject component names that don't match safe pattern.
    # Use bash regex directly — grep matches per-line and would pass
    # newline-injected names like "mimir\nevil" (CVE-style bypass).
    if ! ws_component_name_is_valid "$name"; then
        echo "ERROR: Invalid target name '$name'. Components must be lowercase alphanumeric with hyphens/dots (no trailing dots or consecutive dots); no realm or hoard dir matched it either." >&2
        exit 1
    fi

    if [[ "$WS_TARGET_MATCH_COMPONENT" == "true" ]]; then
        local eco="" component_declared="false"
        eco="$(ws_resolve_ecosystem)" || exit 1
        if ! component_declared="$(COMPONENT_NAME="$name" yq -r '(((.components // {}) | select(kind == "map") | has(strenv(COMPONENT_NAME))) // false)' "$eco" 2>/dev/null)"; then
            echo "ERROR: Cannot inspect component declarations in ecosystem config." >&2
            exit 1
        fi
        if [[ "$component_declared" != "true" ]]; then
            WS_TARGET_MATCH_COMPONENT=false
        fi
    fi

    if [[ "$WS_TARGET_MATCH_COMPONENT" != "true" ]]; then
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
#   2. Empty (every realm requires explicit `ws realm use` trust)
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

    echo ""
}

# Hash the semantic realm trust inputs rather than the realm Git revision.
# Canonical JSON ignores YAML comments, formatting, and mapping order while
# retaining every ecosystem/adapter value that the workspace may consume.
# Existing realm-owned files referenced as adapter command tokens join the
# fingerprint because they are executable continuations of those values.
_ws_lexical_absolute_path() {
    local path="$1" segment result=""
    local IFS='/'
    local -a segments=()
    [[ "$path" == /* ]] || return 1
    read -r -a segments <<< "${path#/}"
    for segment in "${segments[@]}"; do
        case "$segment" in
            ""|.) ;;
            ..) result="${result%/*}" ;;
            *) result="$result/$segment" ;;
        esac
    done
    printf '%s' "${result:-/}"
}

ws_realm_trust_fingerprint() {
    local name="$1" realm_dir realm_file realm_real realm_lexical canonical adapter_file adapter_basename relative fingerprint
    local commands target_name target_dir command word candidate candidate_path
    local candidate_lexical lexical_in_realm candidate_parent_real referenced_path referenced_relative content_hash
    local LC_ALL=C
    local -a records=()
    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid realm name '$name' for trust fingerprinting." >&2
        return 1
    fi
    realm_dir="$REALMS_DIR/$name"
    realm_real="$(cd "$realm_dir" 2>/dev/null && pwd -P)" || {
        echo "ERROR: Cannot resolve realm directory for trust fingerprinting: $realm_dir" >&2
        return 1
    }
    realm_lexical="$(_ws_lexical_absolute_path "$realm_dir")" || {
        echo "ERROR: Cannot normalize realm directory for trust fingerprinting: $realm_dir" >&2
        return 1
    }
    realm_file="$realm_dir/ecosystem.yaml"
    if [[ ! -f "$realm_file" || -L "$realm_file" ]]; then
        echo "ERROR: Realm '$name' has no regular ecosystem.yaml trust input." >&2
        return 1
    fi
    if ! canonical="$(yq -o=json -I=0 'sort_keys(..)' "$realm_file" 2>/dev/null)"; then
        echo "ERROR: Cannot canonicalize $realm_file for trust approval." >&2
        return 1
    fi
    records+=("ecosystem.yaml"$'\t'"$canonical")
    for adapter_file in "$realm_dir"/adapters/*.yaml; do
        [[ -e "$adapter_file" || -L "$adapter_file" ]] || continue
        adapter_basename="${adapter_file##*/}"
        if [[ ! "$adapter_basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.yaml$ ]]; then
            echo "ERROR: Realm adapter filename must match <target>.yaml; refusing trust approval." >&2
            return 1
        fi
        if [[ ! -f "$adapter_file" || -L "$adapter_file" ]]; then
            echo "ERROR: Realm adapter trust input must be a regular file: $adapter_file" >&2
            return 1
        fi
        relative="adapters/$adapter_basename"
        if ! canonical="$(yq -o=json -I=0 'sort_keys(..)' "$adapter_file" 2>/dev/null)"; then
            echo "ERROR: Cannot canonicalize $adapter_file for trust approval." >&2
            return 1
        fi
        records+=("$relative"$'\t'"$canonical")

        # Adapter commands execute from the target directory. Resolve existing
        # path-shaped tokens from that same cwd and bind only regular files
        # canonically contained by this realm. Unrelated realm files remain
        # outside the trust surface, preserving documentation-only pulls.
        target_name="${adapter_basename%.yaml}"
        case "$target_name" in
            yggdrasil) target_dir="$ROOT_DIR" ;;
            *)
                if [[ "$target_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ -d "$REALMS_DIR/$target_name/.git" ]]; then
                    target_dir="$REALMS_DIR/$target_name"
                elif [[ "$target_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ -d "$HOARDS_DIR/$target_name/.git" ]]; then
                    target_dir="$HOARDS_DIR/$target_name"
                else
                    target_dir="$COMPONENTS_DIR/$target_name"
                fi
                ;;
        esac
        if ! commands="$(yq -r '.commands // {} | to_entries | .[].value | select(tag == "!!str")' "$adapter_file" 2>/dev/null)"; then
            echo "ERROR: Cannot inspect adapter commands in $adapter_file for referenced trust inputs." >&2
            return 1
        fi
        while IFS= read -r command; do
            [[ -n "$command" ]] || continue
            # Candidate extraction must not under-collect relative to what the
            # shell will execute: whitespace words alone lose quoted spans
            # (spaced helper paths run as ONE argument but split here), and an
            # operator glued to a token (helper.sh;) hides the real path from
            # the existence probe. Collect plain words (quote/assignment
            # stripped, trailing operators trimmed) AND every quoted span.
            local -a command_words=() candidate_tokens=()
            local quoted_scan quoted_regex="\"([^\"]+)\"|'([^']+)'"
            read -r -a command_words <<< "$command"
            for word in "${command_words[@]}"; do
                candidate="$word"
                [[ "$candidate" == *=* ]] && candidate="${candidate#*=}"
                case "$candidate" in
                    \"*\") candidate="${candidate#\"}"; candidate="${candidate%\"}" ;;
                    \'*\') candidate="${candidate#\'}"; candidate="${candidate%\'}" ;;
                esac
                candidate="${candidate%%[\;\&\|\<\>\)]*}"
                candidate_tokens+=("$candidate")
            done
            quoted_scan="$command"
            while [[ "$quoted_scan" =~ $quoted_regex ]]; do
                candidate_tokens+=("${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}")
                quoted_scan="${quoted_scan#*"${BASH_REMATCH[0]}"}"
            done
            for candidate in "${candidate_tokens[@]}"; do
                [[ -n "$candidate" ]] || continue
                case "$candidate" in
                    /*) candidate_path="$candidate" ;;
                    *) candidate_path="$target_dir/$candidate" ;;
                esac
                [[ -e "$candidate_path" || -L "$candidate_path" ]] || continue
                candidate_lexical="$(_ws_lexical_absolute_path "$candidate_path")" || continue
                lexical_in_realm=0
                case "$candidate_lexical" in
                    "$realm_lexical"/*) lexical_in_realm=1 ;;
                esac
                if ! candidate_parent_real="$(cd "$(dirname "$candidate_path")" 2>/dev/null && pwd -P)"; then
                    if [[ "$lexical_in_realm" -eq 1 ]]; then
                        echo "ERROR: Cannot resolve adapter-referenced realm trust input: $candidate_lexical" >&2
                        return 1
                    fi
                    continue
                fi
                referenced_path="$candidate_parent_real/$(basename "$candidate_path")"
                case "$referenced_path" in
                    "$realm_real"/*) ;;
                    *)
                        if [[ "$lexical_in_realm" -eq 1 ]]; then
                            echo "ERROR: Adapter-referenced trust input escapes the reviewed realm through a symlink: $candidate_lexical" >&2
                            return 1
                        fi
                        continue
                        ;;
                esac
                if [[ -L "$candidate_path" ]]; then
                    echo "ERROR: Adapter-referenced realm trust input must not be a symlink: $referenced_path" >&2
                    return 1
                fi
                [[ -f "$referenced_path" ]] || continue
                if ! content_hash="$(git hash-object "$referenced_path" 2>/dev/null)"; then
                    echo "ERROR: Cannot hash adapter-referenced realm trust input: $referenced_path" >&2
                    return 1
                fi
                referenced_relative="${referenced_path#"$realm_real"/}"
                records+=("referenced/$referenced_relative"$'\t'"$content_hash")
            done
        done <<< "$commands"
    done
    if ! fingerprint="$(printf '%s\n' "${records[@]}" | sort -u | git hash-object --stdin 2>/dev/null)"; then
        echo "ERROR: Cannot calculate the trust fingerprint for realm '$name'." >&2
        return 1
    fi
    if [[ ! "$fingerprint" =~ ^[0-9a-f]{40,64}$ ]]; then
        echo "ERROR: Invalid trust fingerprint produced for realm '$name'." >&2
        return 1
    fi
    printf '%s\n' "$fingerprint"
}

# Report the selected realm's approval state without blocking read-only status
# surfaces such as `ws orient`. This function intentionally emits one token.
ws_realm_trust_state() {
    local name="$1" local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    local realm_tag fingerprint_tag approved_realm approved_fingerprint current_fingerprint
    if [[ ! -f "$local_file" ]]; then
        echo "missing"
        return 0
    fi
    if ! yq '.' "$local_file" >/dev/null 2>&1; then
        echo "error"
        return 0
    fi
    realm_tag="$(yq -r '._gdd.realmTrust.realm | tag' "$local_file" 2>/dev/null)" || { echo "error"; return 0; }
    fingerprint_tag="$(yq -r '._gdd.realmTrust.fingerprint | tag' "$local_file" 2>/dev/null)" || { echo "error"; return 0; }
    if [[ "$realm_tag" == "!!null" && "$fingerprint_tag" == "!!null" ]]; then
        echo "missing"
        return 0
    fi
    if [[ "$realm_tag" != "!!str" || "$fingerprint_tag" != "!!str" ]]; then
        echo "error"
        return 0
    fi
    approved_realm="$(yq -r '._gdd.realmTrust.realm' "$local_file" 2>/dev/null)" || { echo "error"; return 0; }
    approved_fingerprint="$(yq -r '._gdd.realmTrust.fingerprint' "$local_file" 2>/dev/null)" || { echo "error"; return 0; }
    if [[ ! "$approved_fingerprint" =~ ^[0-9a-f]{40,64}$ ]]; then
        echo "error"
        return 0
    fi
    if [[ "$approved_realm" != "$name" ]]; then
        echo "stale"
        return 0
    fi
    if ! current_fingerprint="$(ws_realm_trust_fingerprint "$name" 2>/dev/null)"; then
        echo "error"
        return 0
    fi
    if [[ "$current_fingerprint" == "$approved_fingerprint" ]]; then
        echo "current"
    else
        echo "stale"
    fi
}

ws_require_realm_trust() {
    local name="$1" state
    state="$(ws_realm_trust_state "$name")"
    [[ "$state" == "current" ]] && return 0
    echo "ERROR: Realm '$name' trust reapproval is required (state: $state)." >&2
    echo "  Review the current trust summary, then run: ws realm use $name" >&2
    return 1
}

# Require the selected realm's current trust record before an executable
# adapter surface is read. The optional name lets callers reuse an already
# detected realm; without one, detection remains centralized here.
ws_require_active_realm_trust() {
    local name="${1:-}"
    [[ -n "$name" ]] || name="$(ws_detect_realm)"
    [[ -n "$name" ]] || return 0
    ws_require_realm_trust "$name"
}

# Persist exactly the trust inputs the human reviewed. Recompute immediately
# before writing so a concurrent pull/edit cannot turn the approval prompt into
# authorization for different realm content.
ws_realm_record_approval() {
    local name="$1" reviewed_fingerprint="$2" current_fingerprint
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    if ! current_fingerprint="$(ws_realm_trust_fingerprint "$name")"; then
        return 1
    fi
    if [[ "$current_fingerprint" != "$reviewed_fingerprint" ]]; then
        echo "ERROR: Realm trust inputs changed while they were being reviewed; refusing approval." >&2
        echo "  Review the new summary and try again: ws realm use $name" >&2
        return 1
    fi
    if [[ ! -f "$local_file" ]]; then
        printf '{}\n' > "$local_file"
    fi
    REALM_NAME="$name" REALM_FINGERPRINT="$reviewed_fingerprint" yq -i '
        .realm = strenv(REALM_NAME) |
        ._gdd.realmTrust = {
          "realm": strenv(REALM_NAME),
          "fingerprint": strenv(REALM_FINGERPRINT)
        }
    ' "$local_file"
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
        ws_require_realm_trust "$active_realm" || return 1
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

if ! type -P yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

ws_realm_help() {
    echo "Usage: ws realm <subcommand>" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init            Clone the template realm for tutorials" >&2
    echo "  <git-url>       Clone a community realm" >&2
    echo "  use [--trust] <name>  Review and select a cloned realm" >&2
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

After it runs, review and activate the template with
'ws realm use realm-template'. You can then try the quick tutorial
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
        echo "  Review and activate it with: ws realm use realm-template"
        return 0
    fi
    mkdir -p "$REALMS_DIR"
    echo "CLONE: template realm -> $target"
    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    git_auth_env_for_url "$template_url"
    git_auth_run git clone -- "$template_url" "$target"
    echo ""
    echo "Template realm ready, but inactive until you review and select it."
    echo ""
    echo "Review and activate:              ws realm use realm-template"
    echo "Then try the fastest first loop:  ws component init gh-pages my-page   (edit -> PR -> live site)"
    echo "Make it your own:                fork this repo on GitHub, rename it realm-<your-community>,"
    echo "                                 then adopt your fork:  ws realm <your-fork-url>"
    echo "Or browse the example projects:  ws clone --all   (clones the realm's suggested repos as-is)"
}

# Render each realm-controlled field on one physical trust-summary line. The
# record renderers add structural separators only after fields are escaped.
_ws_realm_summary_inline_text() {
    local value="$1"
    value="${value//$'\r'/\\r}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value" | jq -jRs 'gsub("[\\x{0000}-\\x{001f}\\x{007f}-\\x{009f}]"; "")'
}

_ws_realm_render_key_value_records() {
    local records="$1" value_prefix="${2:-}" record key value
    while IFS= read -r record; do
        [[ -n "$record" ]] || continue
        if ! key="$(jq -er '.key | select(type == "string")' <<< "$record" 2>/dev/null)" ||
           ! value="$(jq -er '.value | select(type == "string")' <<< "$record" 2>/dev/null)"; then
            return 1
        fi
        printf '    %s  →  %s%s\n' "$(_ws_realm_summary_inline_text "$key")" "$value_prefix" "$(_ws_realm_summary_inline_text "$value")"
    done <<< "$records"
}

ws_realm_trust_summary() {
    local name="$1" realm_dir="$REALMS_DIR/$1" realm_file="$REALMS_DIR/$1/ecosystem.yaml"
    ws_validate_component_keys "$realm_file" || return 1
    echo "Realm trust summary: $name"
    echo "  Component repository routes:"
    local found=0 component repo host route adapter_file adapter_basename adapter_name commands routes command_record command_key command_value
    if ! routes="$(yq -o=json -I=0 '.components // {} | to_entries | .[] | {"component": .key, "repo": (.value.repo // "")}' "$realm_file" 2>/dev/null)"; then
        echo "ERROR: cannot safely render repository routing from $realm_file; refusing realm adoption." >&2
        return 1
    fi
    while IFS= read -r route; do
        [[ -n "$route" ]] || continue
        if ! component="$(ROUTE_JSON="$route" yq -n -r 'strenv(ROUTE_JSON) | from_json | .component' 2>/dev/null)" ||
           ! repo="$(ROUTE_JSON="$route" yq -n -r 'strenv(ROUTE_JSON) | from_json | .repo' 2>/dev/null)"; then
            echo "ERROR: cannot safely render repository routing from $realm_file; refusing realm adoption." >&2
            return 1
        fi
        [[ -n "$repo" ]] || continue
        host="$(git_remote_host "$repo" 2>/dev/null || echo "invalid/local")"
        # Redact any embedded credential before display — the summary must
        # never be the thing that leaks a token into terminal scrollback.
        echo "    $(_ws_realm_summary_inline_text "$component")  $(_ws_realm_summary_inline_text "$host")  ←  $(_ws_realm_summary_inline_text "$(git_remote_display_value "$repo")")"
        found=1
    done <<< "$routes"
    [[ "$found" -eq 1 ]] || echo "    (none declared)"

    echo "  Adapter commands:"
    found=0
    for adapter_file in "$realm_dir"/adapters/*.yaml; do
        [[ -e "$adapter_file" || -L "$adapter_file" ]] || continue
        adapter_basename="${adapter_file##*/}"
        if [[ ! "$adapter_basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.yaml$ ]]; then
            echo "ERROR: adapter filename must match <target>.yaml; refusing realm adoption." >&2
            return 1
        fi
        adapter_name="${adapter_basename%.yaml}"
        if [[ ! -f "$adapter_file" || -L "$adapter_file" ]]; then
            echo "ERROR: adapter trust input must be a regular file: $adapter_file" >&2
            return 1
        fi
        if ! commands="$(yq -o=json -I=0 '.commands // {} | to_entries | .[] | {"key": .key, "value": .value}' "$adapter_file" 2>/dev/null)"; then
            echo "ERROR: cannot safely render adapter commands from $adapter_file; refusing realm adoption." >&2
            return 1
        fi
        if [[ -n "$commands" ]]; then
            echo "    $adapter_name:"
            while IFS= read -r command_record; do
                if ! command_key="$(jq -er '.key | select(type == "string")' <<< "$command_record" 2>/dev/null)" ||
                   ! command_value="$(jq -er '.value | select(type == "string")' <<< "$command_record" 2>/dev/null)"; then
                    echo "ERROR: cannot safely render adapter commands from $adapter_file; refusing realm adoption." >&2
                    return 1
                fi
                printf '      %s  %s\n' "$(_ws_realm_summary_inline_text "$command_key")" "$(_ws_realm_summary_inline_text "$command_value")"
            done <<< "$commands"
            found=1
        fi
    done
    [[ "$found" -eq 1 ]] || echo "    (none declared)"

    echo "  Fork routing requests:"
    if ! commands="$(yq -o=json -I=0 '
        ([
          {"key": "identity.forkRemote", "value": (.identity.forkRemote // "")},
          {"key": "identity.homes.fork.namespace", "value": (.identity.homes.fork.namespace // "")}
        ] + [
          .components // {} | to_entries | .[] |
          {"key": ("components." + .key + ".forkRepo"), "value": (.value.forkRepo // "")}
        ])
        | .[] | select(.value != "")
    ' "$realm_file" 2>/dev/null)"; then
        echo "ERROR: cannot safely render fork routing from $realm_file; refusing realm adoption." >&2
        return 1
    fi
    if [[ -n "$commands" ]]; then
        if ! _ws_realm_render_key_value_records "$commands"; then
            echo "ERROR: cannot safely render fork routing from $realm_file; refusing realm adoption." >&2
            return 1
        fi
    else
        echo "    (none declared)"
    fi

    echo "  Provider and workflow routing:"
    if ! commands="$(yq -o=json -I=0 '
        ([
          {"key": "defaults.gddHome", "value": (.defaults.gddHome // "")},
          {"key": "defaults.upstreamRemote", "value": (.defaults.upstreamRemote // "")},
          {"key": "defaults.gitProvider", "value": (.defaults.gitProvider // "")}
        ] + [
          .defaults.gitProviders // {} | to_entries | .[] |
          {"key": ("defaults.gitProviders." + .key), "value": .value}
        ])
        | .[] | select(.value != "")
    ' "$realm_file" 2>/dev/null)"; then
        echo "ERROR: cannot safely render provider/workflow routing from $realm_file; refusing realm adoption." >&2
        return 1
    fi
    if [[ -n "$commands" ]]; then
        if ! _ws_realm_render_key_value_records "$commands"; then
            echo "ERROR: cannot safely render provider/workflow routing from $realm_file; refusing realm adoption." >&2
            return 1
        fi
    else
        echo "    (none declared)"
    fi

    echo "  Credential-mapping requests (not authoritative until copied locally):"
    if ! commands="$(yq -o=json -I=0 '.defaults.gitTokens // {} | to_entries | .[] | {"key": .key, "value": .value}' "$realm_file" 2>/dev/null)"; then
        echo "ERROR: cannot safely render credential mappings from $realm_file; refusing realm adoption." >&2
        return 1
    fi
    if [[ -n "$commands" ]]; then
        if ! _ws_realm_render_key_value_records "$commands" '$'; then
            echo "ERROR: cannot safely render credential mappings from $realm_file; refusing realm adoption." >&2
            return 1
        fi
    else
        echo "    (none declared)"
    fi

    echo "  MCP endpoints:"
    if ! commands="$(yq -o=json -I=0 '.mcp.servers // {} | to_entries | .[] | {"key": .key, "transport": .value.transport, "url": .value.url}' "$realm_file" 2>/dev/null)"; then
        echo "ERROR: cannot safely render MCP endpoints from $realm_file; refusing realm adoption." >&2
        return 1
    fi
    if [[ -n "$commands" ]]; then
        while IFS= read -r command_record; do
            [[ -n "$command_record" ]] || continue
            if ! command_key="$(jq -er '.key | select(type == "string")' <<< "$command_record" 2>/dev/null)" ||
               ! command_value="$(jq -er '.url | select(type == "string")' <<< "$command_record" 2>/dev/null)" ||
               ! route="$(jq -er '.transport | select(type == "string")' <<< "$command_record" 2>/dev/null)"; then
                echo "ERROR: cannot safely render MCP endpoints from $realm_file; refusing realm adoption." >&2
                return 1
            fi
            printf '    %s  →  transport=%s %s\n' "$(_ws_realm_summary_inline_text "$command_key")" "$(_ws_realm_summary_inline_text "$route")" "$(_ws_realm_summary_inline_text "$command_value")"
        done <<< "$commands"
    else
        echo "    (none declared)"
    fi
}

ws_realm_use() {
    local trust=0 name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --trust) trust=1 ;;
            -*) echo "ERROR: Unknown option '$1'." >&2; exit 1 ;;
            *)
                [[ -z "$name" ]] || { echo "Usage: ws realm use [--trust] <name>" >&2; exit 1; }
                name="$1"
                ;;
        esac
        shift
    done
    if [[ -z "$name" ]]; then
        echo "Usage: ws realm use [--trust] <name>" >&2
        exit 1
    fi
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
    local realm_file="$REALMS_DIR/$name/ecosystem.yaml"
    if [[ ! -f "$realm_file" ]] || ! yq '.' "$realm_file" >/dev/null 2>&1; then
        echo "ERROR: Realm '$name' has no valid ecosystem.yaml." >&2
        exit 1
    fi

    local reviewed_fingerprint
    if ! reviewed_fingerprint="$(ws_realm_trust_fingerprint "$name")"; then
        return 1
    fi
    ws_realm_trust_summary "$name" || return 1
    echo ""
    if [[ "$trust" -ne 1 ]]; then
        if [[ -t 0 ]]; then
            local confirm
            read -r -p "Trust and activate this realm? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; return 0; }
        else
            echo "Review step complete — no realm activated yet. This two-step flow is by design:" >&2
            echo "the trust summary above is what you are approving. When it looks right, re-run:" >&2
            echo "  ws realm use --trust $name" >&2
            exit 1
        fi
    fi
    ws_realm_record_approval "$name" "$reviewed_fingerprint" || return 1
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
    git_auth_run git clone -- "$url" "$target"
    echo ""
    echo "Community realm cloned but not active. Review and select it with:"
    echo "  ws realm use $repo_name"
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
    if ! ws_component_name_is_valid "$comp"; then
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
    exists=$(COMPONENT_NAME="$comp" yq '.components[strenv(COMPONENT_NAME)] // "missing"' "$eco")
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
