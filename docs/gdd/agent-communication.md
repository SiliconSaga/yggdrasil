# Agent Communication

An agent that edits code is reviewed before its work lands. An agent that posts to a public tracker is not — the comment arrives the moment it is written, in front of people who did not ask for it.

That makes four decisions unavoidable for any project running agents against a shared repository. Most maintainers have not noticed they are decisions, because the defaults were never chosen; they were inherited from whatever the agent felt like writing. This page names them and shows three worked settings. **It does not pick one for you.** How your community should be spoken to is a governance question about your project's culture, and GDD has no standing to answer it.

## The mechanism: legibility, not tone

Consider why a stale-issue bot is inoffensive. It closes people's work — sometimes work they cared about — and almost nobody resents it. The usual explanation is that it is polite, or neutral, or specific. Those are true, but they are instruments. The property doing the work is that **no reader can mistake it for a person holding an opinion.**

An agent writing fluent prose from a maintainer's account fails that test no matter how factual the content is. The reader sees a name they recognise, attached to a considered-sounding judgement, and concludes that a person formed it. The better the prose, the more completely that reading takes hold — competence is what makes it convincing.

This is why "be neutral" is the wrong instruction. An agent can satisfy it while still sounding like a thoughtful human being diplomatic, which is exactly the failure. The instruction that works is *leave no room for a reader to believe a human formed this judgement*.

It also explains the ranking that follows: **identity matters more than disclosure.** A machine account is structural and renders on every comment. A disclaimer is content — one sentence, easily skimmed, and in an international project frequently read by someone whose English does not reach it. Everything after that sentence still reads like a person.

## What GDD already does, and where it stops

GDD ships two of the four pieces and should be honest about which:

- **Separate agent identities** are documented and practised — see [access.md](access.md), which covers running a distinct agent account with its own scoped token.
- **A disclaimer is mechanically enforced** on change-request bodies and issue bodies. `ws cr` and `ws issue` both refuse a bodyfile whose first line does not carry it, naming the human driving the agent.

Two gaps follow from that:

- **The disclaimer covers bodies, not replies.** `ws review reply` enforces nothing today. Review replies and issue comments are where dispositions actually get typed, which makes the least-protected surface the highest-exposure one.
- **Nothing constrains register anywhere.** No skill and no template says how agent-authored text should read.

## Name the decision, never the verdict

An agent working through a tracker produces findings. A rule that only forbids expressing them leaves the finding nowhere to go — and a prohibition with no discharge path gets violated, because the agent still has to do *something* with what it found.

So the useful form is a redirect rather than a ban:

> **The agent names which decision is needed. It never names which way it goes.**

"This needs someone to decide whether the module is still in scope" is useful and carries no opinion. "This is out of scope, closing" is a verdict. The first is work; the second is authority the agent does not have.

The division this draws is that **the agent prepares and tests; humans review and judge.** That is not a demotion. Preparing work well is most of the labour, and it is the part an agent is actually good at.

### The organizer surface

The redirect needs a destination. A project board whose columns are named for the *kind of judgement required* — needs reproduction, needs a scope call, needs a contributor response, ready for technical review — lets an agent do real triage while expressing nothing.

Two properties make it work:

- **Columns name judgement types, not verdicts.** "Needs a scope call" is a routing fact. "Won't fix" is a decision.
- **The surface is low-visibility.** Moving a card notifies nobody. Someone who filed an issue two years ago never receives a message telling them their work is dead.

The second is what makes this better than a carefully-worded comment. The best version of the stale-issue interaction is one the contributor never sees.

A board is not required. Labels or a triage milestone do the same job. What is required is somewhere to put a finding that does not page a human about it.

## The four dimensions

| Dimension | The question | Range |
|---|---|---|
| **Identity** | Which account does agent-authored content post from? | Machine account required / recommended / not required |
| **Register** | How does agent-authored content read? | Neutral mandatory / advisory / unconstrained |
| **Disposition authority** | May an agent close, merge, resolve, or characterise something as stale? | Never / with human review / permitted |
| **Privilege inversion** | Does agent access narrow as the driving human's access widens? | Mandated for owners / recommended / not applicable |

GDD does not set these. A three-person project and a thousand-contributor international one have genuinely different right answers, and the cost of choosing wrong is paid entirely by the project, not by the framework. The settings below are starting points to copy and edit, not a ladder to climb.

Privilege inversion is the least familiar of the four and is covered in [access.md](access.md#privilege-inversion): the short version is that agent access should *narrow* as the driving human's access widens, because both blast radius and social weight scale with it.

## Three flavors

Each block is written to be pasted into an `AGENTS.md` — a project's, or a realm's — and edited from there.

### OSS-wide contributor base

For a project taking contributions from strangers across many countries and first languages. The strictest setting, and the reasoning is cultural distance: the more varied the audience, the less a maintainer can predict how their agent's words will land, and the less a disclaimer written in English will be understood by the person it is meant to protect.

```markdown
## Agent-authored communication

Neutral tone. Fairly concise. Simple language, few idioms or unusual turns of phrase. No judgement. The agent prepares and tests work so that others can review and judge it.

- Post from a machine account. Never from a maintainer's personal account.
- Do not close, merge, resolve, or characterise the state of someone's contribution. Route it to the triage surface and name the decision that is needed.
- Say what was observed and what decision it requires. Do not say which way the decision should go.
```

### Solo or central-contributor project

For a project where one person effectively sets the culture. The audience is small and mostly known, the maintainer's voice and the project's voice are already the same thing, and the failure modes above cost less when they happen.

They are still real. This is a reduced setting of the same dimensions, not an exemption from them — worth revisiting the moment the contributor base widens.

```markdown
## Agent-authored communication

Neutral tone, concise, plain language, no judgement. Disclose that a comment is agent-authored.

Do not close or merge anything without the maintainer saying so for that specific issue or pull request.
```

### Corporate or internal

For work inside an organisation, where colleagues share vocabulary and context, and where governance already exists and should not be reinvented here.

```markdown
## Agent-authored communication

Post from a machine account so activity is attributable in audit.

Register is unconstrained internally; colleagues share the vocabulary and the context.

Closing, merging, and approving follow the organisation's existing change control. The agent does not create an exception to it.
```

## Making the choice visible

A decision nobody can see is one nobody can check. Two ecosystem-config fields record it:

```yaml
comms:
  flavor: oss-wide          # oss-wide | solo | corporate | none
  snippet: "…"              # optional; an additional instruction extending the register
```

`ws orient` renders both at the top of every session, above the subcommand survey, because the register governs everything the agent writes afterwards.

Leaving `comms.flavor` unset is not an error. Orient renders it as an open question pointing back at this page — which is the intended behaviour, since GDD's position is that the project decides and the prompt should keep appearing until it has.

`comms.snippet` is the escape hatch. Someone who wants their agent writing review comments in pirate speak may have it: they wrote the snippet, it is attributable to them, and orient restates it at every session start so it is never quietly in force. That is the same shape as GDD's other deliberate-act escapes — `--trust`, `--human`, `ws hook-bypass`.

## See also

- [Access](access.md) — agent identities, token scope, the fork-home pattern, and privilege inversion.
- [Trust and Safety](trust-and-safety.md) — the trust hierarchy these decisions sit inside.
- [Permissions](permissions.md) — the local half: what an agent may run, as distinct from what it may say.
