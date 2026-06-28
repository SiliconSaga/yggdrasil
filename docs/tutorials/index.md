# Tutorials

Hands-on, chaptered walkthroughs of individual GDD features. Each one is followable solo — just read and run the commands — or alongside your AI agent. Turn on the mentoring overlay for your first pass through any of them and the agent explains each command and decision as you go rather than just running it.

These differ from the [Getting Started](../getting-started/index.md) walkthrough, which onboards you to the workspace as a whole. A tutorial here goes deep on one feature.

## Available tutorials

| Tutorial | What you practice | Prerequisite |
|---|---|---|
| [Guarded Kubernetes](guarded-kubernetes.md) | Practising `kubectl` safely behind the `ws k8s` training-wheels guard — armed scopes, the allow/block verdicts, and the agent + human paths. | A Kubernetes cluster context you can write to (a throwaway local cluster is fine). |

## A note on shapes

Most tutorials in this section are **docs pages** like the ones above — read-and-run walkthroughs of a feature.

One tutorial is a **scaffold** instead: the `gh-pages` component template. Running `ws component init gh-pages <name>` drops a tutorial *instance* into `components/<name>/` whose own `README.md` is a chaptered walkthrough — from scaffold to a live GitHub Pages site through the full edit → PR → bot-review → merge loop, in about 15 minutes. It lives with the template rather than here because the thing you learn on is a real repo you create. See [Getting Started → Recommended first scaffold](../getting-started/index.md#recommended-first-scaffold).
