#!/usr/bin/env bash
# ws-docker.sh — docker passthrough that neutralizes MSYS path mangling on
# Windows Git Bash, so container-absolute arguments (/data, /opt/render, and
# -v name:/path mounts) reach docker unrewritten. Transparent passthrough on
# macOS/Linux.
# ws:use-when running docker with Windows/MSYS path conversion handled automatically
set -euo pipefail

DOCKER="${DOCKER:-docker}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
    cat <<'HELP'
Usage: ws docker <docker args...>

Thin docker passthrough. On Git Bash / MSYS (Windows) it exports
MSYS_NO_PATHCONV=1 for this one invocation so Unix-style container paths
(/data, /opt/render, -v vol:/path) are NOT rewritten into Windows paths before
docker sees them. On macOS/Linux it is a transparent passthrough — everything
after 'ws docker' goes straight to docker unchanged.

Prefer this over bare `docker` on Windows: it keeps the env var scoped to the
docker call (not global), so ws/yq and other tools that DO want path
conversion are unaffected.

Examples:
  ws docker build -t kubicrend:dev components/kubicrend
  ws docker run --rm -v kubicrend-data:/data kubicrend:dev
  ws docker logs kr-test
HELP
    exit 0
fi

# Only Windows Git Bash / MSYS mangles Unix paths handed to native docker.exe.
# Scope the override to this process so it never leaks to sibling tools.
case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 ;;
esac

exec "$DOCKER" "$@"
