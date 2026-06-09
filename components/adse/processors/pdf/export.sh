#!/usr/bin/env bash
# Convert assembled SADD markdown to PDF via pandoc.
# Usage: export.sh --input <assembled.md> --output <out.pdf>
set -euo pipefail

INPUT="" OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)  INPUT="$2";  shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$INPUT"  ]] || { echo "error: --input required"  >&2; exit 1; }
[[ -n "$OUTPUT" ]] || OUTPUT="${INPUT%.md}.pdf"

if ! command -v pandoc &>/dev/null; then
    echo "error: pandoc not found. Install from https://pandoc.org/installing.html" >&2
    exit 1
fi

pandoc "$INPUT" \
    --from markdown \
    --to pdf \
    --pdf-engine=xelatex \
    --variable geometry:margin=2cm \
    --variable fontsize=11pt \
    --output "$OUTPUT"

echo "PDF written to $OUTPUT"
