# Shared helpers for the PreToolUse hook bats tests.
#
# Each test gets an isolated $WORK directory under $BATS_TEST_TMPDIR
# with a synthetic project-shaped .claude/ tree, plus an override of
# $HOME pointing into the same tmp area so the hook's user-level
# settings.json / extras lookup doesn't leak into real config.
#
# The hook script lives in the repo at .claude/hooks/. Tests invoke
# it via stdin-redirected JSON, captured by bats' `run` helper —
# which runs in a subshell off the bats interpreter, so the harness's
# own PreToolUse rules don't apply (the harness only watches Claude
# Code tool calls, not nested bats-spawned processes).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HOOK_BIN="$REPO_ROOT/.claude/hooks/gdd-permission-hook.sh"

# Resolve a `timeout`-style command. GNU coreutils ships `timeout` on
# Linux and Git Bash, but macOS only has it under the `g`-prefixed
# Homebrew coreutils install (`gtimeout`). Tests need one or the other
# — see tests/README.md for the install hint.
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="$(command -v gtimeout)"
else
    echo "ERROR: neither 'timeout' nor 'gtimeout' found on PATH." >&2
    echo "  Install GNU coreutils — on macOS: 'brew install coreutils'." >&2
    echo "  See tests/README.md." >&2
    exit 1
fi

# Build an isolated workspace shape:
#   $WORK                           — tmp project root
#   $WORK/.claude/settings.json    — synthetic permissions.allow
#   $WORK/.claude/hooks/safe-bash-extras (optional — caller writes)
#   $HOME = $WORK/_home             — sandbox for user-level state
#   $HOME/.claude/hooks/safe-bash-extras (optional — caller writes)
#
# All envs are exported so the hook subprocess sees them.
init_hook_env() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/.claude"
    mkdir -p "$WORK/.claude/hooks"
    mkdir -p "$WORK/_home/.claude/hooks"
    export HOME="$WORK/_home"
    export CLAUDE_PROJECT_DIR="$WORK"
}

# Write a synthetic project .claude/settings.json with the given
# Bash(...) allowlist entries (passed as newline-separated strings).
write_project_settings() {
    local entries="$1"
    {
        echo "{"
        echo "  \"permissions\": {"
        echo "    \"allow\": ["
        local first=true
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            if $first; then first=false; else echo ","; fi
            printf '      "%s"' "$entry"
        done <<< "$entries"
        echo ""
        echo "    ]"
        echo "  }"
        echo "}"
    } > "$WORK/.claude/settings.json"
}

# Write a project-level safe-bash-extras file with the given content.
write_project_extras() {
    printf '%s\n' "$1" > "$WORK/.claude/hooks/safe-bash-extras"
}

# Write a user-level safe-bash-extras file with the given content.
write_user_extras() {
    printf '%s\n' "$1" > "$HOME/.claude/hooks/safe-bash-extras"
}

# Write a project-level hook-rules file with the given content.
write_project_hook_rules() {
    printf '%s\n' "$1" > "$WORK/.claude/hooks/hook-rules"
}

# Write a project-level hook-rules.local file with the given content.
write_local_hook_rules() {
    printf '%s\n' "$1" > "$WORK/.claude/hooks/hook-rules.local"
}

# Seed the synthetic $WORK project with the REAL committed config — the
# repo's .claude/settings.json (permissions.allow) and
# .claude/hooks/hook-rules (redirect/ask/scratch). Tests that assert the
# *shipped* allow/deny behavior (rather than a hand-written synthetic
# rule) use this so the hook evaluates against the same config the
# workspace actually runs. The synthetic $WORK lives in a tmp tree the
# hook's upward walk can't reach the repo from, so we copy the files in
# explicitly.
seed_real_project_config() {
    cp "$REPO_ROOT/.claude/settings.json" "$WORK/.claude/settings.json"
    cp "$REPO_ROOT/.claude/hooks/hook-rules" "$WORK/.claude/hooks/hook-rules"
}

# Write a bypass marker file under $WORK/.tmp/hook-bypass/<slug>.bypass
# with the given session_id and optional reason. Used by Tier 2 bypass
# tests to simulate a marker created by `ws hook-bypass`.
# Args: $1 = slug, $2 = session_id, $3 = reason (optional)
write_bypass_marker() {
    local slug="$1"
    local session_id="$2"
    local reason="${3:-}"
    mkdir -p "$WORK/.tmp/hook-bypass"
    cat > "$WORK/.tmp/hook-bypass/$slug.bypass" <<EOF
session_id: $session_id
slug: $slug
created_at: 2026-05-20T15:00:00Z
reason: $reason
EOF
}

# Build an Edit/Write tool-call payload and pipe it into the hook.
# The hook's non-Bash branch decides on the file_path, not a command.
# project_dir falls back to cwd when CLAUDE_PROJECT_DIR is unset, so
# the cwd arg anchors the scratch-dir comparison.
#
# Args: $1 = tool name (Edit|Write), $2 = file_path, $3 = cwd (default $WORK)
run_hook_write() {
    local tool="$1"
    local file_path="$2"
    local cwd="${3:-$WORK}"
    local payload
    payload=$(jq -nc --arg t "$tool" --arg fp "$file_path" --arg cwd "$cwd" \
        '{tool_name:$t, tool_input:{file_path:$fp}, cwd:$cwd}')
    run "$TIMEOUT_BIN" 10 bash "$HOOK_BIN" <<< "$payload"
}

# Build an Edit/Write payload carrying introduced content and an
# optional session_id, and pipe it into the hook. Write sends the
# content as tool_input.content; Edit sends it as tool_input.new_string
# — mirroring the harness payload shapes the session-file carve-out
# inspects.
#
# Args: $1 = tool (Edit|Write), $2 = file_path, $3 = content,
#       $4 = session_id (optional), $5 = cwd (default $WORK)
run_hook_write_content() {
    local tool="$1"
    local file_path="$2"
    local content="$3"
    local sid="${4:-}"
    local cwd="${5:-$WORK}"
    local field="content"
    [[ "$tool" == "Edit" ]] && field="new_string"
    local payload
    payload=$(jq -nc --arg t "$tool" --arg fp "$file_path" --arg c "$content" \
        --arg f "$field" --arg sid "$sid" --arg cwd "$cwd" \
        '{tool_name:$t, tool_input:({file_path:$fp} + {($f):$c}), cwd:$cwd}
         + (if $sid != "" then {session_id:$sid} else {} end)')
    run "$TIMEOUT_BIN" 10 bash "$HOOK_BIN" <<< "$payload"
}

# Build the JSON tool-call payload and pipe it into the hook. The
# entire pipeline runs inside the bats subshell, away from the
# harness's PreToolUse watch.
#
# Args: $1 = command string, $2 = cwd (defaults to $WORK)
run_hook() {
    local cmd="$1"
    local cwd="${2:-$WORK}"
    local payload
    payload=$(jq -nc --arg cmd "$cmd" --arg cwd "$cwd" \
        '{tool_input:{command:$cmd}, cwd:$cwd}')
    # `timeout` catches infinite-loop regressions — the original
    # collect_patterns bug hung forever on Windows paths until we
    # added the prev-equals-dir guard. 10s is generous for any
    # legitimate run, certain to fail loudly on a stall.
    #
    # Bash herestring `<<<` feeds $payload as stdin to the hook —
    # cleaner than wrapping in `bash -c` to pipe (which also runs
    # afoul of the workspace's no-inline-shell-scripts convention).
    run "$TIMEOUT_BIN" 10 bash "$HOOK_BIN" <<< "$payload"
}

# Build a tool-call payload that includes session_id, and pipe it
# into the hook. Used by tests that exercise the bypass-marker logic
# (Tier 2). Args: $1 = command string, $2 = session_id, $3 = cwd
# (defaults to $WORK).
run_hook_with_session() {
    local cmd="$1"
    local session_id="$2"
    local cwd="${3:-$WORK}"
    local payload
    payload=$(jq -nc --arg cmd "$cmd" --arg cwd "$cwd" --arg sid "$session_id" \
        '{session_id:$sid, tool_input:{command:$cmd}, cwd:$cwd}')
    run "$TIMEOUT_BIN" 10 bash "$HOOK_BIN" <<< "$payload"
}

# Build a PowerShell tool-call payload and pipe it into the hook.
# The PowerShell branch is deny-by-default with a `powershell` bypass
# slug, so tests need the real tool_name plus (optionally) a session_id
# for the bypass cases.
#
# Args: $1 = command string, $2 = session_id (optional, empty = omit),
#       $3 = cwd (defaults to $WORK)
run_hook_ps() {
    local cmd="$1"
    local session_id="${2:-}"
    local cwd="${3:-$WORK}"
    local payload
    payload=$(jq -nc --arg cmd "$cmd" --arg cwd "$cwd" --arg sid "$session_id" \
        '{tool_name:"PowerShell", tool_input:{command:$cmd}, cwd:$cwd}
         + (if $sid == "" then {} else {session_id:$sid} end)')
    run "$TIMEOUT_BIN" 10 bash "$HOOK_BIN" <<< "$payload"
}

# Set up an active realm + component dir under $WORK so the adapter-
# aware redirect tier (Tier 3) has something to resolve.
#   $1 — component name (e.g. "knarrlike")
#   $2 — adapter content (multi-line YAML); empty string = no adapter
#         file written at all (the "unwired" case where the file is
#         missing entirely).
#   $3 — realm name (default "realm-fixture")
#
# Creates: $WORK/components/<comp>/ (cwd anchor for tests),
#          $WORK/realms/<realm>/ + ecosystem.yaml, optional adapter
#          file. The synthetic local config explicitly selects the
#          realm — community realms only activate via the explicit
#          trust step, so auto-detection no longer exists to lean on.
seed_adapter_fixture() {
    local comp="$1"
    local adapter_yaml="$2"
    local realm="${3:-realm-fixture}"
    mkdir -p "$WORK/components/$comp"
    mkdir -p "$WORK/realms/$realm/adapters"
    printf 'realm: %s\n' "$realm" > "$WORK/ecosystem.local.yaml"
    cat > "$WORK/realms/$realm/ecosystem.yaml" <<'YAML'
identity:
  human_account: testuser
components: {}
YAML
    if [[ -n "$adapter_yaml" ]]; then
        printf '%s\n' "$adapter_yaml" > "$WORK/realms/$realm/adapters/$comp.yaml"
    fi
}
