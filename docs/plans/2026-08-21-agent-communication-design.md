# Agent Communication and Access Restraint Design

Status: proposed design

## Context

An agent posting to a public tracker under a human's account is a different act from an agent editing code. The code is reviewed before it lands; the comment lands the moment it is written, in front of an audience that did not ask for it.

The failure this design addresses is specific and was observed in a real community. An agent-authored GitHub comment that reads as a judgement call — "this issue looks stale, nothing here is recoverable, closing" — is received very differently from the same disposition delivered by a stale-issue bot. The bot is unmistakably a script: narrow, mechanical, named for what it does. It nudges a dead issue toward the archive without insulting anyone, because nobody reads a script as holding an opinion about them. An agent writing fluent prose from a trusted maintainer's account is read as that maintainer forming and expressing a judgement, and the better the prose, the more completely that reading takes hold.

Three things make it worse in the community that prompted this:

- **The account is trusted.** A contributor who recognises the maintainer's name reads the comment as coming from a person whose opinion carries weight in the project.
- **The disclaimer is a sentence.** GDD already stamps `> **AI-assisted change proposal.** Filed by agent driven by @HUMAN via GDD` on CR and issue bodies, enforced in `scripts/git-cr.sh:457` and `scripts/git-issue.sh:67`. A sentence is exactly what a reader skims past — and in an international community, exactly what a reader with limited English fails to parse. Everything after it still reads like a person.
- **The surface with the worst exposure has the least protection.** `ws review reply` enforces no attribution at all today. Review replies and issue comments are where dispositions get typed, and they are unguarded.

GDD's existing posture is therefore half-built: separate agent identities are documented and practised (`docs/gdd/access.md` §1), the disclaimer is mechanically enforced on two of four surfaces, and there is no guidance anywhere on register — `gdd-review-triage` and `gdd-github-issues` say nothing about how to write.

## Goals

- Give GDD a published page that raises the question and hands the decision to the community, rather than mandating an answer.
- Give the SiliconSaga realm a concrete, argued policy that works as a reference example for a large, diverse, international OSS project.
- Ship portable text people can paste into a realm or a bare project's `AGENTS.md` without adopting anything else.
- Make the register in force visible at session start, so a non-default setting is never silently active.
- Record the access half — that agent restraint should tighten as the driving human's privilege widens — in the doc that already argues scope minimisation.

## Non-Goals

- Mechanical enforcement of register. No regex distinguishes analysis from judgement; attempting it would produce false confidence.
- A GDD-level mandate on machine accounts, closing, or merging. GDD names the dimensions; communities set them.
- Building the organizer board, or `ws` tooling for it. The pattern is described; the implementation is roadmap.
- GitHub App authentication. Named as the better destination, deferred.
- A skill, unless the always-loaded rule is shown to fail.

## The mechanism: legibility, not tone

The property that makes the stale bot safe is not politeness and not even neutrality. It is that **no reader can mistake it for a person holding an opinion.** Specificity and objectivity are how it achieves that; they are instruments, not the goal.

Naming the mechanism this way changes what the rule says. "Be neutral" is a tone instruction an agent can satisfy while still sounding like a thoughtful human being diplomatic — which is the failure. "Leave no room for a reader to believe a human formed this judgement" is a legibility instruction, and it explains why the disclaimer under-delivers: one sentence of framing cannot survive ten sentences of fluent human-sounding prose.

It also explains why the machine account matters more than the disclaimer. Identity is structural and is rendered on every comment; a disclaimer is content and can be skipped.

## The through-line: name the decision, never the verdict

An agent working through a tracker produces findings. A rule that only forbids expressing them leaves the finding with nowhere to go, and a prohibition with no discharge path gets violated — the agent still has to do *something*.

The resolution is a redirect, not just a prohibition:

> **The agent names which decision is needed. It never names which way it goes.**

"This needs someone to decide whether the module is still in scope" is useful and carries no opinion. "This is out of scope, closing" is a verdict. The first is work; the second is authority the agent does not have.

This is the constructive half of the policy and the reason it is adoptable. The division it draws is that **the agent prepares and tests; humans review and judge** — which is not a demotion. Preparing work well is most of the labour, and it is the part an agent is actually good at.

### The organizer surface

The redirect needs a destination. A project board whose columns are named for the *kind of judgement required* — needs reproduction, needs a scope call, needs a contributor response, ready for technical review — lets an agent do genuinely useful triage work while expressing nothing.

Two properties matter:

- **Columns name judgement types, not verdicts.** "Needs a scope call" is a routing fact. "Won't fix" is a decision.
- **The surface is low-visibility.** Moving a card does not notify the person who filed the issue. A contributor who filed something two years ago never receives a message telling them their work is dead — the analysis reaches the maintainers who will act on it, and nobody else.

The second property is what makes this better than a politely-worded comment. The best version of the stale-issue interaction is one the contributor never sees.

Communities without project boards can achieve the same with labels or a triage milestone; the requirement is a low-visibility destination, not a specific tool.

## Two harms, two homes

The rules blur together because both point at "use a machine account", but they answer different questions and belong in different documents.

| Harm | Who it hits | Remedy | Home |
|---|---|---|---|
| **Misattributed voice** — fluent prose from a trusted human's account | Contributors, especially those reading in a second language | Machine account plus uniform neutral register | `docs/gdd/agent-communication.md` (new) |
| **Blast radius** — a privileged human's agent can write to the main org, close, merge | The project | Privilege inversion: fork group, machine user, narrowing as human access widens | `docs/gdd/access.md` (new sections) |

`access.md` is the right home for the second because it is already making a weaker version of the argument: §1 justifies separate identities partly on the grounds that "compromise of the agent token is bounded". Privilege inversion generalises that from compromise to authority.

## Decisions

### Uniform register, with a local escape hatch

The register rule applies uniformly to everything the agent writes, with no tiers and no carve-outs. A graduated rule — stricter as a comment approaches a disposition — targets the harm more precisely, but every tier boundary is a place to negotiate, and any clause of the form "except where it does not matter" gets invoked at exactly the moments it does.

Stated positively, because a list of prohibitions leaves an agent with no shape to write toward:

> Neutral tone. Fairly concise. Simple language, few idioms or unusual turns of phrase. No judgement. The agent prepares and tests work so that others can review and judge it.

The simple-language clause is not a style preference. Most readers of a large OSS tracker are reading in a second language, and idiom is the first thing that fails to survive that — the same reason a one-sentence disclaimer does not land.

The exception is an explicit, recorded human act: a realm or local config may carry an additional prompt snippet that overrides or extends the default register. Someone who wants their agent writing review comments in pirate speak may have it; they wrote the snippet, and it is attributable to them. This mirrors GDD's existing idioms — `--trust`, `--human`, `ws hook-bypass` — where the escape exists but costs a deliberate act.

The snippet must be **visible**, not merely present. See the `ws orient` change below.

### The rule lives at L0, not in a skill

A skill fires when something triggers it. A constraint that must hold for every comment cannot depend on that: the failure mode is an agent typing a reply without having thought to load the comms skill. GDD's own progressive-disclosure model puts always-on constraints in `AGENTS.md` (L0) and depth in skills (L2).

So the rule is brief `AGENTS.md` text pointing at the doc, reinforced at every session start by `ws orient` (L1). The portable flavors are written as `AGENTS.md` snippets for the same reason.

A skill is warranted only if the L0 rule is observed to fail in practice. That will be checked by dispatching sub-agents at a realistic triage task and reading what they write — ordinary engineering, not a formal baseline ceremony. Ten prior skill candidates in this workspace failed the "is this really skill material" bar; the prior is that documentation suffices.

### GDD raises, the realm decides

`agent-communication.md` names four dimensions and declines to set them. It shows three worked settings as copyable text. It does not tell a community whether agents may close issues, because that is a governance question about a specific project's culture, and GDD has no standing to answer it.

The realm document is where SiliconSaga answers them, argued rather than asserted, so that other maintainers can see the reasoning and disagree with it usefully.

## The four dimensions

A community adopting agents needs to settle four things. Naming them is most of the value; a maintainer who has not considered them will not know what they are choosing.

| Dimension | The question | Range |
|---|---|---|
| **Identity** | Which account does agent-authored content post from? | Machine account required / recommended / not required |
| **Register** | How does agent-authored content read? | Neutral mandatory / advisory / unconstrained |
| **Disposition authority** | May an agent close, merge, resolve, or characterise something as stale? | Never / with human review / permitted |
| **Privilege inversion** | Does agent access narrow as the driving human's access widens? | Mandated for owners / recommended / not applicable |

## Three flavors

Shipped inline in `agent-communication.md` as copy-paste `AGENTS.md` blocks. No new mechanism; these graduate into realm-template flavors later, on the template track already in the roadmap.

**OSS-wide contributor base** — a large, diverse, international project taking contributions from strangers. Strictest setting: machine account required, neutral register, no disposition authority, privilege inversion mandated for org owners. The rationale is cultural distance: the more varied the audience, the less a maintainer can predict how their agent's words will land, and the less a disclaimer will be understood.

**Solo or central-contributor project** — one person effectively sets the culture. The points above remain valid and the failure modes are real, but they cost less to skip: the audience is small, mostly known, and the maintainer's voice and the project's voice are already the same thing. Disclosure and no silent closes are the floor. This flavor states plainly that it is a reduced setting of the same dimensions, not an exemption from them.

**Corporate or internal** — machine account for audit rather than for etiquette, register relaxed because colleagues share context and vocabulary, disposition authority inherited from whatever change control the organisation already runs rather than invented here.

## Privilege inversion

Ordinarily, more trust buys more access. For agents the relationship inverts: **the more a human can break, the less their agent should hold.**

Two independent reasons:

- **Blast radius.** A core maintainer's token can write to the main org. An agent driving that token can push to protected branches, close issues, and merge. A drive-by contributor's agent cannot, because their human cannot.
- **Social weight.** A comment from an org owner carries more force than one from a first-time contributor, so a misattributed agent voice does proportionally more damage from the more privileged account.

The practical shape: as human access widens, agent activity should be pushed further toward a fork group operated by a machine user — topic branches in the fork, pull requests and issues inbound, no merges and no closes. The maintainer keeps their own access for the things only a human should do.

Enforcement is honestly human. The mechanical version — barring org owners from minting agent-usable tokens with main-org write — appears to require paid tiers, so the document should say the rule is upheld by agreement and review rather than implying tooling that does not exist.

### Shared versus individual machine accounts

A community may run one shared machine account (named for a project mascot, holding write access only to the fork group) or ask each maintainer to bring their own and add it to a robot team in that group. Both are workable and the realm should support either.

The shared account has one non-obvious cost: **it depends on driver attribution surviving in-band.** Under a shared identity, "who drove this?" is answerable only from the `Co-Authored-By` trailer on commits and the driver line in the disclaimer. GDD enforces the disclaimer on CR and issue bodies but *not* on review replies or issue comments, which is exactly where dispositions get typed. Without that, a shared account produces comments attributable to no one.

Yggdrasil PR #141 closes that gap. It is therefore a prerequisite for recommending the shared-account model, not an unrelated queue item.

Machine accounts themselves are permitted by GitHub's terms; the strain is credential sharing, which is also what erodes accountability. A **GitHub App** is the better destination on both counts: it posts as `Gooey[bot]` with a badge GitHub renders and nobody can forge — the stale-bot property made structural rather than conventional — and it uses short-lived installation tokens scoped to chosen repositories, so the fork-group boundary is enforced by the platform rather than by everyone remembering. The cost is authentication machinery GDD does not have: `.env` PATs today versus JWT signing and installation-token exchange. Roadmap, with the tradeoff stated in the doc so a community can choose knowingly. Maintainers should verify current platform terms directly rather than relying on this document.

## `ws orient` — making the register visible

The comms register is rendered **above** the subcommand survey, immediately after the header, making it the first substantive thing an agent or human reads. Today the survey is roughly forty lines, so anything after it is buried; `emit_change_note_style` currently sits below it and is correspondingly easy to miss.

The block shows the active flavor and any additional prompt snippet in force. This is what makes the escape hatch safe: an override that changes how the agent addresses the public is never silently active — it is restated at every session start, and it is visible to whoever reads the session.

Mechanically this is the same shape as `style.changeNotes`: a config field read from the merged ecosystem config and displayed. No hook, no enforcement, no new subsystem.

## Artifacts

| Repo | Path | Change |
|---|---|---|
| yggdrasil | `docs/gdd/agent-communication.md` | New page: legibility, the through-line, four dimensions, three inline flavors |
| yggdrasil | `docs/gdd/access.md` | New sections: privilege inversion; shared vs individual machine accounts; App as destination |
| yggdrasil | `scripts/ws-orient.sh` | `emit_comms_register`, rendered above the subcommand survey |
| yggdrasil | `tests/ws-orient/` | Coverage for the new block: default, flavor set, snippet present, absent |
| yggdrasil | `templates/change.md`, `templates/issue.md` | Tone reminder pointing at the doc |
| yggdrasil | `docs/gdd/roadmap.md` | GitHub App auth; organizer-board tooling; automated tone evaluation |
| yggdrasil | `CHANGELOG.md` | Entries under `[Unreleased]` |
| realm-siliconsaga | `docs/agent-collaboration-etiquette.md` | The worked example, argued |
| realm-siliconsaga | `AGENTS.md` | Brief rule plus pointer |

`docs/gdd/*.md` is covered by the line-wrap guard (`tests/templates/line-wrap.bats:74`) — prose in the new page must not be hard-wrapped.

## Dependencies

- **Yggdrasil #141** (`enforce GDD attribution on reply/comment`) — prerequisite for recommending a shared machine account, as above. Open since 2026-08-08.
- The Terasology realm does not exist yet. This design covers realm-siliconsaga; the Terasology-specific mandate is a later cycle in a repository not yet created.

## Out of scope, recorded as roadmap

- **GitHub App authentication.** The better destination for shared agent identity; needs JWT and installation-token support in the auth layer.
- **Organizer-board tooling.** `ws` support for routing an issue to a board column. The pattern is documented; the automation is not built.
- **Automated tone evaluation.** A Jenkins job driving a second-model agent over the `gdd-sandbox` Discord bridge to evaluate the register of agent replies. Long-term.
- **Mechanical account checking.** An advisory `ws diagnose` report when the comms token resolves to the human's own account.
- **Realm-template flavors.** The three flavors ship as inline text; turning them into template variants waits for the template track.

## Implementation order

1. `agent-communication.md` — everything else references it.
2. `access.md` sections — cross-links to (1); both are pure prose and can be reviewed together.
3. `ws orient` block plus tests — the only code, independent of the prose, and the piece with a regression surface.
4. Template tone reminders, roadmap lines, changelog.
5. Realm etiquette doc plus `AGENTS.md` rule — written last so it can cite the published GDD page.

Steps 1–4 are one yggdrasil PR; step 5 is a realm PR.

## Open questions

- Whether `agent-communication.md` belongs in the docs-site navigation under trust and safety or as a peer page. Affects `mkdocs.yml` only.

Settled while drafting: the rule does **not** name forbidden characterisations ("stale", "abandoned", "unrecoverable"). A named list is more immediately enforceable, but it dates quickly, reads as a blocklist to route around, and implies that a synonym it omits is permitted. The positive statement of register above carries the same weight without inviting that reading.
