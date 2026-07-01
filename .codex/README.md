# Codex project configuration

Yggdrasil uses this directory for Codex-specific project configuration. Workspace policy and reusable skills remain agent-neutral under `AGENTS.md` and `.agent/skills/`; this layer contains only behavior that must integrate with a Codex lifecycle surface.

## Kubernetes scope-guard bridge

[`hooks.json`](hooks.json) registers one focused `PreToolUse` bridge for Bash calls. [`hooks/gdd-k8s-hook.sh`](hooks/gdd-k8s-hook.sh) classifies raw `kubectl`, guarded `ws k8s`, and directly invoked scripts containing `kubectl` whether or not the current GDD session has a Kubernetes scope armed.

The bridge is deny-or-defer:

- Unscoped Kubernetes writes are denied with guidance to arm a scope or obtain explicit user confirmation before creating the audited session bypass. Codex's focused bridge does not claim Claude's force-ask semantics.
- Unsafe, out-of-scope, or misrouted scoped writes are denied with guidance from the shared `scripts/ws-k8s-guard.sh` policy. Local Kustomize directories are rendered so every resulting resource can be checked.
- Safe reads, guarded `ws k8s` calls, scope management, and unrelated commands return no hook decision. Codex still applies its normal sandbox, network, rules, and approval flow.
- `ws hook-bypass k8s` lifts the unscoped write floor and raw-command interception for the current session after explicit user confirmation. It does not disable an already-armed guard inside `ws k8s`.

The bridge does not import Claude's generic command allowlist, shell-composition checks, destructive-command prompts, or component adapter redirects. The proposed conversion path for those independent features is documented in [`../docs/plans/2026-06-29-codex-k8s-hook-design.md`](../docs/plans/2026-06-29-codex-k8s-hook-design.md).

## Trust the hook

Codex reviews project-local command hooks by content hash. After cloning this workspace or changing a hook, open `/hooks`, inspect the `.codex/hooks.json` registration and command, then trust it. Codex skips an untrusted or changed hook and prints a startup warning until it is reviewed.

The hook writes only deny, bypass, and infrastructure-warning entries to `~/.codex/hook-audit.log`. Deferred calls are already visible through normal Codex execution and are not duplicated there.

Set `WS_HOOK_DISABLE=1` for an emergency session-local passthrough. Managed Codex policy may still restrict execution, and `ws k8s` continues to enforce its own scope when invoked.

## Troubleshooting

- Run `ws session get GDD_K8S_CONTEXT` and `ws session get GDD_K8S_NAMESPACES` to confirm the active scope.
- Run `ws k8s scope show` to inspect the scope through the supported wrapper.
- Check `~/.codex/hook-audit.log` for deny or prerequisite-warning entries.
- Use `/hooks` to confirm the project hook is enabled and trusted after any content change.
- Run `ws test yggdrasil tests/hook/codex-k8s-hook.bats` to verify the focused bridge contract.
