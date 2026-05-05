# Adapters

An **adapter file** declares per-component commands the workspace
can list and (where wired) invoke. Today, `ws test` reads
`commands.test` to choose the test runner — adapter > auto-detection.
Other commands (`build`, `run`, `lint`, anything you care to declare)
are surfaced by `ws actions <component>` for human and agent
reference; they're documentation today, not bound to dedicated `ws`
subcommands. Adapter files live in the active realm at
`realms/<active>/adapters/<component>.yaml` — realm-side
configuration, kept out of the component repo so a community can wire
up commands without forking upstream.

Components without an adapter file fall back to auto-detection
(Gradle, Make, Go, Python, npm) for `ws test`. Adapters are optional;
add one when you want to override the test runner, document
project-specific commands, or pin a different default for your
community.

---

## File shape

```yaml
# realms/<active>/adapters/<component>.yaml
commands:
  build: "./gradlew build"
  test: "./gradlew test"
  run: "./gradlew run"
  clean: "./gradlew clean"

ai_context:
  - path: "CONTRIBUTING.md"
    description: "Contribution guidelines and PR conventions"
  - path: "docs/architecture.md"
    description: "Architecture overview for AI orientation"
```

- **`commands`** — a map from action name to shell command. Keys are
  free-form (`build`, `test`, `lint`, `serve`, anything the community
  cares to expose). Values run from the component directory.
- **`ai_context`** — optional list of paths agents should orient
  against when working on the component, with one-line descriptions.

A starter file with comments ships in the upstream
[`realm-template`](realms.md) repo (cloned via `ws realm init`) at
`adapters/example.yaml`. Copy it to your community realm at
`realms/<your-realm>/adapters/<comp>.yaml` and edit.

---

## `ws actions <component>`

Inspect what's wired up for a given component:

```bash
ws actions <component>
```

The command prints two sections:

- **Configured (from realm)** — commands declared in the adapter file,
  if one exists for the component.
- **Auto-detected** — what the workspace would fall back to if no
  adapter file existed (e.g. `./gradlew build`, `go test ./...`).

If the component has neither an adapter file nor a recognized build
system, `ws actions` prints a hint pointing at the path you'd create
to add one.

Realm commands take precedence; auto-detection only fires for
unconfigured commands.

---

## When to add an adapter

The auto-detect fallback covers the common case for `ws test` — a
Gradle component gets `./gradlew test` for free. Add an adapter file
when:

- The component uses a non-default test runner the workspace doesn't
  auto-detect.
- You want to document project-specific commands (e.g. `e2e`,
  `migrate`, `bench`) so `ws actions` surfaces them for agents and
  contributors.
- Different communities want different defaults for the same
  component (one realm wires `test` to a quick subset, another wires
  it to the full suite).

---

## See also

- [Realms](realms.md) — where adapter files live and why they're
  realm-side configuration.
- [Ecosystem Architecture](../ecosystem-architecture.md) — how realms
  fit into the three-layer config merge.
- [`ws help actions`](../ws-cli-guide.md) — CLI behavior and arguments.
