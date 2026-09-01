# Adapters

An **adapter file** declares per-component commands the workspace can list and (where wired) invoke. `ws test`, `ws lint`, and `ws build` read `commands.test` / `commands.lint` / `commands.build` to choose what to run — adapter > auto-detection. Other declared commands (`run`, `serve`, anything you care to expose) are surfaced by `ws actions <component>` for human and agent reference without a dedicated `ws` subcommand. Adapter files live in the active realm at `realms/<active>/adapters/<component>.yaml` — realm-side configuration, kept out of the component repo so a community can wire up commands without forking upstream.

Components without an adapter file fall back to auto-detection (Gradle, Make, Go, Python, npm) for `ws test`. Adapters are optional; add one to override the test runner, document project-specific commands, or pin a different default for your community.

Adapter config lives in the *realm* rather than the component because on its own it makes no sense — an adapter is added scaffolding for GDD to work a given component better, worthless to anyone not running GDD. Improvements that help *everybody* (a better Makefile target, a CI fix, clearer docs) belong in the component itself as native changes; the adapter is the GDD-specific overlay a community maintains without asking upstream for anything.

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

nested:
  - "modules/*"
  - "libs/*"
```

- **`commands`** — a map from action name to shell command. Keys are free-form (`build`, `test`, `lint`, `serve`, anything the community cares to expose). Values run from the component directory.
- **`ai_context`** — optional list of paths agents should orient against when working on the component, with one-line descriptions.
- **`nested`** — optional list of globs, relative to the component directory, describing where independent git repos live *inside* this component. See below.

---

## Nested repos — components that contain other repos

Some projects are workspaces in their own right. Terasology's `modules/` holds well over a hundred independent repos, each with its own upstream and review norms, gitignored by the parent because they are meant to be checked out *inside* the engine tree where they can actually build.

Those repos are not components: they are not declared in ecosystem config, they churn far too fast to enumerate, and their names are upstream-controlled CamelCase that the component naming rule rejects. Declaring the **shape** instead keeps the config stable while the contents move:

```yaml
nested:
  - "modules/*"
```

With that in place, every target-taking `ws` verb accepts `<component>/<repo>`:

```bash
ws commit terasology/Health .commits/fix.md
ws push terasology/Health
ws cr terasology/Health "fix: ..." .crs/fix.md
```

The bare name is matched against the basename of each expanded glob, so you do not have to remember which typed subdirectory a repo lives under. When two nested repos share a name, qualify with the full relative path (`terasology/libs/Health`) — the ambiguity is reported rather than guessed.

Patterns are relative and may not contain `..` or whitespace, and a resolved repo whose real path falls outside the component is refused — so a symlink cannot be used to walk a write verb out of the component tree.

**What stays out of scope, deliberately:** nothing recurses. `ws pull` never refreshes nested repos in its sweep (it reports how many it skipped), and there is no bulk commit or push across them. These are independent upstreams with their own review norms; a sweep that committed across a hundred of them would be a far worse accident than the one this feature exists to prevent. Nested targets are always explicit and always singular.

`ws status` shows a nested repo count per component for free, and `ws status --nested` runs git status across them, listing only the dirty ones — the case where an edit is sitting in a repo nobody is watching.

Because `nested` lives in the adapter, adding or changing it makes realm trust stale: re-approve with `ws realm use --trust <realm>` so the change passes through the same review as a command string.

A starter file with comments ships in the upstream [`realm-template`](https://github.com/SiliconSaga/realm-template) repo (cloned via `ws realm init`) at `adapters/example.yaml`. Copy it to your community realm at `realms/<your-realm>/adapters/<comp>.yaml` and edit. See [Realms](realms.md) for the realm-template's role in the workspace.

---

## Adapter trust — executable config is config that executes

An adapter file is **executable configuration**: when `ws test` runs, the string in `commands.test` is what actually gets exec'd in the component dir. That makes the adapter file a trust boundary, not just a config surface. Allowlisting `ws test` / `ws lint` by default is reasonable because the *wrapper* is trusted to dispatch what the realm wires — but the wrapped command itself comes from a YAML file the realm author controls.

**`ws orient` surfaces the resolved command** for every wired component so the executable-config surface stays auditable:

```text
nordri
  ws test [runs: make test]
  ws lint [runs: make lint]
ting
  ws test [runs: .venv/bin/python -m pytest tests/unit tests/integration -v]
  ws lint [runs: .venv/bin/python -m ruff check src/ tests/]
```

If you can't audit what `ws test` will actually run from `ws orient` output, the wrapper is hiding the executable-config surface — that's the regression the `runs:` form prevents.

The orientation skill runs a **risk scan** on every realm activation, flagging adapter commands that contain `curl | sh` / `wget | sh`, base64 decode-execute, writes outside the component dir, outbound network calls in test/lint runners, or `eval`. Rigor scales by realm provenance — light for your own / team realms, heavy for community / wild realms. Realm approval fingerprints each adapter and any realm-owned regular file its command strings reference, so changing an executable wrapper makes trust stale while editing unrelated realm documentation does not. Final symlinks and intermediate symlinks that escape the realm are rejected rather than followed across the reviewed boundary. See [Trust and Safety § Adapter Command Trust](trust-and-safety.md#adapter-command-trust).

---

## `ws actions <component>`

Inspect what's wired up for a given component:

```bash
ws actions <component>
```

The command prints two sections:

- **Configured (from realm)** — commands declared in the adapter file, if one exists for the component.
- **Auto-detected** — what the workspace would fall back to if no adapter file existed (e.g. `./gradlew build`, `go test ./...`).

If the component has neither an adapter file nor a recognized build system, `ws actions` prints a hint pointing at the path you'd create to add one.

---

## When to add an adapter

The auto-detect fallback covers the common case for `ws test` — a Gradle component gets `./gradlew test` for free. Add an adapter file when:

- The component uses a non-default test runner the workspace doesn't auto-detect.
- You want to document project-specific commands (e.g. `e2e`, `migrate`, `bench`) so `ws actions` surfaces them for agents and contributors.
- Different communities want different defaults for the same component (one realm wires `test` to a quick subset, another wires it to the full suite).

---

## See also

- [Realms](realms.md) — where adapter files live and why they're realm-side configuration.
- [Ecosystem Architecture](../ecosystem-architecture.md) — how realms fit into the three-layer config merge.
- `ws actions --help` — CLI behavior and arguments (the help system is the command reference).
