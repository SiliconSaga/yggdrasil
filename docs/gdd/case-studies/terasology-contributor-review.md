# Reviewing a contributor's PR — GDD v1.0

* **Date:** 2026-07-25 (four days after the v1.0.0 tag)
* **Workspace:** yggdrasil on `Dionysus` — an aging Win10 desktop
* **Stance / Role:** flow / developer
* **Subject:** [Terasology](https://github.com/MovingBlocks/Terasology), a 15-year-old open-source voxel game engine
* **Contributor:** [@soloturn](https://github.com/soloturn), who reviewed this write-up and agreed to be named — thank you, soloturn, for the fixes and for being the first outside contributor to meet GDD in the wild!
* **Duration:** A few hours scattered across a day. Very little of it at a desk.

![Gooey's augmented workshop — Terasology's gelatinous-cube mascot, freshly fitted with cybernetic upgrades, running the Grand Terasology Improvement Engine alongside GDD's bee-bots](../../assets/images/GooeysAugmentedWorkshop.jpg)

## Overview

A contributor opened a fix for a crash in a Terasology world-generation module and asked for review. An ordinary open-source moment, and often where things stall: reviewing it properly means having the right repos checked out at the right revisions, building a large Java project, running the game, and holding a facet-border dependency graph in your head. That is a focused-evening task, and focused evenings are exactly what a parent of a 2-, 5-, and 7-year-old does not have.

This session ran instead across childcare — starting with a toddler on lap, continuing from a phone while making lunch and going outside, and reaching a desk alone for the first time near the end. The work that came out of it: both PRs reviewed, an engine-level root cause identified beneath the reported bug, a second apparently-unrelated PR revealed to share that root cause, a failing CI build diagnosed and fixed, a deterministic regression test built where a reproduction was thought impossible, two follow-up PRs merged or approved, and one deliberately-declined bot finding filed as an issue.

The point of this study is not that an agent wrote some Java. It is *where the human was standing* while it happened.

---

## Part 1: Picking up a months-old workspace

**Human:** I'm trying to review and test `Terasology/CoreWorlds` PR #48 — I already have terasology as a component in this GDD workspace, and it has enough modules to where we should be able to fetch + push the nested gits. Can you help make sure everything is up to date, then check out that PR's branch, double check that its description matches the code and is a likely fix, then run the game once to make sure we can start without errors.

*The agent ran `ws orient`, read the orientation skill, resolved the per-machine Thalamus, and set its commit identity — the standard startup. Then it looked at the workspace it had actually inherited.*

This is the part that would have been fatal before GDD. The Terasology component had been sitting untouched for months in the middle of a mega-review effort following the big dependency-injection PR merge — one of the oldest arcs in this machine's Thalamus. The state was genuinely messy:

- the engine sat on `test/salvage-mte-network-tests`, 32 commits ahead of a local `develop` that was itself 25 behind upstream
- 72 uncommitted lines in `docs/Engine-Testing-Patterns.md`
- six stale local branches, including two `-backup` ones
- `ModuleTestingEnvironment` parked on a local `review/post-di` branch that upstream had since absorbed
- and `ws status` itself was broken

> **The old reflex:** start a clean workspace rather than disturb all that. Then forget the old one. Then start a third later. GDD's answer is that the mess is *state*, not obstacle — the Thalamus says what the arcs were, and `ws status` says where every repo actually is.

**Agent:** `ws status`, `ws list`, and `ws pull` are all failing with `ERROR: Invalid component name in ecosystem config`. The cause is in your `ecosystem.local.yaml` — the key `DestinationSol.github.io` has uppercase letters, which the validator regex rejects.

*The agent proposed lowercasing the key, and — noticing the real repo lives under the `DestinationSol` org rather than `MovingBlocks` — added the correct `repo:` override rather than a guessed one. `ws status` came back, and resolved the already-cloned component correctly.*

Then it stashed the doc edits with a descriptive message, fast-forwarded `develop`, pulled all 13 module repos, and found `ModuleTestingEnvironment`'s local branch was content-identical to upstream (`git diff origin/develop review/post-di` empty) — so it moved that repo onto `develop` rather than leaving a superseded branch lying around.

**Agent:** Nothing anywhere was ahead of its remote, so there was nothing to push.

A months-dormant workspace made current in a few minutes, with a stashed change preserved and every deviation explained. No new workspace required.

---

## Part 2: Reading the fix against the engine

The PR clamped an out-of-bounds read in `DensityNoiseProvider`, and its description explained why. The agent's job was to check whether the description was actually true.

*It read the changed file, then the engine's `BaseFacet2D`, `Border3D`, and `WorldBuilder` to verify each claim independently.*

**Agent:** The diff does exactly what the body says, and the technical details check out. `BaseFacet2D.getWorldIndex` throws exactly the message shape the description attributes to the stack trace. The comment's axis note is right — `Border3D.expandTo2D` builds `new BlockArea(minX-sides, minZ-sides, …)`, so the `BlockArea`'s Y axis really is world Z. Clamping `z` against `minY()/maxY()` is correct, not a typo.

**But the diagnosis is incomplete.** The body says borders are "computed independently per-facet from whatever the largest declared requirement happens to be." The max part is right; the actual failure is sharper. `WorldBuilder.determineBorders` is a *single reverse pass* over a provider list whose order is not a guaranteed topological order — and border propagation is a fixed-point problem, so one pass over a heuristic order is not sound.

*It then went looking for what actually supplied the offending border, and found it in a module that was not even cloned locally — fetching `Caves`' `CaveToSurfaceProvider` from GitHub to read its annotations:*

```java
@Requires({
    @Facet(SeaLevelFacet.class),
    @Facet(value = DensityFacet.class, border = @FacetBorder(sides = 3, ...))
})
```

**Agent:** Nothing in CoreWorlds itself gives `DensityFacet` a `sides` border — `DensityNoiseProvider`'s own `@Updates` border is `top = 1` only. So `Caves` is the sole reason `densityRegion` outgrows the roughness facet, which matches "noticed when starting JoshariasSurvival" exactly.

It also flagged something the bots had missed entirely: the PR committed `src/test/resources/logback-test.xml`, a **build artifact**. The agent verified it was byte-identical to `templates/module.logback-test.xml`, which the engine's root build copies into every module, and confirmed all twelve sibling modules carried it *untracked*.

> **What CI cannot see.** #48 had eleven green Jenkins checks — Checkstyle, PMD, SpotBugs, unit and integration tests. None of them can say "this fix is at the wrong layer" or "this file is generated."

---

## Part 3: Running the game, and a scope decision

**Human:** *(from Discord, mid-childcare)* toddler actually already fighting so I'm getting up — but now that I got the agent started I can continue somewhat on my phone, at least until we need to run the game

*The agent built the PC facade and launched the game. It reached the main menu in 4.6 seconds and shut down cleanly. But it flagged the limitation rather than declaring victory:*

**Agent:** The smoke test confirms the game boots, but it **won't exercise this bug** — no Caves module means `DensityFacet` never gets the `sides = 3` border. Reproducing it needs JoshariasSurvival's ~25 dependencies. Your call — it's additive and reversible, but it does add a pile of clones.

The log had already agreed, unprompted:

```text
WARN o.t.e.w.g.i.WorldGeneratorManager - Could not resolve dependencies for module: JoshariasSurvival
```

**Human:** Game launches, but yes, let us recurse all the JS dependencies so we can test fully.

*`groovyw module recurse JoshariasSurvival` silently did nothing — it skips modules that already exist. The agent noticed the no-op instead of assuming success, listed the 21 missing dependencies explicitly, and pulled them. The workspace went from 13 modules to 55, including Caves.*

---

## Part 4: The reproduction problem, and a better answer

**Human:** This is an inconsistent crash depending on a randomly chosen seed to build the conditions needed to cause the problem. We might not have an easy time doing a repro then fix.

This is where the session turned. The agent had been building a headless harness to run the game repeatedly and count crashes — a reasonable but slow plan at ~130 seconds per iteration. The human's message reframed the problem, and the agent's analysis contradicted the premise:

**Agent:** Your intuition is close but the variable is different. It's not seed-dependent — it's **per-JVM-run**. `providerChains` is an `ArrayListMultimap`, backed by a `HashMap`, keyed by `Class` objects. `Class` doesn't override `hashCode()`, so it uses identity hash — which is re-randomized every JVM start. Same seed, different launches, different outcome.

*Crucially, the agent then abandoned its own experiment rather than defending it:*

**Agent:** Crash-roulette at ~130s per iteration is a poor use of time, and you already flagged the repro as hard. Better approach: a unit test on the invariant, run in fresh JVMs — seconds each, and it becomes the regression test both PRs lack.

> **The human said "we probably can't reproduce this."** The agent heard "stop trying to reproduce it the expensive way" and found the cheap deterministic path instead. Nobody specified that; it fell out of taking the constraint seriously.

The headless harness built along the way was still worth keeping, and is documented in the Thalamus as reusable: `--headless` plus `--homedir` pointed at a scratch directory, with a *partial* `config.cfg` selecting the gameplay module. (`Config.load()` merges the user file over `/default.cfg`, so no certificates or saves need copying out of the real home — and `StateHeadlessSetup` loads `savedGames.get(0)` if any save exists, which makes the isolated home mandatory rather than merely tidy.)

---

## Part 5: Two PRs, one root cause

**Human:** Can you also grab MovingBlocks/Terasology#5330 which has a fix in the same area and a single code review comment from CodeRabbit so we can also exercise `ws review`?

This is where the session paid off in a way nobody planned. PR #5330 — filed as an unrelated bug about loading a saved game — turned out to touch `determineProviderChains`, the **sibling method** to the `determineBorders` the agent had already fingered. And soloturn's own diagnosis there named the same mechanism: hash-ordered provider iteration.

**Agent:** #5330 and #48 are two symptoms of one disease, and there's a third unfixed instance. Neither PR says this.

*Running `ws review terasology 5330` surfaced CodeRabbit's finding, and the agent evaluated it on the merits rather than implementing it:*

**Agent:** Valid observation, wrong PR. The non-filtering is **pre-existing** — the original single loop didn't filter either. And the proposed diff would convert a silent degradation into a hard `IllegalStateException` at world load — the exact failure class #5330 exists to remove.

Then, reading the existing test file before checking anything else, it predicted a failure it had not yet observed:

**Agent:** `WorldBuilderTest.testIncorrectProviderOrder` asserts `IllegalStateException` for exactly the ordering #5330 makes legal. #5330 changed one file and never touched the test.

*Checked: `Tests / Unit Tests` — **fail**. Confirmed locally. The test was encoding the bug as the contract.*

The root cause turned out to be a one-method contract violation. `updatePriority`'s **own Javadoc** already specified the correct behaviour — "if provider *requires* facet, it's `PRIORITY_REQUIRES`" — while the implementation short-circuited on `updates != null` and returned the update priority for every facet, including require-only ones. That understates how much of a chain a requirement depends on, so `CaveToSurfaceProvider` could be ordered ahead of `DensityNoiseProvider`, and the `sides = 3` border arrived too late to propagate.

The fix was making the code do what its documentation said.

---

## Part 6: Verification, and the trust boundary

The agent inverted the bug-enshrining test, added separate coverage for a genuinely missing provider, fixed `updatePriority`, and wrote a regression test mirroring the CoreWorlds/Caves topology with synthetic facets.

Then it did the step that matters: **it verified the regression test could fail.**

*Stashed the fix. Ran the test. `testRequiredFacetCoversUpdatedFacet() FAILED`. Restored the fix. Passed.* A regression test that never fails without the fix is decoration.

It split the work into two commits, each verified green independently, so a maintainer could take only the CI fix if the root-cause change felt like scope creep.

Then the push failed:

```console
remote: Permission to MovingBlocks/Terasology.git denied to agent-refr.
```

**Human:** *(on Discord)* Correction I will end up agent pushing to its forks because wisely I did not give my agent push access to the moving blocks orgs 😉

> **The boundary held at exactly the right moment.** A rushed maintainer, on a phone, had said "go ahead and push to both branches" — and the token simply could not. `agent-refr` has `push: false` but `triage: true`: enough to open issues and post PR comments, not enough to write to an org repo. The correct path — fork, push there, open a PR *into the contributor's branch* — is more etiquette-preserving anyway, because it hands soloturn the additions instead of rewriting his PR under him.

One legitimate bypass was needed and taken deliberately. Terasology keeps ~55 module repos as plain nested clones, which `ws` cannot address as targets — `ws commit coreworlds` fails outright. Rather than route around the hook silently, the agent used the sanctioned escape hatch with a stated reason:

```bash
ws hook-bypass git-commit --reason "CoreWorlds is a nested module git under \
  components/terasology/modules/ which ws commit cannot resolve as a target"
```

Session-scoped, swept by `ws clean`, and logged. The gap it exposed went into the Thalamus as a design note for a future `ws` capability.

---

## Part 7: Circling back

**Human:** *(from the phone)* Coincidentally I saw a Copilot review comment on my phone that seemed valid.

*Copilot had flagged that the new test compared region **sizes** while claiming **coverage** — a larger-but-offset region would pass. The agent verified the objection was real, tightened the assertion to check `minX`/`maxX`/`minZ`/`maxZ` containment, and then re-ran the falsification: still failed without the fix. It pushed, and resolved the thread without a reply, per this workspace's convention that Copilot gets bare resolves.*

The declined CodeRabbit finding became [issue #5332](https://github.com/MovingBlocks/Terasology/issues/5332) — framed as a *decision* (fail loudly vs. degrade deliberately) rather than a patch, because the mechanical fix has a real trade-off. The issue notes that `WorldBuilderTest` currently has no test exercising `scalable = true` at all.

Then the contributor merged everything, and the session ended where it began — in Discord, with the same person who had opened the PR that morning.

---

## Outputs

All four pull requests merged the same day, within about six hours of the contributor's first message.

| Artifact | Outcome |
|---|---|
| [CoreWorlds #48](https://github.com/Terasology/CoreWorlds/pull/48) | **Merged** — the contributor's original fix, reviewed and verified correct |
| [CoreWorlds #49](https://github.com/Terasology/CoreWorlds/pull/49) | **Merged** into #48 — dropped the generated `logback-test.xml`, rewrote the comment to name the engine defect |
| [Terasology #5330](https://github.com/MovingBlocks/Terasology/pull/5330) | **Merged** to `develop` — the contributor's engine fix, its red CI diagnosed and repaired |
| [Terasology #5331](https://github.com/MovingBlocks/Terasology/pull/5331) | **Merged** into #5330 — fixes the failing test, plus the `updatePriority` root cause and a deterministic regression test |
| [Terasology #5332](https://github.com/MovingBlocks/Terasology/issues/5332) | Filed — the deliberately-declined CodeRabbit finding, framed as a decision rather than a patch |

The engine root cause found partway through a phone-driven review is now on Terasology's `develop`.

Plus, in the workspace itself: a repaired `ecosystem.local.yaml`, 42 newly cloned module repos, a reusable headless world-gen harness recipe, and three Thalamus notes — two of them `ws` gaps this session exposed (nested git repos as targets; replying to out-of-diff bot findings).

## The Discord thread

Running in parallel the whole time, lightly tidied. This is the texture the transcript above cannot show.

> **Cervator** — 10:50
> I'm looking at the CoreWorlds PR now 😅 Admittedly with a toddler on my lap, so I am one-handedly driving my agent
>
> **soloturn** — 10:51
> @Cervator another pull request, when trying to load Joshariassurvival it could not — with this merge request it is able to load the stored game again: MovingBlocks/Terasology#5330
>
> **Cervator** — 10:51
> nice catch, will try next (current computer time uncertain)
> (toddler actually already fighting so I'm getting up — but now that I got the agent started I can continue somewhat on my phone, at least until we need to run the game)
>
> **Lampe2020** — 11:03
> I'mma read that in more detail tomorrow, but from the quick, superficial scroll-through it looks like it's sensible. And don't get me wrong, I sometimes use AI as well, but the thing I hate the most about AI is that tech CEOs try to frame it as this revolutionary thing that will replace human workforce, instead of admitting that it's just a tool. And a tool can't work on its own, it needs to be used by a human.
>
> **Cervator** — 11:04
> I can agree with all that, yes. Thus the balancing act
>
> **soloturn** — 11:22
> Is this a new toddler or the old one?
>
> **Cervator** — 11:24
> Probably the old one, but my sense of time has completely broken as of some time back 😁 They all just had their birthdays over the last 3-11 days, so now they're 2, 5, and 7. Youngest on lap, back at PC for a bit. Been just approving and looking at things in my workspace, no second prompt needed yet, it has your code
>
> I remember the small but meaningfully repeated toil of just defining remotes to get the right code, sometimes across a bunch of repos all at once. Now I just pasted in a link and told my agent to help me out. I'll write this up later, think it'll be a good example
>
> I started this out of the messy setup I was using to do dependency injection PR merge post-PRs for further review and tweaks, so there were piles of dirty stuff, branches, etc for it to tidy up.
>
> **Cervator** — 11:43
> Pulling in the engine fix PR and letting it continue, it might be finding another tweak or two that could help. And I need to go get the toddler lunch while this runs, will keep supervising via Claude RC from my phone 🙂
>
> **Cervator** — 11:55
> Oh clever. GDD knows to use Test Driven Development if possible, but Claude realized that won't work with the full 3D game launching. So other than individual tests it has made a headless server config file so it can at least run the game that way to validate a full game launch with the right modules active
>
> I told it none of that. Just that we can't easily reproduce the crash with a known seed that causes it
>
> **Cervator** — 12:25
> This is a perfect case — thank you for bringing in @soloturn! I had my agent review both and found an intriguing deeper bug. Small tweaks being added to both branches for your counter-review if able, hope that's ok!
>
> **Cervator** — 12:51
> Correction I will end up agent pushing to its forks because wisely I did not give my agent push access to the moving blocks orgs 😉
>
> **Cervator** — 13:02
> Okay @soloturn you should have two PRs adding to yours you can approve and merge when you like, if they make sense. I have done this with zero focused time, more on my phone than by PC with my toddler on hand. That's the magic of GDD 🙂
>
> Normally I'd wait till I do get focus time to finish up, but you're the consumer this time so if you find it good enough go ahead!
>
> **soloturn** — 13:28
> Ha I now read the Guardian Driven Development docs. Need to dive deeper into setting it up
>
> **Cervator** — 13:41
> Just finished reading the PRs fully from my phone. I saw it start talking about hash values differing between JVM launches, how wild is that? Yet it seems to have also proven it via tests, and it does make sense
>
> I'm going to slowly start running an agent or two when able on our projects, just like this — and this in fact is the start. I wonder how many obscure old bugs that have caused us grief for years that now have their days numbered 🙂
>
> **Cervator** — 14:06
> Alright, I have made it to my PC, alone, for the first time today! The two older kids may show up any minute, but I can sometimes work through that still focused.
>
> Coincidentally I saw a Copilot review comment on my phone that seemed valid. Ran the agent through my ws review process and it fixed it (with extra care locally to reproduce without the test coverage being complete enough), pushed that fix, and resolved the Copilot comment
>
> So now I can do a last bit of looking in just a few minutes, while before it would have taken hours of spare time to get to this point — which would have meant days or weeks in calendar time 😬
>
> **soloturn** — 14:21
> i am very impressed haha ... it sounds fine and i'll merge if i have the right. then will try to run gdd.
>
> **soloturn** — 14:23
> gdd needs a "caveman clause" to make it less verbose and easier to understand 🙂
>
> **Cervator** — 14:24
> It has that! Ask the agent to enable "mentoring mode". There are also tutorials
>
> **soloturn** — 14:45
> can i put your agent as reviewer to a pull request, and some GDD would be triggered?
>
> **Cervator** — 14:48
> Not yet. GDD always runs from a locally prepared workspace triggered manually. However one of my active projects puts a GDD workspace into a Docker container, opening the possibility of cloud-type environments, including spinning up one based on some trigger

## Key takeaways

- **The workspace was the point.** A months-dormant Terasology checkout mid-way through a dependency-injection review effort would previously have prompted a fresh workspace — and then a forgotten one, and then a third. The Thalamus held the arcs, `ws status` held the repo states, and the session grafted onto the mess instead of fleeing it. That avoided toil is invisible in the diff and is arguably the largest single win here.
- **Found time is real time.** Toddler on lap → phone while cooking → phone outdoors → fifteen focused minutes at a desk. The output was a root-cause fix in a 15-year-old engine, with tests. The claim GDD has always made about snippets of attention got its hardest test yet.
- **The agent argued with the bots, and with itself.** It declined one CodeRabbit finding with reasoning and filed it as an issue; it accepted a Copilot finding after verifying the objection was real; and it abandoned its own expensive experiment when a cheaper, stronger one appeared.
- **Falsification, not just green checks.** Every claim of "this fixes it" was backed by stashing the fix and watching the test fail. Twice — including after tightening the assertion, because a stricter test that no longer catches the original bug is worse than the loose one.
- **Guardrails earn their keep when the human is distracted.** The push denial landed *after* a phone-typed "go ahead and push to both branches." The human was wrong for a moment; the boundary was not.
- **One bypass, used correctly.** Nested module repos are a genuine `ws` blind spot. The bypass was explicit, reasoned, session-scoped, and turned into a design note rather than a habit.
- **CI and bots found none of the three most valuable findings** — the shared root cause across two PRs, the test that enshrined the bug, and the committed build artifact.

---

*The v1.0.0 release this session followed by four days is described in the [roadmap](../roadmap.md) and the [features tour](../features.md). For GDD's origins, see [Early GDD](early-gdd.md) — same loop, eighteen weeks and a great deal of scaffolding earlier.*
