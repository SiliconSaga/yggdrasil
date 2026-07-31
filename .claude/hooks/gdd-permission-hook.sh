#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# gdd-permission-hook.sh — Claude Code tool-permission hook (GDD)
# ─────────────────────────────────────────────────────────────────────
#
# PURPOSE
# Fires on PreToolUse for Bash (four-tier deny/ask/allow logic), for
# Edit/Write (scratch-dir auto-allow), and for PowerShell (deny-by-
# default with a test-wrapper carve-out + `powershell` bypass slug —
# see the PowerShell branch below). Has dormant PermissionRequest
# support wired in but not registered by default. Inspects the tool
# input and emits one of four outcomes:
#
#   1. ALLOW   → emit JSON instructing the harness to skip its prompt
#                and run the command. The hook becomes the trust
#                source for that specific call.
#   2. DENY    → emit JSON instructing the harness to block the call
#                AND attach a human-readable reason that the agent
#                sees on the next turn. The reason is the corrective
#                feedback loop — vague denies don't teach.
#   3. ASK     → emit JSON telling the harness to prompt the user for
#                this call regardless of permission mode (acceptEdits
#                included). Unlike DENY it does not block — the agent
#                runs the command once the human approves.
#   4. (none)  → exit 0 with no JSON. Harness treats this as "no
#                opinion" and falls back to its normal flow (consult
#                its own permissions.allow, then prompt the user if
#                no static match).
#
# The hook never modifies the command — only inspects and decides.
# Hook decisions are deterministic; the agent is not.
#
# ─── THREAT MODEL ───────────────────────────────────────────────────
#
# A hook can only see the literal command STRING. It cannot see what
# the command will actually DO at runtime. Treat allowlist patterns
# as "I trust the verb + arguments at this surface level" — never
# allow patterns that could mask destructive operations through
# innocuous-looking syntax (e.g. `find ... -delete`, `rm` variants,
# `chmod` with broad scopes, network calls).
#
# This script is security-sensitive: a permissive pattern here lets
# the agent skip user confirmation for commands matching that pattern.
# Keep deny logic conservative (Tiers 1-3 below) and allow logic narrow
# (Tiers 5-6). Note Tier 1 (composition) is an unconditional deny, while
# Tiers 2 and 3 (redirect + adapter-redirect) are training-aid denies
# with human-approved bypass — do not treat them as a hard security
# floor. When uncertain, default to passthrough — the harness's own
# prompt is the safety net, not a fallback to be eliminated.
#
# ─── DECISION TIERS (in order) ──────────────────────────────────────
#
# Tier 1 — Shell composition guard (DENY)
#   Reject any command containing &&, ||, ;, |, command substitution
#   (`...` or $(...)), or output/input redirection (>, <). Each arm
#   denies with a specific corrective message so the agent learns
#   what to do instead. This trains the agent to use one tool call
#   per action and to prefer native flags (--limit, --output) over
#   shell pipelines.
#
# Tier 2 — Redirect deny (DENY, with per-slug bypass override)
#   Commands matching a [redirect-commands] entry in hook-rules deny
#   with a corrective message pointing at the right `ws` subcommand
#   (e.g. `git commit` → use `ws commit`). Each entry declares a slug
#   (column 1), the deny pattern (column 2), and the suggestion text
#   (column 3, free text).
#
#   A session-scoped bypass marker — written by `ws hook-bypass
#   <slug>` after a human-approved ask prompt — overrides the deny
#   for that slug. The marker lives at .tmp/hook-bypass/<slug>.bypass
#   and is honored only when its session_id matches the current
#   session id (this hook reads it from the stdin payload's
#   `.session_id`; `ws hook-bypass` writes it from
#   $CLAUDE_CODE_SESSION_ID — the same UUID). Marker hits log
#   BYPASS-ALLOW to the audit log
#   with the slug + optional reason.
#
# Tier 3 — Adapter-aware redirect (DENY-OR-NUDGE, with per-slug bypass)
#   Commands matching an [adapter-redirect-commands] entry route based
#   on whether the realm's adapter file declares the verb wired:
#     - $cwd inside components/<comp>/ AND adapter has commands.<verb>
#       → DENY with a `ws <verb> <comp>` pointer (same bypass-marker
#       shape as Tier 2).
#     - $cwd inside components/<comp>/ AND adapter missing or no
#       commands.<verb> → emit one stderr nudge, fall through to
#       later tiers (the agent's allowlist may still let the raw
#       command run).
#     - $cwd outside any component → rule doesn't fire (workspace-
#       level raw runner invocations are left alone).
#
# Tier 4 — Ask-list from hook-rules [ask-commands] (ASK)
#   Destructive commands that should always prompt, even under
#   acceptEdits. Any match → ask.
#
# Tier 5 — Per-project allowlist from .claude/settings.json (ALLOW)
#   Walk up from $cwd, collect Bash(...) entries from each
#   .claude/settings.json found, then check $HOME/.claude/settings.json
#   too. Glob-match each pattern against the command. Any match → allow.
#
# Tier 6 — [allow-extras] from hook-rules.local (ALLOW, optional)
#   Personal per-machine glob patterns declared in hook-rules.local's
#   [allow-extras] section. Parsed into allow_extras above. Any
#   match → allow. Silently absent if hook-rules.local has no section.
#
# Default — Passthrough
#   Exit 0 with no JSON. Harness handles as normal.
#
# Config: the scratch-dir, ask-command, and redirect-command lists
# live in .claude/hooks/hook-rules (committed baseline); per-machine
# additions and [allow-extras] live in hook-rules.local (gitignored).
# See .claude/hooks/README.md.
#
# ─── AUDIT LOG ──────────────────────────────────────────────────────
#
# Every ALLOW and DENY is appended to $HOME/.claude/hook-audit.log
# with timestamp and reason. Passthroughs are NOT logged (would
# overwhelm the file under normal use). Review the log periodically:
#
#   - ALLOW entries you didn't want → narrow the matching pattern
#   - DENY entries that should have worked → refine the deny message
#     or add a settings.json / extras allow rule for that command
#
# ─── REGISTRATION ───────────────────────────────────────────────────
#
# This script ships in the yggdrasil repo at .claude/hooks/. Register
# in the project's .claude/settings.json (committed — applies to
# everyone working in the repo):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             { "type": "command",
#               "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/gdd-permission-hook.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# $CLAUDE_PROJECT_DIR is set by Claude Code at hook invocation time
# and resolves to the project root — portable across Win / Mac /
# Linux without per-machine path tweaking.
#
# Invoking via `bash <script>` avoids needing chmod +x on Windows
# (where the executable bit doesn't carry through Git Bash uniformly).
#
# The hook-rules.local file (.claude/hooks/hook-rules.local) is
# per-machine / gitignored, NOT shipped in the repo. Each developer
# manages their own local overrides alongside the shared hook-rules.
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Read the tool-call payload from stdin ──────────────────────────
# The harness sends JSON on stdin describing the tool invocation:
#   {
#     "session_id": "...",
#     "tool_name": "Bash",
#     "tool_input": { "command": "...", "description": "..." },
#     "cwd": "..."
#   }
# We need .tool_input.command to match patterns against, and .cwd
# to anchor the upward walk for project-scoped settings.json files.
input=$(cat)

# ─── jq prerequisite check ──────────────────────────────────────────
#
# The hook parses its JSON payload with jq and emits deny decisions
# as JSON via jq. Without jq on PATH, every jq invocation below
# would fail under `set -e` and the hook would crash on every Bash
# tool call — including the user trying to run `ws preflight` to
# diagnose what's missing. Chicken-and-egg trap.
#
# Stdin is already drained above (line 118), so exiting now doesn't
# leave the harness writing into a closed pipe. Fall back to
# passthrough so the harness's own permission flow still applies.
# Log a single warning to the audit file so a confused user has
# somewhere to look for the cause.
if ! command -v jq >/dev/null; then
    audit_log="$HOME/.claude/hook-audit.log"
    mkdir -p "$(dirname "$audit_log")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PASSTHROUGH (jq not on PATH): hook cannot function without jq. Install jq and re-run 'ws preflight' to verify." >> "$audit_log"
    exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# Native Windows jq writes its output stream in text mode, translating every
# LF to CRLF — so a command with an embedded newline reaches this hook with
# an injected CR the harness will never execute (bash line-continuation
# parsing then misses, and quote-state walkers see a stray control char).
# The translation is exactly invertible: content LF → CRLF and content CRLF
# → CR+CRLF, so collapsing CRLF back to LF restores the original string
# byte-for-byte. Probe the jq binary once and undo only when it translates —
# POSIX jq passes through untouched, and a genuine lone CR (the Tier-1
# deny case) survives on both.
if [[ "$cmd" == *$'\r\n'* ]]; then
    _jq_probe="$(jq -rn '"a\nb"')"
    if [[ "$_jq_probe" == *$'\r'* ]]; then
        cmd="${cmd//$'\r\n'/$'\n'}"
    fi
fi

# Externally-supplied paths (payload cwd/file_path, CLAUDE_PROJECT_DIR)
# arrive in whatever form the host favors — POSIX /tmp/x, C:/x, or D:\x on
# Windows, and any mix of the three for the SAME location once MSYS path
# conversion or a native harness is involved. Every tier below compares
# paths textually, so one input in a different form silently defeats the
# comparison (an anchored prefix match that never matches fails open as
# passthrough). Normalize every external path to POSIX form up front:
# cygpath reconciles drive-letter, backslash, and mount forms on Git Bash;
# on POSIX hosts it is absent and paths are already consistent.
_normalize_host_path() {
    local p="$1"
    if [[ -n "$p" ]] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$p" 2>/dev/null || printf '%s' "$p"
        return
    fi
    printf '%s' "$p"
}

# Security-sensitive workspace names and configured scratch roots must compare
# consistently on case-insensitive filesystems. Apply an ASCII-only fold for
# policy matching while preserving the original path for filesystem access and
# audit output. ASCII covers every reserved workspace path and avoids locale-
# dependent surprises in `tr`.
_policy_path_fold() {
    if [[ "${_policy_case_insensitive_paths:-0}" == "1" ]]; then
        LC_ALL=C printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
        return
    fi
    printf '%s' "$1"
}

# Fall back to the script's own pwd if the harness didn't supply
# a cwd field — better than aborting on a missing key.
cwd=$(echo "$input" | jq -r '.cwd // empty')
[[ -z "$cwd" ]] && cwd=$(pwd)
cwd="$(_normalize_host_path "$cwd")"

# Which hook event are we firing on? The same script supports both
# PreToolUse and PermissionRequest — the output JSON shape and the
# allowed decision values differ between events, so we branch on this
# in allow() / deny(). Default to PreToolUse when the field is missing
# (e.g., a manual `bash hook.sh < payload.json` test that omits it).
event=$(echo "$input" | jq -r '.hook_event_name // "PreToolUse"')

# Which tool is being invoked? The script handles a small set:
# Bash (the main case, with command-pattern allowlists) and the
# file-editing tools Edit/Write (path-based scratch-dir allowlist).
# The tool routing block (after the helpers) short-circuits non-Bash
# tools before the Bash-only tier logic runs.
tool_name=$(echo "$input" | jq -r '.tool_name // ""')

# Anchor project policy to the harness project root, never to the command cwd.
# A component or realm may contain its own .claude files, but those nested
# files are content inside this workspace—not authorities over the root hook.
_hook_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
_trusted_root="$(_normalize_host_path "${CLAUDE_PROJECT_DIR:-$_hook_root}")"
if [[ ! -d "$_trusted_root" ]]; then
    _trusted_root="$_hook_root"
fi

# Detect the project filesystem's case behavior without creating a probe file.
# The committed `.claude` directory is always present; `-ef` proves that its
# upper-case spelling resolves to the same inode rather than a distinct Linux
# path. Only case-fold scratch roots when the filesystem requires it, so a
# separate `.TMP` directory on a case-sensitive host never gains scratch trust.
_policy_case_insensitive_paths=0
if [[ -e "$_trusted_root/.claude" && "$_trusted_root/.claude" -ef "$_trusted_root/.CLAUDE" ]]; then
    _policy_case_insensitive_paths=1
fi

# ─── Opt-out escape hatch ───────────────────────────────────────────
# A user can disable this hook entirely on their own machine without
# editing the committed settings.json. Set WS_HOOK_DISABLE=1 in your
# shell, .env, or a shell profile to make every invocation return
# passthrough immediately. The harness then falls back to its normal
# permission flow (consult permissions.allow, prompt the user if no
# match). The hook installation stays intact for everyone else.
#
# Stdin is already drained above, so exiting now doesn't leave the
# harness writing into a closed pipe.
#
# Compare to literal "1" — NOT a non-empty check. The non-empty form
# would treat `WS_HOOK_DISABLE=0` as "disable", which is the opposite
# of every other env-var-flag convention. Documentation already says
# "set WS_HOOK_DISABLE=1", so users expect 1-means-on.
if [[ "${WS_HOOK_DISABLE:-0}" == "1" ]]; then
    exit 0
fi

# ─── Audit log path ─────────────────────────────────────────────────
audit_log="$HOME/.claude/hook-audit.log"
mkdir -p "$(dirname "$audit_log")"

# ─── Decision helpers ───────────────────────────────────────────────

# allow() — emit the JSON the harness expects to skip its own prompt.
# The minimal allow object: hookEventName + permissionDecision: allow.
# Logged with the reason so the audit trail shows which rule fired.
# audit_safe() — flatten embedded newlines / carriage returns to
# their literal `\n` / `\r` escape sequences. Without this, an input
# containing newlines would split a single audit entry across
# multiple lines — corrupting the log's one-entry-per-line shape and
# making `tail -100` or grep behave unpredictably.
#
# Applied to BOTH $cmd and $reason: while $cmd comes through jq from
# the agent's tool call (clearly user-controlled), $reason isn't
# fully hard-coded either — `allow "settings.json: $raw"` and
# `allow "extras ${file}: $line"` embed user-controlled pattern
# strings. In practice `read -r` already strips embedded newlines
# from those sources, but the defense-in-depth costs nothing and
# the comment now matches the actual call surface.
audit_safe() {
    local s="$1"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

#
# Output shape differs per event:
#   PreToolUse       → hookSpecificOutput.permissionDecision = "allow"
#   PermissionRequest → hookSpecificOutput.decision.behavior  = "allow"
# Both bypass the prompt for that event. PermissionRequest has no
# "defer"/"ask" — passthrough (no JSON, exit 0) is the only way to
# yield to other hooks or the default prompt for that event.
allow() {
    local reason="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALLOW [$event] ($(audit_safe "$reason")): $(audit_safe "$cmd")" >> "$audit_log"
    if [[ "$event" == "PermissionRequest" ]]; then
        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    else
        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    fi
    exit 0
}

# deny() — block the command AND surface an explanation to the agent.
# permissionDecisionReason is the field the harness reads when
# composing the agent-visible block message. Without a reason field
# the agent sees only "blocked" with no guidance, which doesn't
# correct future behavior — defeating the point of an enforcing hook.
#
# Output shape differs per event:
#   PreToolUse       → hookSpecificOutput.permissionDecision = "deny"
#                       + permissionDecisionReason (agent-visible)
#   PermissionRequest → hookSpecificOutput.decision.behavior  = "deny"
#                       (no documented reason field; corrective text
#                       still appears in the audit log)
deny() {
    local reason="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DENY [$event] ($(audit_safe "$reason")): $(audit_safe "$cmd")" >> "$audit_log"
    if [[ "$event" == "PermissionRequest" ]]; then
        jq -nc '{
          hookSpecificOutput: {
            hookEventName: "PermissionRequest",
            decision: { behavior: "deny" }
          }
        }'
    else
        jq -nc --arg reason "$reason" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
          }
        }'
    fi
    exit 0
}

# ask() — force a permission prompt without blocking. Used by the
# Tier 4 ask-list for destructive-but-sometimes-legitimate commands.
# Unlike deny(), the agent can still run the command once the human
# approves; unlike allow(), it never auto-runs. The `ask` decision
# overrides the harness's permission mode — it prompts even under
# acceptEdits / bypassPermissions.
#
# PermissionRequest has no "ask" behavior; for that event the hook
# passes through (exit 0, no JSON), which yields to the default
# prompt — the same net effect. (PermissionRequest is dormant in this
# workspace; this branch is parity-only.)
ask() {
    local reason="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ASK [$event] ($(audit_safe "$reason")): $(audit_safe "$cmd")" >> "$audit_log"
    if [[ "$event" == "PermissionRequest" ]]; then
        exit 0
    fi
    jq -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}

# ─── Hook rules config ──────────────────────────────────────────────
#
# Flat sectioned text at .claude/hooks/hook-rules (committed baseline)
# and .claude/hooks/hook-rules.local (gitignored per-machine override).
# Parsed by pure bash — no yq/jq dependency for config. Four sections:
#   [scratch-dirs]      — Edit/Write auto-allow path prefixes (Tier consumer)
#   [redirect-commands] — Tier 2 redirect-deny entries (slug | pattern | suggestion)
#   [adapter-redirect-commands] — Tier 3 adapter-aware deny-or-nudge entries
#                          (slug | pattern | verb)
#   [ask-commands]      — Tier 4 ask-list glob patterns
#   [allow-extras]      — Tier 6 allow glob patterns (hook-rules.local ONLY;
#                         an [allow-extras] section in the committed hook-rules
#                         is silently inert — only per-machine local files may
#                         grant Tier 6 allows)
# hook-rules.local entries ADD to the baseline (additive merge).
scratch_dirs=()
ask_commands=()
allow_extras=()
redirect_commands=()  # entries: "<slug>|<pattern>|<suggestion>"
adapter_redirect_commands=()  # entries: "<slug>|<pattern>|<verb>"
scoped_redirect_commands=()  # entries: "<slug>|<pattern>|<session-key>|<suggestion>"

# Parse one rules file, appending entries to the section arrays.
# $1 = file path; $2 = non-empty when parsing hook-rules.local (local).
# [allow-extras] entries are honored ONLY when $2 is non-empty.
# A content line before any [section] header is a file error: log a
# warning and skip the rest of that file (degrade to whatever's
# already parsed — never crash the hook).
_parse_rules_file() {
    local file="$1"
    local is_local="${2:-}"
    local section="" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == "#"* ]] && continue
        case "$line" in
            "["*"]")
                section="${line#\[}"
                section="${section%\]}"
                ;;
            *)
                case "$section" in
                    scratch-dirs) scratch_dirs+=("$line") ;;
                    ask-commands) ask_commands+=("$line") ;;
                    allow-extras)
                        # Only honored from hook-rules.local (is_local non-empty).
                        # In the committed hook-rules this section is silently inert.
                        if [[ -n "$is_local" ]]; then
                            allow_extras+=("$line")
                        fi
                        ;;
                    redirect-commands)
                        # Parse three pipe-separated columns: slug | pattern | suggestion.
                        # Split on the first two " | " occurrences; remainder is suggestion.
                        local slug pattern suggestion rest
                        if [[ "$line" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [redirect-commands] entry, missing separator): $file" >> "$audit_log"
                            continue
                        fi
                        slug="${line%% | *}"
                        rest="${line#* | }"
                        if [[ "$rest" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [redirect-commands] entry, only two columns): $file" >> "$audit_log"
                            continue
                        fi
                        pattern="${rest%% | *}"
                        suggestion="${rest#* | }"
                        # Trim trailing whitespace from slug and pattern (suggestion is free text — keep as-is)
                        slug="${slug%"${slug##*[![:space:]]}"}"
                        pattern="${pattern%"${pattern##*[![:space:]]}"}"
                        # Validate slug shape: ^[a-z][a-z0-9-]*$ (must
                        # start with a letter so the `ws hook-bypass [a-z]*`
                        # ask-pattern always catches a slug invocation).
                        if [[ ! "$slug" =~ ^[a-z][a-z0-9-]*$ ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [redirect-commands] entry, bad slug '$slug'): $file" >> "$audit_log"
                            continue
                        fi
                        # Pack as "slug|pattern|suggestion" (internal separator, never displayed)
                        redirect_commands+=("$slug|$pattern|$suggestion")
                        ;;
                    adapter-redirect-commands)
                        # Parse three pipe-separated columns: slug | pattern | verb.
                        # Verb is one of test/lint/build — the ws subcommand the
                        # raw command maps to, AND the key under `commands.` in
                        # the realm's adapter file (realms/<r>/adapters/<comp>.yaml).
                        local ar_slug ar_pattern ar_verb ar_rest
                        if [[ "$line" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [adapter-redirect-commands] entry, missing separator): $file" >> "$audit_log"
                            continue
                        fi
                        ar_slug="${line%% | *}"
                        ar_rest="${line#* | }"
                        if [[ "$ar_rest" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [adapter-redirect-commands] entry, only two columns): $file" >> "$audit_log"
                            continue
                        fi
                        ar_pattern="${ar_rest%% | *}"
                        ar_verb="${ar_rest#* | }"
                        ar_slug="${ar_slug%"${ar_slug##*[![:space:]]}"}"
                        ar_pattern="${ar_pattern%"${ar_pattern##*[![:space:]]}"}"
                        ar_verb="${ar_verb%"${ar_verb##*[![:space:]]}"}"
                        ar_verb="${ar_verb#"${ar_verb%%[![:space:]]*}"}"
                        if [[ ! "$ar_slug" =~ ^[a-z][a-z0-9-]*$ ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [adapter-redirect-commands] entry, bad slug '$ar_slug'): $file" >> "$audit_log"
                            continue
                        fi
                        # Verb must be a known ws action surface — keeps the
                        # adapter lookup predictable and prevents typos from
                        # silently degrading to "no commands.X found".
                        case "$ar_verb" in
                            test|lint|build) ;;
                            *)
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [adapter-redirect-commands] entry, bad verb '$ar_verb' — must be test/lint/build): $file" >> "$audit_log"
                                continue
                                ;;
                        esac
                        adapter_redirect_commands+=("$ar_slug|$ar_pattern|$ar_verb")
                        ;;
                    scoped-redirect-commands)
                        # 4 columns: slug | pattern | session-key | suggestion.
                        local sr_slug sr_pattern sr_key sr_suggestion sr_rest
                        if [[ "$line" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [scoped-redirect-commands], missing separator): $file" >> "$audit_log"
                            continue
                        fi
                        sr_slug="${line%% | *}"; sr_rest="${line#* | }"
                        sr_pattern="${sr_rest%% | *}"; sr_rest="${sr_rest#* | }"
                        if [[ "$sr_rest" != *" | "* ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: malformed [scoped-redirect-commands], need 4 columns): $file" >> "$audit_log"
                            continue
                        fi
                        sr_key="${sr_rest%% | *}"; sr_suggestion="${sr_rest#* | }"
                        sr_slug="${sr_slug%"${sr_slug##*[![:space:]]}"}"
                        sr_pattern="${sr_pattern%"${sr_pattern##*[![:space:]]}"}"
                        sr_key="${sr_key%"${sr_key##*[![:space:]]}"}"
                        if [[ ! "$sr_slug" =~ ^[a-z][a-z0-9-]*$ ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: bad slug '$sr_slug'): $file" >> "$audit_log"
                            continue
                        fi
                        scoped_redirect_commands+=("$sr_slug|$sr_pattern|$sr_key|$sr_suggestion")
                        ;;
                    *)
                        if [[ -z "$section" ]]; then
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: content before any [section] header, file skipped): $file" >> "$audit_log"
                        else
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING (hook-rules: unknown section [$section], file skipped): $file" >> "$audit_log"
                        fi
                        return
                        ;;
                esac
                ;;
        esac
    done < "$file"
}

# The committed baseline and operator-local additive override are the only
# rule files. Nested components, realms, and hoards cannot replace them.
_rules_dir="$_trusted_root/.claude/hooks"
if [[ -f "$_rules_dir/hook-rules" ]]; then
    _parse_rules_file "$_rules_dir/hook-rules"
    [[ -f "$_rules_dir/hook-rules.local" ]] && _parse_rules_file "$_rules_dir/hook-rules.local" local
fi
# Source the k8s guard for scoped-redirect evaluation (Tier 2b). Track whether
# the policy loaded: Kubernetes-looking commands must force-ask if the guard is
# missing or broken, rather than silently dropping the safety floor.
# Use BASH_SOURCE[0] so the path resolves relative to the hook file
# itself (two levels up from .claude/hooks/ to the workspace root),
# not relative to the agent's cwd — the agent's cwd can be anywhere.
# Deviation from brief: brief used ${_rules_dir%/.claude/hooks}/scripts/
# which fails in the test environment (cwd → $WORK, no $WORK/scripts/).
_k8s_guard_loaded=0
# shellcheck source=../../scripts/ws-k8s-guard.sh
if source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/ws-k8s-guard.sh" 2>/dev/null \
    && declare -F k8s_guard_evaluate >/dev/null 2>&1; then
    _k8s_guard_loaded=1
fi

# ─── Tool routing: non-Bash branch (Edit / Write) ──────────────────
#
# Edit and Write decisions are path-based, not command-pattern-based.
# Paths under any configured scratch directory auto-allow; everything
# else falls through to the harness's normal prompt flow. Scratch
# dirs come from the [scratch-dirs] section of hook-rules (parsed
# above) and are anchored to $CLAUDE_PROJECT_DIR (with a $cwd
# fallback for manual test invocations).
#
# Defense-in-depth: tools not handled here (Read, MCP, WebFetch, etc.)
# shouldn't reach this script because the matcher in settings.json
# names the supported tools explicitly. If one slips through anyway,
# the fall-through `exit 0` at the bottom of the branch means
# passthrough — the harness's normal flow handles it.
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
    project_dir="$_trusted_root"
    file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    file_path="$(_normalize_host_path "$file_path")"

    # Traversal and symlink aliases must never inherit the scratch auto-allow,
    # but resolve them before falling through: an alias may target protected
    # workspace state that requires an explicit human decision even when the
    # host is otherwise running in acceptEdits mode.
    edit_alias_path=0
    case "$file_path" in
        ..|../*|*/..|*/../*)
            edit_alias_path=1
            ;;
    esac

    # Anchor relative paths to the project root before comparing.
    case "$file_path" in
        /*) abs_path="$file_path" ;;
        *)  abs_path="$project_dir/$file_path" ;;
    esac

    # Follow a symlink at the final path element before resolving the parent.
    # `pwd -P` below handles symlinked ancestors; this bounded loop covers the
    # otherwise-missed `.tmp/alias -> ../.env` shape. Any resolution failure
    # falls through to the host rather than gaining a scratch allow.
    resolve_path="$abs_path"
    edit_link_depth=0
    while [[ -L "$resolve_path" ]]; do
        edit_alias_path=1
        edit_link_depth=$((edit_link_depth + 1))
        [[ "$edit_link_depth" -le 32 ]] || exit 0
        edit_link_target="$(readlink "$resolve_path" 2>/dev/null)" || exit 0
        case "$edit_link_target" in
            /*) resolve_path="$edit_link_target" ;;
            *) resolve_path="${resolve_path%/*}/$edit_link_target" ;;
        esac
    done

    # Resolve the deepest existing directory ancestor of the effective target
    # with `cd … && pwd -P` and confirm it remains under the resolved project
    # root. Resolving both sides also handles a symlinked project checkout.
    #
    # `cd`/`pwd -P` is POSIX and needs no `realpath` (which varies
    # across OSes). Any failure → passthrough, never a false allow.
    sym_probe="${resolve_path%/*}"
    unresolved_suffix=""
    while [[ ! -d "$sym_probe" && "$sym_probe" == */* ]]; do
        unresolved_suffix="/${sym_probe##*/}$unresolved_suffix"
        sym_probe="${sym_probe%/*}"
    done
    real_probe="$(cd "$sym_probe" 2>/dev/null && pwd -P)" || exit 0
    real_project="$(cd "$project_dir" 2>/dev/null && pwd -P)" || exit 0
    resolved_abs_path="$real_probe$unresolved_suffix/${resolve_path##*/}"
    case "$real_probe/" in
        "$real_project/"*) : ;;   # resolves inside the project — OK
        *) exit 0 ;;              # resolves outside — passthrough
    esac

    # Guard state and security configuration must never inherit the broad
    # scratch-directory auto-allow. Check both the requested path and its
    # resolved ancestor so a scratch symlink alias cannot hide a sensitive
    # destination inside the workspace.
    abs_path_fold="$(_policy_path_fold "$abs_path")"
    project_dir_fold="$(_policy_path_fold "$project_dir")"
    resolved_abs_path_fold="$(_policy_path_fold "$resolved_abs_path")"
    real_project_fold="$(_policy_path_fold "$real_project")"
    sensitive_path=0
    sensitive_sessions_only=1
    case "$abs_path_fold" in
        "$project_dir_fold/.tmp/gdd-agent-sessions"|"$project_dir_fold/.tmp/gdd-agent-sessions/"*)
            sensitive_path=1
            ;;
        "$project_dir_fold/.tmp/hook-bypass"|"$project_dir_fold/.tmp/hook-bypass/"*|\
        "$project_dir_fold/.claude"|"$project_dir_fold/.claude/"*|\
        "$project_dir_fold/.env"|"$project_dir_fold/ecosystem.local.yaml"|\
        "$project_dir_fold/scripts/ws-k8s-guard.sh")
            sensitive_path=1
            sensitive_sessions_only=0
            ;;
    esac
    case "$resolved_abs_path_fold" in
        "$real_project_fold/.tmp/gdd-agent-sessions"|"$real_project_fold/.tmp/gdd-agent-sessions/"*)
            sensitive_path=1
            ;;
        "$real_project_fold/.tmp/hook-bypass"|"$real_project_fold/.tmp/hook-bypass/"*|\
        "$real_project_fold/.claude"|"$real_project_fold/.claude/"*|\
        "$real_project_fold/.env"|"$real_project_fold/ecosystem.local.yaml"|\
        "$real_project_fold/scripts/ws-k8s-guard.sh")
            sensitive_path=1
            sensitive_sessions_only=0
            ;;
    esac

    # Session env-file carve-out. Sub-agents legitimately create their own
    # identity files here at birth (ws commit --co-author-file reads
    # .tmp/gdd-agent-sessions/<name>.env), and a session replacing its own
    # complete <sid>.env is equivalent to the allowlisted `ws whoami --set` — so a
    # blanket ask converts every sub-agent dispatch into prompt noise.
    # Reclassify as non-sensitive (falling through to the scratch tier)
    # only when ALL of these hold:
    #   - both the requested and resolved parents ARE the sessions dir
    #     itself (a symlinked ancestor cannot smuggle the write elsewhere)
    #   - the target is a single-segment <name>.env
    #   - this is a full-file Write, not a partial Edit whose surrounding
    #     guard-key context is absent from the hook payload
    #   - the complete content carries no guard-scope key (GDD_K8S_*):
    #     arming a kubectl scope must remain a `ws k8s` ceremony
    #   - it is this session's own <sid>.env, or a Write CREATING a file
    #     that does not exist yet (the sub-agent birth case). Overwriting
    #     another session's existing file — identity forgery on a live
    #     session — still asks, as does every partial Edit.
    if [[ "$sensitive_path" -eq 1 && "$sensitive_sessions_only" -eq 1 && "$tool_name" == "Write" ]]; then
        _sess_basename="${abs_path##*/}"
        _sess_ok=0
        if [[ "$(_policy_path_fold "${abs_path%/*}")" == "$project_dir_fold/.tmp/gdd-agent-sessions" ]] \
            && [[ "$(_policy_path_fold "${resolved_abs_path%/*}")" == "$real_project_fold/.tmp/gdd-agent-sessions" ]] \
            && [[ "$_sess_basename" =~ ^[A-Za-z0-9._-]+\.env$ ]]; then
            _sess_new_content=$(echo "$input" | jq -r '.tool_input.content // ""')
            if [[ "$_sess_new_content" != *GDD_K8S_* ]]; then
                _sess_sid=$(echo "$input" | jq -r '.session_id // ""')
                _sess_sid_safe="${_sess_sid//[^A-Za-z0-9._-]/_}"
                if [[ -n "$_sess_sid" && "$_sess_basename" == "$_sess_sid_safe.env" ]]; then
                    _sess_ok=1
                elif [[ ! -e "$abs_path" && ! -e "$resolved_abs_path" ]]; then
                    _sess_ok=1
                fi
            fi
        fi
        if [[ "$_sess_ok" -eq 1 ]]; then
            sensitive_path=0
        fi
    fi

    if [[ "$sensitive_path" -eq 1 ]]; then
        cmd="$tool_name $file_path"
        ask "This edit changes security-sensitive workspace state or configuration and requires human approval."
    fi

    # Non-sensitive aliases still pass through to the host permission flow;
    # they never inherit a textual scratch-directory auto-allow.
    [[ "$edit_alias_path" -eq 1 ]] && exit 0

    # Scratch dirs that auto-allow Edit / Write come from the
    # [scratch-dirs] section of hook-rules (parsed above). The baseline
    # mirrors the "Workspace-local scratch" section of .gitignore;
    # hook-rules.local may add more. If no hook-rules file was found,
    # scratch_dirs is empty and every Edit/Write passes through.
    for prefix in ${scratch_dirs[@]+"${scratch_dirs[@]}"}; do
        prefix_fold="$(_policy_path_fold "$prefix")"
        if [[ "$abs_path_fold" == "$project_dir_fold/$prefix_fold"* ]]; then
            # cmd is empty for Edit/Write — re-purpose it so the
            # audit-log entry names the tool + path instead of
            # silently logging a blank command.
            cmd="$tool_name $file_path"
            allow "scratch-dir: $prefix"
        fi
    done

    # No scratch-dir match → passthrough so the harness prompts.
    exit 0
fi

# ─── Tool routing: PowerShell branch (deny-by-default) ──────────────
#
# Policy (2026-06-11): PowerShell is not part of the workspace toolkit.
# The `ws` CLI + Bash tool cover the sanctioned surface, and porting the
# Bash tiers to PowerShell grammar would be a large, error-prone job for
# a tool agents shouldn't be drifting into (PS 5.1 has no && / ||, so
# `;` is its ONLY statement separator — a naive port of the Tier 1 deny
# rules would be unusable rather than safe). So: deny everything, with
# two narrow exceptions —
#
#   1. Component kuttl test wrappers. kuttl ships no native Windows
#      binary, so components wrap it in Docker via test.ps1 (mimir,
#      nidavellir). The shapes `./test.ps1 [args]` and
#      `Set-Location <dir>; ./test.ps1 [args]` auto-allow, with both
#      segments restricted to composition-free characters. As with bash
#      scripts, the hook audits the invocation string only — script
#      internals are out of scope by design.
#   2. A session-scoped bypass marker (`ws hook-bypass powershell`),
#      human-approved through the ask tier like every other slug — for
#      the rare legitimate raw-PowerShell need (e.g. piping payloads
#      into THIS hook while debugging it, which Bash Tier 1 blocks).
if [[ "$tool_name" == "PowerShell" ]]; then
    # Carve-out: component test wrapper, optionally preceded by ONE
    # Set-Location/cd (the PowerShell tool's cwd persists across calls,
    # so suite runs are typically `Set-Location <comp>; ./test.ps1 …`).
    # The character class excludes composition, redirection, variable /
    # subexpression expansion, backticks, and script blocks in BOTH the
    # path and the args — `./test.ps1 $(...)` must not slip through.
    #
    # CR/LF guard first: newline is a full statement separator in
    # PowerShell, and both [[:space:]] and a negated bracket class match
    # it — so without this case arm, `./test.ps1<newline>Remove-Item …`
    # would satisfy the regex and auto-allow (caught in review by
    # CodeRabbit + Copilot, repro-verified). The Bash branch's Tier 1
    # newline deny never runs for PowerShell, so the rejection has to
    # live here. The [ \t]-only separators below are belt-and-braces.
    case "$cmd" in
        *$'\n'*|*$'\r'*)
            : ;;  # multi-line — never carve-out; fall through to deny/bypass
        *)
            _ps_seg='[^;|&<>$`(){}'$'\n\r'']'
            _ps_wrapper_re="^(([Ss]et-[Ll]ocation|cd)[ \t]+${_ps_seg}+;[ \t]*)?\.[/\\]test\.ps1([ \t]${_ps_seg}*)?$"
            if [[ "$cmd" =~ $_ps_wrapper_re ]]; then
                # Scratch directories are intentionally agent-writable, so a
                # test.ps1 stored there has no trusted provenance. Resolve the
                # optional Set-Location/cd prefix (or use the payload cwd) and
                # skip the carve-out whenever it points into a configured
                # scratch root. The normal PowerShell bypass remains available
                # for a human-approved exceptional run.
                _ps_effective_dir="$cwd"
                if [[ "$cmd" == *";"* ]]; then
                    _ps_location="${cmd%%;*}"
                    _ps_location="${_ps_location#* }"
                    _ps_location="${_ps_location#\"}"
                    _ps_location="${_ps_location%\"}"
                    _ps_location="${_ps_location#\'}"
                    _ps_location="${_ps_location%\'}"
                    case "$_ps_location" in
                        /*|[A-Za-z]:[/\\]*) _ps_effective_dir="$_ps_location" ;;
                        *) _ps_effective_dir="$cwd/$_ps_location" ;;
                    esac
                fi
                _ps_effective_dir="$(_normalize_host_path "$_ps_effective_dir")"
                if _ps_resolved_dir="$(cd "$_ps_effective_dir" 2>/dev/null && pwd -P)"; then
                    _ps_effective_dir="$(_normalize_host_path "$_ps_resolved_dir")"
                fi
                _ps_project_root="$_trusted_root"
                if _ps_resolved_root="$(cd "$_trusted_root" 2>/dev/null && pwd -P)"; then
                    _ps_project_root="$(_normalize_host_path "$_ps_resolved_root")"
                fi
                _ps_effective_dir_fold="$(_policy_path_fold "$_ps_effective_dir")"
                _ps_project_root_fold="$(_policy_path_fold "$_ps_project_root")"
                _ps_scratch=0
                case "$_ps_effective_dir" in
                    ..|../*|*/..|*/../*) _ps_scratch=1 ;;
                esac
                for _ps_prefix in ${scratch_dirs[@]+"${scratch_dirs[@]}"}; do
                    _ps_prefix_fold="$(_policy_path_fold "${_ps_prefix%/}")"
                    _ps_scratch_root_fold="$_ps_project_root_fold/$_ps_prefix_fold"
                    case "$_ps_effective_dir_fold/" in
                        "$_ps_scratch_root_fold/"*) _ps_scratch=1; break ;;
                    esac
                done
                [[ "$_ps_scratch" -eq 1 ]] || allow "powershell test-wrapper carve-out"
            fi
            ;;
    esac

    # Session-scoped bypass marker — same mechanics as the Tier 2/3
    # slugs (written by `ws hook-bypass powershell`, honored only when
    # its session_id matches the current session). Project root prefers
    # CLAUDE_PROJECT_DIR, then the hook-rules dir found by the config
    # walk, then $cwd — the marker lives at <root>/.tmp/hook-bypass/.
    _ps_session_id=$(echo "$input" | jq -r '.session_id // ""')
    _ps_project_root="${CLAUDE_PROJECT_DIR:-}"
    if [[ -z "$_ps_project_root" && -n "${_rules_dir:-}" ]]; then
        _ps_project_root="${_rules_dir%/.claude/hooks}"
    fi
    [[ -z "$_ps_project_root" ]] && _ps_project_root="$cwd"
    _ps_marker="$_ps_project_root/.tmp/hook-bypass/powershell.bypass"
    if [[ -f "$_ps_marker" ]]; then
        _ps_marker_sid=$(grep '^session_id:' "$_ps_marker" 2>/dev/null | sed 's/^session_id: *//' || true)
        _ps_marker_reason=$(grep '^reason:' "$_ps_marker" 2>/dev/null | sed 's/^reason: *//' || true)
        if [[ -n "$_ps_session_id" && "$_ps_marker_sid" == "$_ps_session_id" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-ALLOW [powershell] reason=\"$(audit_safe "$_ps_marker_reason")\" [$event]: $(audit_safe "$cmd")" >> "$audit_log"
            if [[ "$event" == "PermissionRequest" ]]; then
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
            else
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
            fi
            exit 0
        fi
    fi

    deny "PowerShell is blocked by default in this workspace — use the Bash tool with the \`ws\` wrappers (see AGENTS.md Reflex Contract). Exception: component kuttl wrappers run without a prompt as \`./test.ps1 [suite]\`, optionally preceded by one \`Set-Location <dir>;\`. For a genuine raw-PowerShell need (e.g. hook debugging), request a session-scoped bypass: \`ws hook-bypass powershell --reason \"<why>\"\` — a human approves it and it expires with the session."
fi

# ─── Windows path-token separator normalization ─────────────────────
#
# Agents on Windows routinely echo harness-surfaced native paths
# (D:\Dev\...) into Bash commands — git and the MSYS userland accept
# either separator. Without normalization the backslash ask-arm below
# fires on every such command BEFORE the allowlist is consulted,
# turning the hook into near-always-ask on path-bearing commands and
# training humans to rubber-stamp (#133). A backslash inside a
# fully quoted drive-letter-rooted token is preserved as path data by
# Bash, so those tokens — and only those — rewrite to
# forward slashes before classification. Ambiguous shapes (escaped
# quotes, trailing or doubled backslashes, non-path tokens, mixed
# separators) stay intact and still reach the ask arm.
#
# The rewrite happens BEFORE Tier 1 rather than inside the backslash
# arm: a case statement stops at its first matching arm, so skipping
# the ask from within that arm would let `cat D:\x > out` bypass the
# later redirect deny.
_backslash_token_is_path() {
    local t="$1"
    case "$t" in
        [A-Za-z]:\\*) ;;
        *) return 1 ;;
    esac
    [[ "$t" == *'\' ]] && return 1     # trailing backslash — escape-ambiguous
    [[ "$t" == *'\\'* ]] && return 1   # doubled backslash — quoting-dependent
    [[ "$t" == *'"'* || "$t" == *"'"* ]] && return 1  # embedded quote
    return 0
}

_normalize_windows_path_tokens() {
    local raw="$1"
    # Multi-line input must reach the newline deny untouched — `read`
    # below would silently drop everything past the first line.
    if [[ "$raw" != *'\'* || "$raw" == *$'\n'* || "$raw" == *$'\r'* ]]; then
        printf '%s' "$raw"
        return
    fi
    local -a words=()
    read -r -a words <<< "$raw"
    local rebuilt="" w core quote changed=0
    for w in "${words[@]}"; do
        if [[ "$w" == *'\'* ]]; then
            core="$w" quote=""
            if [[ ${#w} -ge 2 && "$w" == "'"*"'" ]]; then
                quote="'" core="${w:1:${#w}-2}"
            elif [[ ${#w} -ge 2 && "$w" == '"'*'"' ]]; then
                quote='"' core="${w:1:${#w}-2}"
            fi
            if [[ -n "$quote" ]] && _backslash_token_is_path "$core"; then
                core="${core//\\//}"
                w="${quote}${core}${quote}"
                changed=1
            fi
        fi
        rebuilt+="${rebuilt:+ }${w}"
    done
    # Adopt the rebuilt string only when a token was actually
    # rewritten — reconstruction collapses whitespace runs, and that
    # side effect is only justified by a real normalization. The
    # audit log records the normalized form; it names the same
    # filesystem locations as the original spelling.
    if [[ "$changed" == "1" ]]; then
        printf '%s' "$rebuilt"
    else
        printf '%s' "$raw"
    fi
}
cmd="$(_normalize_windows_path_tokens "$cmd")"

# ─── Quoted-span masking for Tier-1 classification ──────────────────
#
# Bash gives single-quoted content zero special meaning, and
# double-quoted content is equally inert as long as no LIVE `$` or
# backtick sits inside (a backslash before an ordinary character is
# literal there; `\$` and `` \` `` are defused to literals). A `\|`
# in a grep pattern, a `;` in a commit message, a `&` in a URL cannot
# hide a shell operator from inside either quoting style. Tier 1's
# substring matching over quoted content was the workspace's dominant
# false-positive source (85 asks across two sessions on 2026-07-26,
# most of them BRE alternation in quoted grep patterns). Mask
# properly-terminated quoted spans — content dropped, `''`/`""` kept
# as a token placeholder — and run Tier 1 over the masked string so
# operator arms see the command the way bash parses it. Every later
# tier still sees the full command.
#
# A double-quoted span containing a bare `$` or backtick is kept
# VERBATIM (quotes and all): expansion and substitution are live
# there and must keep reaching their Tier-1 arms. The pairwise `\x`
# consume inside double quotes means `\"` cannot flip the state and
# `\$` does not count as a live dollar.
#
# Conservative bail-outs (return the raw string, so Tier 1 behaves
# exactly as before): an unquoted backslash anywhere (it escapes the
# next character, making downstream quote boundaries untrustworthy),
# or an unterminated quote at end of string.
#
# Posture note: this means quoted payloads to interpreters
# (`bash -c 'anything'`) no longer trip Tier-1 substring denies. The
# compensating controls are the prefix parser below and the common-form
# ask-list entry in hook-rules — the interpreter passthrough is the risk
# there, not the quoting.
_mask_quoted_spans() {
    local raw="$1"
    if [[ "$raw" != *"'"* && "$raw" != *'"'* ]]; then
        printf '%s' "$raw"
        return
    fi
    local out="" c nxt span="" span_live=0 state="plain"
    local -i i n=${#raw}
    for ((i = 0; i < n; i++)); do
        c="${raw:$i:1}"
        case "$state" in
            plain)
                case "$c" in
                    "'") state="single"; out+="''" ;;
                    '"') state="double"; span=""; span_live=0 ;;
                    "\\") printf '%s' "$raw"; return ;;
                    *) out+="$c" ;;
                esac
                ;;
            single)
                [[ "$c" == "'" ]] && state="plain"
                ;;
            double)
                case "$c" in
                    "\\")
                        nxt=""
                        [[ $((i + 1)) -lt $n ]] && nxt="${raw:$((i + 1)):1}"
                        span+="$c$nxt"
                        i=$((i + 1))
                        ;;
                    '"')
                        state="plain"
                        if [[ "$span_live" == "1" ]]; then
                            out+="\"$span\""
                        else
                            out+='""'
                        fi
                        ;;
                    '$'|'`')
                        span_live=1
                        span+="$c"
                        ;;
                    *) span+="$c" ;;
                esac
                ;;
        esac
    done
    if [[ "$state" != "plain" ]]; then
        printf '%s' "$raw"
        return
    fi
    printf '%s' "$out"
}
tier1_cmd="$(_mask_quoted_spans "$cmd")"

# A word containing an unquoted single-backslash drive-letter path is
# KNOWN-BROKEN, not merely ambiguous: bash strips the backslashes
# before the program runs (D:\Dev\x arrives as D:Devx), so approving
# the ask would just run a command that acts on the wrong path and
# confuses everyone downstream. Deny with the working respellings
# instead. Doubled backslashes (D:\\Dev\\x) are excluded — bash
# collapses them to single ones, so that spelling actually works and
# stays on the generic ask arm.
_bare_windows_path_word() {
    local w="$1"
    # Anchored at word start: a word BEGINNING with a quote is a quoted
    # path, which only reaches this check when masking bailed out — it
    # must fall to the generic ask, not the known-broken deny (the
    # deny's premise, bash stripping the backslashes, is false there).
    case "$w" in
        [A-Za-z]:\\*) ;;
        *) return 1 ;;
    esac
    [[ "$w" == *'\\'* ]] && return 1   # doubled backslash — bash collapses it; that spelling works
    [[ "$w" == *'\' ]] && return 1     # trailing backslash — line continuation, not path stripping
    return 0
}

_has_bare_windows_path() {
    local -a words=()
    read -r -a words <<< "$1"
    local w
    for w in ${words[@]+"${words[@]}"}; do
        _bare_windows_path_word "$w" && return 0
    done
    return 1
}

# ─── Tier 1: Deny shell composition with corrective messages ────────
#
# Order of arms matters in this case statement: the first arm whose
# pattern matches the command wins. The composition operators (&&,
# ||, ;) are checked before the bare pipe (|), because a string
# containing "||" technically also contains a single "|" substring —
# without explicit ordering, the bare-pipe arm could fire first and
# emit the wrong (less specific) deny message.
#
# Note: Tier 1 deliberately does NOT try to parse the command into
# segments and validate each piece. Per-segment parsing is fragile
# (quoted strings, escaped operators, nested expansions) and a parse
# bug would mean trusting an attacker-controlled mix-in. Outright
# denial of compound forms is simpler and verifiable.
#
# Ordering subtlety — the `grep ` arm has to come AFTER the
# redirect / substitution / FD-merge arms. An earlier version put it
# right after the composition arm, but that short-circuited the
# remaining Tier 1 checks: a command like `grep foo file > out`
# matched the grep arm, the inner case found no `|`, and the outer
# case completed silently — bypassing the redirect deny. By checking
# the more-specific deniable operators first, the grep arm only
# fires when the ONLY Tier 1 violation is `|` (regex alternation or
# a grep-pipeline), which is where the corrective message about the
# Grep tool / pipe-free grep is the right substitute.
case "$tier1_cmd" in
    *$'\n'*|*$'\r'*)
        # Embedded newline / CR — bash treats either as a command
        # separator (a literal newline in a string runs whatever
        # follows as a fresh command). Same threat as `;` / `&&`,
        # but easier to miss because it doesn't look like an
        # operator. Catch early so it can't sneak past the other
        # arms via creative whitespace. (A newline masked away above
        # was inside single quotes — data to the program, not a
        # separator — and legitimately skips this arm.)
        deny "Newline-separated command lists are disallowed — each line after the first runs as a fresh command, hidden from per-call audit. Issue one command per tool call."
        ;;
    *"&&"*|*"||"*|*";"*)
        deny "Shell composition (&&, ||, ;) is disallowed by this hook. Run each command as a separate tool call so the harness can validate each segment independently. If you need conditional behavior, check the result of one call before issuing the next."
        ;;
    *'`'*|*'$('*)
        deny "Command substitution (\`...\` or \$(...)) is disallowed — the inner command's output is opaque to static analysis, so the substituted form can't be evaluated for safety. Run the inner command separately, read its output, then pass the literal value to the outer command."
        ;;
    *'$'*)
        ask "Shell parameter expansion requires human approval because expansions such as \${IFS} can hide command boundaries from permission matching. Resolve the value separately and pass a literal argument when possible."
        ;;
    *"{"*|*"}"*)
        ask "Brace expansion requires human approval because one visible token can expand into multiple command arguments before execution. Pass the intended arguments literally instead."
        ;;
    *">&"[0-9]*|*"<&"[0-9]*)
        # File-descriptor merges like `2>&1` (stderr → stdout) and
        # `1>&2` (stdout → stderr) are common shell jargon, but they
        # add nothing in this tool environment: the Bash tool already
        # captures both stdout and stderr — the agent and human see
        # both streams regardless of merge state. Every legitimate
        # use of `2>&1` involves piping, redirecting to a file, or
        # command substitution, ALL of which Tier 1 has already
        # denied above. Bare `cmd 2>&1` is purely cargo-cult.
        #
        # Deny with a corrective message that names the redundancy
        # explicitly — saves newbies from needing to learn FD-merge
        # syntax to read transcripts in this workspace.
        deny "File-descriptor merges like \`2>&1\` and \`1>&2\` aren't needed — the Bash tool already captures both stdout and stderr natively. Remove the merge; both streams will still be visible in the tool output."
        ;;
    *">"*|*"<"*)
        deny "Output / input redirection is disallowed — the destination is opaque to static analysis. Use a tool's native --output flag (e.g. \`ws review --output <phrase>\`) for saved output, or use the Write tool when you need to author a file."
        ;;
    *"\\"*)
        # Redirect operators are checked first so an otherwise ambiguous bare
        # Windows path cannot downgrade a real shell redirect from deny to ask.
        # Any backslash still visible here sits outside single quotes (masking
        # above removed the safe ones). The known-broken shape — an unquoted
        # single-backslash drive-letter path — denies with the working
        # respellings; everything else keeps the generic ask.
        if _has_bare_windows_path "$tier1_cmd"; then
            deny "Unquoted Windows path detected: bash strips single backslashes before the command runs (D:\\Dev\\file arrives as D:Devfile), so this would act on the wrong path. Re-run with the full path quoted (\"D:\\Dev\\file\") or with forward slashes (D:/Dev/file)."
        else
            ask "Backslash escapes require human approval because quoting changes whether the backslash is syntax or literal data, and a transformed match could otherwise reach the wrong permission tier. For Windows paths, use forward slashes (D:/Dev/...) or wrap the complete drive-letter path in quotes."
        fi
        ;;
    *"&"*)
        # Background / command-list separator. By this point `&&` is
        # already handled (composition arm above), `>&N`/`<&N` are
        # caught by the FD-merge arm, and `>&`/`<&` without a digit
        # would have hit the redirect arm. The remaining `&` here is
        # the dangerous bare form: `cmd1 & cmd2` runs cmd1 in
        # background and cmd2 right after, both invisible to per-call
        # audit. Deny.
        deny "Background separator (\`&\`) is disallowed — the trailing command runs immediately after the backgrounded one, both invisible to per-call audit. Issue one command per tool call; if you need true background work, surface the request first."
        ;;
    "grep "*|"grep")
        # Specific redirect: grep with `|` (regex alternation OR a
        # `cmd | grep ...` pipe) is a recurring false-positive case
        # where the Grep tool is the cleaner substitute when it's
        # available — but in some Claude Code setups (e.g., partner
        # / managed deployments) Grep isn't exposed. The deny message
        # below names both paths so the agent can recover either way.
        # Catch the grep-with-`|` case BEFORE the generic pipe arm so
        # the corrective text is the more-specific one. Pure
        # `grep <pattern> <file>` (no operators) falls through to
        # Tier 2 — the bare invocation is fine.
        case "$tier1_cmd" in
            *"|"*)
                deny "Prefer the Grep tool over \`grep ... | ...\` or \`grep -E 'a|b' ...\` when available — it handles regex alternation cleanly and bypasses this hook. If the Grep tool isn't exposed in this Claude Code setup, plain \`grep\` is fine — just avoid \`|\`: drop the pipe, narrow the source files, or use \`grep -E '<alt>'\` without a pipeline. See AGENTS.md or CLAUDE.md for the workspace convention." ;;
        esac
        ;;
    *"|"*)
        deny "Pipes (|) are disallowed by this hook. Most ws subcommands have native flags for output management — e.g. \`ws review --limit N --compact\` instead of '| head', or \`--output <phrase>\` instead of '> file'. If a real pipeline is genuinely necessary, surface the request first rather than chaining."
        ;;
esac

# Command-string execution is opaque to Tier 1 after safe quoted spans are
# masked. Parse only the invocation prefix — never the payload — and force
# an ask when a sh-family interpreter enables command-string mode through
# -c (including combined short options such as -lc), or when env constructs
# a command from a split string.
_split_invocation_words() {
    local input="$1" current="" state="" char next
    local -i pos=0 length=${#input} started=0
    _INVOCATION_WORDS=()

    while [[ "$pos" -lt "$length" ]]; do
        char="${input:$pos:1}"
        if [[ -z "$state" ]]; then
            case "$char" in
                [[:space:]])
                    if [[ "$started" -eq 1 ]]; then
                        _INVOCATION_WORDS+=("$current")
                        current=""
                        started=0
                    fi
                    ;;
                "'")
                    state="single"
                    started=1
                    ;;
                '"')
                    state="double"
                    started=1
                    ;;
                \\)
                    [[ $((pos + 1)) -lt "$length" ]] || return 1
                    pos=$((pos + 1))
                    current+="${input:$pos:1}"
                    started=1
                    ;;
                *)
                    current+="$char"
                    started=1
                    ;;
            esac
        elif [[ "$state" == "single" ]]; then
            if [[ "$char" == "'" ]]; then
                state=""
            else
                current+="$char"
            fi
        else
            case "$char" in
                '"')
                    state=""
                    ;;
                \\)
                    if [[ $((pos + 1)) -lt "$length" ]]; then
                        next="${input:$((pos + 1)):1}"
                        case "$next" in
                            $'\n')
                                # Bash removes a quoted line continuation
                                # before forming the invocation word.
                                pos=$((pos + 1))
                                ;;
                            '$'|'`'|'"'|\\)
                                current+="$next"
                                pos=$((pos + 1))
                                ;;
                            *)
                                current+="\\"
                                ;;
                        esac
                    else
                        current+="\\"
                    fi
                    ;;
                *)
                    current+="$char"
                    ;;
            esac
        fi
        pos=$((pos + 1))
    done

    [[ -z "$state" ]] || return 1
    if [[ "$started" -eq 1 ]]; then
        _INVOCATION_WORDS+=("$current")
    fi
}

_is_shell_assignment_word() {
    # Bash accepts scalar, append, indexed-array, and associative-array
    # assignment words here. Treat any identifier-led word containing =
    # as assignment-shaped; a rare invalid lookalike may ask
    # conservatively, but cannot hide a later interpreter invocation.
    [[ "$1" == [A-Za-z_]*=* ]]
}

_opaque_command_string_requires_ask() {
    local command="$1" token runner
    local -a words
    _split_invocation_words "$command" || return 0
    words=(${_INVOCATION_WORDS[@]+"${_INVOCATION_WORDS[@]}"})
    local -i i=0 n=${#words[@]}
    [[ "$n" -gt 1 ]] || return 1

    # Skip transparent wrappers and leading assignments. The word
    # splitter above models invocation-prefix quoting without executing
    # expansions; this parser deliberately recognizes only a small,
    # auditable wrapper and option subset.
    while [[ "$i" -lt "$n" ]]; do
        token="${words[$i]}"
        if _is_shell_assignment_word "$token"; then
            i=$((i + 1))
            continue
        fi
        case "$token" in
            env|*/env)
                i=$((i + 1))
                while [[ "$i" -lt "$n" ]]; do
                    token="${words[$i]}"
                    case "$token" in
                        --)
                            i=$((i + 1))
                            while [[ "$i" -lt "$n" && "${words[$i]}" == ?*=* ]]; do
                                i=$((i + 1))
                            done
                            break
                            ;;
                        -S|-S?*|--split-string|--split-string=*)
                            # env parses this operand into an executable
                            # command, so the nested invocation is opaque to
                            # this prefix parser.
                            return 0
                            ;;
                        -u|--unset|-C|--chdir|-a|--argv0|-P)
                            [[ $((i + 1)) -lt "$n" ]] || return 1
                            i=$((i + 2))
                            ;;
                        -u?*|-C?*|-a?*|-P?*|--unset=*|--chdir=*|--argv0=*)
                            i=$((i + 1))
                            ;;
                        -i|--ignore-environment|-0|--null|-v|--debug)
                            i=$((i + 1))
                            ;;
                        --help|--version)
                            return 1
                            ;;
                        -*)
                            # Unknown env options may consume the following
                            # token. Fail closed rather than guessing where
                            # the nested executable begins.
                            return 0
                            ;;
                        ?*=*)
                            i=$((i + 1))
                            ;;
                        *) break ;;
                    esac
                done
                ;;
            command|*/command)
                i=$((i + 1))
                while [[ "$i" -lt "$n" ]]; do
                    case "${words[$i]}" in
                        --|-p) i=$((i + 1)) ;;
                        *) break ;;
                    esac
                done
                ;;
            exec|*/exec)
                i=$((i + 1))
                while [[ "$i" -lt "$n" ]]; do
                    token="${words[$i]}"
                    case "$token" in
                        --) i=$((i + 1)); break ;;
                        -a)
                            [[ $((i + 1)) -lt "$n" ]] || return 1
                            i=$((i + 2))
                            ;;
                        -a?*|-c|-l|-cl|-lc)
                            i=$((i + 1))
                            ;;
                        -*) return 0 ;;
                        *) break ;;
                    esac
                done
                ;;
            *) break ;;
        esac
    done
    [[ "$i" -lt "$n" ]] || return 1

    token="${words[$i]}"
    runner="${token##*/}"
    # Explicit sh-family set: a bare `*sh` suffix also matches ssh
    # (whose -c selects a cipher) and fish — routine false prompts.
    case "$runner" in
        sh|bash|dash|ash|ksh|ksh93|mksh|zsh) ;;
        *) return 1 ;;
    esac
    i=$((i + 1))
    while [[ "$i" -lt "$n" ]]; do
        token="${words[$i]}"
        case "$token" in
            -c) return 0 ;;
            -o|+o|-O|+O|--rcfile|--init-file)
                [[ $((i + 1)) -lt "$n" ]] || return 1
                i=$((i + 2))
                ;;
            --) return 1 ;;
            --rcfile=*|--init-file=*|--*)
                i=$((i + 1))
                ;;
            -o?*|+o?*|-O?*|+O?*)
                i=$((i + 1))
                ;;
            -[^-]*)
                [[ "$token" == *c* ]] && return 0
                i=$((i + 1))
                ;;
            +[^+]*)
                i=$((i + 1))
                ;;
            *) return 1 ;;
        esac
    done
    return 1
}

# The gate that CALLS the parser lives below the redirect, k8s, and
# adapter tiers — their verdicts are more specific (a scoped kubectl
# inline-shell deny beats a generic approvable ask) and deny/allow
# exits make first-match final. See the call site above Tier 4.

# ─── Normalization for matching (applied to BOTH cmd and pattern) ───
#
# Some agents reach for the bare command (`ws hoard upgrade borgr`)
# while others use the verbose `bash <scriptdir>/<cmd>` form when
# the workspace's scripts/ directory isn't on PATH. Both are
# legitimate; forcing a single style would either require every
# user to add scripts/ to PATH or duplicate every allow pattern in
# settings.json.
#
# Resolution: normalize BOTH sides of the comparison to a common form
# before matching. The committed permissions.allow patterns stay as
# whatever style the project author wrote (bare OR verbose); incoming
# commands from agents can use either style. Both get stripped down
# to bare form for the match.
#
# The literal command — the thing the harness actually runs after
# the hook allows it — is unchanged. Only $match_cmd (used for
# pattern evaluation) and each $match_pattern (computed inside the
# match loops) are normalized.
#
# Recognized prefixes (stripped if present at the very start of
# either the command or the pattern):
#   - `bash scripts/`
#   - `bash ./scripts/`
#   - `./scripts/`
#   - `scripts/`
#
# This is intentionally narrow: only the workspace's own scripts/
# dispatch forms. Arbitrary `bash /path/to/x` isn't normalized —
# absolute paths to elsewhere aren't a "convention slip," they're
# a different command and should match their own pattern (or not).
#
# Audit log entries continue to record the literal command, so
# drift toward one form or the other remains visible over time.
normalize_for_match() {
    local s="$1" mode="${2:-pattern}" allow_script_prefix=1
    local cwd_real="" trusted_real=""
    if [[ "$mode" == "command" ]]; then
        allow_script_prefix=0
        cwd_real="$(cd "$cwd" 2>/dev/null && pwd -P)" || cwd_real=""
        trusted_real="$(cd "$_trusted_root" 2>/dev/null && pwd -P)" || trusted_real=""
        if [[ -n "$cwd_real" && "$cwd_real" == "$trusted_real" ]]; then
            allow_script_prefix=1
        fi
    fi
    if [[ "$allow_script_prefix" -eq 1 ]]; then
        case "$s" in
            "bash ./scripts/"*) s="${s#bash ./scripts/}" ;;
            "bash scripts/"*)   s="${s#bash scripts/}" ;;
            "./scripts/"*)      s="${s#./scripts/}" ;;
            "scripts/"*)        s="${s#scripts/}" ;;
        esac
    fi
    # Matching is conservative, not execution: remove one-token quoting and
    # collapse harmless whitespace so quoting cannot hide an ask-tier action.
    s="${s//\"/}"
    s="${s//\'/}"
    s="${s//$'\t'/ }"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    s="${s# }"
    s="${s% }"
    printf '%s' "$s"
}
match_cmd="$(normalize_for_match "$cmd" command)"

# The committed direct-bats allow is only for focused tests under tests/.
# Bash glob `*` crosses slashes and `..`, so validate every argument before
# settings.json matching; otherwise `tests/../.tmp/evil.bats` inherits the
# broad allow despite executing agent-authored scratch code.
case "$match_cmd" in
    "bash tests/vendor/bats-core/bin/bats "*)
        _bats_args="${match_cmd#bash tests/vendor/bats-core/bin/bats }"
        for _bats_arg in $_bats_args; do
            case "$_bats_arg" in
                tests/*) : ;;
                *) ask "Direct bats execution must stay contained under tests/. Use 'ws test yggdrasil <test-path>' or request approval for a different target." ;;
            esac
            case "$_bats_arg" in
                ..|../*|*/..|*/../*)
                    ask "Direct bats execution must stay contained under tests/; parent traversal requires human approval."
                    ;;
            esac
        done
        ;;
esac

# Git's global execution modifiers and remote-helper transports run programs
# before/under otherwise read-looking subcommands. They are never safe to
# inherit from a broad `git diff`/`git show` allow pattern.
if [[ "$match_cmd" == git || "$match_cmd" == git\ * ]]; then
    # Git accepts unambiguous prefixes of long options. Match each visible
    # option token as a prefix of the dangerous spelling, not just the full
    # spelling, so e.g. --uplo= cannot inherit a broad git-fetch allow as an
    # abbreviated --upload-pack=. The bare `--` end-of-options marker is not a
    # candidate. Tokens longer than or unrelated to these names do not match.
    _git_dangerous_long_options=(
        --config-env --upload-pack --exec --exec-path --extcmd --ext-diff
        --output --output-directory --open-files-in-pager
    )
    _git_words=()
    read -r -a _git_words <<< "$match_cmd"
    for _git_word in "${_git_words[@]}"; do
        _git_option="${_git_word%%=*}"
        [[ "$_git_option" == --?* ]] || continue
        for _git_dangerous_option in "${_git_dangerous_long_options[@]}"; do
            if [[ "$_git_dangerous_option" == "$_git_option"* ]]; then
                deny "Git execution modifier rejected before permission matching. Use the reviewed ws wrapper or a plain read-only Git invocation."
            fi
        done
    done
    if [[ "$match_cmd" =~ (^|[[:space:]])(-c|--config-env($|=|[[:space:]])|--exec-path($|=|[[:space:]])|--upload-pack($|=|[[:space:]])|--exec($|=|[[:space:]])|--extcmd($|=|[[:space:]])|--ext-diff($|[[:space:]])|--output($|=|[[:space:]])|--output-directory($|=|[[:space:]])) ]]; then
        deny "Git execution modifier rejected before permission matching. Use the reviewed ws wrapper or a plain read-only Git invocation."
    fi
    if [[ "$match_cmd" =~ (^|[[:space:]])grep([[:space:]]|$) ]] \
        && [[ "$match_cmd" =~ (^|[[:space:]])(-O[^[:space:]]*|--open-files-in-pager($|=|[[:space:]])) ]]; then
        deny "Git execution modifier rejected before permission matching. Use the reviewed ws wrapper or a plain read-only Git invocation."
    fi
    if [[ "$match_cmd" =~ (^|[[:space:]])(ext|fd):: ]]; then
        deny "Executable Git remote helper syntax is not allowed by read-oriented Git permissions."
    fi
fi

# ─── Tier 2: Redirect deny — raw commands with a `ws` equivalent ────
#
# Walk redirect_commands (parsed from [redirect-commands] in hook-rules).
# A match emits `deny` with the entry's suggestion as the reason — the
# corrective text points at the right `ws` subcommand. Tier 1 (above)
# still runs first, so a composed `git commit -m x && git push` denies
# for composition, never for redirect — the composition message is
# more actionable.
#
# A bypass marker for the matching slug — written by `ws hook-bypass
# <slug>` with the current session_id — turns the deny into an allow
# (BYPASS-ALLOW audit entry). See bypass-check below.

# Read session_id from the stdin payload (already parsed at line 158
# above as the audit `event` was — we re-parse here to keep the Tier 2
# block self-contained).
_t2_session_id=$(echo "$input" | jq -r '.session_id // ""')

# Anchor the bypass-marker lookup to the project root, NOT $cwd. The
# marker is written by `ws hook-bypass` to <project-root>/.tmp/hook-bypass/,
# so a $cwd-anchored lookup would miss it whenever the agent's cwd is a
# subdirectory (e.g. a component dir). _rules_dir is the .claude/hooks
# directory found by walking up from $cwd during config parsing; its
# parent's parent is the project root. _rules_dir is guaranteed non-empty
# here because redirect_commands is only populated from a hook-rules file
# that was actually found.
_t2_project_root="${_rules_dir%/.claude/hooks}"

for _entry in ${redirect_commands[@]+"${redirect_commands[@]}"}; do
    # Entry shape: "<slug>|<pattern>|<suggestion>"
    _t2_slug="${_entry%%|*}"
    _t2_rest="${_entry#*|}"
    _t2_pattern="${_t2_rest%%|*}"
    _t2_suggestion="${_t2_rest#*|}"
    _t2_match_pattern="$(normalize_for_match "$_t2_pattern")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $_t2_match_pattern ]]; then
        # Bypass-marker check: a marker for this slug, written by
        # `ws hook-bypass <slug>`, overrides the deny when its
        # session_id matches the current session.
        _t2_marker_path="$_t2_project_root/.tmp/hook-bypass/$_t2_slug.bypass"
        _t2_bypass_ok=0
        if [[ -f "$_t2_marker_path" ]]; then
            # Parse session_id and reason from the marker file. The
            # trailing `|| true` keeps a malformed marker (missing either
            # line) from aborting the hook under `set -euo pipefail` — a
            # missing field grep-fails the pipeline, which would otherwise
            # exit the script; instead the field defaults to empty, the
            # session check fails to match, and the command denies as usual.
            _t2_marker_sid=$(grep '^session_id:' "$_t2_marker_path" 2>/dev/null | sed 's/^session_id: *//' || true)
            _t2_marker_reason=$(grep '^reason:' "$_t2_marker_path" 2>/dev/null | sed 's/^reason: *//' || true)
            if [[ -n "$_t2_session_id" && "$_t2_marker_sid" == "$_t2_session_id" ]]; then
                _t2_bypass_ok=1
            fi
        fi
        if [[ "$_t2_bypass_ok" == "1" ]]; then
            # Bypass marker matched this session — allow the command and
            # record a BYPASS-ALLOW audit entry (slug + reason) so the
            # recurring-bypass pattern is greppable for later review.
            # Emit the event-appropriate allow shape (PreToolUse uses
            # permissionDecision; PermissionRequest uses decision.behavior),
            # mirroring the allow() helper so the dormant PermissionRequest
            # path stays correct if that hook is ever enabled.
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-ALLOW [$_t2_slug] reason=\"$(audit_safe "$_t2_marker_reason")\" [$event]: $(audit_safe "$cmd")" >> "$audit_log"
            if [[ "$event" == "PermissionRequest" ]]; then
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
            else
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
            fi
            exit 0
        fi
        deny "$_t2_suggestion"
    fi
done

# Session-file access is shared by the unconditional Kubernetes write floor
# and the scope-specific redirect policy below.
_sr_envfile=""
if [[ -n "$_t2_session_id" ]]; then
    _sr_safe="${_t2_session_id//[^A-Za-z0-9._-]/_}"
    _sr_envfile="$_t2_project_root/.tmp/gdd-agent-sessions/${_sr_safe}.env"
fi
_sr_get() {
    local key="$1"; [[ -n "$_sr_envfile" && -f "$_sr_envfile" ]] || return 0
    local l; while IFS= read -r l || [[ -n "$l" ]]; do l="${l%$'\r'}"
        case "$l" in "$key="*) printf '%s' "${l#"$key="}"; return 0 ;; esac
    done < "$_sr_envfile"
}

_k8s_bypass_active() {
    local marker="$_t2_project_root/.tmp/hook-bypass/k8s.bypass" marker_sid=""
    [[ -n "$_t2_session_id" && -f "$marker" ]] || return 1
    marker_sid="$(grep '^session_id:' "$marker" 2>/dev/null | sed 's/^session_id: *//' || true)"
    [[ "$marker_sid" == "$_t2_session_id" ]]
}

# ─── Kubernetes write safety floor (scope-independent) ──────────────
# A scope strengthens policy with context/namespace bounds, but write
# classification must not disappear merely because no scope is armed. This
# tier precedes settings allowlists so a blanket kubectl allow cannot suppress
# the human confirmation.
_k8s_floor_enabled=0
_k8s_match_cmd="$match_cmd"
_k8s_literal_direct=0
_k8s_script_file=""
_k8s_inline_shell=0
case "$match_cmd" in
    kubectl|kubectl\ *|ws\ k8s|ws\ k8s\ *|k8s|k8s\ *) _k8s_literal_direct=1 ;;
esac
for _entry in ${scoped_redirect_commands[@]+"${scoped_redirect_commands[@]}"}; do
    [[ "${_entry%%|*}" == "k8s" ]] && { _k8s_floor_enabled=1; break; }
done
if [[ "$_k8s_floor_enabled" == "1" && "$_k8s_guard_loaded" != "1" ]]; then
    case "$match_cmd" in
        *kubectl*|ws\ k8s|ws\ k8s\ *|k8s|k8s\ *)
            ask "The Kubernetes guard is unavailable, so this command cannot be classified safely. Repair the guard or approve this invocation explicitly."
            ;;
    esac
fi
if [[ "$_k8s_floor_enabled" == "1" ]] && declare -F k8s_guard_evaluate >/dev/null 2>&1; then
    _k8s_match_cmd="$(k8s_guard_normalize_command "$match_cmd")"
    _k8s_script_file="$(k8s_guard_script_path "$cwd" "$cmd" 2>/dev/null || true)"
    # The dispatcher and permission audit entrypoint legitimately mention
    # kubectl while handling unrelated commands. Keep this carve-out exact and
    # shared with Codex; every other script remains content-inspected.
    if k8s_guard_script_content_exempt "$_trusted_root" "$_k8s_script_file"; then
        _k8s_script_file=""
    fi
    k8s_guard_inline_shell_contains_kubectl "$match_cmd" && _k8s_inline_shell=1
    _k8s_floor_ctx="$(_sr_get GDD_K8S_CONTEXT)"
    if [[ -z "$_k8s_floor_ctx" ]]; then
        case "$_k8s_match_cmd" in
            ws\ k8s\ scope|ws\ k8s\ scope\ *|k8s\ scope|k8s\ scope\ *) : ;;
            kubectl|kubectl\ *|ws\ k8s\ *|k8s\ *)
                if _k8s_bypass_active; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-SCOPE [k8s] [$event]: $(audit_safe "$cmd")" >> "$audit_log"
                    allow "unscoped Kubernetes write bypass"
                fi
                # shellcheck disable=SC2086
                if ! _k8s_floor_verdict="$(k8s_guard_evaluate "" "" $_k8s_match_cmd 2>/dev/null)" \
                    || [[ -z "$_k8s_floor_verdict" ]]; then
                    ask "Kubernetes guard evaluation failed, so this command requires explicit human approval."
                fi
                [[ "$_k8s_floor_verdict" == "WRITE_NO_SCOPE" ]] && ask "No Kubernetes guard scope is active. Approve this Kubernetes write once, arm a scope with 'ws k8s scope set', or use the audited session bypass for deliberate automation."
                ;;
            *)
                if { [[ -n "$_k8s_script_file" ]] && grep -Eq '(^|[^[:alnum:]_])kubectl([^[:alnum:]_]|$)' "$_k8s_script_file" 2>/dev/null; } || [[ "$_k8s_inline_shell" == "1" ]]; then
                    if _k8s_bypass_active; then
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-SCOPE [k8s] [$event]: $(audit_safe "$cmd")" >> "$audit_log"
                        allow "unscoped Kubernetes script bypass"
                    fi
                    ask "No Kubernetes guard scope is active and this shell invocation contains kubectl. Approve it once, arm a scope, or use the audited session bypass for deliberate automation."
                fi
                ;;
        esac
    fi
fi

# ─── Tier 2b — scoped redirects (session-key-gated) ─────────────────
#
# Walk scoped_redirect_commands (parsed from [scoped-redirect-commands]
# in hook-rules). Each entry gates on a session env-file key; when the
# key is set in .tmp/gdd-agent-sessions/<sid>.env the tier activates:
#
#   (a) `ws k8s …` / `k8s …` → route by k8s_guard_evaluate verdict.
#       READ_IN_SCOPE: auto-allow; BLOCK: deny; otherwise: fall through.
#   (b) raw command matching the pattern → redirect deny.
#   (c) shell script invocation whose file contains raw kubectl → deny.
#
# Bypass marker (written by `ws hook-bypass <slug>`) turns the deny
# into a continue (falls through to later tiers). Mirrors Tier 2.

for _entry in ${scoped_redirect_commands[@]+"${scoped_redirect_commands[@]}"}; do
    _sr_slug="${_entry%%|*}"; _sr_rest="${_entry#*|}"
    _sr_pattern="${_sr_rest%%|*}"; _sr_rest="${_sr_rest#*|}"
    _sr_key="${_sr_rest%%|*}"; _sr_suggestion="${_sr_rest#*|}"
    _sr_keyval="$(_sr_get "$_sr_key")"
    [[ -n "$_sr_keyval" ]] || continue   # gate: only active when the session key is set
    _sr_marker="$_t2_project_root/.tmp/hook-bypass/$_sr_slug.bypass"
    if [[ -f "$_sr_marker" ]]; then
        _sr_msid="$(grep '^session_id:' "$_sr_marker" 2>/dev/null | sed 's/^session_id: *//' || true)"
        if [[ -n "$_t2_session_id" && "$_sr_msid" == "$_t2_session_id" ]]; then
            # Audit the scope-guard bypass so an operator can grep for sessions
            # where enforcement was lifted (parallels Tier 2's BYPASS-ALLOW).
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-SCOPE [$_sr_slug] [$event]: $(audit_safe "$cmd")" >> "$audit_log"
            continue
        fi
    fi
    _sr_ctx="$(_sr_get GDD_K8S_CONTEXT)"; _sr_ns="$(_sr_get GDD_K8S_NAMESPACES)"
    # (a) ws k8s commands → route by guard verdict.
    if [[ "$_k8s_match_cmd" == ws\ k8s\ * || "$_k8s_match_cmd" == k8s\ * ]]; then
        # shellcheck disable=SC2086
        if ! _sr_verdict="$(k8s_guard_evaluate "$_sr_ctx" "$_sr_ns" $_k8s_match_cmd 2>/dev/null)" \
            || [[ -z "$_sr_verdict" ]]; then
            ask "Kubernetes guard evaluation failed, so this command requires explicit human approval."
        fi
        case "$_sr_verdict" in
            READ_IN_SCOPE) allow "ws k8s in-scope read" ;;
            BLOCK:*) deny "$(k8s_render_block "$_sr_verdict" "$_sr_ctx" "$_sr_slug")" ;;
            *) : ;;  # WRITE_IN_SCOPE / NO_SCOPE → normal flow (prompt)
        esac
        continue
    fi
    # (a2) raw kubectl → route by guard verdict so an in-scope READ auto-allows
    # (reads are free cluster-wide; forcing a redirect for a harmless read is
    # pure friction). A blocked command denies with the guard's own class-aware
    # message instead of the bare redirect text. An in-scope WRITE deliberately
    # falls through to the (b) redirect so it runs via `ws k8s`, which injects
    # --context — a raw write hitting the current-but-wrong context is exactly
    # the accident the guard exists to prevent.
    if [[ "$_k8s_match_cmd" == kubectl\ * || "$_k8s_match_cmd" == kubectl ]]; then
        # shellcheck disable=SC2086
        if ! _sr_kverdict="$(k8s_guard_evaluate "$_sr_ctx" "$_sr_ns" $_k8s_match_cmd 2>/dev/null)" \
            || [[ -z "$_sr_kverdict" ]]; then
            ask "Kubernetes guard evaluation failed, so this command requires explicit human approval."
        fi
        case "$_sr_kverdict" in
            READ_IN_SCOPE)
                if [[ "$_k8s_literal_direct" == "1" ]]; then
                    allow "raw kubectl in-scope read (guard)"
                fi
                ;;
            BLOCK:*) deny "$(k8s_render_block "$_sr_kverdict" "$_sr_ctx" "$_sr_slug")" ;;
            *) : ;;  # WRITE_IN_SCOPE → fall through to (b) redirect
        esac
    fi
    # (b) raw tool matching the pattern → redirect.
    # shellcheck disable=SC2053
    if [[ "$_k8s_match_cmd" == $_sr_pattern ]]; then
        deny "$_sr_suggestion"
    fi
    # (c) temp-script scan: a script-exec whose file contains a raw match.
    if [[ -n "$_k8s_script_file" ]] && grep -Eq '(^|[^[:alnum:]_])kubectl([^[:alnum:]_]|$)' "$_k8s_script_file" 2>/dev/null; then
        deny "Script $_k8s_script_file calls raw kubectl within a guarded scope — run each step via 'ws k8s', or 'ws hook-bypass $_sr_slug'."
    fi
    if [[ "$_k8s_inline_shell" == "1" ]]; then
        deny "Inline shell command calls raw kubectl within a guarded scope — use 'ws k8s', or 'ws hook-bypass $_sr_slug'."
    fi
done

# ─── Tier 3: Adapter-aware redirect — raw test/lint runners ─────────
#
# When a [adapter-redirect-commands] pattern matches AND the agent's
# $cwd resolves to a component under $project_root/components/<comp>/,
# consult the active realm's adapter (realms/<realm>/adapters/<comp>.yaml)
# to decide:
#   - commands.<verb> wired  → deny-with-bypass pointing at `ws <verb> <comp>`
#   - commands.<verb> missing → emit a stderr nudge, fall through
# If $cwd is not in a component dir, the rule doesn't fire at all
# (raw pytest at the workspace root is a legitimate workspace-test
# invocation — leave it alone).
#
# yq is required for the adapter parse. The hook script's outer
# bash-runner already has it (workspace prereq via ws preflight).

# Resolve the active realm from a project root. Mirrors ws_detect_realm's
# logic minus the heavy error handling — we either find one or skip
# the rule. Returns 0 and prints the realm dir name on success.
_ar_resolve_realm() {
    local root="$1"
    local local_file="$root/ecosystem.local.yaml"
    if [[ -f "$local_file" ]] && command -v yq >/dev/null 2>&1; then
        local sel
        sel="$(yq -r '.realm // ""' "$local_file" 2>/dev/null || echo "")"
        if [[ -n "$sel" && "$sel" != "null" && -d "$root/realms/$sel" ]]; then
            echo "$sel"
            return 0
        fi
    fi
    # No selector → only the trusted bundled realm-template may be implied,
    # mirroring ws_detect_realm: a community realm activates exclusively via
    # the explicit `ws realm use` trust step, so the hook must not route
    # adapter redirects through a realm the user never accepted.
    if [[ -d "$root/realms/realm-template" ]]; then
        echo "realm-template"
        return 0
    fi
    return 1
}

# Resolve the component name from $cwd. Returns 0 + prints the name
# if $cwd is under $root/components/<comp>/, else returns 1.
#
# The pattern `"$root/components/"*` also matches `$cwd == "$root/components/"`
# itself (empty tail after the prefix strip), which would produce an
# empty component name — Tier 3 would then treat the workspace-level
# `components/` directory as a "component", emit a blank-component
# nudge, and look up `realms/<realm>/adapters/.yaml`. Guard against
# that by rejecting an empty first segment so the rule only fires
# under a real `components/<comp>/` path.
_ar_resolve_component() {
    local cwd="$1" root="$2"
    if [[ "$cwd" == "$root/components/"* ]]; then
        # Quote $root inside the expansion so a root path with glob
        # metacharacters (e.g. /home/user/my[project]) is matched
        # literally rather than as a pattern. shellcheck SC2295.
        local rest="${cwd#"$root"/components/}"
        local comp="${rest%%/*}"
        [[ -n "$comp" ]] || return 1
        echo "$comp"
        return 0
    fi
    return 1
}

# Walk the adapter-redirect entries. The bypass marker check + the
# wired/unwired branch live inline so the tier's flow reads top-to-
# bottom without jumping helpers.
for _entry in ${adapter_redirect_commands[@]+"${adapter_redirect_commands[@]}"}; do
    _ar_slug="${_entry%%|*}"
    _ar_rest="${_entry#*|}"
    _ar_pattern="${_ar_rest%%|*}"
    _ar_verb="${_ar_rest#*|}"
    _ar_match_pattern="$(normalize_for_match "$_ar_pattern")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $_ar_match_pattern ]]; then
        # Component anchor required — raw pytest outside components/
        # is fine, the rule only applies inside a component.
        _ar_comp="$(_ar_resolve_component "$cwd" "$_t2_project_root" 2>/dev/null)" || continue
        # Realm required for adapter path resolution.
        _ar_realm="$(_ar_resolve_realm "$_t2_project_root" 2>/dev/null)" || continue
        _ar_adapter_file="$_t2_project_root/realms/$_ar_realm/adapters/$_ar_comp.yaml"
        # yq is the parser. Missing yq, missing file, or missing key
        # all collapse to "unwired".
        _ar_cmd_value=""
        if [[ -f "$_ar_adapter_file" ]] && command -v yq >/dev/null 2>&1; then
            _ar_cmd_value="$(ADAPTER_VERB="$_ar_verb" yq -r '.commands[strenv(ADAPTER_VERB)] // ""' "$_ar_adapter_file" 2>/dev/null || echo "")"
        fi
        if [[ -n "$_ar_cmd_value" && "$_ar_cmd_value" != "null" ]]; then
            # WIRED — deny with bypass pointer (matches Tier 2 shape).
            _ar_marker_path="$_t2_project_root/.tmp/hook-bypass/$_ar_slug.bypass"
            _ar_bypass_ok=0
            if [[ -f "$_ar_marker_path" ]]; then
                _ar_marker_sid=$(grep '^session_id:' "$_ar_marker_path" 2>/dev/null | sed 's/^session_id: *//' || true)
                _ar_marker_reason=$(grep '^reason:' "$_ar_marker_path" 2>/dev/null | sed 's/^reason: *//' || true)
                if [[ -n "$_t2_session_id" && "$_ar_marker_sid" == "$_t2_session_id" ]]; then
                    _ar_bypass_ok=1
                fi
            fi
            if [[ "$_ar_bypass_ok" == "1" ]]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-ALLOW [$_ar_slug] reason=\"$(audit_safe "$_ar_marker_reason")\" [$event]: $(audit_safe "$cmd")" >> "$audit_log"
                if [[ "$event" == "PermissionRequest" ]]; then
                    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
                else
                    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
                fi
                exit 0
            fi
            deny "Use \`ws $_ar_verb $_ar_comp\` — adapter wired for this component (realms/$_ar_realm/adapters/$_ar_comp.yaml). \`ws $_ar_verb --help\` for filters. \`ws hook-bypass $_ar_slug\` for a session-scoped bypass if you genuinely need raw access."
        else
            # UNWIRED — emit stderr nudge and fall through to later
            # tiers. No JSON output here — the harness then applies
            # the normal ask/allow evaluation (ask-list, allowlist,
            # or passthrough prompt). The audit log captures the
            # nudge for later workflow-audit review.
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] UNWIRED-NUDGE [$_ar_slug] no commands.$_ar_verb in realms/$_ar_realm/adapters/$_ar_comp.yaml [$event]: $(audit_safe "$cmd")" >> "$audit_log"
            echo "↪ No \`ws $_ar_verb\` adapter for $_ar_comp yet. Wire one at realms/$_ar_realm/adapters/$_ar_comp.yaml with \`commands.$_ar_verb: ...\` and \`ws $_ar_verb $_ar_comp\` will dispatch it. Running raw this time." >&2
            # Break after the first unwired match so an overlapping
            # glob in hook-rules doesn't emit a second nudge / audit
            # entry for the same command. The break exits this for
            # loop; later tiers (Tier 4 ask-list, Tier 5-6 allow
            # evaluation, passthrough prompt) still run because we
            # didn't emit a JSON decision or exit.
            break
        fi
    fi
done

# Opaque command-string gate — after the redirect / k8s / adapter
# tiers so their more-specific verdicts (including the scoped kubectl
# denies) win, before the ask-list and allow tiers so an interpreter
# passthrough can never be auto-approved. Checks both the masked and
# raw strings: the raw side catches quoted spellings masking removed.
if _opaque_command_string_requires_ask "$tier1_cmd" \
    || _opaque_command_string_requires_ask "$cmd"; then
    ask "Opaque command-string execution requires human approval because its payload cannot be classified safely by Tier 1. Use a reviewed script file when practical."
fi

# ─── Tier 4: Ask-list — force a prompt for destructive commands ─────
#
# A match emits `ask`: the harness prompts regardless of permission
# mode (acceptEdits included), but the agent may still run the command
# once the human approves. The ask-list is a safety FLOOR — it is
# checked before the Tier 5/6 allow logic, so a destructive command
# prompts even if some allowlist entry would otherwise pass it.
#
# Help-only carve-out: `ws <sub> --help` / `ws <sub> -h` with NOTHING
# else prints help and exits before any subcommand logic runs (help
# handling is unified at every level), so asking on it just teaches
# humans to rubber-stamp. Exactly three tokens — a --help appearing
# after further arguments (e.g. `ws exec <comp> <cmd> --help`) is an
# argument to the wrapped command and keeps its ask.
if [[ "$match_cmd" =~ ^ws\ [a-z][a-z0-9-]*\ (--help|-h)$ ]]; then
    allow "help-only invocation"
fi
for _ask in ${ask_commands[@]+"${ask_commands[@]}"}; do
    _ask_match="$(normalize_for_match "$_ask")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $_ask_match ]]; then
        _ask_reason="This command is on the GDD hook's ask-list — destructive or hard to undo."
        case "$match_cmd" in
            rm|rm\ *)
                _ask_reason="$_ask_reason Caution: symlinks here could delete outside the workspace."
                ;;
            "ws hook-bypass "*)
                # Tailored message: `ws hook-bypass` is NOT destructive — it
                # requests a session-scoped bypass of a Tier 2 redirect deny.
                # The generic ask line misdescribes it and never names what's
                # being bypassed, so surface the slug + the --reason instead.
                _bp_rest="${match_cmd#ws hook-bypass }"
                _bp_slug="${_bp_rest%% *}"
                _bp_reason=""
                case "$match_cmd" in
                    *--reason=*)   _bp_reason="${match_cmd#*--reason=}" ;;
                    *"--reason "*) _bp_reason="${match_cmd#*--reason }" ;;
                esac
                # Strip one layer of surrounding double quotes, if present.
                _bp_reason="${_bp_reason#\"}"
                _bp_reason="${_bp_reason%\"}"
                # The slug is NOT the raw command — look up the matching
                # redirect pattern so the message names what actually gets
                # unblocked (e.g. slug `git-commit` → `git commit*`).
                _bp_pattern=""
                for _bp_entry in ${redirect_commands[@]+"${redirect_commands[@]}"}; do
                    if [[ "${_bp_entry%%|*}" == "$_bp_slug" ]]; then
                        _bp_entry_rest="${_bp_entry#*|}"
                        _bp_pattern="${_bp_entry_rest%%|*}"
                        break
                    fi
                done
                if [[ -n "$_bp_pattern" ]]; then
                    _bp_target="raw commands matching \`$_bp_pattern\` (e.g. \`${_bp_pattern%\*}…\`), which the '$_bp_slug' redirect normally denies"
                else
                    _bp_target="the raw command behind the '$_bp_slug' redirect slug"
                fi
                _ask_reason="Approve to grant a session-scoped bypass of the '$_bp_slug' redirect — the agent will then be able to run $_bp_target for the rest of this session (it still issues that command as a separate step). Per-slug, expires when the session ends. Reason given: ${_bp_reason:-(none)}. Decline if you'd rather it use the ws wrapper."
                ;;
        esac
        ask "$_ask_reason"
    fi
done

# ─── Tier 5: Match against settings.json `permissions.allow` ────────
#
# Walk up from $cwd looking for .claude/settings.json files. Closer
# files (project-specific) come first; the user-level file at
# $HOME/.claude/settings.json is checked last. Each Bash(...) entry
# is glob-matched against the command; any match returns ALLOW.
#
# The pattern syntax stripping:
#   - "Bash(" prefix and ")" suffix are removed
#   - Claude's `:*` continuation shorthand is normalized to bash
#     glob `*` so either `Bash(git status:*)` or `Bash(git status*)`
#     in settings.json works as the user expects
collect_patterns() {
    # JSON parse guard: this script runs under `set -euo pipefail`.
    # A malformed settings.json would make jq exit non-zero and abort
    # the script mid-walk — turning a single corrupted file into a
    # hard hook failure. `jq empty <file>` validates parse-ability
    # cheaply; we skip the file on failure rather than crashing the
    # whole hook. Stderr from the validate goes to /dev/null because
    # the user's already seen the corruption when they edited the
    # file, and a per-invocation parse warning would be noise.
    local project_settings="$_trusted_root/.claude/settings.json"
    if [[ -f "$project_settings" ]] \
        && jq empty "$project_settings" 2>/dev/null; then
        jq -r '.permissions.allow[]? | select(test("^Bash\\("))' \
            "$project_settings" 2>/dev/null
    fi
    if [[ -f "$HOME/.claude/settings.json" ]] \
        && jq empty "$HOME/.claude/settings.json" 2>/dev/null; then
        jq -r '.permissions.allow[]? | select(test("^Bash\\("))' \
            "$HOME/.claude/settings.json" 2>/dev/null
    fi
}

while IFS= read -r raw; do
    # Strip trailing CR for cross-platform robustness — settings.json
    # files committed on Windows with autocrlf=true carry CRLF line
    # endings, and `read -r` preserves the CR. Without this strip,
    # `${pattern%)}` below would try to remove `)` from a line that
    # actually ends `)\r`, leaving the closing paren intact and
    # breaking every subsequent glob match.
    raw="${raw%$'\r'}"
    [[ -z "$raw" ]] && continue
    pattern="${raw#Bash(}"
    pattern="${pattern%)}"
    continuation=0
    if [[ "$pattern" == *':*' ]]; then
        pattern="${pattern%:\*}"
        continuation=1
    fi
    # Normalize the pattern with the same transform applied to
    # $match_cmd above. Symmetric normalization lets either side use
    # bare or verbose form without breaking the match — so existing
    # `Bash(bash scripts/ws hoard upgrade *)` entries still work
    # when an agent invokes `ws hoard upgrade borgr`, and vice versa.
    match_pattern="$(normalize_for_match "$pattern")"
    # The shellcheck disable is intentional: bash's `[[ str == glob ]]`
    # uses pathname-style globbing on the right side ONLY when the
    # variable is unquoted. We WANT the glob behavior here.
    if [[ "$continuation" -eq 1 ]]; then
        if [[ "$match_cmd" == "$match_pattern" || "$match_cmd" == "$match_pattern "* ]]; then
            allow "settings.json: $raw"
        fi
    else
        # shellcheck disable=SC2053
        if [[ "$match_cmd" == $match_pattern ]]; then
            allow "settings.json: $raw"
        fi
    fi
done < <(collect_patterns)

# ─── Tier 6: Allow via [allow-extras] from hook-rules.local ─────────
#
# Personal allow-patterns the user trusts on this machine — declared
# in the [allow-extras] section of hook-rules.local (gitignored,
# per-machine). Parsed into `allow_extras` above. Each entry is a
# bash glob matched against the normalized command; any match → allow.
# Empty if hook-rules.local is absent or has no [allow-extras] section.
for _extra in ${allow_extras[@]+"${allow_extras[@]}"}; do
    match_extra="$(normalize_for_match "$_extra")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $match_extra ]]; then
        allow "hook-rules.local [allow-extras]: $_extra"
    fi
done

# ─── Default: exit 0 with no JSON decision (passthrough) ────────────
#
# Treated by the harness as "the hook had no opinion." It then runs
# its own permission flow: consults permissions.allow itself, prompts
# the user otherwise. We don't log passthroughs — that file would
# balloon to gigabytes during normal sessions. The audit log focuses
# on the things this hook actively decided.
#
# Passthrough logging — opt-in via WS_HOOK_DEBUG=1. Off by default:
# passthroughs are the common case and would balloon the audit log.
# Enable when investigating "did the hook see this command, and what
# did it decide?" — e.g. tracing whether a no-prompt run was a hook
# decision or a harness-side (permission-mode) one. Matches the
# WS_HOOK_DISABLE convention: compared to literal "1", so
# WS_HOOK_DEBUG=0 is off, not "non-empty means on".
if [[ "${WS_HOOK_DEBUG:-0}" == "1" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PASSTHROUGH [$event] (tool=$tool_name): $(audit_safe "$cmd")" >> "$audit_log"
fi
exit 0
