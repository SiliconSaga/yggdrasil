# Tutorials

Hands-on, chaptered walkthroughs of individual GDD features. Each one is followable solo — just read and run the commands — or alongside your AI agent. Turn on the mentoring overlay for your first pass through any of them and the agent explains each command and decision as you go rather than just running it.

These differ from the [Getting Started](../getting-started/index.md) walkthrough, which onboards you to the workspace as a whole. A tutorial here goes deep on one feature.

## Available tutorials

| Tutorial | Shape | What you practice | Prerequisite |
|---|---|---|---|
| [Guarded Kubernetes](guarded-kubernetes.md) | docs page | `kubectl` safely behind the `ws k8s` guard — armed scopes, the allow/block verdicts, and the agent + human paths. | A Kubernetes cluster context you can write to (a throwaway local cluster is fine). |
| [GitHub Pages site](https://github.com/SiliconSaga/yggdrasil/blob/main/templates/components/gh-pages/README.md) | scaffold | The full GDD loop on a tiny live target — scaffold, deploy, edit, open a PR, watch the bots review, merge. | A GitHub account (a public repo gives free Pages). |

## A note on shapes

Most tutorials here are **docs pages** like Guarded Kubernetes — read-and-run walkthroughs of a feature.

The **GitHub Pages** one is a **scaffold** instead: run `ws component init gh-pages <name>` and the walkthrough is the generated `components/<name>/README.md` (the table links to the template version). It lives with its template rather than as a docs page because the thing you learn on is a real repo you create and deploy. See [Getting Started → Recommended first scaffold](../getting-started/index.md#recommended-first-scaffold) for where it fits in onboarding.

## Three ways a newcomer meets GDD

These are easy to conflate — they're different things:

1. **Scaffold a template** — `ws component init gh-pages <name>` creates a brand-new repo you own and deploy. The fastest way to feel the full loop on a tiny live target. Templates are starting points, not standalone courses; each is a scaffold, not a guided lesson.
2. **Explore a suggested realm project** — the active realm may list existing live projects in its `ecosystem.yaml`; `ws clone <project>` (or `ws clone --all`) pulls them **as-is** to read or contribute to. These are real codebases, not tutorials — reach for one only if its domain interests you, not as a first "learn GDD" step.
3. **Feature walkthroughs** — the docs-page tutorials in the table above. Note Guarded Kubernetes is **process, not code**, and assumes a cluster you can write to — valuable, but not a first stop for a total newcomer.

The `realm-template` starter's own README currently points first-timers at option 2 (`ws clone --all`); for most newcomers option 1 (the `gh-pages` scaffold) is the gentler first loop.
