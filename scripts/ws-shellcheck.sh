#!/usr/bin/env bash
# ws-shellcheck.sh — Optional static lint of shell scripts via shellcheck.
# ws:use-when statically linting bash (the ws CLI itself, realm/component tooling)
#
# Detect-and-run: if shellcheck is installed, lint the given paths; if not, print a
# one-line setup recommendation and skip (exit 0) so a machine without it is never
# blocked. Runs with `-x` (follow `source`d files) and `--severity=warning` so the
# signal is real bugs, not style/info noise — pass --pedantic to widen to everything.
# Opt into hard failure when shellcheck is absent with --strict (for CI).
#
# Env:
#   WS_SHELLCHECK_QUIET=1   silence the "not installed" recommendation
#
# Usage:
#   ws-shellcheck.sh [--strict] [--pedantic] [shellcheck-flags...] [path ...]
#     path: a file (checked directly) or a dir (searched for *.sh plus extensionless
#     files with a sh/bash shebang — so the `ws` dispatcher is covered). Default: the
#     workspace 'scripts/' dir (the ws CLI).

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

strict=0
sc_args=(-x --severity=warning)
paths=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)   strict=1; shift ;;
        --pedantic) sc_args=(-x --severity=style); shift ;;
        --help|-h)  sed -n '2,21p' "${BASH_SOURCE[0]}"; exit 0 ;;
        --*)        sc_args+=("$1"); shift ;;   # passthrough other shellcheck flags
        *)          paths+=("$1"); shift ;;
    esac
done
[[ ${#paths[@]} -eq 0 ]] && paths=("$SELF_DIR")

if ! command -v shellcheck >/dev/null 2>&1; then
    if [[ "${WS_SHELLCHECK_QUIET:-0}" != 1 ]]; then
        echo "note: shellcheck not installed — skipping shell lint (optional)." >&2
        echo "      add it for an extra layer of bash checks: 'brew install shellcheck'" >&2
        echo "      (Linux/Windows hints: 'ws preflight'). Silence: WS_SHELLCHECK_QUIET=1." >&2
    fi
    [[ "$strict" == 1 ]] && exit 1
    exit 0
fi

# Resolve paths -> concrete files. The two finds are disjoint (has-.sh vs extensionless),
# so no de-dup is needed. The shebang match catches the extensionless `ws` dispatcher.
files=()
for p in "${paths[@]}"; do
    if [[ -f "$p" ]]; then
        files+=("$p")
    elif [[ -d "$p" ]]; then
        while IFS= read -r f; do files+=("$f"); done < <(
            find "$p" -type f -name '*.sh'
            find "$p" -type f ! -name '*.*' -exec sh -c 'head -n1 "$1" | grep -qE "^#!.*[ /](ba)?sh($| )" && printf "%s\n" "$1"' _ {} \;
        )
    else
        echo "warning: '$p' not found — skipping." >&2
    fi
done

if [[ ${#files[@]} -eq 0 ]]; then
    echo "ws-shellcheck: no shell scripts found in: ${paths[*]}"
    exit 0
fi

echo "ws-shellcheck: linting ${#files[@]} script(s) [${sc_args[*]}]…"
shellcheck "${sc_args[@]}" "${files[@]}"
