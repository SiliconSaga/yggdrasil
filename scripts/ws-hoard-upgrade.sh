#!/usr/bin/env bash
# ws-hoard-upgrade.sh — Refresh a hoard's plugins and configs from its
# template's upgrade.yaml.
#
# Templates that need an "after init" or "ongoing refresh" phase ship
# the recipe under templates/hoards/<flavor>/.upgrade/ — specifically
# .upgrade/upgrade.yaml plus companion data/<plugin-id>/data.json
# overlays. Today only obsidian-vault has one, but the discovery is
# generic.
#
# What an upgrade does (driven by upgrade.yaml + companion files):
#   - Downloads pinned plugin releases from GitHub into
#     <hoard>/.obsidian/plugins/<id>/
#   - Copies template's .upgrade/data/<plugin-id>/data.json into the
#     hoard, seeding plugin settings
#   - Writes <hoard>/.obsidian/community-plugins.json (the enabled list)
#   - Disables conflicting core plugins in core-plugins.json
#   - Removes redundant files (e.g. core daily-notes.json once
#     Periodic Notes supersedes it)
#   - Refreshes a marked plugin table in the hoard's README.md
#     between sentinel comments (idempotent on re-run)
#
# This is a one-shot install AND a refresh: re-running re-downloads,
# re-overwrites data.json files, and replaces the README block.
#
# Future work tracked in the followup to yggdrasil#54:
#   - Hoard-side provenance tracking (`.hoard.yaml`) so we can resolve
#     the originating template for free instead of scanning
#   - JSON-merge instead of overwrite for plugin data.json so user
#     tweaks survive an upgrade

# Sourced by ws-hoard.sh; do not enable strict mode here.

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
    local hoard_dir="$1" template_dir="$2"
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    local cp_json="$hoard_dir/.obsidian/community-plugins.json"

    local version applied prov
    version="$(_ws_hoard_manifest_version "$template_dir")" || return 1
    if prov="$(_ws_hoard_provenance_read "$hoard_dir")"; then
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

    # files_remove: destructive when the target exists.
    local fn fi rel
    fn="$(yq '.files_remove // [] | length' "$upgrade_yaml")"
    fi=0
    while [[ $fi -lt $fn ]]; do
        rel="$(yq ".files_remove[$fi]" "$upgrade_yaml")"
        [[ -e "$hoard_dir/$rel" ]] && printf 'destructive\tremove %s\n' "$rel"
        fi=$((fi+1))
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
}

# Snapshot the whole hoard into .upgrade-backup/<timestamp>/, excluding
# .git/ and .upgrade-backup/ itself. Prints the snapshot path. Returns 1 on
# failure so callers can abort an apply before touching anything.
_ws_hoard_backup() {
    local hoard_dir="$1"
    local ts snap
    ts="$(date '+%Y%m%d-%H%M%S')"
    snap="$hoard_dir/.upgrade-backup/$ts"
    mkdir -p "$snap" || return 1
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
    local backups_dir="$hoard_dir/.upgrade-backup"
    [[ -d "$backups_dir" ]] || return 1
    local latest
    latest="$(find "$backups_dir" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
    [[ -n "$latest" ]] || return 1
    local entry base
    for entry in "$latest"/* "$latest"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        rm -rf "$hoard_dir/$base"
        cp -R "$entry" "$hoard_dir/"
    done
    printf 'Restored %s\n' "$latest"
}

# Splice a template-managed region into a file. If the BEGIN marker is
# present, replace everything between BEGIN/END; otherwise append a freshly
# wrapped block. Content outside the markers is preserved verbatim.
_ws_hoard_region_splice() {
    local file="$1" id="$2" source_file="$3"
    local begin="<!-- BEGIN upgrade-$id -->"
    local end="<!-- END upgrade-$id -->"
    local out
    out="$(mktemp)"
    if [[ -f "$file" ]] && grep -qF "$begin" "$file" 2>/dev/null; then
        awk -v b="$begin" -v e="$end" -v insert="$source_file" '
            $0 == b { print; while ((getline line < insert) > 0) print line; close(insert); skip=1; next }
            $0 == e { skip=0 }
            !skip { print }
        ' "$file" > "$out"
    else
        {
            [[ -f "$file" ]] && cat "$file"
            printf '\n%s\n' "$begin"
            cat "$source_file"
            printf '%s\n' "$end"
        } > "$out"
    fi
    mv "$out" "$file"
}

ws_hoard_upgrade_help() {
    echo "Usage: ws hoard upgrade <hoard-name>" >&2
    echo "" >&2
    echo "DISABLED pending a provenance fix. The command has no per-hoard" >&2
    echo "provenance and would apply the only upgradeable template" >&2
    echo "(obsidian-vault) to ANY hoard, pushing the full plugin suite onto" >&2
    echo "thalami hoards that only need Dataview. Re-enable once hoards carry" >&2
    echo ".hoard.yaml provenance and/or the thalami template ships its own" >&2
    echo "minimal upgrade.yaml (yggdrasil#54). Override on an obsidian-vault" >&2
    echo "hoard with WS_HOARD_UPGRADE_ENABLED=1." >&2
    echo "" >&2
    echo "When enabled: re-fetch plugins and refresh configs for a hoard," >&2
    echo "using the upgrade.yaml shipped by its template. Idempotent." >&2
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

    if [[ ! -f "$upgrade_yaml" ]]; then
        echo "ERROR: template has no upgrade.yaml: $template_dir" >&2
        return 1
    fi
    if [[ ! -d "$hoard_dir/.obsidian" ]]; then
        echo "ERROR: $hoard_dir does not appear to be an Obsidian vault" >&2
        echo "  No .obsidian/ directory found." >&2
        return 1
    fi
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
        local i=0
        while [[ $i -lt $plugin_count ]]; do
            local id repo pin
            id="$(yq ".plugins[$i].id" "$upgrade_yaml")"
            repo="$(yq ".plugins[$i].repo" "$upgrade_yaml")"
            pin="$(yq ".plugins[$i].pin" "$upgrade_yaml")"
            local plugin_dir="$hoard_dir/.obsidian/plugins/$id"
            mkdir -p "$plugin_dir"
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
        cp -R "$template_dir/.upgrade/data/." "$hoard_dir/.obsidian/plugins/"
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
                -e "s|<!-- BEGIN upgrade:$marker_id -->|$begin_marker|g" \
                -e "s|<!-- END upgrade:$marker_id -->|$end_marker|g" \
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

# Back-compat alias: `ws hoard init` calls this with an explicit, known
# template (no provenance gap), so it maps straight to the mechanical apply.
_ws_hoard_upgrade_from_template() {
    _ws_hoard_apply_manifest "$@"
}

# Apply an upgrade end to end: backup, mechanical manifest apply, region
# splices, provenance bump. Aborts before any change if the backup fails.
# Args: <hoard_dir> <template_dir>.
_ws_hoard_upgrade_apply() {
    local hoard_dir="$1" template_dir="$2"
    local version
    version="$(_ws_hoard_manifest_version "$template_dir")" || return 1

    local snap
    if ! snap="$(_ws_hoard_backup "$hoard_dir")"; then
        echo "ERROR: backup failed; aborting upgrade (nothing changed)." >&2
        return 1
    fi
    echo "Backed up hoard to: $snap"

    # Mechanical manifest apply (plugins, data.json, community-plugins.json,
    # core-disable, files_remove, README block).
    _ws_hoard_apply_manifest "$template_dir" "$hoard_dir" || return 1

    # Managed regions.
    local upgrade_yaml="$template_dir/.upgrade/upgrade.yaml"
    local rn ri rfile rid rsrc
    rn="$(yq '.managed_regions // [] | length' "$upgrade_yaml")"
    ri=0
    while [[ $ri -lt $rn ]]; do
        rfile="$(yq ".managed_regions[$ri].file" "$upgrade_yaml")"
        rid="$(yq ".managed_regions[$ri].id" "$upgrade_yaml")"
        rsrc="$(yq ".managed_regions[$ri].source" "$upgrade_yaml")"
        _ws_hoard_region_splice "$hoard_dir/$rfile" "$rid" "$template_dir/.upgrade/$rsrc"
        echo "Spliced region $rfile#$rid"
        ri=$((ri+1))
    done

    # Provenance bump last, so a mid-apply failure leaves it un-bumped and the
    # upgrade is safely retryable.
    local template
    template="$(basename "$template_dir")"
    _ws_hoard_provenance_write "$hoard_dir" "$template" "$version"
}

# Public command: resolve template by auto-discovery, then run the
# upgrade. Errors clearly if zero or multiple upgradeable templates
# exist (the latter is forward-looking; today there's just one).
ws_hoard_upgrade() {
    local hoard_name="${1:-}"
    if [[ -z "$hoard_name" || "$hoard_name" == "--help" || "$hoard_name" == "-h" ]]; then
        ws_hoard_upgrade_help
        return 1
    fi

    # ─── DISABLED by default pending a provenance fix (TODO) ────────
    # This command has no per-hoard provenance: it applies the single
    # template that ships an .upgrade/upgrade.yaml (today only
    # obsidian-vault) to ANY hoard named, regardless of that hoard's
    # actual flavor. Run against a thalami hoard it pushed the full
    # PARA-vault plugin suite — including Linter (auto-format on save)
    # and Filename Heading Sync (renames H1/filename) — onto a vault
    # that only needs Dataview, risking edits to the thalamus files on
    # next Obsidian open (observed 2026-05-22).
    #
    # Re-enable (remove this gate) once hoards carry a .hoard.yaml
    # provenance marker (the yggdrasil#54 follow-up) and/or the thalami
    # template ships its own minimal upgrade.yaml. The internal
    # _ws_hoard_upgrade_from_template is intentionally left active —
    # `ws hoard init` calls it with an explicit, known template, so that
    # path has no provenance gap. The WS_HOARD_UPGRADE_ENABLED escape
    # hatch (matching the WS_HOOK_DISABLE / WS_HOOK_DEBUG idiom) lets a
    # power user who knows their hoard is obsidian-vault-shaped override.
    if [[ "${WS_HOARD_UPGRADE_ENABLED:-0}" != "1" ]]; then
        echo "DISABLED: 'ws hoard upgrade' is intentionally off pending a provenance fix (TODO)." >&2
        echo "  It has no per-hoard provenance and would apply the obsidian-vault" >&2
        echo "  upgrade recipe to ANY hoard — pushing the full plugin suite onto" >&2
        echo "  thalami hoards that only need Dataview (Linter / Filename Heading" >&2
        echo "  Sync can then edit the thalamus files on next Obsidian open)." >&2
        echo "  Re-enable once hoards carry .hoard.yaml provenance and/or the" >&2
        echo "  thalami template ships its own minimal upgrade.yaml (yggdrasil#54)." >&2
        echo "  Override for an obsidian-vault hoard with WS_HOARD_UPGRADE_ENABLED=1." >&2
        return 1
    fi

    local hoard_dir="$HOARDS_DIR/$hoard_name"
    if [[ ! -d "$hoard_dir" ]]; then
        echo "ERROR: hoard not found: $hoard_dir" >&2
        echo "  Run \`ws hoard list\` to see what's available." >&2
        return 1
    fi

    # Discover which templates ship an upgrade.yaml. v1: if exactly
    # one, use it. Future: read provenance from <hoard>/.hoard.yaml.
    local upgradeable=()
    local d
    for d in "$TEMPLATES_DIR"/hoards/*/; do
        [[ -f "$d/.upgrade/upgrade.yaml" ]] && upgradeable+=("$(basename "$d")")
    done
    if [[ ${#upgradeable[@]} -eq 0 ]]; then
        echo "ERROR: no template ships an upgrade.yaml — nothing to upgrade." >&2
        return 1
    fi
    if [[ ${#upgradeable[@]} -gt 1 ]]; then
        echo "ERROR: multiple templates have upgrade.yaml: ${upgradeable[*]}" >&2
        echo "  Hoard-side provenance tracking is not yet implemented; this" >&2
        echo "  command currently requires exactly one upgradeable template." >&2
        return 1
    fi

    local template="${upgradeable[0]}"
    local template_dir="$TEMPLATES_DIR/hoards/$template"
    echo "Upgrading hoard '$hoard_name' from template '$template'..."
    echo "  Template: $template_dir"
    echo "  Hoard:    $hoard_dir"
    echo ""
    _ws_hoard_upgrade_from_template "$template_dir" "$hoard_dir"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo ""
        echo "Upgrade complete. Open the hoard in Obsidian — plugins"
        echo "will activate on first launch."
    fi
    return $rc
}
