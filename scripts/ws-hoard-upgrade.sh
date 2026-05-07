#!/usr/bin/env bash
# ws-hoard-upgrade.sh — Refresh a hoard's plugins and configs from its
# template's upgrade.yaml.
#
# Templates that need an "after init" or "ongoing refresh" phase ship
# an upgrade.yaml at templates/hoards/<flavor>/upgrade.yaml. Today
# only obsidian-vault has one, but the discovery is generic.
#
# What an upgrade does (driven by upgrade.yaml + companion files):
#   - Downloads pinned plugin releases from GitHub into
#     <hoard>/.obsidian/plugins/<id>/
#   - Copies template's data/<plugin-id>/data.json into the hoard,
#     seeding plugin settings
#   - Writes <hoard>/.obsidian/community-plugins.json (the enabled list)
#   - Disables conflicting core plugins in core-plugins.json
#   - Removes redundant files (e.g. core daily-notes.json once
#     Periodic Notes supersedes it)
#   - Injects a marked section into the hoard's README.md from the
#     template's vault_readme_section.md (idempotent via sentinel
#     comments)
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

ws_hoard_upgrade_help() {
    echo "Usage: ws hoard upgrade <hoard-name>" >&2
    echo "" >&2
    echo "Re-fetch plugins and refresh configs for a hoard, using the" >&2
    echo "upgrade.yaml shipped by its template. Idempotent — safe to" >&2
    echo "re-run." >&2
    echo "" >&2
    echo "The originating template is auto-discovered today (only one" >&2
    echo "template currently ships upgrade.yaml). When more arrive," >&2
    echo "this command will require --template <flavor> to disambiguate." >&2
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
_ws_hoard_upgrade_from_template() {
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
            sed -i \
                -e "s|<!-- BEGIN upgrade:$marker_id -->|$begin_marker|g" \
                -e "s|<!-- END upgrade:$marker_id -->|$end_marker|g" \
                "$_migrate_target" 2>/dev/null || true
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
            echo "Plugin code (\`main.js\`, \`styles.css\`) is gitignored — only \`manifest.json\` and \`data.json\` are committed. \`ws hoard upgrade $(basename "$hoard_dir")\` re-fetches the JS from upstream releases at the pinned versions above."
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

# Public command: resolve template by auto-discovery, then run the
# upgrade. Errors clearly if zero or multiple upgradeable templates
# exist (the latter is forward-looking; today there's just one).
ws_hoard_upgrade() {
    local hoard_name="${1:-}"
    if [[ -z "$hoard_name" || "$hoard_name" == "--help" || "$hoard_name" == "-h" ]]; then
        ws_hoard_upgrade_help
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
