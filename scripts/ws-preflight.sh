#!/usr/bin/env bash
# ws-preflight.sh — Check that workspace prerequisites are installed.
#
# Reports per-tool status (✓ found / ✗ missing / ⚠ wrong-version) plus
# an install hint for the detected OS when something is missing. Exit
# code 0 if all required tools are present; 1 otherwise. Exit always
# 0 with --soft (prints the same report but doesn't exit nonzero, for
# CI noise control).
#
# This is a read-only check — it never installs anything. Sudo /
# elevation handling is its own future arc.
#
# Usage:
#   ws preflight              Check required + recommended; exit 1 on missing required
#   ws preflight --soft       Same checks, always exit 0 (informational)
#   ws preflight --help

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: ws preflight [--soft]

Check workspace prerequisites and report per-tool status with
install hints for your OS.

  --soft   Always exit 0 (informational). Default exits 1 if any
           required tool is missing.

Required: bash, git, yq (v4+, mikefarah/yq specifically), jq.
Provider: at least one of gh (GitHub) or glab (GitLab).
Recommended (optional): uv (for MCP servers and Python components),
realpath (path canonicalization on macOS — usually present).
HELP
    exit 0
fi

SOFT=false
[[ "${1:-}" == "--soft" ]] && SOFT=true

# Detect OS for install-hint targeting. Bash on Windows reports
# msys/cygwin/mingw under $OSTYPE; macOS is darwin*; Linux is linux*.
case "${OSTYPE:-}" in
    darwin*)            OS="mac" ;;
    linux*)             OS="linux" ;;
    msys*|cygwin*|mingw*) OS="windows" ;;
    *)                  OS="unknown" ;;
esac

# Per-OS install hints. Each hint is a short imperative the user can
# copy-paste. Windows defaults to winget (built-in on Win 10/11);
# choco is noted as the elevated-shell alternative for older SKUs or
# locked-down environments where winget isn't available.
hint_for() {
    local tool="$1"
    case "$OS:$tool" in
        mac:bash)         echo "Should be present. If not: 'brew install bash' (and add to /etc/shells)." ;;
        mac:git)          echo "'brew install git' (or install Xcode Command Line Tools: 'xcode-select --install')." ;;
        mac:yq)           echo "'brew install yq' (Mike Farah's Go-based yq, NOT the Python pip one)." ;;
        mac:jq)           echo "'brew install jq'." ;;
        mac:gh)           echo "'brew install gh'." ;;
        mac:glab)         echo "'brew install glab'." ;;
        mac:uv)           echo "'brew install uv' or 'curl -LsSf https://astral.sh/uv/install.sh | sh'." ;;
        mac:realpath)     echo "Usually present via coreutils. If missing: 'brew install coreutils' (then 'grealpath' or 'PATH=$(brew --prefix coreutils)/libexec/gnubin:\$PATH')." ;;

        linux:bash)       echo "Should be present. Most distros ship bash by default." ;;
        linux:git)        echo "'sudo apt install git' (Debian/Ubuntu) or 'sudo dnf install git' (Fedora)." ;;
        linux:yq)         echo "Download from https://github.com/mikefarah/yq/releases — apt's 'yq' is a different (Python) tool that won't work here." ;;
        linux:jq)         echo "'sudo apt install jq' or 'sudo dnf install jq'." ;;
        linux:gh)         echo "'sudo apt install gh' (after adding the GitHub CLI repo — see https://cli.github.com)." ;;
        linux:glab)       echo "Download from https://gitlab.com/gitlab-org/cli/-/releases — distro packages are spotty." ;;
        linux:uv)         echo "'curl -LsSf https://astral.sh/uv/install.sh | sh'." ;;
        linux:realpath)   echo "Usually present via coreutils. 'sudo apt install coreutils' if missing." ;;

        windows:bash)     echo "Use Git Bash (bundled with Git for Windows). Run all 'ws' commands from a Git Bash shell, not cmd.exe or PowerShell." ;;
        windows:git)      echo "'winget install Git.Git' (includes Git Bash). https://git-scm.com/download/win is the manual installer." ;;
        windows:yq)       echo "'winget install MikeFarah.yq'. Fallback: 'choco install yq' from an ELEVATED PowerShell (right-click → Run as administrator)." ;;
        windows:jq)       echo "'winget install jqlang.jq'. Fallback: 'choco install jq' from elevated PowerShell." ;;
        windows:gh)       echo "'winget install GitHub.cli'. Fallback: 'choco install gh' from elevated PowerShell." ;;
        windows:glab)     echo "'winget install GLab.GLab'. Fallback: download from https://gitlab.com/gitlab-org/cli/-/releases." ;;
        windows:uv)       echo "'winget install astral-sh.uv'. Fallback: 'powershell -c \"irm https://astral.sh/uv/install.ps1 | iex\"'." ;;
        windows:realpath) echo "Comes with Git Bash; if missing, reinstall Git for Windows." ;;

        *) echo "See https://github.com/mikefarah/yq, https://cli.github.com, etc., for install instructions on your platform." ;;
    esac
}

# Report a single tool. Args: tool name, severity (required|provider|optional), version-check (optional).
# Sets MISSING_REQUIRED=1 in the parent scope when something required is absent.
MISSING_REQUIRED=0
MISSING_PROVIDER=0
PROVIDER_FOUND=0

check_tool() {
    local name="$1"
    local severity="$2"
    local version_check="${3:-}"

    if ! command -v "$name" &>/dev/null; then
        case "$severity" in
            required) echo "  ✗ $name (required) — not found"; MISSING_REQUIRED=1 ;;
            provider) echo "  ✗ $name (provider) — not found"; MISSING_PROVIDER=$((MISSING_PROVIDER + 1)) ;;
            optional) echo "  ⚠ $name (optional) — not found" ;;
        esac
        echo "       hint: $(hint_for "$name")"
        return
    fi

    [[ "$severity" == "provider" ]] && PROVIDER_FOUND=1

    if [[ -n "$version_check" ]]; then
        # Version check is a small bash snippet that exits 0 if the
        # installed version is acceptable, nonzero otherwise.
        if eval "$version_check"; then
            echo "  ✓ $name"
        else
            case "$severity" in
                required) echo "  ⚠ $name — found, but version check failed"; MISSING_REQUIRED=1 ;;
                *)        echo "  ⚠ $name — found, but version check failed" ;;
            esac
            echo "       hint: $(hint_for "$name")"
        fi
    else
        echo "  ✓ $name"
    fi
}

echo "Workspace prerequisites check (OS: $OS)"
echo ""

echo "Required:"
check_tool bash required
check_tool git  required
# yq must be Mike Farah's Go-based yq v4+. The Python yq prints
# usage lines that don't include "mikefarah" and uses different
# syntax — we'd misbehave silently if pointed at it.
check_tool yq required 'yq --version 2>&1 | grep -qE "(mikefarah|version v?4\.)"'
check_tool jq required

echo ""
echo "Provider CLI (need at least one):"
check_tool gh   provider
check_tool glab provider

echo ""
echo "Optional (only needed for specific component types):"
check_tool uv       optional
check_tool realpath optional

echo ""

if [[ "$MISSING_REQUIRED" -eq 1 ]]; then
    echo "✗ Some required tools are missing or wrong version. See hints above."
    [[ "$SOFT" == false ]] && exit 1
fi

if [[ "$PROVIDER_FOUND" -eq 0 ]]; then
    echo "✗ No provider CLI found (need at least one of gh or glab)."
    [[ "$SOFT" == false ]] && exit 1
fi

if [[ "$MISSING_REQUIRED" -eq 0 && "$PROVIDER_FOUND" -eq 1 ]]; then
    echo "✓ All required prerequisites present. You're ready to use 'ws'."
fi
