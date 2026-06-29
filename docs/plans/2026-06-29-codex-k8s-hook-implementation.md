# Codex Kubernetes Hook Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-local Codex `PreToolUse` bridge that catches unsafe or misrouted Kubernetes commands while preserving normal Codex sandbox and approval routing for safe calls.

**Architecture:** A small Bash bridge under `.codex/hooks/` normalizes the Codex hook payload, reads the exact GDD session scope through `scripts/ws-session.sh`, and delegates Kubernetes classification and corrective text to `scripts/ws-k8s-guard.sh`. The bridge emits only deny decisions; every allowed-by-policy call returns no decision and remains subject to Codex sandbox, network, and approval controls.

**Tech Stack:** Bash, jq, Codex project hooks JSON, Bats, existing GDD session and Kubernetes guard helpers.

---

## File map

- Create `.codex/hooks.json`: trusted project-local Codex `PreToolUse` registration for Bash.
- Create `.codex/hooks/gdd-k8s-hook.sh`: Codex payload/decision bridge; contains no Kubernetes verb policy.
- Create `.codex/README.md`: hook trust, behavior, audit, and troubleshooting instructions.
- Create `tests/hook/codex-k8s-hook.bats`: isolated behavior and registration coverage.
- Modify `docs/gdd/features.md`: distinguish Claude and Codex interception while retaining `ws k8s` as the portable enforcement path.
- Modify `docs/plans/2026-06-29-codex-k8s-hook-design.md`: commit the reviewed deny-or-defer correction already made during planning.

### Task 1: Establish the Codex bridge contract with failing tests

**Files:**
- Create: `tests/hook/codex-k8s-hook.bats`
- Test: `tests/hook/codex-k8s-hook.bats`

- [ ] **Step 1: Add isolated bridge fixtures and invocation helpers**

Create a Bats setup that points `CODEX_HOOK_BIN` at the repository script, creates a synthetic workspace with `scripts/ws-session.sh` and `scripts/ws-k8s-guard.sh`, sets an isolated `HOME`, and supplies these helpers:

```bash
setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CODEX_HOOK_BIN="$REPO_ROOT/.codex/hooks/gdd-k8s-hook.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/.codex/hooks" "$WORK/scripts" "$WORK/.tmp/gdd-agent-sessions" "$WORK/_home/.codex"
    cp "$REPO_ROOT/scripts/ws-session.sh" "$WORK/scripts/ws-session.sh"
    cp "$REPO_ROOT/scripts/ws-k8s-guard.sh" "$WORK/scripts/ws-k8s-guard.sh"
    export HOME="$WORK/_home"
}

seed_scope() {
    cat > "$WORK/.tmp/gdd-agent-sessions/$1.env" <<EOF
GDD_K8S_CONTEXT=$2
GDD_K8S_NAMESPACES=$3
EOF
}

run_codex_hook() {
    local command="$1" session_id="${2:-codex-test}" tool_name="${3:-Bash}"
    local payload
    payload="$(jq -nc --arg sid "$session_id" --arg tool "$tool_name" --arg command "$command" --arg cwd "$WORK" '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:$tool,tool_input:{command:$command},cwd:$cwd}')"
    run env GDD_PROJECT_ROOT="$WORK" bash "$CODEX_HOOK_BIN" <<< "$payload"
}
```

- [ ] **Step 2: Add pass-through and defer tests**

Add tests that expect status 0 and empty stdout for an unrelated Bash command, a non-Bash tool, `kubectl get pods -n kube-system` under an active scope, `ws k8s get pods`, `ws k8s delete pod foo -n alice-sandbox`, and each `ws k8s scope set/show/clear` form. Add an inactive-scope raw `kubectl` case that also defers.

```bash
@test "raw kubectl read defers to normal Codex routing under an active scope" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl get pods -n kube-system'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
```

- [ ] **Step 3: Add deny-decision tests**

Add cases for raw in-scope writes, raw out-of-scope writes, cluster-scoped writes, guarded `ws k8s` out-of-scope writes, and direct script invocation containing `kubectl`. Assert the Codex `PreToolUse` deny shape and the corrective message:

```bash
@test "raw in-scope kubectl write redirects through ws k8s" {
    seed_scope codex-test kind-practice alice-sandbox
    run_codex_hook 'kubectl delete pod foo -n alice-sandbox'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = "deny" ]
    [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"ws k8s"* ]]
}
```

For the out-of-scope and cluster-scoped cases, assert `REJECTED by the k8s scope guard` and assert that raw internal verdict tags such as `unbounded:` do not leak.

- [ ] **Step 4: Add bypass, malformed-input, and missing-dependency tests**

Create matching and stale `.tmp/hook-bypass/k8s.bypass` fixtures. The matching marker must produce empty stdout and a `BYPASS-SCOPE [k8s]` line in `$HOME/.codex/hook-audit.log`; the stale marker must still deny. Feed `{}` and non-JSON input and assert fail-open status 0 with no stdout. Run once with `JQ=jq-command-that-does-not-exist` and assert fail-open status 0 with no stdout. Set `GDD_PROJECT_ROOT` to a fixture without `scripts/ws-k8s-guard.sh` and assert pass-through plus one infrastructure warning in the Codex audit log.

- [ ] **Step 5: Run the focused file and verify RED**

Run:

```text
ws test yggdrasil tests/hook/codex-k8s-hook.bats
```

Expected: FAIL because `.codex/hooks/gdd-k8s-hook.sh` does not exist.

### Task 2: Implement the minimal deny-or-defer Codex bridge

**Files:**
- Create: `.codex/hooks/gdd-k8s-hook.sh`
- Test: `tests/hook/codex-k8s-hook.bats`

- [ ] **Step 1: Add payload parsing, project resolution, and fail-open prerequisites**

Implement a strict Bash script that drains stdin, verifies `jq`, parses only a `PreToolUse` `Bash` command, and resolves the project root from `GDD_PROJECT_ROOT` for tests or two levels above the script for production:

```bash
#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
JQ="${JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0
"$JQ" -e . >/dev/null 2>&1 <<< "$input" || exit 0

event="$("$JQ" -r '.hook_event_name // "PreToolUse"' <<< "$input")"
tool_name="$("$JQ" -r '.tool_name // ""' <<< "$input")"
cmd="$("$JQ" -r '.tool_input.command // ""' <<< "$input")"
session_id="$("$JQ" -r '.session_id // ""' <<< "$input")"
[[ "$event" == "PreToolUse" && "$tool_name" == "Bash" && -n "$cmd" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GDD_PROJECT_ROOT:="$(cd "$SCRIPT_DIR/../.." && pwd)"}"
```

Create `$HOME/.codex/hook-audit.log` only when recording a deny, bypass, or prerequisite warning. If the session helper or guard file is absent, record a sanitized warning and exit 0.

- [ ] **Step 2: Reuse session and guard helpers**

Set `ROOT_DIR="$GDD_PROJECT_ROOT"`, source `scripts/ws-session.sh` and `scripts/ws-k8s-guard.sh`, obtain the sanitized session file with `ws_session_identity_path_for "$session_id"`, and read `GDD_K8S_CONTEXT` and `GDD_K8S_NAMESPACES` with `ws_session_get`. Exit 0 when the session ID or context is absent.

- [ ] **Step 3: Add narrow command normalization and deny serialization**

Normalize only the existing workspace dispatcher prefixes (`bash ./scripts/`, `bash scripts/`, `./scripts/`, and `scripts/`) so `bash scripts/ws k8s ...` is treated as `ws k8s ...`. Add a deny helper with the Codex hook response:

```bash
deny() {
    local reason="$1"
    audit "DENY [PreToolUse] ($(audit_safe "$reason")): $(audit_safe "$cmd")"
    jq -nc --arg reason "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0
}
```

Do not add an allow helper. Policy-permitted calls exit 0 without stdout.

- [ ] **Step 4: Implement Kubernetes routing with the shared evaluator**

Check a matching session-scoped bypass first. Then apply this routing order:

1. Pass through `ws k8s scope set/show/clear`.
2. For `ws k8s ...`, call `k8s_guard_evaluate "$ctx" "$namespaces"` with a normalized `kubectl` argv; deny only `BLOCK:*`, otherwise defer.
3. For raw `kubectl ...`, deny `BLOCK:*` with `k8s_render_block`; deny `WRITE_IN_SCOPE` with `Use 'ws k8s <args>' so the armed context is injected.`; otherwise defer.
4. For direct `bash`, `sh`, `source`, or `./script` invocation, inspect the first script path and deny when the file contains a `kubectl` token.

Avoid `eval`. Split only the already-normalized command using Bash word splitting, matching the existing guard integration's accepted command surface.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```text
ws test yggdrasil tests/hook/codex-k8s-hook.bats
```

Expected: all Codex hook bridge tests pass.

- [ ] **Step 6: Run shared guard and Claude regression coverage**

Run:

```text
ws test yggdrasil tests/ws-k8s tests/hook/gdd-permission-hook.bats
```

Expected: existing `ws k8s`, guard evaluator, and Claude scoped-redirect tests remain green.

- [ ] **Step 7: Commit the bridge and focused tests**

Create a bodyfile from `templates/commit.md` listing `.codex/hooks/gdd-k8s-hook.sh` and `tests/hook/codex-k8s-hook.bats`, then run:

```text
ws commit yggdrasil .commits/codex-k8s-hook-bridge.md
```

Use subject `feat(codex): guard Kubernetes commands with focused hook bridge`.

### Task 3: Register and document the trusted project hook

**Files:**
- Create: `.codex/hooks.json`
- Create: `.codex/README.md`
- Modify: `docs/gdd/features.md`
- Test: `tests/hook/codex-k8s-hook.bats`

- [ ] **Step 1: Add a failing registration test**

Assert `.codex/hooks.json` parses with jq, has exactly one `PreToolUse` group, matches `^Bash$`, and invokes `.codex/hooks/gdd-k8s-hook.sh` through a repository-root lookup. Also assert no `PermissionRequest` registration exists in this slice.

```bash
@test "Codex project registration contains only the focused Bash PreToolUse bridge" {
    run jq -e '.hooks.PreToolUse | (length == 1 and .[0].matcher == "^Bash$" and (.[0].hooks | length == 1) and (.[0].hooks[0].command | contains(".codex/hooks/gdd-k8s-hook.sh")))' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
    run jq -e '.hooks | has("PermissionRequest") | not' "$REPO_ROOT/.codex/hooks.json"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the registration test and verify RED**

Run `ws test yggdrasil tests/hook/codex-k8s-hook.bats`.

Expected: FAIL because `.codex/hooks.json` does not exist.

- [ ] **Step 3: Add the project hook registration**

Create:

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
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Document trust and the intentionally narrow scope**

In `.codex/README.md`, explain that Codex hashes project hooks and requires `/hooks` review after installation or changes; the bridge is deny-or-defer; audit entries live at `~/.codex/hook-audit.log`; `WS_HOOK_DISABLE=1` is the emergency opt-out; and `ws k8s` remains guarded even when the raw-command bridge is bypassed. Link the full conversion design without duplicating its matrix.

Update the Kubernetes feature section to say Claude and Codex use separate focused hook paths today, both backed by `scripts/ws-k8s-guard.sh`, while other harnesses retain the portable `AGENTS.md` plus `ws k8s` path until their hook capabilities are verified.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run `ws test yggdrasil tests/hook/codex-k8s-hook.bats`.

Expected: all bridge and registration tests pass.

- [ ] **Step 6: Commit registration and documentation**

Create a bodyfile listing `.codex/hooks.json`, `.codex/README.md`, `docs/gdd/features.md`, the approved design correction, and this implementation plan. Run:

```text
ws commit yggdrasil .commits/codex-k8s-hook-registration.md
```

Use subject `docs(codex): register and explain Kubernetes hook bridge`.

### Task 4: Full verification and CR readiness

**Files:**
- Verify only; modify files only for failures directly caused by this branch.

- [ ] **Step 1: Run focused hook and Kubernetes suites**

Run:

```text
ws test yggdrasil tests/hook/codex-k8s-hook.bats tests/hook/gdd-permission-hook.bats tests/ws-k8s
```

Expected: all selected Bats tests pass.

- [ ] **Step 2: Run the complete workspace suite**

Run:

```text
ws test yggdrasil
```

Expected: the full Bats suite passes with zero failures.

- [ ] **Step 3: Inspect branch commits and attribution**

Run `ws log yggdrasil --limit 10`.

Expected: only the focused design, bridge, tests, registration, and documentation commits are ahead of `main`; each commit contains `Co-Authored-By: Codex GPT-5 <noreply@openai.com>`.

- [ ] **Step 4: Prepare the CR body without opening the CR yet**

Create `.crs/codex-k8s-hook.md` from `templates/change.md`, summarizing deny-or-defer semantics, trusted hook review through `/hooks`, focused/full test evidence, and the deferred platform-neutral policy-engine work. The user requested a focused PR/CR, so opening it remains a deliberate final remote action after local review.
