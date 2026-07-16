#!/usr/bin/env bash
# ws-hoard-upgrade.sh — Provenance-tracked, plan-first hoard upgrades.
#
# A hoard records its source template + last-applied version in a
# git-committed .hoard.yaml. A template ships its recipe under
# templates/hoards/<flavor>/.upgrade/upgrade.yaml: a `version`, the desired
# plugins (pinned GitHub releases), core plugins to disable, files to remove,
# and `managed_regions` (sentinel-delimited blocks the template owns inside a
# content file). Design: docs/plans/2026-05-23-hoard-upgrade-v2-design.md.
#
# Flow (public: ws_hoard_upgrade):
#   --plan      Resolve the template via .hoard.yaml, diff desired-vs-live, and
#               print classified CLASS<TAB>DETAIL lines (uptodate / additive /
#               region-insert / region-edit / destructive). Changes nothing.
#   --apply     Snapshot the whole hoard to .upgrade-backup/<ts>/, run the
#               mechanical manifest apply (_ws_hoard_apply_manifest), splice
#               managed regions, then bump .hoard.yaml. Aborts before any
#               change if the backup fails.
#   --rollback  Restore the most recent pre-apply snapshot.
# The gdd-hoard-upgrade skill drives plan → propose → apply with a human gate
# on the destructive + region lines.
#
# _ws_hoard_upgrade_from_template stays as a thin alias to
# _ws_hoard_apply_manifest, so `ws hoard init`'s post-copy call is unchanged.
#
# Deferred (yggdrasil#77): plugin data.json is still overwrite-on-apply (no
# three-way merge yet), so a user's in-hoard data.json tweaks don't survive.

# Sourced by ws-hoard.sh; do not enable strict mode here.

# Resolve a manifest-controlled relative path and prove its deepest existing
# ancestor remains physically below ROOT. Reject absolute paths, parent
# traversal, Windows/UNC absolute forms, and symlink escapes. Prints the
# textual candidate path on success.
_ws_hoard_contained_path() {
    local root="$1" rel="$2" label="$3"
    if [[ "$rel" =~ [[:cntrl:]] ]]; then
        echo "ERROR: $label path contains a control character." >&2
        return 1
    fi
    if [[ -z "$rel" || "$rel" == /* || "$rel" == \\* || "$rel" =~ ^[A-Za-z]:[/\\] ]]; then
        echo "ERROR: $label '$rel' escapes the $label root (absolute or empty path)." >&2
        return 1
    fi
    case "$rel" in
        ..|../*|*/..|*/../*)
            echo "ERROR: $label '$rel' escapes the $label root (parent traversal)." >&2
            return 1
            ;;
    esac

    local root_real candidate probe probe_real
    root_real="$(cd "$root" 2>/dev/null && pwd -P)" || {
        echo "ERROR: cannot resolve $label root: $root" >&2
        return 1
    }
    candidate="$root/$rel"
    if [[ -L "$candidate" ]]; then
        echo "ERROR: $label '$rel' escapes the $label root (symlink target)." >&2
        return 1
    fi

    probe="$candidate"
    if [[ -e "$probe" && ! -d "$probe" ]]; then
        probe="${probe%/*}"
    fi
    while [[ ! -d "$probe" && "$probe" == */* ]]; do
        probe="${probe%/*}"
    done
    probe_real="$(cd "$probe" 2>/dev/null && pwd -P)" || {
        echo "ERROR: cannot resolve $label path '$rel'." >&2
        return 1
    }
    case "$probe_real/" in
        "$root_real/"*) printf '%s\n' "$candidate" ;;
        *)
            echo "ERROR: $label '$rel' escapes the $label root (symlinked ancestor)." >&2
            return 1
            ;;
    esac
}

_ws_hoard_validate_manifest_paths() {
    local hoard_dir="$1" template_dir="$2"
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    [[ -f "$upgrade_yaml" ]] || return 0

    local count i rel rfile rsrc plugin_id plugin_asset
    count="$(yq '.plugins // [] | length' "$upgrade_yaml")"
    i=0
    while [[ $i -lt $count ]]; do
        plugin_id="$(yq ".plugins[$i].id" "$upgrade_yaml")"
        if [[ ! "$plugin_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            echo "ERROR: Invalid plugin id '$plugin_id'; expected one safe path segment." >&2
            return 1
        fi
        _ws_hoard_contained_path "$hoard_dir" ".obsidian/plugins/$plugin_id" "hoard" >/dev/null || return 1
        for plugin_asset in main.js manifest.json styles.css; do
            _ws_hoard_contained_path "$hoard_dir" ".obsidian/plugins/$plugin_id/$plugin_asset" "hoard" >/dev/null || return 1
        done
        i=$((i + 1))
    done

    local data_path data_id
    if [[ -d "$template_dir/.upgrade/data" ]]; then
        for data_path in "$template_dir/.upgrade/data"/*/data.json; do
            [[ -e "$data_path" || -L "$data_path" ]] || continue
            data_id="$(basename "$(dirname "$data_path")")"
            if [[ ! "$data_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
                echo "ERROR: Invalid plugin data id '$data_id'; expected one safe path segment." >&2
                return 1
            fi
            _ws_hoard_contained_path "$template_dir/.upgrade" "data/$data_id/data.json" "template upgrade" >/dev/null || return 1
            _ws_hoard_contained_path "$hoard_dir" ".obsidian/plugins/$data_id" "hoard" >/dev/null || return 1
            _ws_hoard_contained_path "$hoard_dir" ".obsidian/plugins/$data_id/data.json" "hoard" >/dev/null || return 1
        done
    fi

    count="$(yq '.files_remove // [] | length' "$upgrade_yaml")"
    i=0
    while [[ $i -lt $count ]]; do
        rel="$(yq ".files_remove[$i]" "$upgrade_yaml")"
        _ws_hoard_contained_path "$hoard_dir" "$rel" "hoard" >/dev/null || return 1
        i=$((i + 1))
    done

    count="$(yq '.managed_regions // [] | length' "$upgrade_yaml")"
    i=0
    while [[ $i -lt $count ]]; do
        rfile="$(yq ".managed_regions[$i].file" "$upgrade_yaml")"
        rsrc="$(yq ".managed_regions[$i].source" "$upgrade_yaml")"
        _ws_hoard_contained_path "$hoard_dir" "$rfile" "hoard" >/dev/null || return 1
        _ws_hoard_contained_path "$template_dir/.upgrade" "$rsrc" "template upgrade" >/dev/null || return 1
        i=$((i + 1))
    done

    # The upgrade also writes a fixed set of metadata/plugin paths that do not
    # appear in the manifest. Validate those targets with the same physical
    # containment rule so a hoard-shipped symlink cannot redirect a backup,
    # JSON rewrite, provenance bump, or managed README migration.
    local fixed_rel
    for fixed_rel in \
        .hoard.yaml \
        .gitignore \
        .upgrade-backup \
        .obsidian \
        .obsidian/plugins \
        .obsidian/community-plugins.json \
        .obsidian/core-plugins.json \
        README.md \
        Welcome.md \
        00_Inbox \
        00_Inbox/Welcome.md; do
        _ws_hoard_contained_path "$hoard_dir" "$fixed_rel" "hoard" >/dev/null || return 1
    done
}

# Read a hoard's provenance. Prints "<template> <applied_version>" on
# success; returns 1 if .hoard.yaml is missing or has no template.
_ws_hoard_provenance_read() {
    local hoard_dir="$1"
    local f="$hoard_dir/.hoard.yaml"
    [[ -f "$f" ]] || return 1
    local tmpl ver
    tmpl="$(yq '.template // ""' "$f" 2>/dev/null)"
    ver="$(yq '.applied_version // 0' "$f" 2>/dev/null)"
    [[ -n "$tmpl" && "$tmpl" != "null" ]] || return 1
    [[ "$ver" =~ ^[0-9]+$ ]] || ver=0
    printf '%s %s\n' "$tmpl" "$ver"
}

# Write a hoard's provenance file (git-committed, hoard root).
_ws_hoard_provenance_write() {
    local hoard_dir="$1" template="$2" version="$3"
    printf 'template: %s\napplied_version: %s\n' "$template" "$version" \
        > "$hoard_dir/.hoard.yaml"
}

# Print the integer `version` from a template's upgrade.yaml. Returns 1 if
# the manifest is absent. Defaults a missing/invalid version to 0.
_ws_hoard_manifest_version() {
    local template_dir="$1"
    local f="$template_dir/.upgrade/upgrade.yaml"
    [[ -f "$f" ]] || return 1
    local v
    v="$(yq '.version // 0' "$f" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    printf '%s\n' "$v"
}

# Compute and print the upgrade plan as CLASS<TAB>DETAIL lines, without
# modifying the hoard. CLASS in uptodate|additive|region-insert|region-edit|
# destructive. The caller (skill/human) decides on the destructive + region
# lines; additive lines are safe to auto-apply.
_ws_hoard_upgrade_plan() {
    local hoard_dir="$1" template_dir="$2" applied_override="${3:-}"
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    local cp_json="$hoard_dir/.obsidian/community-plugins.json"

    _ws_hoard_validate_manifest_paths "$hoard_dir" "$template_dir" || return 1

    local version applied prov
    version="$(_ws_hoard_manifest_version "$template_dir")" || return 1
    if [[ -n "$applied_override" ]]; then
        applied="$applied_override"   # in-memory baseline for an untracked adoption (--plan must not write)
    elif prov="$(_ws_hoard_provenance_read "$hoard_dir")"; then
        applied="${prov##* }"
    else
        applied=-1   # no provenance yet; everything is "new"
    fi
    if [[ "$applied" -ge "$version" ]]; then
        printf 'uptodate\tapplied %s >= version %s\n' "$applied" "$version"
        return 0
    fi

    # Plugins: additive if id not already in community-plugins.json.
    local n i id
    n="$(yq '.plugins // [] | length' "$upgrade_yaml")"
    i=0
    while [[ $i -lt $n ]]; do
        id="$(yq ".plugins[$i].id" "$upgrade_yaml")"
        if [[ -f "$cp_json" ]] && jq -e --arg id "$id" 'index($id)' "$cp_json" >/dev/null 2>&1; then
            :  # already enabled — no change
        else
            printf 'additive\tenable plugin %s\n' "$id"
        fi
        i=$((i+1))
    done

    # Managed regions: insert (markers absent) vs edit (markers present).
    local rn ri rfile rid begin
    rn="$(yq '.managed_regions // [] | length' "$upgrade_yaml")"
    ri=0
    while [[ $ri -lt $rn ]]; do
        rfile="$(yq ".managed_regions[$ri].file" "$upgrade_yaml")"
        rid="$(yq ".managed_regions[$ri].id" "$upgrade_yaml")"
        begin="<!-- BEGIN upgrade-$rid -->"
        if [[ -f "$hoard_dir/$rfile" ]] && grep -qF "$begin" "$hoard_dir/$rfile" 2>/dev/null; then
            printf 'region-edit\t%s#%s\n' "$rfile" "$rid"
        else
            printf 'region-insert\t%s#%s\n' "$rfile" "$rid"
        fi
        ri=$((ri+1))
    done

    # files_remove: destructive when the target exists AND is a file. apply uses
    # `rm -f` (which skips directories), so the plan only flags what apply can
    # actually remove — a directory entry would otherwise show in the plan but
    # be silently skipped on apply.
    local fn fidx rel
    fn="$(yq '.files_remove // [] | length' "$upgrade_yaml")"
    fidx=0
    while [[ $fidx -lt $fn ]]; do
        rel="$(yq ".files_remove[$fidx]" "$upgrade_yaml")"
        [[ -e "$hoard_dir/$rel" && ! -d "$hoard_dir/$rel" ]] \
            && printf 'destructive\tremove %s\n' "$rel"
        fidx=$((fidx+1))
    done

    # core_plugins_disable: destructive when currently enabled.
    local cn ci cid core_json
    core_json="$hoard_dir/.obsidian/core-plugins.json"
    cn="$(yq '.core_plugins_disable // [] | length' "$upgrade_yaml")"
    ci=0
    while [[ $ci -lt $cn ]]; do
        cid="$(yq ".core_plugins_disable[$ci]" "$upgrade_yaml")"
        if [[ -f "$core_json" ]] && jq -e --arg id "$cid" \
            'if type=="array" then index($id) else .[$id] == true end' \
            "$core_json" >/dev/null 2>&1; then
            printf 'destructive\tdisable core plugin %s\n' "$cid"
        fi
        ci=$((ci+1))
    done

    # Community plugins the hoard has enabled but the template doesn't ship:
    # --apply overwrites community-plugins.json with exactly the template ids,
    # so these would be disabled. Surface them so the plan stays truthful.
    if [[ -f "$cp_json" ]]; then
        # Newline-delimited template ids (NOT -o tsv, which row-orients them onto
        # one tab-separated line). Membership via a bash `case` substring —
        # portable (bash 3.2) and avoids a grep-here-string-in-while-read fd
        # clash on Git Bash. Strip a trailing CR from each enabled id: jq on
        # Windows emits CRLF, so `read` would otherwise yield "id\r" and never
        # match a clean template id.
        local tmpl_ids enabled_id
        tmpl_ids="$(yq '.plugins // [] | .[].id' "$upgrade_yaml" 2>/dev/null)"
        while IFS= read -r enabled_id; do
            enabled_id="${enabled_id%$'\r'}"
            [[ -n "$enabled_id" ]] || continue
            case $'\n'"$tmpl_ids"$'\n' in
                *$'\n'"$enabled_id"$'\n'*) continue ;;
            esac
            printf 'destructive\tdisable plugin %s (overwrite of community-plugins.json drops it)\n' "$enabled_id"
        done < <(jq -r '.[]?' "$cp_json" 2>/dev/null)
    fi

    # data.json overlays overwrite existing plugin settings on --apply.
    if [[ -d "$template_dir/.upgrade/data" ]]; then
        local dpath did
        for dpath in "$template_dir/.upgrade/data"/*/data.json; do
            [[ -f "$dpath" ]] || continue
            did="$(basename "$(dirname "$dpath")")"
            [[ -f "$hoard_dir/.obsidian/plugins/$did/data.json" ]] \
                && printf 'destructive\toverwrite %s data.json\n' "$did"
        done
    fi
}

# Snapshot the whole hoard into .upgrade-backup/<timestamp>/, excluding
# .git/ and .upgrade-backup/ itself. Prints the snapshot path. Returns 1 on
# failure so callers can abort an apply before touching anything.
_ws_hoard_backup() {
    local hoard_dir="$1"
    local ts snap
    _ws_hoard_contained_path "$hoard_dir" ".upgrade-backup" "hoard" >/dev/null || return 1
    _ws_hoard_contained_path "$hoard_dir" ".gitignore" "hoard" >/dev/null || return 1
    ts="$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$hoard_dir/.upgrade-backup" || return 1
    # Ensure git ignores the snapshots. Hoards adopted via --template predate
    # the template's .gitignore entry, so without this they'd commit backups.
    if [[ -d "$hoard_dir/.git" ]]; then
        local gi="$hoard_dir/.gitignore"
        if ! { [[ -f "$gi" ]] && grep -qxF '.upgrade-backup/' "$gi"; }; then
            printf '\n# Pre-upgrade snapshots written by `ws hoard upgrade --apply`\n.upgrade-backup/\n' >> "$gi"
        fi
    fi
    # A fixed-width sequence suffix preserves creation order when multiple snapshots land in the same second. Atomic mkdir handles a concurrent creator without allowing snapshots to merge.
    local sequence=0 candidate candidate_base candidate_sequence
    for candidate in "$hoard_dir/.upgrade-backup/${ts}-"*; do
        [[ -d "$candidate" && ! -L "$candidate" ]] || continue
        candidate_base="$(basename "$candidate")"
        [[ "$candidate_base" =~ ^${ts}-([0-9]{6})$ ]] || continue
        candidate_sequence=$((10#${BASH_REMATCH[1]}))
        [[ "$candidate_sequence" -ge "$sequence" ]] && sequence=$((candidate_sequence + 1))
    done
    while [[ "$sequence" -le 999999 ]]; do
        printf -v snap '%s/.upgrade-backup/%s-%06d' "$hoard_dir" "$ts" "$sequence"
        if mkdir "$snap" 2>/dev/null; then
            break
        fi
        if [[ -e "$snap" || -L "$snap" ]]; then
            sequence=$((sequence + 1))
            continue
        fi
        echo "ERROR: cannot create backup snapshot: $snap" >&2
        return 1
    done
    [[ -d "$snap" && ! -L "$snap" ]] || {
        echo "ERROR: exhausted same-second backup sequence for $ts" >&2
        return 1
    }
    local entry base
    for entry in "$hoard_dir"/* "$hoard_dir"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        [[ "$base" == ".git" || "$base" == ".upgrade-backup" ]] && continue
        cp -R "$entry" "$snap/" || return 1
    done
    printf '%s\n' "$snap"
}

# Restore the most recent .upgrade-backup/<ts>/ over the hoard. Returns 1 if
# there is no snapshot.
_ws_hoard_rollback() {
    local hoard_dir="$1"
    # Guard before any rm -rf below: never operate on an empty or root path.
    [[ -n "$hoard_dir" && "$hoard_dir" != "/" ]] || {
        echo "ERROR: unsafe hoard_dir for rollback: '$hoard_dir'" >&2
        return 1
    }
    local backups_dir="$hoard_dir/.upgrade-backup"
    _ws_hoard_contained_path "$hoard_dir" ".upgrade-backup" "hoard" >/dev/null || return 1
    [[ -d "$backups_dir" ]] || return 1
    local latest="" latest_base="" latest_timestamp="" latest_suffix="" latest_is_sequence=0
    local candidate candidate_base candidate_timestamp candidate_suffix candidate_is_sequence
    for candidate in "$backups_dir"/*; do
        [[ -d "$candidate" && ! -L "$candidate" ]] || continue
        candidate_base="$(basename "$candidate")"
        [[ "$candidate_base" =~ ^([0-9]{8}-[0-9]{6})-([A-Za-z0-9]{6})$ ]] || continue
        candidate_timestamp="${BASH_REMATCH[1]}"
        candidate_suffix="${BASH_REMATCH[2]}"
        candidate_is_sequence=0
        [[ "$candidate_suffix" =~ ^[0-9]{6}$ ]] && candidate_is_sequence=1
        if [[ -z "$latest_base" || "$candidate_timestamp" > "$latest_timestamp" ]] ||
           { [[ "$candidate_timestamp" == "$latest_timestamp" ]] && [[ "$candidate_is_sequence" -gt "$latest_is_sequence" ]]; } ||
           { [[ "$candidate_timestamp" == "$latest_timestamp" ]] && [[ "$candidate_is_sequence" -eq "$latest_is_sequence" ]] && [[ "$candidate_suffix" > "$latest_suffix" ]]; }; then
            latest="$candidate"
            latest_base="$candidate_base"
            latest_timestamp="$candidate_timestamp"
            latest_suffix="$candidate_suffix"
            latest_is_sequence="$candidate_is_sequence"
        fi
    done
    [[ -n "$latest" ]] || return 1
    # Clear the hoard first (except .git and the backups themselves) so files
    # created after the snapshot — e.g. freshly downloaded plugin dirs — don't
    # survive a rollback, leaving a true revert rather than a merged state.
    local cur curbase
    for cur in "$hoard_dir"/* "$hoard_dir"/.[!.]*; do
        [[ -e "$cur" ]] || continue
        curbase="$(basename "$cur")"
        [[ "$curbase" == ".git" || "$curbase" == ".upgrade-backup" ]] && continue
        rm -rf "$cur" || {
            echo "ERROR: rollback failed to remove $cur; hoard may be half-cleared." >&2
            return 1
        }
    done
    local entry base
    for entry in "$latest"/* "$latest"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        cp -R "$entry" "$hoard_dir/" || {
            echo "ERROR: rollback failed to restore $base; hoard may be half-restored." >&2
            return 1
        }
    done
    printf 'Restored %s\n' "$latest"
}

# Splice a template-managed region into a file. If the BEGIN marker is
# present, replace everything between BEGIN/END; otherwise append a freshly
# wrapped block. Content outside the markers is preserved verbatim.
_ws_hoard_region_splice() {
    local file="$1" id="$2" source_file="$3"
    # Refuse a missing/unreadable source: otherwise the append path would write
    # empty markers and the replace path would drop the managed block, both
    # corrupting the target.
    [[ -r "$source_file" ]] || {
        echo "ERROR: managed-region source not readable: $source_file" >&2
        return 1
    }
    local begin="<!-- BEGIN upgrade-$id -->"
    local end="<!-- END upgrade-$id -->"
    # Surface malformed markers as a conflict instead of silently rewriting:
    # an unbalanced BEGIN/END (e.g. END deleted by hand) would make the awk
    # replace path truncate the rest of the file.
    local begin_count end_count
    begin_count="$(grep -cF "$begin" "$file" 2>/dev/null || true)"
    end_count="$(grep -cF "$end" "$file" 2>/dev/null || true)"
    if [[ "${begin_count:-0}" -ne "${end_count:-0}" ]]; then
        echo "ERROR: malformed managed-region markers in $file for id '$id' (BEGIN=$begin_count END=$end_count)" >&2
        return 1
    fi
    # Render into a temp file in the SAME directory as the target so the final
    # mv is an atomic same-filesystem rename, and clean the temp up on any
    # failure so a partial render never replaces the original.
    local out
    out="$(mktemp "$(dirname "$file")/.upgrade-splice.XXXXXX")" || return 1
    if [[ -f "$file" ]] && grep -qF "$begin" "$file" 2>/dev/null; then
        awk -v b="$begin" -v e="$end" -v insert="$source_file" '
            $0 == b { print; while ((getline line < insert) > 0) print line; close(insert); skip=1; next }
            $0 == e { skip=0 }
            !skip { print }
        ' "$file" > "$out" || { rm -f "$out"; return 1; }
    else
        # Subshell so an internal `exit 1` (on a failed cat) aborts the render
        # without killing the caller; only prepend a separating blank line when
        # the file already has content — a brand-new file shouldn't start blank.
        (
            if [[ -s "$file" ]]; then
                cat "$file" || exit 1
                printf '\n'
            fi
            printf '%s\n' "$begin"
            cat "$source_file" || exit 1
            printf '%s\n' "$end"
        ) > "$out" || { rm -f "$out"; return 1; }
    fi
    mv "$out" "$file" || { rm -f "$out"; return 1; }
}

ws_hoard_upgrade_help() {
    cat >&2 <<'HELP'
Usage: ws hoard upgrade <hoard> [--plan | --apply | --rollback] [--template <name>]

  --plan       Show what would change; touch nothing (default).
  --apply      Back up the hoard, then apply the plan; bump .hoard.yaml.
  --rollback   Restore the most recent pre-apply backup.
  --template   Name the source template for a hoard with no .hoard.yaml yet
               (establishes provenance, then applies the latest version).

Reads the source template from <hoard>/.hoard.yaml. The gdd-hoard-upgrade
skill drives the propose-then-apply flow; run it instead of --apply by hand
when there are destructive or region changes to review.
HELP
}

# Try `gh release download <tag> ...` with the literal pin first, then
# a v-prefixed fallback (some plugin repos tag with v<version>, others
# without). Returns 0 on first success, 1 if both fail.
_ws_hoard_upgrade_gh_download() {
    local pin="$1" repo="$2" out_dir="$3"
    local tag
    for tag in "$pin" "v$pin"; do
        if gh release download "$tag" -R "$repo" \
            --pattern "main.js" --pattern "manifest.json" --pattern "styles.css" \
            --dir "$out_dir" --clobber 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Internal: run an upgrade given resolved paths. Used by both the
# public `ws hoard upgrade` command and ws_hoard_init's post-copy
# step. Args: <template_dir> <hoard_dir>.
# Mechanical manifest apply: download plugins, seed data.json, write
# community-plugins.json, disable core plugins, remove declared files, refresh
# the README plugin table. No backup, no provenance bump, no managed regions —
# those are the caller's job (--apply / region splice). Args: <template_dir> <hoard_dir>.
_ws_hoard_apply_manifest() {
    local template_dir="$1"
    local hoard_dir="$2"
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"

    _ws_hoard_validate_manifest_paths "$hoard_dir" "$template_dir" || return 1

    if [[ ! -f "$upgrade_yaml" ]]; then
        echo "ERROR: template has no upgrade.yaml: $template_dir" >&2
        return 1
    fi
    # Bootstrap .obsidian/ if absent. Templates like thalami don't ship one
    # (it's per-machine, gitignored), and a hoard may not have been opened in
    # Obsidian yet — so create it rather than erroring, letting init/upgrade
    # seed plugins + config cleanly on a fresh hoard.
    mkdir -p "$hoard_dir/.obsidian" || return 1
    if ! command -v gh &>/dev/null; then
        echo "ERROR: gh (GitHub CLI) is required to download plugin releases." >&2
        echo "  Install: https://cli.github.com/" >&2
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required for JSON manipulation." >&2
        return 1
    fi

    # 1. Download each plugin's release assets.
    local plugin_count
    plugin_count="$(yq '.plugins | length' "$upgrade_yaml")"
    if [[ "$plugin_count" -gt 0 ]]; then
        echo "Downloading $plugin_count plugin(s) from GitHub releases..."
        local i=0 plugin_asset
        while [[ $i -lt $plugin_count ]]; do
            local id repo pin
            id="$(yq ".plugins[$i].id" "$upgrade_yaml")"
            repo="$(yq ".plugins[$i].repo" "$upgrade_yaml")"
            pin="$(yq ".plugins[$i].pin" "$upgrade_yaml")"
            local plugin_rel=".obsidian/plugins/$id" plugin_dir
            plugin_dir="$(_ws_hoard_contained_path "$hoard_dir" "$plugin_rel" "hoard")" || return 1
            mkdir -p "$plugin_dir" || return 1
            # Revalidate after creation and immediately before the download so
            # an existing or newly introduced per-plugin symlink cannot turn
            # the release client's --dir into an out-of-hoard write.
            plugin_dir="$(_ws_hoard_contained_path "$hoard_dir" "$plugin_rel" "hoard")" || return 1
            for plugin_asset in main.js manifest.json styles.css; do
                _ws_hoard_contained_path "$hoard_dir" "$plugin_rel/$plugin_asset" "hoard" >/dev/null || return 1
            done
            printf "  [%d/%d] %s @ %s — " $((i+1)) "$plugin_count" "$id" "$pin"
            if _ws_hoard_upgrade_gh_download "$pin" "$repo" "$plugin_dir"; then
                echo "ok"
            else
                echo "FAILED"
                echo "    Could not download from $repo at tag '$pin' or 'v$pin'." >&2
                return 1
            fi
            i=$((i+1))
        done
        echo ""
    fi

    # 2. Overlay template's data/<id>/data.json files into the hoard.
    if [[ -d "$template_dir/.upgrade/data" ]]; then
        echo "Seeding plugin settings (data.json)..."
        local data_path data_id data_source data_plugin_rel data_plugin_dir data_target
        for data_path in "$template_dir/.upgrade/data"/*/data.json; do
            [[ -e "$data_path" || -L "$data_path" ]] || continue
            data_id="$(basename "$(dirname "$data_path")")"
            if [[ ! "$data_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
                echo "ERROR: Invalid plugin data id '$data_id'; expected one safe path segment." >&2
                return 1
            fi
            data_source="$(_ws_hoard_contained_path "$template_dir/.upgrade" "data/$data_id/data.json" "template upgrade")" || return 1
            data_plugin_rel=".obsidian/plugins/$data_id"
            data_plugin_dir="$(_ws_hoard_contained_path "$hoard_dir" "$data_plugin_rel" "hoard")" || return 1
            mkdir -p "$data_plugin_dir" || return 1
            data_plugin_dir="$(_ws_hoard_contained_path "$hoard_dir" "$data_plugin_rel" "hoard")" || return 1
            data_target="$(_ws_hoard_contained_path "$hoard_dir" "$data_plugin_rel/data.json" "hoard")" || return 1
            cp "$data_source" "$data_target" || return 1
        done
        echo ""
    fi

    # 3. Write community-plugins.json — the list of *enabled* plugin ids.
    local cp_json="$hoard_dir/.obsidian/community-plugins.json"
    yq -o json '[.plugins[].id]' "$upgrade_yaml" > "$cp_json"
    echo "Wrote $cp_json"

    # 4. Disable conflicting core plugins.
    local cp_disable_count
    cp_disable_count="$(yq '.core_plugins_disable // [] | length' "$upgrade_yaml")"
    if [[ "$cp_disable_count" -gt 0 ]]; then
        local core_json="$hoard_dir/.obsidian/core-plugins.json"
        if [[ -f "$core_json" ]]; then
            local j=0
            while [[ $j -lt $cp_disable_count ]]; do
                local core_id
                core_id="$(yq ".core_plugins_disable[$j]" "$upgrade_yaml")"
                local tmp
                tmp="$(mktemp)"
                # core-plugins.json comes in two valid Obsidian shapes:
                #   - array form: ["file-explorer", "templates", ...]
                #     (enabled listed; absence = disabled)
                #   - object form: {"file-explorer": true, ...}
                # Detect and patch accordingly.
                if jq -e 'type == "array"' "$core_json" >/dev/null 2>&1; then
                    jq --arg id "$core_id" 'map(select(. != $id))' "$core_json" > "$tmp"
                else
                    jq --arg id "$core_id" '.[$id] = false' "$core_json" > "$tmp"
                fi
                mv "$tmp" "$core_json"
                echo "Disabled core plugin: $core_id"
                j=$((j+1))
            done
        fi
    fi

    # 5. Remove redundant files.
    local rm_count
    rm_count="$(yq '.files_remove // [] | length' "$upgrade_yaml")"
    if [[ "$rm_count" -gt 0 ]]; then
        local k=0
        while [[ $k -lt $rm_count ]]; do
            local rel
            rel="$(yq ".files_remove[$k]" "$upgrade_yaml")"
            local target="$hoard_dir/$rel"
            if [[ -e "$target" ]]; then
                rm -f "$target"
                echo "Removed: $rel"
            fi
            k=$((k+1))
        done
    fi

    # 6. Refresh the README's auto-managed "Installed plugins" block.
    # The block is delimited by sentinel HTML comments; everything
    # between them is replaced on each upgrade. Content outside the
    # markers is preserved verbatim — the user can edit prose around
    # the table, or remove the entire block (markers and all) to opt
    # out of upgrade-managed content.
    #
    # The plugin table is generated fresh from upgrade.yaml each run,
    # so versions track current pins automatically.
    local readme="$hoard_dir/README.md"
    local marker_id
    marker_id="$(basename "$template_dir")"
    local begin_marker="<!-- BEGIN upgrade-$marker_id -->"
    local end_marker="<!-- END upgrade-$marker_id -->"

    # Migration: convert any legacy `upgrade:<name>` markers (with
    # colon, which Obsidian's spell-checker squiggles) to the new
    # `upgrade-<name>` form. Touches README and any prior Welcome
    # locations that may have legacy markers from earlier upgrades.
    local legacy_begin="<!-- BEGIN upgrade:$marker_id -->"
    local legacy_end="<!-- END upgrade:$marker_id -->"
    for _migrate_target in "$readme" "$hoard_dir/Welcome.md" "$hoard_dir/00_Inbox/Welcome.md"; do
        if [[ -f "$_migrate_target" ]] && grep -qF "$legacy_begin" "$_migrate_target" 2>/dev/null; then
            # Avoid `sed -i` — its in-place flag differs between GNU
            # (no arg) and BSD/macOS (requires an empty backup arg
            # like `-i ''`). Write to a temp file and atomically swap
            # via mv to stay portable across both.
            local _migrate_tmp
            _migrate_tmp="$(mktemp)"
            sed \
                -e "s|$legacy_begin|$begin_marker|g" \
                -e "s|$legacy_end|$end_marker|g" \
                "$_migrate_target" > "$_migrate_tmp" 2>/dev/null \
                && mv "$_migrate_tmp" "$_migrate_target" \
                || rm -f "$_migrate_tmp"
            echo "Migrated legacy marker format in $(basename "$_migrate_target")"
        fi
    done

    if [[ -f "$readme" ]] && grep -qF "$begin_marker" "$readme" 2>/dev/null; then
        local table_tmp
        table_tmp="$(mktemp)"
        # Generate the plugin table rows from upgrade.yaml. Each
        # plugin's name / description / pin came from the same yaml
        # the script just used to install — single source of truth.
        {
            echo
            echo "| Plugin | Version | Role |"
            echo "|--------|---------|------|"
            local n=0
            n="$(yq '.plugins | length' "$upgrade_yaml")"
            local p=0
            while [[ $p -lt $n ]]; do
                local pname pdesc ppin
                pname="$(yq ".plugins[$p].name" "$upgrade_yaml")"
                pdesc="$(yq ".plugins[$p].description" "$upgrade_yaml")"
                ppin="$(yq ".plugins[$p].pin" "$upgrade_yaml")"
                printf '| **%s** | %s | %s |\n' "$pname" "$ppin" "$pdesc"
                p=$((p+1))
            done
            echo
            echo "Versions track upstream releases at the pins above. \`ws hoard upgrade $(basename "$hoard_dir")\` re-fetches plugin code on demand — useful on a fresh clone (when \`main.js\` has been gitignored) or after bumping pins. See this vault's \`.gitignore\` for the plugin-code commit policy."
        } > "$table_tmp"

        # Splice the new table between the existing markers,
        # preserving everything before BEGIN and after END.
        local out_tmp
        out_tmp="$(mktemp)"
        awk -v b="$begin_marker" -v e="$end_marker" -v insert="$table_tmp" '
            $0 == b { print; while ((getline line < insert) > 0) print line; close(insert); skip = 1; next }
            $0 == e { skip = 0 }
            !skip { print }
        ' "$readme" > "$out_tmp"
        mv "$out_tmp" "$readme"
        rm -f "$table_tmp"
        echo "Refreshed plugin table in README.md"
    fi

    # Migration: strip any orphan block from a previous-shape Welcome.md
    # (earlier versions of this script injected there). Welcome.md may
    # or may not exist — only act if the marker is present.
    local welcome="$hoard_dir/Welcome.md"
    if [[ -f "$welcome" ]] && grep -qF "$begin_marker" "$welcome" 2>/dev/null; then
        local tmp
        tmp="$(mktemp)"
        awk -v b="$begin_marker" -v e="$end_marker" '
            $0 == b { skip = 1 }
            !skip { print }
            $0 == e { skip = 0 }
        ' "$welcome" > "$tmp"
        mv "$tmp" "$welcome"
        echo "Stripped legacy upgrade block from Welcome.md"
    fi
    # Same migration cleanup for any 00_Inbox/Welcome.md that may
    # have accumulated a stale block from a different earlier shape
    local inbox_welcome="$hoard_dir/00_Inbox/Welcome.md"
    if [[ -f "$inbox_welcome" ]] && grep -qF "$begin_marker" "$inbox_welcome" 2>/dev/null; then
        local tmp
        tmp="$(mktemp)"
        awk -v b="$begin_marker" -v e="$end_marker" '
            $0 == b { skip = 1 }
            !skip { print }
            $0 == e { skip = 0 }
        ' "$inbox_welcome" > "$tmp"
        mv "$tmp" "$inbox_welcome"
        echo "Stripped legacy upgrade block from 00_Inbox/Welcome.md"
    fi
}

# Splice every managed region declared in the template manifest into the hoard.
# Aborts (returns 1) on a missing/unreadable source or a splice failure, so a
# caller can refuse to bump provenance on a partial apply. Args: <hoard_dir> <template_dir>.
_ws_hoard_apply_regions() {
    local hoard_dir="$1" template_dir="$2"
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    _ws_hoard_validate_manifest_paths "$hoard_dir" "$template_dir" || return 1
    local rn ri rfile rid rsrc
    rn="$(yq '.managed_regions // [] | length' "$upgrade_yaml")"
    ri=0
    while [[ $ri -lt $rn ]]; do
        rfile="$(yq ".managed_regions[$ri].file" "$upgrade_yaml")"
        rid="$(yq ".managed_regions[$ri].id" "$upgrade_yaml")"
        rsrc="$(yq ".managed_regions[$ri].source" "$upgrade_yaml")"
        _ws_hoard_region_splice "$hoard_dir/$rfile" "$rid" "$template_dir/.upgrade/$rsrc" || {
            echo "ERROR: region splice failed for $rfile#$rid; aborting (provenance not bumped, --rollback to restore)." >&2
            return 1
        }
        echo "Spliced region $rfile#$rid"
        ri=$((ri+1))
    done
}

# Back-compat alias: `ws hoard init` calls this with an explicit, known
# template (no provenance gap), so it maps straight to the mechanical apply.
_ws_hoard_upgrade_from_template() {
    _ws_hoard_apply_manifest "$@"
}

# Keep only the N most recent .upgrade-backup/<ts>/ snapshots (default 3,
# override with WS_HOARD_BACKUP_KEEP). Portable: collects dirs oldest-first and
# removes all but the last N (avoids the non-portable `head -n -N`).
_ws_hoard_prune_backups() {
    local hoard_dir="$1" keep="${2:-${WS_HOARD_BACKUP_KEEP:-3}}"
    local backups_dir="$hoard_dir/.upgrade-backup"
    [[ -d "$backups_dir" ]] || return 0
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=3
    local dirs=() d
    while IFS= read -r d; do
        dirs+=("$d")
    done < <(find "$backups_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    local total=${#dirs[@]} i
    local to_delete=$(( total - keep ))
    [[ "$to_delete" -gt 0 ]] || return 0
    for (( i = 0; i < to_delete; i++ )); do
        rm -rf "${dirs[$i]}"
    done
}

# Apply an upgrade end to end: backup, mechanical manifest apply, region
# splices, provenance bump. Aborts before any change if the backup fails.
# Args: <hoard_dir> <template_dir> [adopt_baseline]. When adopt_baseline is
# given (first-time adoption), it is written ONLY after the backup succeeds —
# so the snapshot captures the pre-adoption state and rollback stays clean.
_ws_hoard_upgrade_apply() {
    local hoard_dir="$1" template_dir="$2" adopt_baseline="${3:-}"
    local version
    version="$(_ws_hoard_manifest_version "$template_dir")" || return 1

    local snap
    if ! snap="$(_ws_hoard_backup "$hoard_dir")"; then
        echo "ERROR: backup failed; aborting upgrade (nothing changed)." >&2
        return 1
    fi
    echo "Backed up hoard to: $snap"
    if [[ -n "$adopt_baseline" ]]; then
        _ws_hoard_provenance_write "$hoard_dir" "$(basename "$template_dir")" "$adopt_baseline"
    fi

    # Mechanical manifest apply (plugins, data.json, community-plugins.json,
    # core-disable, files_remove, README block), then managed regions.
    _ws_hoard_apply_manifest "$template_dir" "$hoard_dir" || return 1
    _ws_hoard_apply_regions "$hoard_dir" "$template_dir" || return 1

    # Provenance bump last, so a mid-apply failure leaves it un-bumped and the
    # upgrade is safely retryable.
    local template
    template="$(basename "$template_dir")"
    _ws_hoard_provenance_write "$hoard_dir" "$template" "$version"

    # Self-trim the snapshots so backups don't accumulate forever (no separate
    # human chore). Best-effort — a prune failure must not fail the upgrade.
    _ws_hoard_prune_backups "$hoard_dir" || true
}

# Public command. Resolves the source template from <hoard>/.hoard.yaml
# (or --template for a not-yet-tracked hoard), then plans / applies / rolls
# back. No global enable gate: provenance scopes each run to the right
# template, so there is no cross-template misapplication to guard against.
ws_hoard_upgrade() {
    local hoard_name="" mode="plan" template_override="" mode_set=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan|--apply|--rollback)
                if [[ "$mode_set" -eq 1 ]]; then
                    echo "ERROR: only one of --plan / --apply / --rollback may be given." >&2
                    ws_hoard_upgrade_help; return 1
                fi
                mode="${1#--}"; mode_set=1
                ;;
            --template)
                shift
                if [[ -z "${1:-}" || "${1:-}" == -* ]]; then
                    echo "ERROR: --template requires a template name." >&2
                    ws_hoard_upgrade_help; return 1
                fi
                template_override="$1"
                ;;
            -h|--help) ws_hoard_upgrade_help; return 0 ;;
            -*) echo "ERROR: unknown flag '$1'" >&2; ws_hoard_upgrade_help; return 1 ;;
            *)
                if [[ -n "$hoard_name" ]]; then
                    echo "ERROR: unexpected extra argument '$1' (hoard already set to '$hoard_name')." >&2
                    ws_hoard_upgrade_help; return 1
                fi
                hoard_name="$1"
                ;;
        esac
        shift
    done
    if [[ -z "$hoard_name" ]]; then
        ws_hoard_upgrade_help; return 1
    fi
    if [[ ! "$hoard_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid hoard name '$hoard_name'." >&2
        return 1
    fi

    local hoard_dir="$HOARDS_DIR/$hoard_name"
    if [[ ! -d "$hoard_dir" ]]; then
        echo "ERROR: hoard not found: $hoard_dir" >&2
        echo "  Run \`ws hoard list\` to see what's available." >&2
        return 1
    fi

    if [[ "$mode" == "rollback" ]]; then
        _ws_hoard_rollback "$hoard_dir" || { echo "ERROR: no backup to roll back to." >&2; return 1; }
        return 0
    fi

    # Resolve template; adopt a not-yet-tracked hoard via --template. For an
    # adoption we compute a baseline (one version behind, so the latest bump
    # applies) but DO NOT persist it here — writing .hoard.yaml during --plan
    # would mutate the hoard and break the "touch nothing" contract. The plan
    # uses the baseline in-memory; --apply persists it before applying.
    local template prov adopting=0 baseline=""
    if prov="$(_ws_hoard_provenance_read "$hoard_dir")"; then
        template="${prov%% *}"
    elif [[ -n "$template_override" ]]; then
        template="$template_override"
        local tv
        tv="$(_ws_hoard_manifest_version "$TEMPLATES_DIR/hoards/$template")" || {
            echo "ERROR: template '$template' has no .upgrade/upgrade.yaml" >&2; return 1; }
        adopting=1
        baseline=$(( tv > 0 ? tv - 1 : 0 ))
        printf 'provenance\twould adopt %s @ %s (untracked; persisted on --apply)\n' "$template" "$baseline"
    else
        echo "ERROR: $hoard_name has no .hoard.yaml; pass --template <name> to adopt it." >&2
        return 1
    fi

    if [[ ! "$template" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "ERROR: Invalid hoard template name '$template'." >&2
        return 1
    fi

    local template_dir="$TEMPLATES_DIR/hoards/$template"
    if [[ ! -f "$template_dir/.upgrade/upgrade.yaml" ]]; then
        echo "ERROR: template '$template' has no .upgrade/upgrade.yaml" >&2
        return 1
    fi
    _ws_hoard_validate_manifest_paths "$hoard_dir" "$template_dir" || return 1

    if [[ "$mode" == "plan" ]]; then
        _ws_hoard_upgrade_plan "$hoard_dir" "$template_dir" "$baseline"
    elif [[ "$adopting" -eq 1 ]]; then
        # Pass the baseline so apply records it AFTER its backup (keeps the
        # snapshot pre-adoption and never mutates before the safety net exists).
        _ws_hoard_upgrade_apply "$hoard_dir" "$template_dir" "$baseline"
    else
        _ws_hoard_upgrade_apply "$hoard_dir" "$template_dir"
    fi
}
