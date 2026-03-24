#!/usr/bin/env bash
# ws-review.sh — PR review comments and thread management
#
# Usage:
#   ws-review.sh <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]
#   ws-review.sh <comp> <pr#> [--reviewer <name>] [--since <time>]
#
# Requires GH_TOKEN in .env. Component name is always required.
#
# GraphQL expansion note: if this script accumulates 4-5+ queries,
# consider extracting them to scripts/graphql/*.graphql loaded at runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Function definitions (must precede routing block at bottom) ---

review_help() {
    echo "Usage: ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]"
    echo "       ws review <comp> <pr#> [--reviewer <name>] [--since <time>]"
    echo ""
    echo "PR review comments and thread management."
    echo ""
    echo "Subcommands:"
    echo "  threads <pr#>              List unresolved review threads"
    echo "    --status                 Show resolved/unresolved counts"
    echo "    --resolve <thread-id>    Resolve a single thread"
    echo "    --resolve-all            Resolve all unresolved threads"
    echo ""
    echo "  <pr#>                      List review comments (default)"
    echo "    --reviewer <name>        Filter by reviewer login"
    echo "    --since <time>           Filter by time (last-push, prev-push, Nh, Nm, ISO 8601)"
    echo ""
    echo "Examples:"
    echo "  ws review yggdrasil threads 8              # List unresolved threads"
    echo "  ws review yggdrasil threads 8 --status     # Thread counts"
    echo "  ws review yggdrasil threads 8 --resolve-all"
    echo "  ws review yggdrasil 8                      # All review comments"
    echo "  ws review ymir 5 --reviewer coderabbitai"
    echo "  ws review yggdrasil 8 --since last-push"
    exit 0
}

review_comments() {
    echo "ERROR: review_comments not yet implemented" >&2
    exit 1
}

review_threads() {
    echo "ERROR: review_threads not yet implemented" >&2
    exit 1
}

# --- Shared setup ---

# Source .env for GH_TOKEN
env_file="$ROOT_DIR/.env"
if [[ -z "${GH_TOKEN:-}" ]] && [[ -f "$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_file"
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "ERROR: GH_TOKEN not set. Create .env from .env.example." >&2
    exit 1
fi

# Handle --help before component parsing (--help is not a valid component name)
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    review_help
fi

# Parse component (first positional arg, always required)
if [[ $# -lt 1 ]]; then
    echo "Usage: ws review <comp> threads <pr#> [--status | --resolve <id> | --resolve-all]" >&2
    echo "       ws review <comp> <pr#> [--reviewer <name>] [--since <time>]" >&2
    echo "" >&2
    echo "Run 'ws review --help' for details." >&2
    exit 1
fi

COMP="$1"
shift

# Validate component name (same regex as ws_validate_component)
if [[ ! "$COMP" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: Invalid component name '$COMP'. Must match [a-z][a-z0-9-]*." >&2
    exit 1
fi

REPO_SLUG="SiliconSaga/$COMP"

# --- Route to subcommand ---
# All function definitions are above this block.

if [[ "${1:-}" == "threads" ]]; then
    shift
    review_threads "$@"
else
    review_comments "$@"
fi
