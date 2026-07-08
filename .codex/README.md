# Codex project configuration

Yggdrasil uses this directory for Codex-specific project configuration. Workspace policy and reusable skills remain agent-neutral under `AGENTS.md` and `.agent/skills/`; this layer contains only behavior that must integrate with a Codex lifecycle surface.

## Focused PreToolUse bridges

[`hooks.json`](hooks.json) registers two focused `PreToolUse` bridges for Bash calls:

- [`hooks/gdd-k8s-hook.sh`](hooks/gdd-k8s-hook.sh) enforces the guarded-Kubernetes scope contract.
- [`hooks/gdd-redirect-hook.sh`](hooks/gdd-redirect-hook.sh) reads the shared `[redirect-commands]` policy and redirects raw commit, push, PR-creation, and rename commands to their `ws` workflows.

Both bridges deny or defer. Unrelated commands and valid redirect bypasses return no hook decision, so Codex still applies its normal sandbox, network, rules, and approval flow.

### Kubernetes scope guard

The Kubernetes bridge classifies raw `kubectl`, guarded `ws k8s`, and directly invoked scripts containing `kubectl` whether or not the current GDD session has a Kubernetes scope armed.

Before classification, the bridge normalizes common transparent launch forms: leading environment assignments, `env`, `command`, absolute kubectl paths, shell options before a direct script, relative script paths anchored to the tool cwd, and literal kubectl inside `bash -c` or `sh -c`. It does not claim visibility into arbitrary nested execution through task runners, client libraries, Helm, or dynamically constructed command names.

The bridge is deny-or-defer:

- Unscoped Kubernetes writes are denied with guidance to arm a scope or obtain explicit user confirmation before creating the audited session bypass. Codex's focused bridge does not claim Claude's force-ask semantics.
- Unsafe, out-of-scope, or misrouted scoped writes are denied with guidance from the shared `scripts/ws-k8s-guard.sh` policy. Local Kustomize directories are rendered so every resulting resource can be checked.
- Safe reads, guarded `ws k8s` calls, scope management, and unrelated commands return no hook decision. Codex still applies its normal sandbox, network, rules, and approval flow.
- `ws hook-bypass k8s` lifts the unscoped write floor and raw-command interception for the current session after explicit user confirmation. It does not disable an already-armed guard inside `ws k8s`.

### Workflow redirects

The redirect bridge reads only `[redirect-commands]` from `.claude/hooks/hook-rules` and the additive local rules file. A match returns the same corrective `ws` suggestion used by Claude. `ws hook-bypass <slug>` remains session-bound, but a valid Codex bypass defers to normal routing rather than auto-allowing the raw command.

The bridges do not import Claude's generic command allowlist, shell-composition checks, destructive-command prompts, or component adapter redirects. Those independent features remain Claude-specific until each has a suitable focused bridge or an evidence-backed shared evaluator.

## Trust the hook

Codex reviews project-local command hooks by content hash. After cloning this workspace or changing either hook, open `/hooks`, inspect the `.codex/hooks.json` registrations and commands, then trust them. Codex skips an untrusted or changed hook and prints a startup warning until it is reviewed.

The hook writes only deny, bypass, and infrastructure-warning entries to `~/.codex/hook-audit.log`. Deferred calls are already visible through normal Codex execution and are not duplicated there.

Set `WS_HOOK_DISABLE=1` for an emergency session-local passthrough. Managed Codex policy may still restrict execution, and `ws k8s` continues to enforce its own scope when invoked.

## Troubleshooting

- Run `ws session get GDD_K8S_CONTEXT` and `ws session get GDD_K8S_NAMESPACES` to confirm the active scope.
- Run `ws k8s scope show` to inspect the scope through the supported wrapper.
- Check `~/.codex/hook-audit.log` for deny or prerequisite-warning entries.
- Use `/hooks` to confirm the project hook is enabled and trusted after any content change.
- Run `ws test yggdrasil tests/hook/codex-k8s-hook.bats tests/hook/codex-redirect-hook.bats` to verify both focused bridge contracts.
