#!/usr/bin/env bash
# Local convenience wrapper around mark.
# Usage: bash publish.sh [--dry-run] [--root <path>]
set -euo pipefail

ROOT="."
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$ROOT" && pwd)"
CONF_CFG="$ROOT/.publish.yaml"

[[ -f "$CONF_CFG" ]] || { echo "error: $CONF_CFG not found" >&2; exit 1; }

PROCESSED="$ROOT/.processed"

if [[ ! -d "$PROCESSED" ]]; then
    echo "error: $PROCESSED not found — run preprocess.py first" >&2
    exit 1
fi

if ! command -v mark &>/dev/null; then
    echo "error: mark not found. Install from https://github.com/kovetskiy/mark/releases" >&2
    exit 1
fi

BASE_URL=$(grep 'base_url:' "$CONF_CFG" | head -1 | sed 's/.*base_url: *//')
USER=$(grep 'user:' "$CONF_CFG" | head -1 | sed 's/.*user: *//')

if ! $DRY_RUN; then
    [[ -n "${CONFLUENCE_TOKEN:-}" ]] || { echo "error: CONFLUENCE_TOKEN is not set" >&2; exit 1; }
fi

for f in "$PROCESSED"/*.md; do
    [[ -f "$f" ]] || continue
    if $DRY_RUN; then
        echo "[dry-run] would publish: $f"
    else
        mark -u "$USER" -p "$CONFLUENCE_TOKEN" -b "$BASE_URL" -f "$f"
    fi
done
