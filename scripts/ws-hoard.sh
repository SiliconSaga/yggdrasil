#!/usr/bin/env bash
# ws-hoard.sh — Hoard management
# ws:use-when managing oddly shaped (non-code) collections (thalami, vaults)
#
# Subcommands (called via ws hoard):
#   init [template] [args...]   Scaffold a new hoard locally
#                               (template defaults to 'thalami')
#   <git-url>                   Clone an existing hoard from a git URL
#   list                        Show hoards and which thalami hoard is active
#
# Templates ship under templates/hoards/<name>/.
# Currently shipped: thalami.

# Apply strict mode only when executed directly, NOT when sourced —
# many callers don't want errexit/nounset/pipefail in their shell.
# When executed, strict mode is enabled before any top-level command
# (notably the `source ws-realm.sh` below) so a failed source
# fail-fasts instead of producing confusing downstream errors.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${HOARDS_DIR:="$ROOT_DIR/hoards"}"
: "${TEMPLATES_DIR:="$ROOT_DIR/templates"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"   # for ws_resolve_ecosystem
# shellcheck source=ws-hoard-upgrade.sh
source "$SCRIPT_DIR/ws-hoard-upgrade.sh"   # for ws_hoard_upgrade

# Resolve identity.human_account from merged ecosystem config.
# Errors with guidance if unset — used for the initial commit
# attribution, the printed `gh repo create` URL, and the recommended
# remote name when scaffolding a hoard. Hoard *directory* names no
# longer carry a username suffix, so this is no longer needed for the
# directory itself, but the three uses above still depend on it.
ws_resolve_human_account() {
    local eco
    eco="$(ws_resolve_ecosystem)"
    local who
    who="$(yq '.identity.human_account // ""' "$eco" 2>/dev/null)"
    if [[ -z "$who" || "$who" == "null" ]]; then
        echo "ERROR: identity.human_account is not set." >&2
        echo "  Set it in ecosystem.local.yaml — used for the initial commit" >&2
        echo "  attribution, the printed gh repo create URL, and the" >&2
        echo "  recommended remote name. Example:" >&2
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
    local raw=""
    # Same yq-tolerance as ws_detect_thalami_hoard: read the
    # `machine:` override only if the file exists AND yq is
    # available. Fresh-machine `ws hoard thalamus-path` flows here
    # and must not abort if yq isn't installed yet.
    if [[ -f "$local_file" ]] && command -v yq &>/dev/null; then
        raw="$(yq '.machine // ""' "$local_file" 2>/dev/null)" || raw=""
        [[ "$raw" == "null" ]] && raw=""
    fi
    if [[ -z "$raw" ]]; then
        # ${HOSTNAME%%.*} keeps everything before the first dot.
        # If $HOSTNAME isn't set (rare), fall back to plain `hostname`.
        local h="${HOSTNAME:-$(hostname)}"
        raw="${h%%.*}"
    fi
    # Sanitize to filesystem-safe characters. Hostnames or override
    # values with spaces, colons, backslashes, etc. would otherwise
    # produce broken thalamus filenames (`hoards/thalami-X/My PC-thalamus.md`
    # is fine on disk but ugly; colons are illegal on Windows/macOS).
    # `tr -cs` replaces any character not in the allowed set with a
    # single dash, squeezing consecutive replacements. `printf '%s'`
    # avoids tr eating the trailing newline into a trailing dash.
    local sanitized
    sanitized="$(printf '%s' "$raw" | tr -cs 'A-Za-z0-9._-' '-')"
    # Defensive default: if sanitization left nothing useful (raw was
    # empty or all-bad-chars), fall back to a placeholder rather than
    # producing `<empty>-thalamus.md` or `--thalamus.md`.
    [[ -z "$sanitized" || "$sanitized" == "-" ]] && sanitized="unknown"
    echo "$sanitized"
}

# Detect the active thalami hoard.
# Returns the hoard directory name (not full path), or empty.
#
# Discovery rule:
#   1. ecosystem.local.yaml `hoards.thalami:` selector
#   2. Single `thalami` or `thalami-*` directory in hoards/
#      (current default is plain `thalami`; legacy `thalami-<user>` form
#      stays supported indefinitely)
#   3. None
ws_detect_thalami_hoard() {
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    # Read the selector via yq IF the config file exists AND yq is
    # actually installed. Lightweight subcommands like `ws hoard
    # thalamus-path` are exempt from the global yq guard so they
    # work on fresh machines; this function gets called by those
    # paths and must not fail when yq is absent. Without yq we just
    # skip the selector lookup and rely on the disk-walk below.
    if [[ -f "$local_file" ]] && command -v yq &>/dev/null; then
        local selector
        selector="$(yq '.hoards.thalami // ""' "$local_file" 2>/dev/null)" || selector=""
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$HOARDS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi

    local candidates=()
    if [[ -d "$HOARDS_DIR" ]]; then
        # Match the current `thalami` default and the legacy `thalami-*`
        # form. Both globs are evaluated; the [[ -d ]] guard filters out
        # any literal that didn't expand.
        for d in "$HOARDS_DIR"/thalami "$HOARDS_DIR"/thalami-*/; do
            [[ -d "$d" ]] || continue
            candidates+=("$(basename "$d")")
        done
    fi

    case "${#candidates[@]}" in
        0) echo "" ;;
        1) echo "${candidates[0]}" ;;
        *)
            echo "ERROR: Multiple thalami hoards found in hoards/: ${candidates[*]}." >&2
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

# Classify a hoard directory by flavor.
# Echoes a comma-separated list of flavors, or empty if none.
# Argument is the hoard directory path. Flavors stack — a hoard can
# carry multiple flavors.
#
# Detection rules:
#   thalami  — directory name is bare `thalami` or matches `thalami-*`
#   obsidian — has a `.obsidian/` subdirectory
ws_classify_hoard() {
    local hoard_path="$1"
    local hoard_name
    hoard_name="$(basename "$hoard_path")"
    local flavors=()

    # thalami: name pattern (matches existing ws_detect_thalami_hoard
    # convention — bare `thalami` is the current default for `ws hoard
    # init`, plus the legacy `thalami-*` suffixed form).
    if [[ "$hoard_name" == "thalami" || "$hoard_name" == thalami-* ]]; then
        flavors+=("thalami")
    fi

    # obsidian: .obsidian/ directory present
    if [[ -d "$hoard_path/.obsidian" ]]; then
        flavors+=("obsidian")
    fi

    if [[ ${#flavors[@]} -eq 0 ]]; then
        echo ""
    else
        local IFS=,
        echo "${flavors[*]}"
    fi
}

# Iterate hoards/ and emit a YAML inventory with flavor classification.
# Optional flags:
#   --flavor <name>   Only emit hoards containing the named flavor.
#                     Concrete flavors: thalami, obsidian.
#                     Meta-flavors: vault (matches obsidian).
#                     Meta-flavors are query-time only — they never appear
#                     in the recorded `flavors:` array of the YAML output.
#   --names-only      Emit just hoard names (one per line) — for shell pipelines
ws_hoard_scan() {
    local filter_flavor=""
    local names_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --flavor)
                if [[ -z "${2:-}" ]]; then
                    echo "ERROR: --flavor requires a value" >&2
                    return 2
                fi
                filter_flavor="$2"
                shift 2
                ;;
            --names-only)
                names_only=true
                shift
                ;;
            -h|--help)
                echo "Usage: ws hoard scan [--flavor <name>] [--names-only]" >&2
                echo "" >&2
                echo "Emit a YAML inventory of hoards/ classified by flavor." >&2
                echo "" >&2
                echo "Flavors detected:" >&2
                echo "  thalami       — directory name is 'thalami' or matches thalami-*" >&2
                echo "  obsidian      — contains .obsidian/" >&2
                echo "" >&2
                echo "Flags:" >&2
                echo "  --flavor <name>   Only emit hoards containing the named flavor." >&2
                echo "                    Concrete flavors: thalami, obsidian." >&2
                echo "                    Meta-flavors: vault (currently equiv to obsidian)." >&2
                echo "  --names-only      Emit just hoard names, one per line." >&2
                return 0
                ;;
            *)
                echo "ERROR: Unknown flag: $1" >&2
                return 2
                ;;
        esac
    done

    [[ -d "$HOARDS_DIR" ]] || return 0

    # Iterate via find + sort under LC_ALL=C so YAML output order is
    # stable across filesystems and locales (design contract — the
    # gdd-scribe skill and other consumers depend on reproducible output).
    local d hoard_name flavors_csv
    while IFS= read -r d; do
        [[ -d "$d" ]] || continue
        hoard_name="$(basename "$d")"
        flavors_csv="$(ws_classify_hoard "$d")"

        # Apply --flavor filter
        if [[ -n "$filter_flavor" ]]; then
            local found=false
            local IFS=,
            for f in $flavors_csv; do
                if [[ "$f" == "$filter_flavor" ]]; then
                    found=true
                    break
                fi
                # Meta-flavor: `vault` currently matches just `obsidian`.
                # Kept as an indirection in case other vault concrete
                # flavors return later. Query-time only — does not
                # appear in the recorded YAML `flavors:` array.
                if [[ "$filter_flavor" == "vault" ]] && \
                   [[ "$f" == "obsidian" ]]; then
                    found=true
                    break
                fi
            done
            $found || continue
        fi

        if $names_only; then
            echo "$hoard_name"
        else
            echo "- name: $hoard_name"
            echo "  path: $d"
            if [[ -z "$flavors_csv" ]]; then
                echo "  flavors: []"
            else
                # Convert "a,b" → "[a, b]" for inline YAML list form
                local yaml_list="${flavors_csv//,/, }"
                echo "  flavors: [$yaml_list]"
            fi
        fi
        # Discovery semantics — keep aligned with ws_hoard_list's bash glob:
        #   * Hidden directories (`.cache/`, `.git/`, ...) are skipped via
        #     `! -name '.*'` because the default bash glob `*/` doesn't
        #     match leading dots either.
        #   * `-L` follows symlinks-to-directories so hoards that the user
        #     symlinked in from elsewhere show up here just like they do
        #     in `ws hoard list` (which, being a bash glob, follows them
        #     by default). DO NOT drop `-maxdepth 1` without rethinking
        #     this — combined with `-L` it's the guard against pathological
        #     symlink loops; we don't recurse, so there's nothing to loop on.
    done < <(LC_ALL=C find -L "$HOARDS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name '.*' -print 2>/dev/null | LC_ALL=C sort)
}

ws_hoard_help() {
    # Enumerate available templates from disk so the help text never drifts
    # from what ships under templates/hoards/. Sort under LC_ALL=C for
    # stable, locale-independent output. macOS find lacks GNU's `-printf`,
    # so cd into the dir and strip the leading `./` for portability.
    local templates_list
    if [[ -d "$TEMPLATES_DIR/hoards" ]]; then
        templates_list="$(
            cd "$TEMPLATES_DIR/hoards" && \
            LC_ALL=C find . -maxdepth 1 -mindepth 1 -type d ! -name '.*' -print 2>/dev/null \
                | sed 's|^\./||' \
                | LC_ALL=C sort \
                | tr '\n' ',' \
                | sed 's/,/, /g; s/, $//'
        )"
    fi
    [[ -z "${templates_list:-}" ]] && templates_list="(none)"

    echo "Usage: ws hoard <subcommand> [args...]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init [template] [--name <name>] [template-args]" >&2
    echo "                           Scaffold a new hoard locally (default template: thalami)" >&2
    echo "                           --name overrides the directory name" >&2
    echo "                           (default: <template> — same as the template name)" >&2
    echo "                           Available templates: $templates_list" >&2
    echo "                           Per-template args:" >&2
    echo "                             thalami --from-thalamus" >&2
    echo "                                  Move root Thalamus.md into the new hoard" >&2
    echo "  <git-url>                Clone an existing hoard" >&2
    echo "  list                     Show hoards and which thalami hoard is active" >&2
    echo "  scan [--flavor <name>] [--names-only]" >&2
    echo "                           Emit a YAML inventory of hoards classified by" >&2
    echo "                           flavor (thalami / obsidian)" >&2
    echo "  cadence                  Report dirty/staleness of the active per-machine" >&2
    echo "                           thalamus file (used by gdd-orientation Step 0a)" >&2
    echo "  thalamus-path            Print the resolved path to the active per-machine" >&2
    echo "                           thalamus file (empty if no active hoard)" >&2
    echo "  upgrade <hoard> [--plan|--apply|--rollback] [--template <name>]" >&2
    echo "                           Provenance-tracked upgrade from the hoard's" >&2
    echo "                           template (.hoard.yaml). --plan previews;" >&2
    echo "                           --apply backs up then applies; --rollback" >&2
    echo "                           restores the last backup. The gdd-hoard-upgrade" >&2
    echo "                           skill drives the propose-then-apply flow." >&2
}

# Read staleness_days from a hoard's `.ws-cadence.yaml`. Defaults to 2
# if the file is absent or the field isn't set. Argument is the hoard
# directory path (the file lives at `<hoard_path>/.ws-cadence.yaml`).
#
# Hoard-wide config, committable, shared across the hoard's machines —
# replaces the earlier per-machine `commit_staleness_days` frontmatter
# field that lived in `<machine>-thalamus.md`. Hoard-wide is the right
# scope: the cadence threshold is a workflow preference for the user,
# not a per-machine value.
ws_hoard_read_staleness_days() {
    local hoard_path="$1"
    local config="$hoard_path/.ws-cadence.yaml"
    [[ -f "$config" ]] || { echo 2; return; }
    # Capture yq's exit status separately so a YAML parse error or
    # other tooling failure surfaces a warning, instead of silently
    # collapsing to the same "field not set → default 2" path. A
    # corrupt config should be fixable, not invisible.
    local value
    local yq_stderr
    yq_stderr="$(mktemp)"
    if ! value="$(yq '.staleness_days // ""' "$config" 2>"$yq_stderr")"; then
        echo "WARNING: $config: yq failed to parse — falling back to 2 days." >&2
        [[ -s "$yq_stderr" ]] && sed 's/^/  yq: /' "$yq_stderr" >&2
        rm -f "$yq_stderr"
        echo 2
        return
    fi
    rm -f "$yq_stderr"
    [[ "$value" == "null" ]] && value=""
    [[ -z "$value" ]] && { echo 2; return; }
    # Validate: must be a non-negative integer. The cadence math
    # downstream feeds this into `(( threshold_days * 86400 ))`; a
    # non-numeric or negative value would break classification or
    # error out. Warn loudly and fall back to the default rather than
    # silently misbehaving.
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "WARNING: $config: staleness_days='$value' is not a non-negative integer; falling back to 2." >&2
        echo 2
        return
    fi
    echo "$value"
}

# Report cadence state for the active per-machine thalamus file.
# Output is `key: value` lines on stdout — easy for the orientation
# skill (or any caller) to grep. Always exit 0 except on tooling
# failure; "nothing to check" is a status, not an error.
#
# Statuses:
#   clean             — file exists, has no uncommitted changes
#   dirty-fresh       — dirty, last commit within threshold (no nudge)
#   dirty-stale       — dirty, last commit older than threshold (nudge!)
#   never-committed   — dirty, no prior commit for this file at all
#   no-active-hoard   — no thalami hoard found
#   no-thalamus-file  — active hoard but expected file isn't on disk
ws_hoard_cadence() {
    local hoard
    hoard="$(ws_detect_thalami_hoard)"
    if [[ -z "$hoard" ]]; then
        echo "status: no-active-hoard"
        return 0
    fi

    # Build the thalamus path from the already-resolved $hoard rather
    # than calling ws_resolve_thalamus_path() (which re-runs hoard
    # detection internally). Keeps this function single-pass.
    local machine
    machine="$(ws_resolve_machine_name)"
    local machine_file="${machine}-thalamus.md"
    local hoard_path="$HOARDS_DIR/$hoard"
    local thalamus_path="$hoard_path/$machine_file"

    if [[ ! -f "$thalamus_path" ]]; then
        # Could legitimately mean "first session on this machine,
        # template-copy hasn't happened yet." Caller decides what to
        # do; we just report.
        echo "status: no-thalamus-file"
        echo "file: $thalamus_path"
        return 0
    fi

    local threshold_days
    threshold_days="$(ws_hoard_read_staleness_days "$hoard_path")"
    local threshold_seconds=$(( threshold_days * 86400 ))

    # File-scoped dirty check via porcelain. Empty output = clean;
    # non-empty (including untracked `??`) = dirty. Capture git's
    # exit status explicitly — without the `if !` guard, a tooling
    # failure (corrupt repo, permission denied, etc.) would yield an
    # empty `$porcelain` and we'd misreport `clean`.
    local porcelain
    if ! porcelain="$(git -C "$hoard_path" status --porcelain -- "$machine_file" 2>/dev/null)"; then
        echo "ERROR: failed to read git status for '$machine_file' in '$hoard_path'." >&2
        return 1
    fi

    if [[ -z "$porcelain" ]]; then
        echo "status: clean"
        echo "file: $thalamus_path"
        echo "threshold_days: $threshold_days"
        return 0
    fi

    # Dirty. Need timestamp to classify fresh vs stale vs never.
    # Same exit-status guard as the porcelain call above — otherwise
    # a git failure would silently look like "no prior commit."
    local last_commit_ts
    if ! last_commit_ts="$(git -C "$hoard_path" log -1 --format=%ct -- "$machine_file" 2>/dev/null)"; then
        echo "ERROR: failed to read git history for '$machine_file' in '$hoard_path'." >&2
        return 1
    fi

    if [[ -z "$last_commit_ts" ]]; then
        echo "status: never-committed"
        echo "file: $thalamus_path"
        echo "threshold_days: $threshold_days"
        return 0
    fi

    local now_ts
    now_ts="$(date +%s)"
    local elapsed_seconds=$(( now_ts - last_commit_ts ))
    local elapsed_days=$(( elapsed_seconds / 86400 ))
    local elapsed_hours=$(( (elapsed_seconds % 86400) / 3600 ))

    local status="dirty-fresh"
    [[ "$elapsed_seconds" -gt "$threshold_seconds" ]] && status="dirty-stale"

    echo "status: $status"
    echo "file: $thalamus_path"
    echo "elapsed_days: $elapsed_days"
    echo "elapsed_hours: $elapsed_hours"
    echo "threshold_days: $threshold_days"
    echo "last_commit_unix: $last_commit_ts"
}

# Init a hoard from a template that uses `template.yaml` for clone-on-init
# semantics (instead of the standard cp -R). Returns 0 on success, 1 if
# the template doesn't have a template.yaml (caller should fall back to
# the standard flow), or exits non-zero on actual failure.
#
# Args:
#   $1 — template directory (e.g. a future templates/hoards/<name>)
#   $2 — target hoard directory (e.g. hoards/my-vault)
#
# template.yaml schema:
#   upstream: <url>     — required; git URL to clone from
#   pin: <ref>          — optional; git ref to check out post-clone
#   fallback: <url>     — optional; tried if upstream clone fails
#   post_clone:         — ordered list of post-clone step names
#     - strip_git       — rm -rf .git so ws_hoard_init's git init can re-init
#     - apply_bridge    — overlay <template>/gdd-bridge/* into the clone
ws_hoard_init_from_yaml() {
    local template_dir="$1"
    local target="$2"
    local manifest="$template_dir/template.yaml"

    [[ -f "$manifest" ]] || return 1   # Not a yaml-driven template

    # The top-level dispatch already enforces yq for any subcommand that
    # could land here, but keep a defensive check — ws_hoard_init() can
    # also be called from sourced contexts that bypassed the dispatcher.
    if ! command -v yq &>/dev/null; then
        echo "ERROR: yq (v4+) is required for yaml-driven hoard templates." >&2
        echo "  Install: https://github.com/mikefarah/yq" >&2
        exit 1
    fi

    local upstream pin fallback
    upstream="$(yq '.upstream // ""' "$manifest" 2>/dev/null)"
    pin="$(yq '.pin // ""' "$manifest" 2>/dev/null)"
    fallback="$(yq '.fallback // ""' "$manifest" 2>/dev/null)"

    [[ "$upstream" == "null" ]] && upstream=""
    [[ "$pin" == "null" ]] && pin=""
    [[ "$fallback" == "null" ]] && fallback=""

    if [[ -z "$upstream" ]]; then
        echo "ERROR: $manifest is missing the 'upstream' field." >&2
        exit 1
    fi
    if [[ ! "$pin" =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "ERROR: $manifest must set 'pin' to a full 40-character commit SHA." >&2
        exit 1
    fi
    git_remote_validate "$upstream" local
    if [[ -n "$fallback" ]]; then
        git_remote_validate "$fallback" local
    fi

    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    git_auth_env_for_url "$upstream"
    echo "Cloning $upstream into $target..."
    if ! env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git clone -- "$upstream" "$target" 2>/dev/null; then
        if [[ -n "$fallback" ]]; then
            # The failed upstream clone may have left $target half-populated
            # (partial fetch, broken .git/, etc.). Wipe it before retrying so
            # the fallback clone starts from a clean target path.
            rm -rf "$target"
            echo "  Upstream clone failed; trying fallback: $fallback" >&2
            git_auth_env_for_url "$fallback"
            if ! env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git clone -- "$fallback" "$target" 2>/dev/null; then
                echo "ERROR: clone failed for both upstream and fallback." >&2
                echo "  upstream: $upstream" >&2
                echo "  fallback: $fallback" >&2
                exit 1
            fi
        else
            echo "ERROR: clone failed and no fallback configured." >&2
            echo "  upstream: $upstream" >&2
            echo "  Check network access or update the manifest:" >&2
            echo "    $manifest" >&2
            exit 1
        fi
    fi

    # The manifest pin is mandatory and immutable. A detached checkout avoids
    # silently following a mutable branch or tag on later runs.
    if ! git -C "$target" checkout -q --detach "$pin"; then
        echo "ERROR: failed to check out pin '$pin' in $target." >&2
        echo "  Verify the full commit SHA exists in the cloned upstream's history." >&2
        exit 1
    fi

    # Iterate post_clone steps in the manifest's declared order, so future
    # templates can reorder steps without code changes here.
    # Contract: step names must be CSV-safe shell tokens — no commas, no
    # quoting, no whitespace. `yq -o=csv` would otherwise emit quoted
    # fields and break this naive split-on-comma loop.
    local steps_csv
    steps_csv="$(yq -o=csv '.post_clone // []' "$manifest" 2>/dev/null | tr -d '\r')"
    if [[ -n "$steps_csv" ]]; then
        local IFS=,
        local step
        for step in $steps_csv; do
            # Skip blanks (e.g. trailing comma artifacts from yq -o=csv)
            [[ -z "$step" ]] && continue
            case "$step" in
                strip_git)
                    # Strip cloned .git so the upcoming git init in
                    # ws_hoard_init() can re-init this as the user's own repo
                    # (matches the standard flow's post-condition).
                    rm -rf "$target/.git"
                    ;;
                apply_bridge)
                    # Overlay <template_dir>/gdd-bridge/* into target.
                    if [[ -d "$template_dir/gdd-bridge" ]]; then
                        cp -R "$template_dir/gdd-bridge/." "$target/"
                        echo "Applied gdd-bridge overlay."
                    fi
                    ;;
                *)
                    echo "WARNING: unknown post_clone step '$step' in $manifest; skipping." >&2
                    ;;
            esac
        done
    fi

    # Print optional /init-bootstrap tip if the cloned vault advertises one
    # in its README. We grep loosely so this works for any future template
    # that wants to surface a similar tip.
    local clone_readme="$target/README.md"
    if [[ -f "$clone_readme" ]] && grep -qiE 'init-bootstrap|bootstrap wizard' "$clone_readme" 2>/dev/null; then
        echo ""
        echo "Tip: this vault has an optional onboarding wizard. To run it:"
        echo "  cd $target"
        echo "  claude"
        echo "  /init-bootstrap"
        echo ""
    fi

    return 0
}

# ws_hoard_init [template] [--name <hoard-name>] [template-args...]
# Default template: thalami.
# --name overrides the hoard directory name (default: <template>).
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

    if [[ ! "$template" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid hoard template name '$template'." >&2
        exit 2
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

    # Parse --name and per-template args from remaining args
    local custom_name=""
    local from_thalamus=false
    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                [[ -z "${2:-}" ]] && { echo "ERROR: --name requires a value." >&2; exit 2; }
                custom_name="$2"
                shift 2
                ;;
            --name=*)
                custom_name="${1#--name=}"
                [[ -z "$custom_name" ]] && { echo "ERROR: --name requires a value." >&2; exit 2; }
                shift
                ;;
            --from-thalamus)
                from_thalamus=true
                shift
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#remaining_args[@]} -gt 0 ]]; then
        echo "ERROR: unexpected args for '$template' template: ${remaining_args[*]}" >&2
        exit 2
    fi

    # Validate custom name if given
    if [[ -n "$custom_name" ]]; then
        if [[ ! "$custom_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            echo "ERROR: --name must be a safe directory name (got: $custom_name)." >&2
            exit 2
        fi
    fi

    # Warn if a thalami hoard is being created with a non-conforming name.
    # ws_detect_thalami_hoard() globs `thalami` and `thalami-*`; anything
    # else won't be auto-detected as the active thalami without an explicit
    # selector in ecosystem.local.yaml. Warn rather than reject — the
    # selector is a perfectly valid escape hatch and the user may be doing
    # this on purpose.
    if [[ "$template" == "thalami" && -n "$custom_name" ]]; then
        if [[ "$custom_name" != "thalami" && "$custom_name" != thalami-* ]]; then
            echo "WARNING: --name '$custom_name' won't be auto-detected as the active thalami." >&2
            echo "  ws_detect_thalami_hoard() globs 'thalami' or 'thalami-*' only." >&2
            echo "  To use this hoard as the active thalami, set in ecosystem.local.yaml:" >&2
            echo "    hoards:" >&2
            echo "      thalami: $custom_name" >&2
            echo "" >&2
        fi
    fi

    # Resolve target directory: --name override, else <template>.
    # No username suffix — hoards live under hoards/ which is already
    # per-developer (gitignored), so an extra owner suffix is redundant
    # and forces an awkward name on whatever the user actually wants
    # to call this hoard.
    local hoard_name="${custom_name:-$template}"
    local target="$HOARDS_DIR/$hoard_name"
    if [[ -d "$target" ]]; then
        echo "ERROR: Hoard already exists at $target." >&2
        echo "  Remove it first if you want to start over." >&2
        exit 1
    fi

    # thalami-specific validation
    case "$template" in
        thalami) ;;  # --from-thalamus already parsed above
        *)
            if [[ "$from_thalamus" == true ]]; then
                echo "ERROR: --from-thalamus is only valid for the thalami template." >&2
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

    # Copy template directory — UNLESS this is a yaml-driven template,
    # in which case follow the clone-on-init flow instead. The helper
    # returns 1 to signal "no template.yaml; fall through to standard
    # cp -R"; on success it returns 0; on actual failure it exits.
    mkdir -p "$HOARDS_DIR"
    if ws_hoard_init_from_yaml "$template_dir" "$target"; then
        : # YAML-driven flow handled the clone + post-clone steps
    else
        # Standard flow: copy template files verbatim
        cp -R "$template_dir" "$target"
    fi

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

    # If the template ships an .upgrade/ recipe, run the upgrade phase against
    # the freshly-created hoard (install plugins, seed data.json, write
    # community-plugins.json, disable core plugins, splice managed regions).
    # Gate on the *template's* recipe, not on $target/.upgrade: the cp path
    # copies .upgrade into the instance, but the yaml-driven clone path does
    # not, so checking $target would skip the phase for clone-based templates.
    if [[ -f "$template_dir/.upgrade/upgrade.yaml" ]]; then
        # The cp path leaves a copy of .upgrade in the instance — strip it
        # (template-internal, not user content). The clone path won't have one.
        [[ -d "$target/.upgrade" ]] && rm -rf "$target/.upgrade"
        local _tmpl_name _applied_version
        _tmpl_name="$(basename "$template_dir")"
        _applied_version=0   # baseline: recipe not yet applied
        # Allow tests / offline / CI to opt out of the upgrade phase via
        # WS_HOARD_NO_UPGRADE=1 (it hits GitHub for plugin downloads).
        if [[ -z "${WS_HOARD_NO_UPGRADE:-}" ]]; then
            echo ""
            echo "Running upgrade phase from template..."
            if _ws_hoard_apply_manifest "$template_dir" "$target" \
                && _ws_hoard_apply_regions "$target" "$template_dir"; then
                _applied_version="$(_ws_hoard_manifest_version "$template_dir")"
            else
                echo "WARNING: upgrade phase failed; hoard is initialized but" >&2
                echo "  plugins/regions were not fully applied. Re-run" >&2
                echo "  \`ws hoard upgrade $hoard_name --apply\` to retry." >&2
            fi
        else
            echo "Skipping upgrade phase (WS_HOARD_NO_UPGRADE set). Run" >&2
            echo "  \`ws hoard upgrade $hoard_name --apply\` later to install plugins." >&2
        fi
        # Provenance reflects what was actually applied: the manifest version
        # on success, else 0 so a later --apply brings it current (rather than
        # a misleading "uptodate").
        _ws_hoard_provenance_write "$target" "$_tmpl_name" "$_applied_version"
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
            commit -q -m "Initial commit ($hoard_name hoard for ${who})"
    )

    echo ""
    echo "Hoard initialized: $target"
    echo ""
    echo "Push to your own remote when ready, e.g.:"
    echo "  gh repo create ${who}/${hoard_name} --private --source=${target#"$ROOT_DIR"/} --remote=${who} --push"
    echo ""
    echo "Or set up the remote manually (using ${who} as the remote name —"
    echo "the workspace convention is to avoid generic 'origin'):"
    echo "  cd $target"
    echo "  git remote add ${who} <your-url>"
    echo "  git push -u ${who} main"
}

ws_hoard_clone_url() {
    local url="$1"
    shift
    if [[ ! "$url" =~ ^(https?://|git@) ]]; then
        echo "ERROR: Unknown subcommand or invalid URL '$url'." >&2
        echo "  Run 'ws hoard' for usage." >&2
        exit 1
    fi

    # Parse --name from remaining args
    local custom_name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                [[ -z "${2:-}" ]] && { echo "ERROR: --name requires a value." >&2; exit 2; }
                custom_name="$2"; shift 2 ;;
            --name=*)
                custom_name="${1#--name=}"
                [[ -z "$custom_name" ]] && { echo "ERROR: --name requires a value." >&2; exit 2; }
                shift ;;
            *)
                echo "ERROR: unexpected arg for hoard clone: '$1'." >&2; exit 2 ;;
        esac
    done

    # Derive hoard directory name from --name or the URL's repo basename
    local repo_name
    if [[ -n "$custom_name" ]]; then
        repo_name="$custom_name"
    else
        repo_name="${url##*/}"
        repo_name="${repo_name%.git}"
    fi
    if [[ ! "$repo_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: hoard name must be a safe directory name (got: $repo_name)." >&2
        exit 1
    fi

    local target="$HOARDS_DIR/$repo_name"
    if [[ -d "$target" ]]; then
        echo "ERROR: Hoard '$repo_name' already exists at $target." >&2
        exit 1
    fi

    mkdir -p "$HOARDS_DIR"
    echo "CLONE: hoard -> $target"
    local -a GIT_AUTH_ENV=()
    local GIT_AUTH_LABEL="" GIT_AUTH_PROVIDER=""
    git_auth_env_for_url "$url"
    [[ -n "$GIT_AUTH_LABEL" ]] && echo "Using $GIT_AUTH_LABEL for HTTPS $GIT_AUTH_PROVIDER clone auth (no credential helper prompt)"
    git_remote_validate "$url" remote
    env ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"} git clone -- "$url" "$target"
    echo ""
    echo "Hoard cloned: $target"

    # Post-clone heuristic: if the cloned hoard looks like a thalami
    # (has at least one <machine>-thalamus.md file at its root) but the
    # local directory name won't be auto-detected by
    # ws_detect_thalami_hoard()'s `thalami` / `thalami-*` glob, point
    # the user at the explicit selector. We can't know it's a thalami
    # until after the clone, so the warning lives here rather than
    # pre-flight.
    if compgen -G "$target/*-thalamus.md" >/dev/null 2>&1; then
        if [[ "$repo_name" != "thalami" && "$repo_name" != thalami-* ]]; then
            echo "" >&2
            echo "NOTE: $target appears to be a thalami hoard (contains *-thalamus.md)" >&2
            echo "  but its name '$repo_name' won't be auto-detected as the active thalami." >&2
            echo "  ws_detect_thalami_hoard() globs 'thalami' or 'thalami-*' only." >&2
            echo "  To use this hoard as the active thalami, set in ecosystem.local.yaml:" >&2
            echo "    hoards:" >&2
            echo "      thalami: $repo_name" >&2
        fi
    fi
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
            if [[ -n "$active_thalami" && "$dname" == "$active_thalami" ]]; then
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

# Guard: if sourced by another script, stop here. Strict mode is
# already on (from the conditional at top) when we reach this point
# during direct execution, so no second `set -euo pipefail` needed.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

SUBCMD="${1:-}"
shift 2>/dev/null || true

# Subcommands that need yq enforce the dependency at top. Lightweight
# subcommands (--help, thalamus-path) deliberately skip it so they
# work on fresh machines that haven't installed yq yet — important
# for orientation flow where `ws hoard thalamus-path` is one of the
# first probes the agent runs and shouldn't error before the operator
# has even seen `ws preflight`'s install hints.
case "$SUBCMD" in
    ""|help|--help|-h|thalamus-path|scan) ;;
    *)
        if ! command -v yq &>/dev/null; then
            echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
            exit 1
        fi
        ;;
esac

case "$SUBCMD" in
    ""|help|--help|-h)
        ws_hoard_help
        ;;
    init)
        ws_hoard_init "$@"
        ;;
    list)
        ws_hoard_list
        ;;
    scan)
        ws_hoard_scan "$@"
        ;;
    cadence)
        ws_hoard_cadence
        ;;
    thalamus-path)
        # Echo the resolved path or empty if no active hoard. The
        # gdd-orientation skill calls this so it can probe the file
        # in one auto-approved command instead of compound shell.
        ws_resolve_thalamus_path
        ;;
    upgrade)
        ws_hoard_upgrade "$@"
        ;;
    *)
        ws_hoard_clone_url "$SUBCMD" "$@"
        ;;
esac
