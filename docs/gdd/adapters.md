# Adapters

An **adapter file** declares per-component build, test, and lint
commands so the workspace can invoke them uniformly. Adapter files
live in the active realm at `realms/<active>/adapters/<component>.yaml`
— it's realm-side configuration, kept out of the component repo so a
community can wire up commands without forking upstream.

Components without an adapter file fall back to auto-detection
(Gradle, Make, Go, Python, npm) — adapters are optional, but they're
the only way to override defaults or expose project-specific commands.

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

A starter file with comments ships at
`realm-template/adapters/example.yaml`; copy it to
`<your-realm>/adapters/<comp>.yaml` and edit.

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

The fallback patterns cover the common case — a Gradle component gets
`build` and `test` for free. Add an adapter file when:

- The component uses a non-default build system the workspace doesn't
  auto-detect.
- You want to expose project-specific commands (e.g. `e2e`,
  `migrate`, `bench`) under uniform names.
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
