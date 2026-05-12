#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# gdd-allowlist-bridge.sh — Claude Code PreToolUse hook for Bash
# ─────────────────────────────────────────────────────────────────────
#
# PURPOSE
# Fires before every Bash tool call the agent attempts. Inspects the
# command text and emits one of three outcomes:
#
#   1. ALLOW   → emit JSON instructing the harness to skip its prompt
#                and run the command. The hook becomes the trust
#                source for that specific call.
#   2. DENY    → emit JSON instructing the harness to block the call
#                AND attach a human-readable reason that the agent
#                sees on the next turn. The reason is the corrective
#                feedback loop — vague denies don't teach.
#   3. (none)  → exit 0 with no JSON. Harness treats this as "no
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
# Keep deny logic conservative (Tier 1 below) and allow logic narrow
# (Tiers 2-3). When uncertain, default to passthrough — the harness's
# own prompt is the safety net, not a fallback to be eliminated.
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
# Tier 2 — Per-project allowlist from .claude/settings.json (ALLOW)
#   Walk up from $cwd, collect Bash(...) entries from each
#   .claude/settings.json found, then check $HOME/.claude/settings.json
#   too. Glob-match each pattern against the command. Any match → allow.
#
# Tier 3 — User-supplied extras file (ALLOW, optional)
#   If $HOME/.claude/hooks/safe-bash-extras exists, treat each line as
#   a glob pattern to test against the command. Useful for personal
#   utilities the user trusts on this specific machine. Silently
#   skipped if the file is absent.
#
# Default — Passthrough
#   Exit 0 with no JSON. Harness handles as normal.
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
#               "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/gdd-allowlist-bridge.sh" }
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
# The Tier 3 extras file ($HOME/.claude/hooks/safe-bash-extras) is
# per-user / per-machine, NOT shipped in the repo. Each developer
# manages their own extras alongside the shared hook.
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
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# Fall back to the script's own pwd if the harness didn't supply
# a cwd field — better than aborting on a missing key.
cwd=$(echo "$input" | jq -r '.cwd // empty')
[[ -z "$cwd" ]] && cwd=$(pwd)

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
if [[ -n "${WS_HOOK_DISABLE:-}" ]]; then
    exit 0
fi

# ─── Audit log path ─────────────────────────────────────────────────
audit_log="$HOME/.claude/hook-audit.log"
mkdir -p "$(dirname "$audit_log")"

# ─── Decision helpers ───────────────────────────────────────────────

# allow() — emit the JSON the harness expects to skip its own prompt.
# The minimal allow object: hookEventName + permissionDecision: allow.
# Logged with the reason so the audit trail shows which rule fired.
allow() {
    local reason="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALLOW ($reason): $cmd" >> "$audit_log"
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
}

# deny() — block the command AND surface an explanation to the agent.
# permissionDecisionReason is the field the harness reads when
# composing the agent-visible block message. Without a reason field
# the agent sees only "blocked" with no guidance, which doesn't
# correct future behavior — defeating the point of an enforcing hook.
deny() {
    local reason="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DENY ($reason): $cmd" >> "$audit_log"
    jq -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
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
case "$cmd" in
    *"&&"*|*"||"*|*";"*)
        deny "Shell composition (\&\&, ||, ;) is disallowed by this hook. Run each command as a separate tool call so the harness can validate each segment independently. If you need conditional behavior, check the result of one call before issuing the next."
        ;;
    "grep "*|"grep")
        # Specific redirect: grep with `|` (regex alternation OR a
        # `cmd | grep ...` pipe) is a recurring false-positive case
        # where the better answer is "use the Grep tool" anyway —
        # which isn't a Bash call and therefore bypasses this hook.
        # Catch the grep-with-`|` case BEFORE the generic pipe arm
        # so the corrective message names the right substitute.
        # (Pure `grep <pattern> <file>` with no `|` won't reach this
        # tier — the case statement only fires when a deny-eligible
        # operator was already in the command.)
        case "$cmd" in
            *"|"*)
                deny "Use the Grep tool instead of \`grep ... | ...\` or \`grep -E 'a|b' ...\`. The Grep tool handles regex alternation correctly (no shell-pipe confusion) AND isn't a Bash invocation, so it bypasses this hook entirely. See AGENTS.md or CLAUDE.md for the workspace convention." ;;
        esac
        ;;
    *"|"*)
        deny "Pipes (|) are disallowed by this hook. Most ws subcommands have native flags for output management — e.g. \`ws review --limit N --compact\` instead of '| head', or \`--output <phrase>\` instead of '> file'. If a real pipeline is genuinely necessary, surface the request first rather than chaining."
        ;;
    *'`'*|*'$('*)
        deny "Command substitution (\`...\` or \$(...)) is disallowed — the inner command's output is opaque to static analysis, so the substituted form can't be evaluated for safety. Run the inner command separately, read its output, then pass the literal value to the outer command."
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
esac

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
    local s="$1"
    case "$s" in
        "bash ./scripts/"*) printf '%s' "${s#bash ./scripts/}" ;;
        "bash scripts/"*)   printf '%s' "${s#bash scripts/}" ;;
        "./scripts/"*)      printf '%s' "${s#./scripts/}" ;;
        "scripts/"*)        printf '%s' "${s#scripts/}" ;;
        *)                  printf '%s' "$s" ;;
    esac
}
match_cmd="$(normalize_for_match "$cmd")"

# ─── Tier 2: Match against settings.json `permissions.allow` ────────
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
    # Walk up until either we hit a recognized root marker or
    # `dirname` stops shrinking (it returns the same value twice in
    # a row — that's the filesystem boundary, regardless of platform
    # path convention). Without the prev-equals-dir guard we infinite-
    # loop on Windows-style paths where `dirname D:` returns `.`
    # and `dirname .` returns `.` again.
    local dir="$cwd"
    local prev=""
    while [[ "$dir" != "$prev" && "$dir" != "/" && "$dir" != "." && "$dir" != "" ]]; do
        if [[ -f "$dir/.claude/settings.json" ]]; then
            jq -r '.permissions.allow[]? | select(test("^Bash\\("))' \
                "$dir/.claude/settings.json" 2>/dev/null
        fi
        prev="$dir"
        dir=$(dirname "$dir")
    done
    if [[ -f "$HOME/.claude/settings.json" ]]; then
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
    pattern="${pattern//:\*/*}"
    # Normalize the pattern with the same transform applied to
    # $match_cmd above. Symmetric normalization lets either side use
    # bare or verbose form without breaking the match — so existing
    # `Bash(bash scripts/ws hoard upgrade *)` entries still work
    # when an agent invokes `ws hoard upgrade borgr`, and vice versa.
    match_pattern="$(normalize_for_match "$pattern")"
    # The shellcheck disable is intentional: bash's `[[ str == glob ]]`
    # uses pathname-style globbing on the right side ONLY when the
    # variable is unquoted. We WANT the glob behavior here.
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $match_pattern ]]; then
        allow "settings.json: $raw"
    fi
done < <(collect_patterns)

# ─── Tier 3: Extras files (optional, layered) ───────────────────────
#
# Free-form lists of glob patterns the user trusts on this machine
# but doesn't want to commit to a project's settings.json. The hook
# checks two locations, both optional:
#
#   1. Project-level — walk up from $cwd looking for
#      <project>/.claude/hooks/safe-bash-extras. Per-project
#      machine-local; should be gitignored (the live file IS, the
#      `.example` template IS committed for discoverability).
#   2. User-level — $HOME/.claude/hooks/safe-bash-extras.
#      Per-user / cross-project; useful for tools you trust
#      regardless of which workspace you're in.
#
# Both files share the same format:
#   - One glob pattern per line
#   - Lines starting with `#` are comments
#   - Empty / whitespace-only lines are skipped
#   - No `Bash(...)` wrapper; just the bare pattern
#
# Either file is silently skipped if absent. Order doesn't matter —
# any match in either file → ALLOW.
#
# A function builds the list of candidate files so the same parsing
# loop handles both. Walking up from $cwd uses the same prev-equals-
# dir guard as collect_patterns (Tier 2) — otherwise infinite-loops
# on Windows-style paths where `dirname D:` returns `.`.
collect_extras_files() {
    local dir="$cwd"
    local prev=""
    while [[ "$dir" != "$prev" && "$dir" != "/" && "$dir" != "." && "$dir" != "" ]]; do
        if [[ -f "$dir/.claude/hooks/safe-bash-extras" ]]; then
            printf '%s\n' "$dir/.claude/hooks/safe-bash-extras"
        fi
        prev="$dir"
        dir=$(dirname "$dir")
    done
    if [[ -f "$HOME/.claude/hooks/safe-bash-extras" ]]; then
        printf '%s\n' "$HOME/.claude/hooks/safe-bash-extras"
    fi
}

while IFS= read -r extras_file; do
    [[ -z "$extras_file" ]] && continue
    while IFS= read -r line; do
        # Strip trailing CR for cross-platform robustness (see the
        # Tier 2 read loop for the full reasoning).
        line="${line%$'\r'}"
        # Trim leading + trailing whitespace via parameter expansion.
        # Cheap, no subshell.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        # Skip blanks and comments.
        [[ -z "$line" || "$line" == "#"* ]] && continue
        # Symmetric normalization — same as Tier 2. Extras patterns
        # match against both bare and verbose invocation styles
        # regardless of how the pattern itself is written.
        match_line="$(normalize_for_match "$line")"
        # shellcheck disable=SC2053
        if [[ "$match_cmd" == $match_line ]]; then
            # Audit reason names both the file and the pattern so
            # project-vs-user origin is visible at a glance.
            allow "extras ${extras_file/#$HOME/~}: $line"
        fi
    done < "$extras_file"
done < <(collect_extras_files)

# ─── Default: exit 0 with no JSON decision (passthrough) ────────────
#
# Treated by the harness as "the hook had no opinion." It then runs
# its own permission flow: consults permissions.allow itself, prompts
# the user otherwise. We don't log passthroughs — that file would
# balloon to gigabytes during normal sessions. The audit log focuses
# on the things this hook actively decided.
exit 0
