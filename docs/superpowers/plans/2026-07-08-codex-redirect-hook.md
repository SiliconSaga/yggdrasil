# Focused Codex Redirect Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a focused Codex `PreToolUse` bridge that enforces the existing `[redirect-commands]` workflow guidance while deferring unrelated calls to normal Codex routing.

**Architecture:** A new `.codex/hooks/gdd-redirect-hook.sh` independently decodes Codex hook payloads, reads only the shared redirect section from the existing rule files, and returns deny-or-defer decisions. It remains separate from the Kubernetes bridge and from Claude's broader permission monolith; session bypasses defer rather than auto-allow.

**Tech Stack:** Bash, jq, Bats, Codex project hooks JSON, Markdown.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `.codex/hooks/gdd-redirect-hook.sh` | Create | Decode Codex payloads, parse redirect rules, match commands, honor bypass markers, emit deny JSON, audit decisions. |
| `.codex/hooks.json` | Modify | Register the redirect hook beside the existing Kubernetes hook. |
| `tests/hook/codex-redirect-hook.bats` | Create | Focused behavior, parser, local-rule, bypass, and registration tests. |
| `tests/hook/codex-k8s-hook.bats` | Modify | Replace the one-hook invariant with a coexistence invariant. |
| `.codex/README.md` | Modify | Document both focused Codex bridges and trust/audit behavior. |
| `.claude/hooks/README.md` | Modify | Identify `[redirect-commands]` as shared policy data. |
| `docs/gdd/agent-training.md` | Modify | Replace the Kubernetes-only Codex statement with focused bridge coverage. |
| `docs/gdd/permissions.md` | Modify | Describe Codex redirect deny-or-defer semantics and bypass behavior. |
| `docs/gdd/features.md` | Modify | Summarize the redirect bridge alongside the Kubernetes bridge. |

## Task 1: Core Redirect Matching and Registration

**Files:**
- Create: `tests/hook/codex-redirect-hook.bats`
- Create: `.codex/hooks/gdd-redirect-hook.sh`
- Modify: `.codex/hooks.json`
- Modify: `tests/hook/codex-k8s-hook.bats`

- [ ] **Step 1: Write the initial failing hook tests**

Create `tests/hook/codex-redirect-hook.bats` with this initial content:

```bash
#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK_BIN="$REPO_ROOT/.codex/hooks/gdd-redirect-hook.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    export HOME="$WORK/home"
    mkdir -p "$WORK/.claude/hooks" "$WORK/.tmp/hook-bypass" "$HOME/.codex"
    cp "$REPO_ROOT/.claude/hooks/hook-rules" "$WORK/.claude/hooks/hook-rules"
}

run_hook() {
    local command="$1"
    local session_id="${2:-codex-redirect-test}"
    local tool_name="${3:-Bash}"
    local payload
    payload="$(jq -nc \
        --arg sid "$session_id" \
        --arg tool "$tool_name" \
        --arg command "$command" \
        --arg cwd "$WORK" \
        '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:$tool,tool_input:{command:$command},cwd:$cwd}')"
    run env HOME="$HOME" GDD_PROJECT_ROOT="$WORK" bash "$HOOK_BIN" <<< "$payload"
}

@test "unrelated Bash command defers to normal Codex routing" {
    run_hook 'git status'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "non-Bash tool defers" {
    run_hook 'git push' codex-redirect-test apply_patch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "malformed payload defers" {
    run env HOME="$HOME" GDD_PROJECT_ROOT="$WORK" bash "$HOOK_BIN" <<< 'not-json'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git push is denied with the configured ws guidance" {
    run_hook 'git push origin topic'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *'Use `ws push <comp> [branch]`'* ]]
}

@test "each shipped redirect denies a representative raw command" {
    local command slug
    while IFS='|' read -r command slug; do
        run_hook "$command"
        [ "$status" -eq 0 ]
        [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
        grep -q "DENY-REDIRECT \[$slug\]" "$HOME/.codex/hook-audit.log"
    done <<'CASES'
git commit -m test|git-commit
git push|git-push
gh pr create --title test|gh-pr-create
git mv old new|git-mv
CASES
}

@test "WS_HOOK_DISABLE bypasses redirect evaluation" {
    local payload
    payload='{"session_id":"codex-redirect-test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}'
    run env HOME="$HOME" GDD_PROJECT_ROOT="$WORK" WS_HOOK_DISABLE=1 bash "$HOOK_BIN" <<< "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
ws test yggdrasil tests/hook/codex-redirect-hook.bats
```

Expected: FAIL because `.codex/hooks/gdd-redirect-hook.sh` does not exist and redirect assertions receive no valid deny response.

- [ ] **Step 3: Create the minimal core hook**

Create `.codex/hooks/gdd-redirect-hook.sh`:

```bash
#!/usr/bin/env bash
# Focused Codex PreToolUse bridge for GDD workflow redirects.
# Denies configured raw commands with ws guidance and defers everything else.
set -euo pipefail

input="$(cat)"
JQ="${JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0
"$JQ" -e . >/dev/null 2>&1 <<< "$input" || exit 0

event="$("$JQ" -r '.hook_event_name // "PreToolUse"' <<< "$input")"
tool_name="$("$JQ" -r '.tool_name // ""' <<< "$input")"
cmd="$("$JQ" -r '.tool_input.command // ""' <<< "$input")"
[[ "$event" == "PreToolUse" && "$tool_name" == "Bash" && -n "$cmd" ]] || exit 0
[[ "${WS_HOOK_DISABLE:-0}" == "1" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GDD_PROJECT_ROOT:="$(cd "$SCRIPT_DIR/../.." && pwd)"}"
rules_file="${GDD_REDIRECT_RULES_FILE:-$GDD_PROJECT_ROOT/.claude/hooks/hook-rules}"
audit_log="$HOME/.codex/hook-audit.log"

audit_safe() {
    local value="$1"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '%s' "$value"
}

audit() {
    mkdir -p "$(dirname "$audit_log")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$audit_log"
}

deny() {
    local slug="$1" reason="$2"
    audit "DENY-REDIRECT [$slug] [PreToolUse]: $(audit_safe "$cmd")"
    "$JQ" -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}

normalize_for_match() {
    local value="$1"
    case "$value" in
        "bash ./scripts/"*) printf '%s' "${value#bash ./scripts/}" ;;
        "bash scripts/"*) printf '%s' "${value#bash scripts/}" ;;
        "./scripts/"*) printf '%s' "${value#./scripts/}" ;;
        "scripts/"*) printf '%s' "${value#scripts/}" ;;
        *) printf '%s' "$value" ;;
    esac
}

[[ -f "$rules_file" ]] || exit 0
redirect_commands=()
section=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
        "["*"]") section="${line#\[}"; section="${section%\]}"; continue ;;
    esac
    [[ "$section" == "redirect-commands" ]] || continue
    [[ "$line" == *" | "* ]] || continue
    slug="${line%% | *}"
    rest="${line#* | }"
    [[ "$rest" == *" | "* ]] || continue
    pattern="${rest%% | *}"
    suggestion="${rest#* | }"
    slug="${slug%"${slug##*[![:space:]]}"}"
    pattern="${pattern%"${pattern##*[![:space:]]}"}"
    [[ "$slug" =~ ^[a-z][a-z0-9-]*$ && -n "$pattern" && -n "$suggestion" ]] || continue
    redirect_commands+=("$slug|$pattern|$suggestion")
done < "$rules_file"

match_cmd="$(normalize_for_match "$cmd")"
for entry in ${redirect_commands[@]+"${redirect_commands[@]}"}; do
    slug="${entry%%|*}"
    rest="${entry#*|}"
    pattern="${rest%%|*}"
    suggestion="${rest#*|}"
    match_pattern="$(normalize_for_match "$pattern")"
    # shellcheck disable=SC2053
    if [[ "$match_cmd" == $match_pattern ]]; then
        deny "$slug" "$suggestion"
    fi
done

exit 0
```

Make it executable:

```bash
chmod +x .codex/hooks/gdd-redirect-hook.sh
```

- [ ] **Step 4: Register the second focused hook**

Change `.codex/hooks.json` so the existing matcher has two command hooks:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.codex/hooks/gdd-k8s-hook.sh\"",
            "timeout": 30,
            "statusMessage": "Checking Kubernetes guard scope"
          },
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.codex/hooks/gdd-redirect-hook.sh\"",
            "timeout": 30,
            "statusMessage": "Checking GDD command redirects"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Update the Kubernetes registration invariant**

Replace the registration test at the end of `tests/hook/codex-k8s-hook.bats` with:

```bash
@test "Codex registration contains both focused Bash PreToolUse bridges" {
    run jq -e '
        .hooks.PreToolUse
        | length == 1
          and .[0].matcher == "^Bash$"
          and (.[0].hooks | length == 2)
          and any(.[0].hooks[]; .command | contains(".codex/hooks/gdd-k8s-hook.sh"))
          and any(.[0].hooks[]; .command | contains(".codex/hooks/gdd-redirect-hook.sh"))
    ' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]

    run jq -e '.hooks | has("PermissionRequest") | not' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 6: Run both focused hook suites and verify GREEN**

Run:

```bash
ws test yggdrasil tests/hook/codex-redirect-hook.bats tests/hook/codex-k8s-hook.bats
```

Expected: all tests pass.

- [ ] **Step 7: Commit the core hook**

Create `.commits/codex-redirect-hook-core.md` using `templates/commit.md` with:

```yaml
---
message: "feat(codex): add focused workflow redirect hook"
add:
  - .codex/hooks/gdd-redirect-hook.sh
  - .codex/hooks.json
  - tests/hook/codex-redirect-hook.bats
  - tests/hook/codex-k8s-hook.bats
---
```

Body: `Add a deny-or-defer Codex bridge for the committed redirect-command policy while keeping the Kubernetes bridge independent.`

Run:

```bash
ws commit yggdrasil .commits/codex-redirect-hook-core.md
```

Expected: one commit containing the core bridge, registration, and initial tests.

## Task 2: Parser Diagnostics, Local Rules, and Session Bypass

**Files:**
- Modify: `tests/hook/codex-redirect-hook.bats`
- Modify: `.codex/hooks/gdd-redirect-hook.sh`

- [ ] **Step 1: Append failing edge and bypass tests**

Append to `tests/hook/codex-redirect-hook.bats`:

```bash
@test "suggestion text may contain additional pipes" {
    cat > "$WORK/.claude/hooks/hook-rules" <<'RULES'
[redirect-commands]
custom | custom raw* | Use `ws custom` | keep this suffix.
RULES
    run_hook 'custom raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" = 'Use `ws custom` | keep this suffix.' ]
}

@test "malformed redirect rows are audited and later valid rows still work" {
    cat > "$WORK/.claude/hooks/hook-rules" <<'RULES'
[redirect-commands]
missing separators
bad_slug | bad* | invalid slug
valid | valid raw* | Use `ws valid`.
RULES
    run_hook 'valid raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
    grep -q 'malformed \[redirect-commands\]' "$HOME/.codex/hook-audit.log"
}

@test "missing baseline rules defer and audit the infrastructure gap" {
    rm "$WORK/.claude/hooks/hook-rules"
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'redirect rules unavailable' "$HOME/.codex/hook-audit.log"
}

@test "command and pattern normalization match wrapper-path forms" {
    cat > "$WORK/.claude/hooks/hook-rules" <<'RULES'
[redirect-commands]
custom | scripts/custom raw* | Use `ws custom`.
RULES
    run_hook 'bash scripts/custom raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" = 'Use `ws custom`.' ]
}

@test "hook-rules.local adds a redirect" {
    cat > "$WORK/.claude/hooks/hook-rules.local" <<'RULES'
[redirect-commands]
local-tool | local-tool raw* | Use `ws local-tool`.
RULES
    run_hook 'local-tool raw input'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" = 'Use `ws local-tool`.' ]
}

@test "matching-session bypass defers without emitting allow" {
    cat > "$WORK/.tmp/hook-bypass/git-push.bypass" <<'MARKER'
session_id: codex-redirect-test
reason: provider debugging
MARKER
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'BYPASS-REDIRECT \[git-push\]' "$HOME/.codex/hook-audit.log"
}

@test "mismatched-session bypass still denies" {
    cat > "$WORK/.tmp/hook-bypass/git-push.bypass" <<'MARKER'
session_id: another-session
reason: wrong owner
MARKER
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
}

@test "malformed bypass marker still denies" {
    printf '%s\n' 'reason: missing session' > "$WORK/.tmp/hook-bypass/git-push.bypass"
    run_hook 'git push'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
ws test yggdrasil tests/hook/codex-redirect-hook.bats
```

Expected: local-rule and bypass tests fail; malformed-row audit assertion fails.

- [ ] **Step 3: Replace parsing with a diagnostic additive parser**

In `.codex/hooks/gdd-redirect-hook.sh`, replace the single-file parsing block with:

```bash
redirect_commands=()

parse_redirect_rules() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local section="" line slug pattern suggestion rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        case "$line" in
            "["*"]") section="${line#\[}"; section="${section%\]}"; continue ;;
        esac
        [[ "$section" == "redirect-commands" ]] || continue
        if [[ "$line" != *" | "* ]]; then
            audit "WARNING (hook-rules: malformed [redirect-commands] entry, missing separator): $file"
            continue
        fi
        slug="${line%% | *}"
        rest="${line#* | }"
        if [[ "$rest" != *" | "* ]]; then
            audit "WARNING (hook-rules: malformed [redirect-commands] entry, only two columns): $file"
            continue
        fi
        pattern="${rest%% | *}"
        suggestion="${rest#* | }"
        slug="${slug%"${slug##*[![:space:]]}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        if [[ ! "$slug" =~ ^[a-z][a-z0-9-]*$ || -z "$pattern" || -z "$suggestion" ]]; then
            audit "WARNING (hook-rules: malformed [redirect-commands] entry, invalid fields): $file"
            continue
        fi
        redirect_commands+=("$slug|$pattern|$suggestion")
    done < "$file"
}

if [[ ! -f "$rules_file" ]]; then
    audit "PASSTHROUGH [PreToolUse] (redirect rules unavailable): $(audit_safe "$cmd")"
    exit 0
fi
parse_redirect_rules "$rules_file"
parse_redirect_rules "${GDD_REDIRECT_RULES_LOCAL_FILE:-$GDD_PROJECT_ROOT/.claude/hooks/hook-rules.local}"
```

- [ ] **Step 4: Add marker-field parsing and bypass handling**

Before the matching loop, add:

```bash
session_id="$("$JQ" -r '.session_id // ""' <<< "$input")"

marker_field() {
    local file="$1" key="$2" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            "$key="*) printf '%s' "${line#"$key="}"; return 0 ;;
            "$key:"*)
                line="${line#"$key:"}"
                line="${line#"${line%%[![:space:]]*}"}"
                printf '%s' "$line"
                return 0
                ;;
        esac
    done < "$file"
}
```

Inside the matching branch, before `deny`, add:

```bash
marker="$GDD_PROJECT_ROOT/.tmp/hook-bypass/$slug.bypass"
if [[ -n "$session_id" && -f "$marker" ]]; then
    marker_session_id="$(marker_field "$marker" session_id)"
    marker_reason="$(marker_field "$marker" reason)"
    if [[ "$marker_session_id" == "$session_id" ]]; then
        audit "BYPASS-REDIRECT [$slug] reason=\"$(audit_safe "$marker_reason")\" [PreToolUse]: $(audit_safe "$cmd")"
        exit 0
    fi
fi
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run:

```bash
ws test yggdrasil tests/hook/codex-redirect-hook.bats
```

Expected: all redirect-hook tests pass with no Bats warnings.

- [ ] **Step 6: Run both Codex hook suites**

Run:

```bash
ws test yggdrasil tests/hook/codex-redirect-hook.bats tests/hook/codex-k8s-hook.bats
```

Expected: all tests pass; the independent hooks do not change each other's behavior.

- [ ] **Step 7: Commit parser and bypass behavior**

Create `.commits/codex-redirect-hook-bypass.md` with:

```yaml
---
message: "fix(codex): harden redirect rules and bypass handling"
add:
  - .codex/hooks/gdd-redirect-hook.sh
  - tests/hook/codex-redirect-hook.bats
---
```

Body: `Add additive local rules, malformed-row diagnostics, pipe-preserving suggestions, and session-bound bypass deferral without weakening normal Codex approvals.`

Run:

```bash
ws commit yggdrasil .commits/codex-redirect-hook-bypass.md
```

## Task 3: Documentation and Full Verification

**Files:**
- Modify: `.codex/README.md`
- Modify: `.claude/hooks/README.md`
- Modify: `docs/gdd/agent-training.md`
- Modify: `docs/gdd/permissions.md`
- Modify: `docs/gdd/features.md`

- [ ] **Step 1: Update the Codex bridge inventory**

In `.codex/README.md`, replace the Kubernetes-only opening with:

```markdown
[`hooks.json`](hooks.json) registers two focused `PreToolUse` bridges for Bash calls:

- [`hooks/gdd-k8s-hook.sh`](hooks/gdd-k8s-hook.sh) enforces the guarded-Kubernetes scope contract.
- [`hooks/gdd-redirect-hook.sh`](hooks/gdd-redirect-hook.sh) reads the shared `[redirect-commands]` policy and redirects raw commit, push, PR-creation, and rename commands to their `ws` workflows.

Both bridges deny or defer. Unrelated commands and valid redirect bypasses return no hook decision, so Codex still applies its normal sandbox, network, rules, and approval flow.
```

Add troubleshooting bullets naming `~/.codex/hook-audit.log`, `/hooks` trust review after either hook changes, and `ws test yggdrasil tests/hook/codex-redirect-hook.bats`.

- [ ] **Step 2: Mark redirect rules as shared policy data**

In `.claude/hooks/README.md`, replace the statement that Codex only has a Kubernetes bridge with:

```markdown
**Codex uses focused bridges, not this monolith.** Its Kubernetes bridge reuses the shared guard, and its redirect bridge consumes only `[redirect-commands]` from `hook-rules`. The remaining allow, ask, composition, adapter, scratch, PowerShell, and PermissionRequest behavior stays Claude-specific until another focused bridge or an evidence-backed shared evaluator is warranted.
```

In the `[redirect-commands]` documentation, add: `This section is shared by the Claude hook and the focused Codex redirect bridge; keep its glob semantics and suggestion text platform-neutral.`

- [ ] **Step 3: Update public GDD docs**

Apply these content changes without adding organization-specific terminology:

- `docs/gdd/agent-training.md`: state that Codex has focused Kubernetes and redirect bridges, while allow/ask/composition behavior remains Claude-only.
- `docs/gdd/permissions.md`: explain that a Codex redirect match denies with the same `ws` guidance; a valid session bypass defers to normal Codex routing rather than auto-allowing.
- `docs/gdd/features.md`: list the redirect bridge as a focused cross-harness training feature and retain the statement that hooks are not a security boundary.

- [ ] **Step 4: Run focused documentation-adjacent tests**

Run:

```bash
ws test yggdrasil tests/hook/codex-redirect-hook.bats tests/hook/codex-k8s-hook.bats tests/hook/gdd-permission-hook.bats
```

Expected: all focused hook tests pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
ws test yggdrasil
```

Expected: all Bats tests pass.

- [ ] **Step 6: Run static verification**

Run:

```bash
git diff --check
```

Expected: no output and exit status 0.

Run:

```bash
jq -e . .codex/hooks.json
```

Expected: normalized JSON output and exit status 0.

- [ ] **Step 7: Commit documentation**

Create `.commits/codex-redirect-hook-docs.md` with:

```yaml
---
message: "docs(codex): document focused redirect parity"
add:
  - .codex/README.md
  - .claude/hooks/README.md
  - docs/gdd/agent-training.md
  - docs/gdd/permissions.md
  - docs/gdd/features.md
---
```

Body: `Document the two focused Codex bridges, shared redirect policy, bypass deferral semantics, and the remaining boundary around Claude-specific permission behavior.`

Run:

```bash
ws commit yggdrasil .commits/codex-redirect-hook-docs.md
```

## Final Verification

- [ ] Run `ws log yggdrasil` and confirm the branch contains the design, plan, core hook, hardening, and documentation commits.
- [ ] Run `git status --short --branch` and confirm the worktree is clean.
- [ ] Re-run `ws test yggdrasil` if any file changed after the recorded full-suite run.
- [ ] Do not push or open a CR until the human reviews the completed local commit stack.
