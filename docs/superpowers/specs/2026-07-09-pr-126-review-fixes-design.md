# PR 126 Review Fixes Design

## Scope

Address four verified review findings without widening the focused Codex redirect or Kubernetes guard designs.

## Behavior

- The Codex redirect bridge requires an explicit `hook_event_name: PreToolUse`; a parseable payload with no event defers.
- Kubernetes context-only scope is represented only by the canonical `*` sentinel. Omitting `--namespace`, passing `--namespace '*'`, or including `*` in a namespace CSV normalizes to that sentinel.
- `--namespace all` targets the literal, valid Kubernetes namespace named `all`.
- Context-only scope continues to authorize named namespace create/delete operations while retaining context and cluster-scoped protections.

## Validation

Add regression tests before implementation for the missing hook event, mixed wildcard normalization, literal `all`, and context-only namespace lifecycle path. Run the focused redirect and Kubernetes suites, then the full Yggdrasil suite.
