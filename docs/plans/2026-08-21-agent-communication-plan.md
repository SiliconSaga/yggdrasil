# Agent Communication and Access Restraint Implementation Plan

> **For agentic workers:** with [Superpowers](https://github.com/obra/superpowers) installed, `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` will drive this plan task-by-task. Without it, work the tasks in order by hand — the steps are self-contained, and `AGENTS.md` records this as the expected degradation rather than a blocker. Steps use checkbox (`- [ ]`) syntax for tracking either way.

**Goal:** Ship the documentation, configuration surface, and session-start visibility that let a project decide how its agents speak in public and how far agent access is restrained, with SiliconSaga adopting the strictest setting as a worked example.

**Architecture:** Four prose artifacts plus one small code change. GDD names the question and declines to answer it; the realm answers it. The only code is a `ws orient` block that renders the configured register above the subcommand survey, reading `comms.flavor` and `comms.snippet` through the same layered ecosystem read `emit_change_note_style` already uses.

**Tech Stack:** Bash 3.2-compatible shell, `yq` (mikefarah v4), bats-core, MkDocs.

## Global Constraints

- **Source of truth:** `docs/plans/2026-08-21-agent-communication-design.md`. Where this plan says "per design §X", that section carries the argument the prose must make.
- **`docs/gdd/*.md` must not be hard-wrapped.** Enforced by `tests/templates/line-wrap.bats:74`. One line per paragraph and per bullet.
- **`docs/plans/*.md` is excluded from the docs site** via `not_in_nav` in `mkdocs.yml:28-30`. Only `docs/gdd/` pages need nav entries.
- **Bash 3.2 compatibility.** No `local -n` namerefs, no associative arrays. The existing `ws-orient.sh` style is process substitution plus plain arrays.
- **`ws-orient.sh` runs under `set -euo pipefail`** (line 16). A function whose last statement is a failing test returns non-zero and aborts the whole run. Every new function ends with an explicit `return 0`.
- **`ws orient` has a 10s budget under the bats smoke helper** (`tests/ws-smoke/test_helper.bash:59`). It already spawns a `yq` per config layer; do not add a second per-field pass. See Task 3.
- **All user-visible strings pass through `_ws_orient_display_text`** (`scripts/ws-orient.sh:335`), which strips control characters. Config values are realm-supplied and must not be able to forge output rows.
- **Commit with `ws commit yggdrasil .commits/<name>.md`** (or `ws commit realm-siliconsaga …` for Task 5). Bodyfiles declare their own staged paths; there is no separate `git add`.

## File Structure

| File | Responsibility |
|---|---|
| `docs/gdd/agent-communication.md` | New. The question, the mechanism, the four dimensions, three copyable flavors. Answers nothing. |
| `docs/gdd/access.md` | Gains two sections: privilege inversion, and shared-vs-individual machine accounts with the App as destination. |
| `scripts/ws-orient.sh` | Gains `_ws_orient_config_layers` (extracted) and `emit_comms_register`; call order changes. |
| `tests/ws-orient/comms.bats` | New. Covers unset, each valid flavor, invalid, snippet present/absent, ordering, sanitization. |
| `templates/change.md`, `templates/issue.md` | One-line register pointer in the body guidance. |
| `mkdocs.yml` | Nav entry for the new page. |
| `docs/gdd/roadmap.md` | GitHub App auth, organizer-board tooling, automated tone evaluation, escape-hatch enforcement. |
| `CHANGELOG.md` | `[Unreleased]` entries. |
| `realms/realm-siliconsaga/docs/agent-collaboration-etiquette.md` | New. The worked example, argued. |
| `realms/realm-siliconsaga/AGENTS.md` | Tone Guide restructured into universal rule + audience vocabulary. |
| `realms/realm-siliconsaga/ecosystem.yaml` | Sets `comms.flavor: oss-wide`. |

Tasks 1–4 are one yggdrasil PR. Task 5 is a separate realm PR and must land after Task 1, because it cites the published GDD page.

---

### Task 1: The GDD topic page

**Files:**
- Create: `docs/gdd/agent-communication.md`
- Modify: `mkdocs.yml:70-72` (nav entry)

**Interfaces:**
- Consumes: nothing.
- Produces: the anchor `docs/gdd/agent-communication.md` and its section anchors `#the-four-dimensions` and `#three-flavors`. Tasks 2, 3, 4 and 5 all link to this file by that exact path; Task 3 prints the path in `ws orient` output and Task 4 prints it in two templates.

- [ ] **Step 1: Write the page**

Required sections, in order. Source every argument from the design document — this page is the public rendering of it, not new thinking.

1. **Opening.** State what the page is for: a project running agents against a public tracker has four decisions to make, most people have not noticed they are decisions, and GDD does not make them for you.
2. **`## The mechanism: legibility, not tone`** — per design §"The mechanism". Must establish that the property is *no reader can mistake it for a person holding an opinion*, that neutrality is the instrument rather than the goal, and that this is why a one-sentence disclaimer under-delivers.
3. **`## What GDD already does, and where it stops`** — the disclaimer is enforced on CR and issue bodies (`scripts/git-cr.sh`, `scripts/git-issue.sh`) and nowhere else; separate agent identities are documented in [access.md](access.md) §1. Self-critical and specific. Do not claim review replies are covered.
4. **`## Name the decision, never the verdict`** — per design §"The through-line", including the organizer-surface subsection. Must carry the two properties that make a board work: columns name judgement types rather than verdicts, and the surface is low-visibility so moving a card notifies nobody. Must state the division as *the agent prepares and tests; humans review and judge*, and that this is not a demotion.
5. **`## The four dimensions`** — reproduce the design's table verbatim (identity, register, disposition authority, privilege inversion), then one paragraph stating plainly that GDD does not set them.
6. **`## Three flavors`** — the three blocks below, each introduced by one paragraph of when-to-use per design §"Three flavors". The solo blurb must say the points remain valid and are merely cheaper to skip, not that they do not apply.
7. **`## Making the choice visible`** — `comms.flavor` and `comms.snippet` in ecosystem config, rendered by `ws orient` at session start. Cross-reference Task 3's behaviour: unset renders as a prompt to decide.
8. **`## See also`** — [access.md](access.md), [trust-and-safety.md](trust-and-safety.md), [permissions.md](permissions.md).

The three flavor blocks are the load-bearing content and must appear as fenced markdown blocks readers can copy into an `AGENTS.md`:

````markdown
```markdown
## Agent-authored communication

Neutral tone. Fairly concise. Simple language, few idioms or unusual turns of phrase. No judgement. The agent prepares and tests work so that others can review and judge it.

- Post from a machine account. Never from a maintainer's personal account.
- Do not close, merge, resolve, or characterise the state of someone's contribution. Route it to the triage surface and name the decision that is needed.
- Say what was observed and what decision it requires. Do not say which way the decision should go.
```
````

````markdown
```markdown
## Agent-authored communication

Neutral tone, concise, plain language, no judgement. Disclose that a comment is agent-authored.

Do not close or merge anything without the maintainer saying so in that specific case.

(The stricter OSS-wide setting is still sound here — a small, mostly-known audience just makes it cheaper to skip. Revisit if the contributor base widens.)
```
````

````markdown
```markdown
## Agent-authored communication

Post from a machine account so activity is attributable in audit.

Register is unconstrained internally; colleagues share the vocabulary and the context.

Closing, merging, and approving follow the organisation's existing change control. The agent does not create an exception to it.
```
````

- [ ] **Step 2: Add the nav entry**

In `mkdocs.yml`, immediately after the `Trust and Safety` line (currently line 70):

```yaml
    - Agent Communication: gdd/agent-communication.md
```

- [ ] **Step 3: Verify the line-wrap guard passes**

Run: `ws test yggdrasil tests/templates/line-wrap.bats`
Expected: PASS. A failure here means prose was hard-wrapped; join the wrapped lines.

- [ ] **Step 4: Verify every relative link resolves**

Run: `grep -o '](\([a-z./-]*\.md\)' docs/gdd/agent-communication.md`
Then confirm each named file exists under `docs/gdd/`. Expected: `access.md`, `trust-and-safety.md`, `permissions.md` all present.

- [ ] **Step 5: Commit**

Write `.commits/gdd-agent-communication-page.md` with frontmatter staging `docs/gdd/agent-communication.md` and `mkdocs.yml`, then:

```bash
ws commit yggdrasil .commits/gdd-agent-communication-page.md
```

---

### Task 2: Access — privilege inversion and machine accounts

**Files:**
- Modify: `docs/gdd/access.md` (new sections after §4 "Token scopes in practice", renumbering the sections that follow)

**Interfaces:**
- Consumes: the page created in Task 1, linked as `agent-communication.md`.
- Produces: section anchors `#privilege-inversion` and `#shared-versus-individual-machine-accounts`, linked from Task 1's page and Task 5's realm document.

- [ ] **Step 1: Insert the privilege-inversion section**

After §4, as a new §5. Content per design §"Privilege inversion". Must establish:

- The inversion itself: **the more a human can break, the less their agent should hold.** State it as the counterintuitive claim it is, because a reader will assume the opposite.
- Both justifications, separately: blast radius (a maintainer's token can write to the main org; their agent inherits that) and social weight (a comment from an org owner carries more force, so a misattributed agent voice does proportionally more damage from the more privileged account).
- The practical shape: as human access widens, push agent activity toward a fork group operated by a machine user — topic branches in the fork, pull requests and issues inbound, no merges and no closes.
- That enforcement is **human**. The mechanical form — barring org owners from minting agent-usable tokens with main-org write — appears to need paid tiers. Say so rather than implying tooling that does not exist.
- One sentence connecting it to §1's existing argument, which already justifies separate identities on the grounds that "compromise of the agent token is bounded". This section generalises that from compromise to authority.

- [ ] **Step 2: Insert the machine-account section**

As a new §6. Content per design §"Shared versus individual machine accounts". Must establish:

- Both models are workable: one shared account holding write access only to a fork group, or individual machine accounts added to a robot team in that group.
- The shared model's non-obvious cost: driver attribution has to survive in-band. It does on commits (`Co-Authored-By`) and in CR and issue bodies (the disclaimer), and it does **not** on review replies or issue comments, which is where dispositions get typed. Name yggdrasil #141 as the change that closes this, and say plainly that the shared model should not be recommended until it lands.
- Machine accounts are permitted; **credential sharing** is the part that strains platform terms and is also what erodes accountability.
- A **GitHub App** is the better destination on both counts: it posts with a platform-rendered bot marker nobody can forge — legibility made structural rather than conventional — and uses short-lived installation tokens scoped to chosen repositories, so the fork-group boundary is enforced by the platform. The cost is authentication machinery GDD does not have (`.env` PATs today versus JWT signing and installation-token exchange). Roadmap.
- A closing line telling maintainers to verify current platform terms themselves rather than relying on this document.

- [ ] **Step 3: Renumber the following sections**

The existing §5 "Multi-provider workflows", §6 "Diagnostics: `ws diagnose`" and §7 "Future direction: scope-templated PATs" become §7, §8 and §9.

Run: `grep -n '^## [0-9]' docs/gdd/access.md`
Expected: a contiguous run `## 1.` through `## 9.` with no repeats or gaps.

- [ ] **Step 4: Fix any internal cross-references to the renumbered sections**

Run: `grep -rn 'access\.md#\|§[0-9]' docs/ .agent/ realms/realm-siliconsaga/`
Expected: no reference points at a section number that moved. Update any that do.

- [ ] **Step 5: Verify the line-wrap guard**

Run: `ws test yggdrasil tests/templates/line-wrap.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

Write `.commits/gdd-access-privilege-inversion.md` staging `docs/gdd/access.md`, then:

```bash
ws commit yggdrasil .commits/gdd-access-privilege-inversion.md
```

---

### Task 3: `ws orient` renders the communication register

**Files:**
- Modify: `scripts/ws-orient.sh` — extract `_ws_orient_config_layers` from `emit_change_note_style` (currently lines 542-552), add `emit_comms_register`, change the call order at the end of the file (currently lines 608-613)
- Create: `tests/ws-orient/comms.bats`

**Interfaces:**
- Consumes: `_ws_orient_display_text` (line 335); `_ORIENT_REALM`, `_ORIENT_REALM_STATUS`, `_ORIENT_REALM_TRUST` set by `_resolve_orient_realm`.
- Produces: two ecosystem config fields consumed by nothing else yet — `comms.flavor` (string: `oss-wide` | `solo` | `corporate` | `none`) and `comms.snippet` (free string). Task 5 sets `comms.flavor` in the realm's `ecosystem.yaml`. Output lines begin `Communication register: `.

**Why this shape:** the register governs everything the agent writes afterwards, so it renders *before* the ~40-line subcommand survey rather than after it. `emit_change_note_style` sits below the survey today and is correspondingly easy to miss — that is the mistake being avoided, not repeated.

- [ ] **Step 1: Write the failing tests**

Create `tests/ws-orient/comms.bats`:

```bash
#!/usr/bin/env bats

# `ws orient` renders the configured communication register before the
# subcommand survey. Placement is part of the contract, not cosmetics: the
# survey is ~40 lines, so anything below it is missed, and this block governs
# everything the agent writes for the rest of the session.
#
# Unset is the interesting default. GDD names the question and leaves the
# answer to the project, so an unset register renders as a prompt to decide
# rather than as an error or as silence.

load ../ws-smoke/test_helper

setup() {
    init_workspace
}

set_comms() {
    yq -i ".comms.flavor = \"$1\"" "$ECOSYSTEM"
}

@test "ws orient: an unset register prompts the reader to decide" {
    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"Communication register: not set"* ]]
    [[ "$output" == *"agent-communication.md"* ]]
}

@test "ws orient: a set flavor renders with the register summary" {
    set_comms oss-wide

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"Communication register: oss-wide"* ]]
    [[ "$output" == *"prepares and tests"* ]]
}

@test "ws orient: each valid flavor is accepted" {
    for flavor in oss-wide solo corporate; do
        set_comms "$flavor"
        run_ws orient
        [ "$status" -eq 0 ]
        [[ "$output" == *"Communication register: $flavor"* ]] \
            || { echo "flavor not rendered: $flavor"; return 1; }
    done
}

@test "ws orient: 'none' renders as a deliberate choice, not as unset" {
    set_comms none

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"Communication register: none"* ]]
    [[ "$output" != *"not set"* ]]
}

@test "ws orient: an unrecognized flavor is shown and flagged, not swallowed" {
    set_comms piratical

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"unrecognized"* ]]
    [[ "$output" == *"piratical"* ]]
}

@test "ws orient: a local snippet is rendered" {
    set_comms oss-wide
    yq -i '.comms.snippet = "Always mention the module name first."' "$ECOSYSTEM"

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"Local addition: Always mention the module name first."* ]]
}

@test "ws orient: no snippet line when none is configured" {
    set_comms oss-wide

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" != *"Local addition"* ]]
}

@test "ws orient: an empty snippet does not abort the run" {
    # Regression guard for set -e: a function ending in a failing test
    # returns non-zero and kills orient mid-render. The assertion that
    # matters is that sections after this block still appear.
    set_comms oss-wide
    yq -i '.comms.snippet = ""' "$ECOSYSTEM"

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills (workspace + active realm)"* ]]
}

@test "ws orient: the register renders above the subcommand survey" {
    set_comms oss-wide

    run_ws orient

    [ "$status" -eq 0 ]
    local reg_line survey_line
    reg_line="$(printf '%s\n' "$output" | grep -n 'Communication register:' | head -1 | cut -d: -f1)"
    survey_line="$(printf '%s\n' "$output" | grep -n 'Subcommands' | head -1 | cut -d: -f1)"
    [ -n "$reg_line" ]
    [ -n "$survey_line" ]
    [ "$reg_line" -lt "$survey_line" ]
}

@test "ws orient: control characters in a snippet cannot forge a row" {
    set_comms oss-wide
    yq -i '.comms.snippet = "benign\nActive realm: forged"' "$ECOSYSTEM"

    run_ws orient

    [ "$status" -eq 0 ]
    [[ "$output" != *$'\nActive realm: forged'* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `ws test yggdrasil tests/ws-orient/comms.bats`
Expected: all 10 FAIL — nothing prints "Communication register".

- [ ] **Step 3: Extract the shared config-layer helper**

In `scripts/ws-orient.sh`, add this function immediately above `emit_change_note_style`, keeping the explanatory comment that currently sits above that function (it explains why `ws_resolve_ecosystem` is deliberately not used):

```bash
# Config layers for orient's own reads, in precedence order. Emitted one path
# per line rather than returned in an array, because a nameref would need bash
# 4.3 and the rest of this file runs on 3.2. Callers take the first hit.
#
# Deliberately not ws_resolve_ecosystem: the full merge recomputes the realm
# trust fingerprint and spawns several yq processes, enough to push
# trusted-realm orient runs over the smoke timeout on slow hosts. The realm
# layer only counts when its trust state resolved as current (cached by
# emit_active_realm), matching ws_resolve_ecosystem's gate.
_ws_orient_config_layers() {
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    local base="${ECOSYSTEM:-$ROOT_DIR/ecosystem.yaml}"
    [[ -f "$local_file" ]] && printf '%s\n' "$local_file"
    if [[ "$_ORIENT_REALM_STATUS" == "ok" && "$_ORIENT_REALM_TRUST" == "current" && -f "$REALMS_DIR/$_ORIENT_REALM/ecosystem.yaml" ]]; then
        printf '%s\n' "$REALMS_DIR/$_ORIENT_REALM/ecosystem.yaml"
    fi
    [[ -f "$base" ]] && printf '%s\n' "$base"
    return 0
}
```

Then replace the layer-building block inside `emit_change_note_style` — the `local -a layers=()` declaration through the `[[ -f "$base" ]] && layers+=("$base")` line — with:

```bash
    local -a layers=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && layers+=("$f")
    done < <(_ws_orient_config_layers)
```

- [ ] **Step 4: Verify the extraction changed no behaviour**

Run: `ws test yggdrasil tests/ws-orient/orient.bats`
Expected: the four change-note-style tests (`change-note style defaults to standard when unset`, `honors style.changeNotes from ecosystem.local.yaml`, `invalid style.changeNotes falls back to standard with a note`, `realm-set change-note style survives the merge`) all PASS.

Note: five tests in this file (`renders ai_context rows`, `marks an ai_context path that does not resolve`, `does not mark a resolvable ai_context path as missing`, `rejects a symlinked ai_context path`, `multiline ai_context values cannot forge another row`) fail on Windows hosts for pre-existing reasons unrelated to this change — the 10s smoke timeout on two-row adapters, `ln -s` not producing real symlinks, and control-character rendering width. Confirm those five and only those five are the failures, by stashing this change and re-running against a clean tree if there is any doubt.

- [ ] **Step 5: Add the register emitter**

Immediately below `emit_change_note_style`:

```bash
# Communication register — how agent-authored tracker and review output reads,
# and any local instruction extending it. See docs/gdd/agent-communication.md.
#
# One yq per layer reading both fields as TSV, rather than one pass per field.
# Two passes would double the process count on a path already close to the
# smoke timeout. The two fields still resolve independently, because the
# expected combination is a realm-set flavor with a locally-set snippet.
#
# Unset is not a defect. GDD names the question and leaves the answer to the
# project, so an unset register renders as the prompt to decide.
emit_comms_register() {
    local flavor="" snippet="" f row row_flavor row_snippet
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        row="$(yq -r '[(.comms.flavor // ""), (.comms.snippet // "")] | @tsv' "$f" 2>/dev/null)" || continue
        IFS=$'\t' read -r row_flavor row_snippet <<< "$row"
        [[ -z "$flavor" && -n "${row_flavor:-}" && "$row_flavor" != "null" ]] && flavor="$row_flavor"
        [[ -z "$snippet" && -n "${row_snippet:-}" && "$row_snippet" != "null" ]] && snippet="$row_snippet"
    done < <(_ws_orient_config_layers)

    flavor="$(_ws_orient_display_text "$flavor")"
    snippet="$(_ws_orient_display_text "$snippet")"

    case "$flavor" in
        oss-wide|solo|corporate)
            printf '\nCommunication register: %s\n' "$flavor"
            echo "  Neutral tone, fairly concise, simple language, no judgement. The agent prepares and tests work so others can review and judge it."
            ;;
        none)
            printf '\nCommunication register: none (deliberately unconstrained)\n'
            ;;
        "")
            printf '\nCommunication register: not set\n'
            echo "  How agent-authored comments read — and who may close or merge — is your project's call, not GDD's."
            echo "  See docs/gdd/agent-communication.md, then set comms.flavor (oss-wide|solo|corporate|none) in ecosystem config."
            ;;
        *)
            printf '\nCommunication register: unrecognized (%s) — treating as not set\n' "$flavor"
            echo "  Valid values: oss-wide, solo, corporate, none. See docs/gdd/agent-communication.md."
            ;;
    esac

    if [[ -n "$snippet" ]]; then
        echo "  Local addition: $snippet"
    fi
    return 0
}
```

The explicit `return 0` is load-bearing. Under `set -euo pipefail` a function whose last evaluated statement is a false test returns non-zero, which aborts orient before the sections below it render.

- [ ] **Step 6: Call it before the subcommand survey**

At the end of the file, change the call block so `emit_comms_register` runs first:

```bash
emit_comms_register
emit_subcommand_survey
emit_active_realm
emit_change_note_style
emit_component_adapters
emit_workspace_selftest
emit_skill_index
```

- [ ] **Step 7: Run the new tests to verify they pass**

Run: `ws test yggdrasil tests/ws-orient/comms.bats`
Expected: 10/10 PASS.

- [ ] **Step 8: Re-run the orient suite for regressions**

Run: `ws test yggdrasil tests/ws-orient/orient.bats`
Expected: the same pass/fail set as Step 4 — no new failures.

Run: `ws test yggdrasil tests/ws-orient/check.bats`
Expected: 7/7 PASS.

- [ ] **Step 9: Commit**

Write `.commits/orient-comms-register.md` staging `scripts/ws-orient.sh` and `tests/ws-orient/comms.bats`, then:

```bash
ws commit yggdrasil .commits/orient-comms-register.md
```

---

### Task 4: Template pointers, roadmap, changelog

**Files:**
- Modify: `templates/change.md:5`, `templates/issue.md:5`
- Modify: `docs/gdd/roadmap.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the page path from Task 1 and the `ws orient` behaviour from Task 3.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the register pointer to the CR template**

In `templates/change.md`, append to the Summary bullet's guidance, inside the existing bracket, immediately after the `style.changeNotes` sentence:

```
Register — how this reads to whoever receives it — is set by comms.flavor and shown by `ws orient`; see docs/gdd/agent-communication.md.
```

- [ ] **Step 2: Add the same pointer to the issue template**

In `templates/issue.md`, append to the Context bracket, after the `style.changeNotes` sentence:

```
Register is set by comms.flavor and shown by `ws orient`; see docs/gdd/agent-communication.md.
```

Both are pointers rather than rules. GDD ships templates used by projects that have not adopted a register, and a template that asserts one would contradict the page it links to.

- [ ] **Step 3: Verify the templates still pass their guards**

Run: `ws test yggdrasil tests/templates/line-wrap.bats`
Expected: PASS.

Run: `ws test yggdrasil tests/ws-cr`
Expected: PASS — the disclaimer check reads only the first line and must be unaffected.

- [ ] **Step 4: Add the roadmap entries**

In `docs/gdd/roadmap.md`, under the "CLI and infrastructure ideas — waiting on evidence of need" list, add:

```markdown
- **GitHub App identity for agents** — an App posts with a platform-rendered bot marker nobody can forge and uses short-lived installation tokens scoped to chosen repositories, which is a stronger form of both the legibility and the blast-radius arguments in [agent-communication.md](agent-communication.md). Needs JWT signing and installation-token exchange in the auth layer, where today there are `.env` PATs.
- **Organizer-surface routing** — a `ws` verb to move an issue to a triage column, so an agent can discharge a finding without commenting on it. The pattern is documented; the automation is not built.
- **Automated register evaluation** — a CI job driving a second-model agent over the `gdd-sandbox` chat bridge to assess whether agent-authored replies match the configured register. Long-term; manual sub-agent spot checks are the current method.
- **Advisory machine-account check** — `ws diagnose` reporting when the provider token resolves to the same account as the configured human identity.
```

- [ ] **Step 5: Add the changelog entries**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, matching the terse house style now used in that section:

```markdown
- **[Agent communication](docs/gdd/agent-communication.md)** — the four decisions a project makes about how its agents speak in public, three copyable settings, and why a disclaimer is weaker than a machine account. GDD names the question; the project answers it.
- **`comms.flavor` and `comms.snippet`** — the answer, rendered by `ws orient` above everything else. Unset renders as a prompt to decide rather than as silence.
```

Under `### Changed`:

```markdown
- **[access.md](docs/gdd/access.md) gained privilege inversion** — agent access should narrow as the driving human's access widens, because both blast radius and social weight scale with it.
```

- [ ] **Step 6: Commit**

Write `.commits/comms-templates-roadmap.md` staging `templates/change.md`, `templates/issue.md`, `docs/gdd/roadmap.md` and `CHANGELOG.md`, then:

```bash
ws commit yggdrasil .commits/comms-templates-roadmap.md
```

- [ ] **Step 7: Open the yggdrasil PR**

Run the full suite first:

Run: `ws test yggdrasil`
Expected: the pre-existing failures named in Task 3 Step 4 and no others.

Then write `.crs/agent-communication.md` from `templates/change.md` and:

```bash
ws cr yggdrasil "feat(docs): agent communication register and access restraint" .crs/agent-communication.md
```

---

### Task 5: The realm adopts it

**Files:**
- Create: `realms/realm-siliconsaga/docs/agent-collaboration-etiquette.md`
- Modify: `realms/realm-siliconsaga/AGENTS.md:50-75` (the existing Tone Guide)
- Modify: `realms/realm-siliconsaga/ecosystem.yaml`

**Interfaces:**
- Consumes: `docs/gdd/agent-communication.md` from Task 1, cited by URL since it lives in a different repository; `comms.flavor` from Task 3.
- Produces: nothing.

**Why the Tone Guide is restructured rather than extended:** `AGENTS.md` already has a `## Tone Guide` section, but it governs *vocabulary for particular audiences* — avoid techno-utopian language on the civics and schools components — and it opens by saying "most repos can follow any communication style that seems appropriate". That sentence is now false: the register rule is not repo-dependent. Adding a second, contradicting tone section would leave an agent to pick. One section, two clearly separated parts.

- [ ] **Step 1: Write the realm etiquette document**

Create `realms/realm-siliconsaga/docs/agent-collaboration-etiquette.md`, sibling to `agent-doc-layering.md` and named as the design document named this deferred cycle. Required content:

1. **What this is.** SiliconSaga's answers to the four dimensions, and why a realm serving a large international volunteer project picks the strictest ones. Link the GDD page as the source of the dimensions.
2. **The four answers, stated plainly.** Identity: machine account required. Register: neutral, mandatory, uniform. Disposition authority: never — no closing, merging, resolving, or characterising the state of a contribution. Privilege inversion: mandated for org owners.
3. **Why strictest here.** The cultural-distance argument: a large international contributor base means a maintainer cannot predict how their agent's words will land, and a disclaimer written in English is the first thing to fail. Cite the concrete failure the design records.
4. **The machine account, either way.** A shared account holding write access only to the fork group, or an individual machine account added to that group's robot team. Both acceptable. Note the shared model's dependence on driver attribution reaching review replies, and that this is what yggdrasil #141 fixes.
5. **What the agent does instead.** The organizer surface: route to a column naming the judgement required. Restate *the agent prepares and tests; humans review and judge*.
6. **Not yet decided.** The Terasology-specific mandate — core maintainers using a shared agent-org account — belongs to a Terasology realm that does not exist yet. Record it as intended, not as policy.

- [ ] **Step 2: Restructure the Tone Guide**

In `realms/realm-siliconsaga/AGENTS.md`, replace the opening sentence of `## Tone Guide` and insert the universal rule above the existing audience-specific guidance. The section becomes:

```markdown
## Tone Guide

Two separate things: how the agent speaks at all, and what vocabulary suits a particular audience.

### How agent-authored communication reads — always

Neutral tone. Fairly concise. Simple language, few idioms or unusual turns of phrase. No judgement. The agent prepares and tests work so that others can review and judge it.

- Post from a machine account, never a maintainer's personal account.
- Do not close, merge, resolve, or characterise the state of someone's contribution. Route it and name the decision that is needed.
- Say what was observed and what decision it requires. Do not say which way it should go.

This is not repo-dependent and does not relax for internal work. Reasoning and the full policy: [agent-collaboration-etiquette.md](docs/agent-collaboration-etiquette.md).

### Vocabulary for user-facing audiences

Some repos are user-facing in sensitive areas:
```

The existing bullet list of components and the existing vocabulary bullets follow unchanged from that point. Delete only the original opening line ("While most repos can follow any communication style that seems appropriate, some are user-facing in sensitive areas:") and the closing paragraph beginning "This distinction between public-facing civics content", replacing the latter with:

```markdown
The vocabulary distinction is about audience. The register rule above is about who is speaking, and applies to both.
```

- [ ] **Step 3: Set the flavor in realm config**

In `realms/realm-siliconsaga/ecosystem.yaml`, add at the top level:

```yaml
comms:
  flavor: oss-wide
```

- [ ] **Step 4: Verify orient renders it**

Run: `ws orient`
Expected: `Communication register: oss-wide` appears above the `Subcommands` block.

Note: changing the realm's `ecosystem.yaml` alters the realm trust fingerprint, so orient will report that reapproval is required. Re-approve with `ws realm use realm-siliconsaga` after reviewing the trust summary, then re-run.

- [ ] **Step 5: Commit and open the realm PR**

Write `.commits/realm-agent-etiquette.md` staging the three realm paths, then:

```bash
ws commit realm-siliconsaga .commits/realm-agent-etiquette.md
```

Then write `.crs/realm-agent-etiquette.md` and:

```bash
ws cr realm-siliconsaga "feat: agent collaboration etiquette" .crs/realm-agent-etiquette.md
```

---

## Verifying the rule works at all

Not a task — the check that decides whether a skill is ever warranted, per design §"The rule lives at L0, not in a skill".

After Task 5 lands, dispatch three fresh general-purpose sub-agents with the realm loaded and a realistic prompt: a two-year-old Terasology issue with no reproduction, an unresponsive reporter, and an instruction to triage it. Read what they write. The failure mode to look for is a comment carrying a verdict — "stale", "not reproducible, closing" — or an offer to close.

If the L0 rule holds, no skill is needed and that result should be recorded. If agents route around it, the failure text they produce is the input to a skill, and `superpowers:writing-skills` applies from there. Do not write the skill first; ten prior candidates in this workspace failed the "is this really skill material" bar, and one confident prediction that a rule *would* fail was itself wrong.

## Self-review notes

- **Spec coverage.** All nine design artifacts map to tasks: the GDD page (1), access sections (2), orient plus tests (3), templates, roadmap and changelog (4), realm doc, `AGENTS.md` and realm config (5). The design's deferred items appear in Task 4 Step 4 as roadmap entries rather than as work.
- **Dependency recorded.** Yggdrasil #141 is named in Task 2 Step 2 and Task 5 Step 1 as the prerequisite for recommending a shared machine account, matching the design.
- **Naming consistency.** `comms.flavor` and `comms.snippet` are used identically in Task 3 (reader), Task 4 (template and changelog copy) and Task 5 (writer). Flavor values `oss-wide`, `solo`, `corporate`, `none` are the same set in the emitter's `case`, the tests, the unset help text and the realm config.
- **Known gap.** The pre-existing Windows failures in `tests/ws-orient/orient.bats` are not fixed here. They are unrelated to this change and touch a file with other pull requests open against it.
