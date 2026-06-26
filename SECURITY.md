# Security Policy: Yggdrasil

This file is intentionally more agent-centric than human-facing. It exists to help AI agents, security scanners, and reviewers understand Yggdrasil's trust boundaries before treating intentional Guardian Driven Development conveniences as vulnerabilities. Curious human readers are welcome to read through it, but the primary human-facing methodology lives under [docs/gdd/](docs/gdd/index.md).

The Yggdrasil workspace is not intended to be a cybersecurity sandbox (although it could be put inside one). It is a local, agent-assisted workspace methodology that provides guarded conveniences for trusted operators: workspace commands, agent skills, local notes, realms (config), hoards (standalone docs), adapter-driven test commands, fork-aware Git workflows, and provider-token routing. Security review should evaluate whether those guardrails match the stated assumptions below, not whether trusted local agents can do useful work.

Detailed GDD mechanics live in [Trust and Safety](docs/gdd/trust-and-safety.md), [Permissions](docs/gdd/permissions.md), [Access](docs/gdd/access.md), [Agent Training](docs/gdd/agent-training.md), and [Git Provider Setup](docs/git-provider-setup.md). This file is the repository-level security policy and trust-boundary index.

## Reporting a Vulnerability

If you discover a potential security vulnerability, avoid posting exploit details publicly before maintainers have had a chance to assess it.

- Use the repository host's private vulnerability reporting flow, such as GitHub private vulnerability reporting, where available, or find a way to privately message a core maintainer.
- If private reporting is not available, or does not appear to be addressed in a timely manner, open a GitHub issue with a high-level description and ask for a private coordination path rather than including exploit-ready details.
- If the issue affects an internal deployment, fork, realm, hoard, or component maintained by a specific organization, follow that organization's internal security reporting process as well.

Include the project name, affected branch or version, vulnerability type, reproduction steps, proof-of-concept details if available, and expected impact. If the report is about an AI-agent workflow, also include the agent surface involved, such as `ws`, `.claude/hooks/gdd-permission-hook.sh`, `.agent/skills/`, a realm adapter, a hoard template, or provider-token routing.

Maintainers will acknowledge receipt, validate whether the report crosses the trust boundaries described below, coordinate fixes when needed, and publish advisories or release notes when appropriate.

## Security Architecture & Context

Yggdrasil is a local CLI, documentation, and agent-methodology repository. Its main executable surface is the Bash-based `ws` workspace CLI under `scripts/`, plus the Claude Code PreToolUse hook under `.claude/hooks/`. It is not a network service and does not expose an HTTP listener, database, or long-running daemon from this repository.

The repository orchestrates independent local clones under gitignored directories: `components/`, `realms/`, and `hoards/`. Root `ecosystem.yaml`, active realm configuration, and per-developer `ecosystem.local.yaml` merge into the working workspace contract. Realm adapters can declare test, lint, and build commands that `ws test`, `ws lint`, and future build flows execute for trusted components.

The main trust boundaries are local-machine boundaries, not network perimeter boundaries. Yggdrasil assumes the local user, local shell, selected realm, selected hoards, provider CLIs, and checked-out components have been deliberately adopted. It provides prompts, deny messages, audits, and wrapper discipline to reduce agent drift, but those controls are not a substitute for OS sandboxing or endpoint security.

Sensitive inputs include provider tokens in `.env`, Git remote URLs and namespace mappings, CR/MR body files, issue body files, Thalamus and hoard notes, agent skills, realm adapter commands, generated MCP configuration, and local hook permission settings. The root `.env` is sourced by `scripts/ws`, so child subcommands inherit token-bearing environment variables unless a called tool narrows or scrubs its own environment.

The docs site is built by GitHub Actions using MkDocs and Material for MkDocs. Direct docs build dependencies are pinned in `requirements-docs.txt`; transitive dependency pinning or hash locking would be a future hardening step if the documentation pipeline becomes security-sensitive.

## Threat Model

1. **Arbitrary local command execution through `ws exec`:** `ws exec <target> <command...>` intentionally runs a user-provided command plus its arguments inside a resolved component, realm, or hoard directory. The implementation avoids `eval`, does not interpret shell composition, and validates the target through `ws_resolve_target`, but the command itself is arbitrary local code and inherits the `ws` environment, including sourced `.env` values. The committed hook ask-list force-prompts `ws exec *` before execution.

2. **Executable realm adapter configuration:** Realm adapter files under `realms/<realm>/adapters/*.yaml` can define command strings for `ws test`, `ws lint`, and related adapter-routed verbs. This is an intentional executable-config surface similar to Makefile targets or package manager scripts. `ws orient` surfaces the resolved command, and the GDD orientation flow scans adapter commands for high-risk patterns before treating a realm as trusted.

3. **Trusted configuration redirects work and credentials:** `ecosystem.yaml`, realm config, and `ecosystem.local.yaml` control component URLs, fork-home selection, identity metadata, token names, MCP endpoints, and adapter wiring. A malicious or mistaken realm can redirect clones, CRs, pushes, MCP setup, or test execution toward the wrong host or namespace. Review realms before adoption, and treat third-party realms as untrusted until inspected.

4. **Provider-token exposure to local child processes:** `.env` token variables support convenient GitHub/GitLab flows, fork groups, CR automation, and provider-specific wrappers. Because `scripts/ws` sources `.env` at dispatcher startup, any allowed child command may see those variables. Tokens should be scoped, revocable, and stored only in `.env` or provider credential stores; do not run untrusted code with production-strength tokens in the environment.

5. **Agent instruction ingestion from skills, docs, components, realms, and hoards:** Yggdrasil deliberately asks agents to read Markdown instructions and skills from trusted roots. Untrusted or newly adopted content can contain prompt-injection attempts. GDD's black-box pattern, Thalamus concern logging, and orientation trust scan reduce silent instruction adoption, but they do not make malicious text safe to read or execute.

6. **Permission-policy drift between docs, hooks, and local overrides:** `.claude/settings.json`, `.claude/hooks/hook-rules`, and gitignored local overrides decide which Bash commands auto-run, ask, deny, or pass through to the harness. Broad local allow patterns such as a catch-all `ws` or interpreter pattern can weaken the intended workflow. `ws audit-permissions` exists to flag over-broad allow entries, and committed ask-list entries run before local allow extras. Claude Code was the first agent meant for use with GDD but others could be used as well and may have fewer active safeguards in place as a result.

7. **Supply-chain exposure in auxiliary tooling:** Docs builds, vendored test tools, hoard templates, Obsidian vault plugins, and future hoard upgrades may fetch or execute external code. Current mitigations are conservative template workflows, human review, direct dependency pins for the docs workflow, and explicit trust assumptions. Stronger checksum or lockfile enforcement is future hardening, not the current baseline.

## Critical Security Assumptions

- The local operator, local OS account, shell, filesystem, and checked-out Yggdrasil root are trusted.
- Agents are cooperative assistants guided by hooks, wrappers, prompts, and user review; they are not treated as hostile code contained by a tamper-resistant sandbox.
- Realm repositories, hoard repositories, and component repositories become trusted only after the user deliberately adopts them and the agent performs the relevant GDD orientation checks.
- `.env` is a private local configuration file, not committed source. Tokens stored there are scoped, revocable, and appropriate for the work being attempted.
- Provider CLIs such as `gh`, `glab`, and `git` enforce host-side authentication and authorization. Yggdrasil does not override repository, group, or organization permissions.
- MCP configuration generated by Yggdrasil points at servers the user or selected realm intentionally trusts. Yggdrasil does not authenticate or sandbox arbitrary MCP servers by itself.
- Documentation builds are informational publishing workflows. They should not handle secrets, deploy production services, or become a privileged release channel without additional supply-chain hardening.
- The PreToolUse hook is an agent-workflow guardrail. A local user can disable it, edit committed policy, or run commands outside the agent harness.

## Scope and Out of Scope

In scope: bugs that bypass the stated guardrails, misroute Git/provider operations without user intent, expose tokens from committed files, silently auto-approve commands that should ask, execute untrusted realm or hoard configuration without the documented checks, or cause `ws` wrappers to perform materially different operations from their help text.

Out of scope as vulnerabilities by themselves: the existence of local command execution after human approval, execution of trusted adapter commands, provider access allowed by intentionally supplied tokens, AI agents reading trusted skills or docs, or local notes containing sensitive material that the user chose to store in a hoard or Thalamus file.

## Operational Guidance Index

- Session startup and trust scanning: [Trust and Safety](docs/gdd/trust-and-safety.md) and `.agent/skills/gdd-orientation/SKILL.md`.
- Local command prompts, hook rules, `ws exec`, and allowlist safety: [Permissions](docs/gdd/permissions.md), [Agent Training](docs/gdd/agent-training.md), and [WS CLI Guide](docs/ws-cli-guide.md).
- Remote Git identities, fork groups, token routing, and service-account tradeoffs: [Access](docs/gdd/access.md), [CR Internals](docs/gdd/cr-internals.md), and [Git Provider Setup](docs/git-provider-setup.md).
- Realm adapters and executable configuration: [Trust and Safety](docs/gdd/trust-and-safety.md) and [Adapters](docs/gdd/adapters.md).

## Dependency Security

The docs workflow installs direct Python dependencies from `requirements-docs.txt` with exact version pins. Update those pins deliberately, verify `mkdocs build --strict`, and review release notes for `mkdocs-material` and `pymdown-extensions` when refreshing them.

This repository does not currently maintain a full transitive Python lockfile or hash-checked install for the docs workflow. That is an accepted tradeoff while the docs pipeline remains non-secret-bearing and low privilege; it should be revisited if docs publishing becomes a privileged release path.
