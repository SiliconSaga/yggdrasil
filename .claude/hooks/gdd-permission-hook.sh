#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# gdd-permission-hook.sh — Claude Code tool-permission hook (GDD)
# ─────────────────────────────────────────────────────────────────────
#
# PURPOSE
# Fires on PreToolUse for Bash (four-tier deny/ask/allow logic) and for
# Edit/Write (scratch-dir auto-allow). Has dormant PermissionRequest
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
# Keep deny logic conservative (Tiers 1-2 below) and allow logic narrow
# (Tiers 4-5). Note Tier 1 (composition) is an unconditional deny, while
# Tier 2 (redirect) is a training-aid deny with a human-approved bypass —
# do not treat Tier 2 as a hard security floor. When uncertain, default to
# passthrough — the harness's own prompt is the safety net, not a fallback
# to be eliminated.
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
# Tier 3 — Ask-list from hook-rules [ask-commands] (ASK)
#   Destructive commands that should always prompt, even under
#   acceptEdits. Any match → ask.
#
# Tier 4 — Per-project allowlist from .claude/settings.json (ALLOW)
#   Walk up from $cwd, collect Bash(...) entries from each
#   .claude/settings.json found, then check $HOME/.claude/settings.json
#   too. Glob-match each pattern against the command. Any match → allow.
#
# Tier 5 — [allow-extras] from hook-rules.local (ALLOW, optional)
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

# Fall back to the script's own pwd if the harness didn't supply
# a cwd field — better than aborting on a missing key.
cwd=$(echo "$input" | jq -r '.cwd // empty')
[[ -z "$cwd" ]] && cwd=$(pwd)

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
# Tier 3 ask-list for destructive-but-sometimes-legitimate commands.
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
# Parsed by pure bash — no yq/jq dependency for config. Three sections:
#   [scratch-dirs]  — Edit/Write auto-allow path prefixes (Tier consumer)
#   [ask-commands]  — Tier 3 ask-list glob patterns
#   [allow-extras]  — Tier 5 allow glob patterns (hook-rules.local ONLY;
#                     an [allow-extras] section in the committed hook-rules
#                     is silently inert — only per-machine local files may
#                     grant Tier 5 allows)
# hook-rules.local entries ADD to the baseline (additive merge).
scratch_dirs=()
ask_commands=()
allow_extras=()
redirect_commands=()  # entries: "<slug>|<pattern>|<suggestion>"

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

# Locate .claude/hooks/hook-rules by walking up from $cwd (closest
# wins), same upward-walk + prev-equals-dir guard as collect_patterns.
_rules_dir=""
_rd="$cwd"
_rp=""
while [[ "$_rd" != "$_rp" && "$_rd" != "/" && "$_rd" != "." && "$_rd" != "" ]]; do
    if [[ -f "$_rd/.claude/hooks/hook-rules" ]]; then
        _rules_dir="$_rd/.claude/hooks"
        break
    fi
    _rp="$_rd"
    _rd=$(dirname "$_rd")
done
if [[ -n "$_rules_dir" ]]; then
    _parse_rules_file "$_rules_dir/hook-rules"
    [[ -f "$_rules_dir/hook-rules.local" ]] && _parse_rules_file "$_rules_dir/hook-rules.local" local
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
    project_dir="${CLAUDE_PROJECT_DIR:-$cwd}"
    file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

    # Path-traversal guard. The scratch-dir test below is a textual
    # prefix match, so a path like `.tmp/../../etc/whatever` would
    # still START WITH `$project_dir/.tmp/` and wrongly auto-allow a
    # write that RESOLVES outside the project. Reject any path
    # containing a `..` segment up front and fall through to the
    # harness prompt — a legitimate scratch-dir write never needs
    # `..`, so this costs nothing real and closes the bypass without
    # depending on a `realpath`/`readlink` that varies across OSes.
    case "$file_path" in
        ..|../*|*/..|*/../*)
            exit 0  # passthrough — let the harness prompt
            ;;
    esac

    # Anchor relative paths to the project root before comparing.
    case "$file_path" in
        /*) abs_path="$file_path" ;;
        *)  abs_path="$project_dir/$file_path" ;;
    esac

    # Symlink guard. The `..` guard above stops textual traversal, but
    # a symlink INSIDE a scratch dir defeats a textual prefix match a
    # different way: `.tmp/evil` → `/etc` still has a literal path
    # starting with `$project_dir/.tmp/`, yet a write through it lands
    # outside the project. Two checks close this:
    #
    #   1. If the target itself is a symlink, passthrough — a write
    #      follows the link to wherever it points.
    #   2. Resolve the deepest existing directory ancestor of the
    #      target with `cd … && pwd -P` (physical path, symlinks
    #      resolved) and confirm it is still under the *resolved*
    #      project root. Resolving BOTH sides also handles the case
    #      where the whole project is reached via a symlinked path.
    #
    # `cd`/`pwd -P` is POSIX and needs no `realpath` (which varies
    # across OSes). Any failure → passthrough, never a false allow.
    if [[ -L "$abs_path" ]]; then
        exit 0  # target is a symlink — let the harness prompt
    fi
    sym_probe="${abs_path%/*}"
    while [[ ! -d "$sym_probe" && "$sym_probe" == */* ]]; do
        sym_probe="${sym_probe%/*}"
    done
    real_probe="$(cd "$sym_probe" 2>/dev/null && pwd -P)" || exit 0
    real_project="$(cd "$project_dir" 2>/dev/null && pwd -P)" || exit 0
    case "$real_probe/" in
        "$real_project/"*) : ;;   # resolves inside the project — OK
        *) exit 0 ;;              # resolves outside — passthrough
    esac

    # Scratch dirs that auto-allow Edit / Write come from the
    # [scratch-dirs] section of hook-rules (parsed above). The baseline
    # mirrors the "Workspace-local scratch" section of .gitignore;
    # hook-rules.local may add more. If no hook-rules file was found,
    # scratch_dirs is empty and every Edit/Write passes through.
    for prefix in ${scratch_dirs[@]+"${scratch_dirs[@]}"}; do
        if [[ "$abs_path" == "$project_dir/$prefix"* ]]; then
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
case "$cmd" in
    *$'\n'*|*$'\r'*)
        # Embedded newline / CR — bash treats either as a command
        # separator (a literal newline in a string runs whatever
        # follows as a fresh command). Same threat as `;` / `&&`,
        # but easier to miss because it doesn't look like an
        # operator. Catch early so it can't sneak past the other
        # arms via creative whitespace.
        deny "Newline-separated command lists are disallowed — each line after the first runs as a fresh command, hidden from per-call audit. Issue one command per tool call."
        ;;
    *"&&"*|*"||"*|*";"*)
        deny "Shell composition (&&, ||, ;) is disallowed by this hook. Run each command as a separate tool call so the harness can validate each segment independently. If you need conditional behavior, check the result of one call before issuing the next."
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
        case "$cmd" in
            *"|"*)
                deny "Prefer the Grep tool over \`grep ... | ...\` or \`grep -E 'a|b' ...\` when available — it handles regex alternation cleanly and bypasses this hook. If the Grep tool isn't exposed in this Claude Code setup, plain \`grep\` is fine — just avoid \`|\`: drop the pipe, narrow the source files, or use \`grep -E '<alt>'\` without a pipeline. See AGENTS.md or CLAUDE.md for the workspace convention." ;;
        esac
        ;;
    *"|"*)
        deny "Pipes (|) are disallowed by this hook. Most ws subcommands have native flags for output management — e.g. \`ws review --limit N --compact\` instead of '| head', or \`--output <phrase>\` instead of '> file'. If a real pipeline is genuinely necessary, surface the request first rather than chaining."
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
        _t2_marker_path="$cwd/.tmp/hook-bypass/$_t2_slug.bypass"
        _t2_bypass_ok=0
        if [[ -f "$_t2_marker_path" ]]; then
            # Parse session_id and reason from the marker file.
            _t2_marker_sid=$(grep '^session_id:' "$_t2_marker_path" 2>/dev/null | sed 's/^session_id: *//')
            _t2_marker_reason=$(grep '^reason:' "$_t2_marker_path" 2>/dev/null | sed 's/^reason: *//')
            if [[ -n "$_t2_session_id" && "$_t2_marker_sid" == "$_t2_session_id" ]]; then
                _t2_bypass_ok=1
            fi
        fi
        if [[ "$_t2_bypass_ok" == "1" ]]; then
            # Bypass marker matched this session — allow the command and
            # record a BYPASS-ALLOW audit entry (slug + reason) so the
            # recurring-bypass pattern is greppable for later review.
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] BYPASS-ALLOW [$_t2_slug] reason=\"$_t2_marker_reason\" [$event]: $(audit_safe "$cmd")" >> "$audit_log"
            printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
            exit 0
        fi
        deny "$_t2_suggestion"
    fi
done

# ─── Tier 3: Ask-list — force a prompt for destructive commands ─────
#
# A match emits `ask`: the harness prompts regardless of permission
# mode (acceptEdits included), but the agent may still run the command
# once the human approves. The ask-list is a safety FLOOR — it is
# checked before the Tier 4/5 allow logic, so a destructive command
# prompts even if some allowlist entry would otherwise pass it.
for _ask in ${ask_commands[@]+"${ask_commands[@]}"}; do
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $_ask ]]; then
        _ask_reason="This command is on the GDD hook's ask-list — destructive or hard to undo."
        case "$match_cmd" in
            rm|rm\ *)
                _ask_reason="$_ask_reason Caution: symlinks here could delete outside the workspace."
                ;;
        esac
        ask "$_ask_reason"
    fi
done

# ─── Tier 4: Match against settings.json `permissions.allow` ────────
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
    #
    # JSON parse guard: this script runs under `set -euo pipefail`.
    # A malformed settings.json would make jq exit non-zero and abort
    # the script mid-walk — turning a single corrupted file into a
    # hard hook failure. `jq empty <file>` validates parse-ability
    # cheaply; we skip the file on failure rather than crashing the
    # whole hook. Stderr from the validate goes to /dev/null because
    # the user's already seen the corruption when they edited the
    # file, and a per-invocation parse warning would be noise.
    local dir="$cwd"
    local prev=""
    while [[ "$dir" != "$prev" && "$dir" != "/" && "$dir" != "." && "$dir" != "" ]]; do
        if [[ -f "$dir/.claude/settings.json" ]] \
            && jq empty "$dir/.claude/settings.json" 2>/dev/null; then
            jq -r '.permissions.allow[]? | select(test("^Bash\\("))' \
                "$dir/.claude/settings.json" 2>/dev/null
        fi
        prev="$dir"
        dir=$(dirname "$dir")
    done
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

# ─── Tier 5: Allow via [allow-extras] from hook-rules.local ─────────
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
