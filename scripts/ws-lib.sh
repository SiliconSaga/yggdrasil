#!/usr/bin/env bash
# ws-lib.sh — Shared functions for ws scripts
#
# Source this from any ws-* script that needs overlay-aware config:
#   source "$(dirname "${BASH_SOURCE[0]}")/ws-lib.sh"

# Resolve paths (caller may have already set these)
: "${SCRIPT_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"
: "${ECOSYSTEM:="$ROOT_DIR/ecosystem.yaml"}"
: "${OVERLAYS_DIR:="$ROOT_DIR/overlays"}"
: "${COMPONENTS_DIR:="$ROOT_DIR/components"}"

_RESOLVED_ECOSYSTEM=""

ws_detect_overlay() {
    local local_file="$ROOT_DIR/ecosystem.local.yaml"
    if [[ -f "$local_file" ]]; then
        local selector
        selector=$(yq '.overlay // ""' "$local_file" 2>/dev/null)
        if [[ -n "$selector" && "$selector" != "null" ]]; then
            if [[ -d "$OVERLAYS_DIR/$selector" ]]; then
                echo "$selector"
                return
            fi
        fi
    fi
    if [[ -d "$OVERLAYS_DIR/overlay-yggdrasil-live" ]]; then
        echo "overlay-yggdrasil-live"
        return
    fi
    if [[ -d "$OVERLAYS_DIR/overlay-yggdrasil-template" ]]; then
        echo "overlay-yggdrasil-template"
        return
    fi
    echo ""
}

ws_resolve_ecosystem() {
    if [[ -n "$_RESOLVED_ECOSYSTEM" && -f "$_RESOLVED_ECOSYSTEM" ]]; then
        echo "$_RESOLVED_ECOSYSTEM"
        return
    fi

    local base="$ROOT_DIR/ecosystem.yaml"
    local overlay_file=""
    local local_file="$ROOT_DIR/ecosystem.local.yaml"

    local active_overlay
    active_overlay="$(ws_detect_overlay)"
    if [[ -n "$active_overlay" ]]; then
        overlay_file="$OVERLAYS_DIR/$active_overlay/ecosystem.yaml"
    fi

    local merged
    merged="$(mktemp)"
    if [[ -n "$overlay_file" && -f "$overlay_file" ]]; then
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$base" "$overlay_file" > "$merged"
    else
        cp "$base" "$merged"
    fi
    if [[ -f "$local_file" ]]; then
        local tmp
        tmp="$(mktemp)"
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$merged" "$local_file" > "$tmp"
        mv "$tmp" "$merged"
    fi

    _RESOLVED_ECOSYSTEM="$merged"
    echo "$merged"
}

trap 'rm -f "$_RESOLVED_ECOSYSTEM" 2>/dev/null' EXIT
