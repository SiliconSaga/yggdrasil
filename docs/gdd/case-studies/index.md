# Case Studies

GDD applied to real work — recent, concrete, and messier than a tutorial. Most entries here are short vignettes of an actual effort run through the methodology, with a note on what each demonstrates. Longer writeups of several of these are planned (see the [roadmap](../roadmap.md)); the vignettes stand on their own.

Two efforts are written up at length, and together they bracket the project's life so far:

- **[Reviewing a contributor's PR — GDD v1.0](terasology-contributor-review.md)** — a full session from the week of the 1.0 release: an outside contributor's bug fix reviewed, an engine root cause found underneath it, fixes proposed back, and an issue filed — conducted almost entirely from a phone, one-handed, around childcare. The clearest picture of what the finished system feels like in use.
- **[Early GDD — the first sessions](early-gdd.md)** — condensed transcripts and Thalamus files from GDD's first two sessions ever, back in March: dialogue and decisions as captured, technical detail stubbed. They predate most of today's system, so read them as origin material rather than current mechanics.

Reading one after the other is the fastest way to see how far the methodology travelled: the early sessions are GDD *being built*, the v1.0 study is GDD *being used* on someone else's codebase without the human having a desk.

---

## Reviewing a contributor's PR, from a phone

An outside contributor opened a bug fix on a Terasology module and asked for review. Over roughly three hours — spent mostly on childcare, with a toddler on lap and later from a phone — the agent brought a months-old workspace current, checked out the PR, verified the fix against the engine source, ran the game, and found that the bug the PR patched at module level had an engine-level root cause the PR never named. It turned out to be the same root cause as a *second*, apparently unrelated PR from the same contributor. Fixes went back to both branches as PRs from forks, one leftover finding became an issue, and the contributor merged.

Full writeup: **[Reviewing a contributor's PR — GDD v1.0](terasology-contributor-review.md)**.

**What it shows:** the found-time thesis at full stretch. Also the trust boundaries holding under pressure — the agent's token deliberately lacked push access to the upstream orgs, and the fork-and-PR path was the correct answer rather than an obstacle.

## Local political site for a non-technical owner

A local town-council candidate's campaign site was built by a third party as a compiled single-page app: the news articles had no working links, the contact and volunteer forms posted to a backend only the original developer controlled, and the owner couldn't change a word of it himself.

Over one GDD session the site was rebuilt fresh as a `gh-pages` component — the same Jekyll scaffold the [Getting Started](../../getting-started.md) tutorial uses. Content was recovered faithfully (with several look-and-feel passes reviewed live by a human), each news article became its own page by construction, and the captive forms were replaced with channels the candidate owns. The result deployed straight through the standard GDD loop — topic branch, PR, bot review, merge, live — and now carries per-page "edit on GitHub" links plus a maintainer guide, so the owner can keep it current by asking his own agent.

The maintenance loop has since been proven for real: the owner sent a Word document revising his entire policy platform, and the agent read it, applied the restructuring site-wide over several human-reviewed passes, and shipped it to production — a non-technical owner's document edits reaching his live site with no third-party developer in the path.

**What it shows:** the tutorial path is a real production path; GDD's independence story (your content, your repo, your agent) applies to people who don't consider themselves technical; and a fresh-machine dogfood run surfaces onboarding friction that flows straight back into the framework as fixes.

## Three workspaces, two days

Three parallel GDD workspaces, worked in alternation across two days: a community-feedback site for a local school district (QR codes, online surveys, results — ~5.5k LOC), a work skill helping newer engineers operate releases for services following a specific GitOps pattern (~3k LOC), and an arc on GDD itself (a hook rejecting opaque shell composition, plus related utility and safety work — ~3k LOC). Every piece went through design docs, bot review, and testing; the per-machine Thalamus files and arcs kept each workspace's state recoverable whenever attention rotated back to it.

**What it shows:** the methodology's answer to context-switching. Arcs and the Thalamus make it cheap to drop a thread mid-flight and pick it up days later — which is exactly the "found snippets of time" reality the framework was designed around.

## A greenfield platform component, end to end

A new Backstage-based developer portal component went from idea to merged across a handful of sessions on two machines: brainstorm → design and plan docs (reviewed as their own CRs) → BDD scenarios written before the code → a scaffolded app hardened test-first → live end-to-end validation against a homelab cluster → several rounds of CodeRabbit and Copilot review → merged with the component registered into the community realm. The cross-host arc (same slug in each machine's thalamus) helped visibility on which two systems were involved.

**What it shows:** the full GDD loop on something substantial — plans as reviewable artifacts, tests before implementation, bots plus human judgment on review, and multi-machine continuity through the thalami hoard.

## Maintainer attention, horizontally scaled

On a long-running open-source voxel game, a years-old dependency-injection overhaul PR — too large for any human to comfortably hold in their head — was merged as "good enough" and its review findings split into follow-up PRs processed over subsequent days with minimal overhead. GDD's review tooling (`ws review`, the triage skill) let one maintainer keep pace with a broad set of parallel PRs: processing bot findings, harvesting patterns, and filing issues in the gaps between other responsibilities.

**What it shows:** GDD isn't only contributor-side. It scales *maintainer* attention — the scarcest resource in most community projects.

## Two agents, one methodology

GDD's own multi-agent groundwork was built by two different agents in two workspaces: Claude Code on one machine and Codex on another, each committing through `ws commit` with per-session identity so every commit's attribution names the agent that actually made it. The Codex side dogfooded the review cycle on the shared PR and surfaced real cross-harness fixes (token-injected pushes that avoid OS credential prompts, review probes that distinguish "no such PR" from "network blocked") that merged back into the workspace.

**What it shows:** the `ws` CLI and the portable layers (AGENTS.md, `ws orient`, skills-as-markdown) are the agent-neutral core — the [roadmap](../roadmap.md)'s cross-harness track is an extension of something already exercised, not a hope.

---

Another good example is summarized in [this GDD PR comment](https://github.com/SiliconSaga/yggdrasil/pull/38#issuecomment-4313480965).

Honestly though: write-ups do not do the process justice when condensed, and cannot convey the sense of flow experienced. Sometimes the only real way is to just try it yourself. **[Get started here](../../getting-started.md)** — clone the workspace, turn on mentoring, and see what happens.
