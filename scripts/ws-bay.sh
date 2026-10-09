#!/usr/bin/env bash
# ws-bay.sh — bays: child workspaces under bays/, each a complete yggdrasil clone
# ws:use-when making, resetting or driving a second workspace on this machine
#
# Usage:
#   ws-bay.sh add <name> [--with <component>]... [--realm <name>] [--hoard <url>] [--from <url>]
#   ws-bay.sh list
#   ws-bay.sh reset <name> [--deep]
#   ws-bay.sh dir <name>
#   ws-bay.sh exec <name> <ws-args...>
#   ws-bay.sh rm <name> [--force]
#
# A bay is a workspace first. A human uses one for a parallel session: its own
# copy of the ws scripts, its own realm trust, its own machine name so a hoard
# there never shares a Thalamus file with the parent. Naust uses bays to run
# pull requests. Nothing here knows what a job is.

set -euo pipefail

for _arg in "$@"; do
    if [[ "$_arg" == "--help" || "$_arg" == "-h" ]]; then
        cat <<'HELP'
Usage: ws bay add <name> [--with <component>]... [--realm <name>] [--hoard <url>] [--from <url>]
       ws bay list
       ws bay reset <name> [--deep]
       ws bay dir <name>
       ws bay exec <name> <ws-args...>
       ws bay rm <name> [--force]

A bay is a second, complete workspace under bays/<name>/: a clone of this
workspace's yggdrasil, its own realm checkout (trusted inside the bay), the
components you ask for, and a hoard if you want one. Use one for a parallel
session that must not share your scripts or your Thalamus file, or let naust
run pull requests through it.

add      Clone from --from, else this checkout's one remote, else the remote
         defaults.upstreamRemote names. The realm is the parent's active one
         unless --realm. Each --with component is cloned with the bay's own ws
         and then its adapter's provision.init runs in the component directory.
reset    Fetch, hard-reset and clean every repository in the bay (root, realm,
         components, nested repos the adapters declare) back to its remote's
         default branch, then remove each adapter's provision.runtime_dirs.
         Gradle output under build/ and .gradle/ survives; --deep removes it
         too (component and nested repos only). Exit 1 names every repository
         that failed or is still dirty.
exec     Run the bay's own ws, from the bay, with this workspace's roots unset.
rm       Remove the bay. Refuses uncommitted work unless --force.

Adapter keys (all optional, under provision:): init, runtime_dirs, remote, branch.
HELP
        exit 0
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${ECOSYSTEM:="$ROOT_DIR/ecosystem.yaml"}"
: "${ECOSYSTEM_LOCAL:="$ROOT_DIR/ecosystem.local.yaml"}"
: "${REALMS_DIR:="$ROOT_DIR/realms"}"
: "${BAYS_DIR:="$ROOT_DIR/bays"}"
RESET_PARALLEL="${WS_BAY_RESET_PARALLEL:-8}"

type -P yq >/dev/null 2>&1 || { echo "ERROR: ws bay needs yq (ws preflight)." >&2; exit 1; }

bay_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != *..* ]]; }
bay_dir() { printf '%s/%s\n' "$BAYS_DIR" "$1"; }
bay_require() {
    bay_name_ok "$1" || { echo "ERROR: Invalid bay name '$1'." >&2; exit 1; }
    [[ -f "$(bay_dir "$1")/scripts/ws" ]] || { echo "ERROR: No bay named '$1' under $BAYS_DIR." >&2; exit 1; }
}

# Run the bay's own ws, from the bay, with none of this workspace's roots in
# the environment: ws honours a pre-set ROOT_DIR and exports ECOSYSTEM_LOCAL,
# so an inherited value would point the bay's ws straight back at the parent.
bay_ws() { # <name> <args...>
    local dir; dir="$(bay_dir "$1")"; shift
    (cd "$dir" && env -u ROOT_DIR -u ECOSYSTEM -u ECOSYSTEM_LOCAL -u REALMS_DIR -u COMPONENTS_DIR -u HOARDS_DIR -u BAYS_DIR bash scripts/ws "$@")
}

yq_scalar() { # <file> <path> → the value, empty when absent or null
    local v=""
    [[ -f "$1" ]] && { v="$(yq -r "$2 // \"\"" "$1" 2>/dev/null)" || v=""; }
    [[ "$v" != "null" ]] || v=""
    printf '%s\n' "$v"
}
yq_list() { # <file> <path> → one item per line
    [[ -f "$1" ]] || return 0
    yq -r "($2 // [])[]" "$1" 2>/dev/null || true
}

bay_realm() { yq_scalar "$(bay_dir "$1")/ecosystem.local.yaml" .realm; }
bay_adapter_file() { # <name> <component>
    local realm; realm="$(bay_realm "$1")"
    [[ -n "$realm" ]] && printf '%s\n' "$(bay_dir "$1")/realms/$realm/adapters/$2.yaml"
}

# The one remote to clone from or reset to. One remote is no choice; with
# several, defaults.upstreamRemote (in any of the ecosystem files given)
# names it; otherwise an explicit <override> must, or the caller is told.
repo_remote() { # <dir> <override> <eco-file>...
    local dir="$1" want="$2" n up f
    shift 2
    if [[ -n "$want" ]]; then
        git -C "$dir" remote get-url "$want" >/dev/null 2>&1 || { echo "ERROR: $dir has no remote '$want'." >&2; return 1; }
        printf '%s\n' "$want"; return 0
    fi
    n="$(git -C "$dir" remote | wc -l | tr -d ' ')"
    if [[ "$n" -eq 1 ]]; then git -C "$dir" remote; return 0; fi
    for f in "$@"; do
        up="$(yq_scalar "$f" .defaults.upstreamRemote)"
        if [[ -n "$up" ]] && git -C "$dir" remote get-url "$up" >/dev/null 2>&1; then printf '%s\n' "$up"; return 0; fi
    done
    echo "ERROR: $dir has $n remotes and none is named by defaults.upstreamRemote: $(git -C "$dir" remote | tr '\n' ' ')" >&2
    return 1
}

# The remote's default branch, from the remote-tracking HEAD git records at
# clone time; a remote added later gets it fetched once with set-head.
remote_default_branch() { # <dir> <remote>
    local b
    b="$(git -C "$1" symbolic-ref -q --short "refs/remotes/$2/HEAD" 2>/dev/null)" || b=""
    if [[ -z "$b" ]]; then
        git -C "$1" remote set-head "$2" --auto >/dev/null 2>&1 || return 1
        b="$(git -C "$1" symbolic-ref -q --short "refs/remotes/$2/HEAD" 2>/dev/null)" || return 1
    fi
    printf '%s\n' "${b#"$2/"}"
}

# The machine name this workspace goes by, the way ws hoard resolves it:
# `machine:` in ecosystem.local.yaml, else the short hostname, made safe.
parent_machine() {
    local raw
    raw="$(yq_scalar "$ECOSYSTEM_LOCAL" .machine)"
    [[ -n "$raw" ]] || { raw="${HOSTNAME:-$(hostname)}"; raw="${raw%%.*}"; }
    raw="$(printf '%s' "$raw" | tr -cs 'A-Za-z0-9._-' '-')"
    printf '%s\n' "${raw:-unknown}"
}

# Every git repository a reset or a dirt check touches, one per line: each
# component, then the nested repos its adapter declares by glob.
bay_component_repos() { # <name>
    local dir c g d
    dir="$(bay_dir "$1")"
    for c in "$dir"/components/*/; do
        c="${c%/}"
        [[ -d "$c/.git" ]] || continue
        printf '%s\n' "$c"
        while IFS= read -r g; do
            [[ -n "$g" ]] || continue
            for d in "$c"/$g; do [[ -d "$d/.git" ]] && printf '%s\n' "$d"; done
        done < <(yq_list "$(bay_adapter_file "$1" "$(basename "$c")")" .nested)
    done
}

cmd_add() {
    local name="$1" realm="" hoard="" from="" dir src url comp init r
    local -a with=()
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with)  [[ $# -ge 2 ]] || { echo "ERROR: --with needs a component." >&2; exit 1; }; with+=("$2"); shift 2 ;;
            --realm) [[ $# -ge 2 ]] || { echo "ERROR: --realm needs a name." >&2; exit 1; }; realm="$2"; shift 2 ;;
            --hoard) [[ $# -ge 2 ]] || { echo "ERROR: --hoard needs a URL." >&2; exit 1; }; hoard="$2"; shift 2 ;;
            --from)  [[ $# -ge 2 ]] || { echo "ERROR: --from needs a URL." >&2; exit 1; }; from="$2"; shift 2 ;;
            *) echo "ERROR: Unknown option '$1'." >&2; exit 1 ;;
        esac
    done
    bay_name_ok "$name" || { echo "ERROR: Invalid bay name '$name' (letters, digits, . _ -; no leading dot)." >&2; exit 1; }
    dir="$(bay_dir "$name")"
    [[ ! -e "$dir" ]] || { echo "ERROR: $dir already exists." >&2; exit 1; }
    mkdir -p "$BAYS_DIR"

    # The realm first, because the bay's local config names it: the parent's
    # active one unless --realm, and it must be checked out here so its remote
    # URL is known.
    [[ -n "$realm" ]] || realm="$(yq_scalar "$ECOSYSTEM_LOCAL" .realm)"
    if [[ -z "$realm" ]]; then
        local -a realms=()
        for r in "$REALMS_DIR"/*/; do [[ -d "$r/.git" ]] && realms+=("$(basename "$r")"); done
        [[ ${#realms[@]} -eq 1 ]] && realm="${realms[0]}"
    fi
    [[ -n "$realm" ]] || { echo "ERROR: No active realm to give the bay; pass --realm <name>." >&2; exit 1; }
    [[ -d "$REALMS_DIR/$realm/.git" ]] || { echo "ERROR: Realm '$realm' is not checked out at $REALMS_DIR/$realm." >&2; exit 1; }
    src="$(repo_remote "$REALMS_DIR/$realm" "" "$ECOSYSTEM_LOCAL" "$REALMS_DIR/$realm/ecosystem.yaml")" || exit 1
    url="$(git -C "$REALMS_DIR/$realm" remote get-url "$src")"

    # Where the workspace itself comes from.
    if [[ -z "$from" ]]; then
        if ! src="$(repo_remote "$ROOT_DIR" "" "$ECOSYSTEM_LOCAL" "$ECOSYSTEM")"; then
            echo "  Pass --from <url> to say which yggdrasil the bay clones." >&2
            exit 1
        fi
        from="$(git -C "$ROOT_DIR" remote get-url "$src")"
    fi
    echo "bay add $name: cloning $from"
    git clone --quiet "$from" "$dir"

    # Machine-local config: this workspace's identity and overrides, no realm
    # trust (the bay approves its own realm below), the realm named, and a
    # machine name of its own so a hoard here gets its own Thalamus file.
    local machine; machine="$(parent_machine)-$name"
    if [[ -f "$ECOSYSTEM_LOCAL" ]]; then
        BAY_REALM="$realm" BAY_MACHINE="$machine" yq 'del(._gdd) | .realm = strenv(BAY_REALM) | .machine = strenv(BAY_MACHINE)' "$ECOSYSTEM_LOCAL" > "$dir/ecosystem.local.yaml"
    else
        BAY_REALM="$realm" BAY_MACHINE="$machine" yq -n '.realm = strenv(BAY_REALM) | .machine = strenv(BAY_MACHINE)' > "$dir/ecosystem.local.yaml"
    fi

    echo "bay add $name: realm $realm from $url"
    bay_ws "$name" realm "$url"
    bay_ws "$name" realm use "$realm" --trust

    # ${with[@]+"${with[@]}"}: an empty array expands to nothing under set -u on
    # bash 3.2, where a bare "${with[@]}" is an unbound-variable error.
    local with_label=""
    for comp in ${with[@]+"${with[@]}"}; do
        echo "bay add $name: cloning $comp"
        bay_ws "$name" clone "$comp"
        init="$(yq_scalar "$(bay_adapter_file "$name" "$comp")" .provision.init)"
        if [[ -n "$init" ]]; then
            echo "bay add $name: provisioning $comp: $init"
            (cd "$dir/components/$comp" && bash -c "$init")
        fi
        with_label="${with_label:+$with_label }$comp"
    done
    if [[ -n "$hoard" ]]; then
        echo "bay add $name: hoard $hoard"
        bay_ws "$name" hoard "$hoard"
    fi
    echo "bay add $name: ready at $dir (realm $realm${with_label:+, components $with_label}, machine $machine)"
}

# Fetch, hard-reset and switch one repository to <remote>'s default branch (or
# <branch>), then clean. Records the directory under <fails> on any failure so
# the parallel caller can name it.
reset_one() { # <dir> <remote> <branch-or-empty> <deep:yes|no> <fails-dir>
    local d="$1" remote="$2" branch="$3" deep="$4" fails="$5" key clean="-qfd"
    key="$(printf '%s' "$d" | tr '/:\\' '___')"
    [[ "$deep" == yes ]] && clean="-qfdx"
    if [[ -z "$branch" ]] && ! branch="$(remote_default_branch "$d" "$remote")"; then
        printf '%s (no default branch on remote %s)\n' "$d" "$remote" > "$fails/$key"
        return 0
    fi
    if git -C "$d" fetch --quiet "$remote" \
        && git -C "$d" reset -q --hard \
        && git -C "$d" switch -q -C "$branch" "$remote/$branch" \
        && git -C "$d" clean $clean; then
        return 0
    fi
    printf '%s\n' "$d" > "$fails/$key"
    return 0
}

cmd_reset() {
    local name="$1" deep=no dir realm fails failed=0 started r comp adapter st
    local td tdeep remote override obranch rd c t
    local -a pids=()
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deep) deep=yes; shift ;;
            *) echo "ERROR: Unknown option '$1'." >&2; exit 1 ;;
        esac
    done
    bay_require "$name"
    dir="$(bay_dir "$name")"; realm="$(bay_realm "$name")"
    started="$(date +%s)"
    fails="$(mktemp -d)"

    # The bay's root and its realm go first, one after the other, and never
    # deep-clean (their ignored paths are the clones themselves): the realm's
    # adapters say how the components are reset, so they must be current
    # before the component plan is read from them.
    local -a plan=()
    for r in "$dir" ${realm:+"$dir/realms/$realm"}; do
        [[ -d "$r/.git" ]] || continue
        if ! remote="$(repo_remote "$r" "" "$dir/ecosystem.local.yaml" "$dir/realms/$realm/ecosystem.yaml")"; then
            printf '%s\n' "$r" > "$fails/$(printf '%s' "$r" | tr '/:\\' '___')"
            continue
        fi
        reset_one "$r" "$remote" "" no "$fails"
        plan+=("$r"$'\t'no$'\t'$'\t')
    done
    while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        comp="${r#"$dir"/components/}"; comp="${comp%%/*}"
        override=""; obranch=""
        if [[ "$r" == "$dir/components/$comp" ]]; then
            adapter="$(bay_adapter_file "$name" "$comp")"
            override="$(yq_scalar "$adapter" .provision.remote)"
            obranch="$(yq_scalar "$adapter" .provision.branch)"
        fi
        plan+=("$r"$'\t'"$deep"$'\t'"$override"$'\t'"$obranch")
    done < <(bay_component_repos "$name")
    echo "reset $name: ${#plan[@]} repositories (deep=$deep)"

    for t in "${plan[@]}"; do
        IFS=$'\t' read -r td tdeep override obranch <<< "$t"
        [[ "$td" != "$dir" && "$td" != "$dir/realms/$realm" ]] || continue   # already done, above
        if ! remote="$(repo_remote "$td" "$override" "$dir/ecosystem.local.yaml" "$dir/realms/$realm/ecosystem.yaml")"; then
            printf '%s\n' "$td" > "$fails/$(printf '%s' "$td" | tr '/:\\' '___')"
            continue
        fi
        reset_one "$td" "$remote" "$obranch" "$tdeep" "$fails" &
        pids+=("$!")
        # At most RESET_PARALLEL in flight: wait for the oldest. `wait -n`
        # would be the natural throttle but needs bash 4.3, and the dispatcher
        # runs on the 3.2 a stock Mac ships.
        if [[ ${#pids[@]} -ge "$RESET_PARALLEL" ]]; then
            wait "${pids[0]}" || true
            pids=(${pids[@]+"${pids[@]:1}"})
        fi
    done
    wait
    for r in "$fails"/*; do
        [[ -e "$r" ]] || continue
        echo "reset $name: FAILED in $(cat "$r")" >&2
        failed=1
    done
    rm -rf "$fails"
    if [[ "$failed" -ne 0 ]]; then
        echo "ERROR: reset $name: some repositories could not be reset; runtime directories were left alone." >&2
        exit 1
    fi

    # Runtime directories the adapter names: ignored by git, written by the
    # program, not part of any known state. Relative to the component.
    for c in "$dir"/components/*/; do
        c="${c%/}"
        [[ -d "$c/.git" ]] || continue
        while IFS= read -r rd; do
            [[ -n "$rd" ]] || continue
            case "$rd" in
                /*|*..*) echo "ERROR: provision.runtime_dirs entry '$rd' must be a relative path inside the component." >&2; exit 1 ;;
            esac
            rm -rf "${c:?}/$rd"
        done < <(yq_list "$(bay_adapter_file "$name" "$(basename "$c")")" .provision.runtime_dirs)
    done

    # Every repository must now be clean, or the reset did not do its job. A
    # status that cannot be read is not clean either.
    for t in "${plan[@]}"; do
        IFS=$'\t' read -r td tdeep override obranch <<< "$t"
        if ! st="$(git -C "$td" status --porcelain 2>&1)"; then
            echo "reset $name: cannot read the status of $td: $st" >&2
            failed=1
        elif [[ -n "$st" ]]; then
            echo "reset $name: $td is still dirty" >&2
            failed=1
        fi
    done
    [[ "$failed" -eq 0 ]] || exit 1
    echo "reset $name: clean in $(( $(date +%s) - started )) s"
}

cmd_list() {
    local d name realm comps c
    for d in "$BAYS_DIR"/*/; do
        [[ -f "$d/scripts/ws" ]] || continue
        name="$(basename "$d")"
        realm="$(bay_realm "$name")"
        comps=""
        for c in "$d"components/*/; do
            [[ -d "$c/.git" ]] && comps="${comps:+$comps,}$(basename "$c")"
        done
        printf '%s\t%s\t%s\n' "$name" "${realm:--}" "$comps"
    done
}

cmd_rm() {
    local name="$1" force="${2:-}" dir realm r dirty=0 st
    bay_require "$name"
    dir="$(bay_dir "$name")"; realm="$(bay_realm "$name")"
    [[ -z "$force" || "$force" == "--force" ]] || { echo "ERROR: Unknown option '$force'." >&2; exit 1; }
    # The bay's root, its realm clone, every component and every nested repo:
    # the same set a reset touches, since any of them can hold work.
    while IFS= read -r r; do
        [[ -n "$r" && -d "$r/.git" ]] || continue
        if ! st="$(git -C "$r" status --porcelain 2>&1)"; then
            echo "bay rm $name: cannot read the status of $r: $st" >&2
            dirty=1
        elif [[ -n "$st" ]]; then
            echo "bay rm $name: $r has uncommitted work" >&2
            dirty=1
        fi
    done < <(printf '%s\n' "$dir" ${realm:+"$dir/realms/$realm"}; bay_component_repos "$name")
    if [[ "$dirty" -ne 0 && "$force" != "--force" ]]; then
        echo "ERROR: Refusing to remove a bay with uncommitted work; commit or push it first, or pass --force." >&2
        exit 1
    fi
    case "$dir" in "$BAYS_DIR"/?*) ;; *) echo "ERROR: $dir is not under $BAYS_DIR." >&2; exit 1 ;; esac
    rm -rf "$dir"
    echo "bay rm $name: removed $dir"
}

case "${1:-}" in
    add)   shift; [[ $# -ge 1 ]] || { echo "ERROR: ws bay add <name> [...]" >&2; exit 1; }; cmd_add "$@" ;;
    reset) shift; [[ $# -ge 1 ]] || { echo "ERROR: ws bay reset <name> [--deep]" >&2; exit 1; }; cmd_reset "$@" ;;
    list)  cmd_list ;;
    dir)   shift; [[ $# -eq 1 ]] || { echo "ERROR: ws bay dir <name>" >&2; exit 1; }; bay_require "$1"; bay_dir "$1" ;;
    exec)  shift; [[ $# -ge 2 ]] || { echo "ERROR: ws bay exec <name> <ws-args...>" >&2; exit 1; }; bay_require "$1"; bay_ws "$@" ;;
    rm)    shift; [[ $# -ge 1 ]] || { echo "ERROR: ws bay rm <name> [--force]" >&2; exit 1; }; cmd_rm "$@" ;;
    *) echo "ERROR: ws bay {add|list|reset|dir|exec|rm} ...; see ws bay --help" >&2; exit 1 ;;
esac
