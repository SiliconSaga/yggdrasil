# A five-year-old disabled test — GDD on a deep bug

* **Date:** 2026-07-26 to 2026-07-30
* **Workspace:** yggdrasil on `Phoenix` — a laptop old enough to have been used for Terasology development years ago, freshly set up as a quick PR-review box
* **Stance / Role:** flow / developer
* **Subject:** [Terasology](https://github.com/MovingBlocks/Terasology), a 15-year-old open-source voxel game engine
* **Scale:** the session as a whole logged roughly 1,900 agent steps against about thirty human messages

## Overview

This one is not a good tutorial. It is a genuinely arcane bug — Java class loaders, two competing notions of "which module owns this class", and a build system with a decade of sediment in it — and a trimmed transcript would be unreadable. What it is good for is showing what the human-agent pairing does on a problem that neither side could have finished alone.

The short version: module integration tests were all failing with `VerifyException: Environment has no module for <SomeEvent>`. Four rounds of work across two days ended in a root cause nobody had named, a test that had been `@Disabled` for **five years and three months** finally implemented and passing, and a handful of adjacent improvements that were worth making once the area was understood.

## The ages involved

The most striking thing about this bug is how old all of its parts are.

| When | What |
|---|---|
| **April 2021** | A commit titled *"fix(ClasspathCompromisingModuleFactory): allow code from either class or jars of module directories"* adds jar handling to the class predicate — and, in the same commit, leaves behind `@Disabled("TODO: need a jar module alongside a classes directory")` on the test that would have verified it |
| **May 2022** | ModuleTestingEnvironment moves into `engine-tests` |
| **July 2024** | The Gestalt 8 upgrade introduces `UrlClassIndex.byClassLoader(aClass.getClassLoader())` — the defect that actually broke module tests |
| **July 2026** | Both fixed |

Two independent bugs, three years apart, stacked on each other. The 2021 one was latent — the class predicate compared *URLs*, and a jar has two valid spellings (`file:...jar` as a code source, `jar:file:...jar!/` as a classpath root), so a class served from a module's own jar never matched its own module. The disabled test was pointed straight at it. Had that test been live, the defect would have been visible for three years before Gestalt 8 layered a second one on top.

That is not a knock on the engineer who wrote it. Leaving an honest `TODO` beats deleting the test or faking it, and building the fixture it needed — a jar alongside a classes directory, loaded through an isolated class loader — is genuinely fiddly. It is a good illustration of how *the cost of a hard test fixture compounds*: the thing nobody had an afternoon for in 2021 was still unpaid in 2026, and by then it was hiding a second bug.

## What the agent got wrong

Worth recording plainly, because the corrections are the interesting part.

- **Grepped inside a `.jar` for a string constant** and concluded the jar was stale. Jars are compressed; the grep was meaningless.
- **Read results from a Gradle task that reported `UP-TO-DATE`** as though they were fresh, and announced that a fix hadn't worked. It needed `--rerun`.
- **Wrote a regex that captured only the first `cp=` entry** of a multi-entry debug dump, then reasoned for several rounds from the truncated output — concluding a path comparison was failing when the data had been correct all along.
- **Invented a mechanism to explain a non-observation.** When debug traces didn't appear, the agent confidently explained that logback was being reconfigured onto a file appender inside a `deleteOnExit` temp directory, so the logs were being written into the void. It was a tidy, plausible story. It was also false — checked at the human's prompting while preparing this write-up, the temp directories contain no logs at all, and engine `logger.error` output from the same phase was sitting in the test XML the whole time. The traces never printed for the boring reason: the code path never ran.

That last one nearly made it into a published document as an insight. It was caught because the human asked for it to be written up, and writing it up meant checking it.

## What the human contributed

None of the redirections came from more compute.

> *"I have a vaguely familiar memory about how the dependency chain can end up using an engine jar for some module dependencies even with the engine source present locally."*

> *"We also have or have had times where we mess with the build output directories — before the jar gets involved. Then may have the classes directory itself directly on the classpath."*

> *"We have confirmed what engine is running and from where, are we sure about Gestalt?"*

Half-remembered institutional knowledge from a decade of maintaining this codebase — none of it precise, none of it in any document, none of it recoverable by reading the source. The classes-directory-vs-jar memory reframed the search away from "is the fix being delivered?" and toward "what are these two things actually comparing?", which is the question that eventually found both defects. The provenance question forced verification of which gestalt was loaded, which closed off a whole branch of speculation.

The human also called the scope repeatedly: no global test sweeps on a workspace running the full Omega module set, `ws review` before pushing, tests done-or-skipped before a PR goes up.

## The root cause

Two mechanisms decide whether a class belongs to a module, and they have to agree:

| Mechanism | Question | Built by |
|---|---|---|
| Class index | "what classes exist here?" | `UrlClassIndex`, per classpath entry |
| Class predicate | "is this class mine?" | `Module.getClassPredicate()` |

`ModuleManager.loadAndConfigureEngineModule` built the engine module's index from the *app class loader*, so it claimed every `META-INF/subtypes` entry on the entire classpath — including every module jar. The predicate, correctly, refused to own those classes. Anything in that gap got discovered and then failed to be attributed.

It only surfaced in module-land because that is where module jars are on the classpath during `StateHeadlessSetup`, which legitimately runs `registerEvents` against a pre-game environment containing only `engine` and `unittest`. Nothing was wrong with paths, jars, Gradle, or which gestalt was loaded — all four of which were investigated at length.

## What came out of it

Beyond the fix itself, the area was understood well enough to be worth tidying:

- The 2021 `@Disabled` test implemented — builds the `build/classes` + `build/libs/foo.jar` layout, loads the class through an isolated `URLClassLoader`, asserts attribution. It fails against the original URL comparison.
- `VerifyException: Environment has no module for GetItemTooltip` now also reports where the class was loaded from and which modules the environment actually held. Those two facts cost most of a session to reconstruct by hand.
- A new **Module Attribution Failures** section in `Engine-Testing-Patterns.md`, including the trap that instrumenting the class predicate tells you nothing when the module isn't in the environment — which reads misleadingly like broken logging.
- `SimpleFarming`'s two integration tests fixed: they requested `unittest:empty`, a world generator that produces no facets at all, so the spawner could never place a player. Documented alongside.
- `BlockPicker` gained its first tests.

## The contrast that matters

The maintainer's own comparison, unprompted: years earlier and pre-GDD, another agent helped chase a broken-multiplayer problem in the large dependency-injection overhaul branch. That "worked" — and left a wake of partial efforts behind it, fixes layered on fixes without the underlying thing ever being named.

The difference here is not model capability. It is that the framework kept the work honest: scope held (no sweeping test runs on a 144-module workspace), findings were checked before they were written down, the fix was verified against 71 tests across four repos before anything was pushed, and the false explanation was caught rather than shipped. The agent supplied stamina across four rounds and two days of instrumentation. The human supplied three sentences of institutional memory and the judgment to ask whether the tidy story was true.

**What it shows:** on genuinely hard problems the pairing is asymmetric and both halves are load-bearing. The agent will not run out of patience; it will also confidently narrate a mechanism it has not verified. A maintainer's vague half-memory of something that went wrong years ago can be worth more than another thousand steps of search.
