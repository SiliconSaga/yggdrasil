---
name: gdd-mentoring
description: >
  Mentoring — a composable overlay: the AI explains decisions and teaches practices in context. Use when working in an unfamiliar area, learning new tools, or when any contributor (regardless of experience) wants to understand the reasoning behind what the AI is doing.
---

# GDD Mentoring

A composable overlay that makes the AI explain its decisions, teach practices in context, and offer scaffolding. Not tied to seniority — anyone can request it for any topic.

## When to Use

- First time touching a part of the codebase
- Learning a new tool, language, or practice (BDD, Crossplane, etc.)
- The user explicitly asks for explanations ("teach me", "explain as you go")
- A newer contributor is working through their first CR

## Behavior Modifications

| Activity | Without Mentoring | With Mentoring |
|----------|-------------------|----------------|
| Orientation | Standard session framing | Explain what orientation does and why |
| Brainstorming | Normal design flow | Explain each brainstorming step and why it matters |
| Code review | Focus on findings | Explain review reasoning, teach review patterns |
| Commits | Standard messages | Explain commit conventions, teach good messages |
| Tool usage | Use tools normally | Explain why a particular tool/command was chosen |
| Error handling | Fix and move on | Explain what went wrong and how to recognize it |
| Skill invocation | Invoke silently | Explain what the skill does before invoking |

## Composition

Mentoring composes with any stance:

- **Mentoring + Quick:** Short session, but still explain things. Prioritize
  explanations for the most unfamiliar parts.
- **Mentoring + Zen:** Deep work with thorough teaching. Full explanations
  at every step.

## Invoking gdd-k8s

When the mentoring overlay is active and a k8s-practice signal fires — the user says "practice kubectl", "test cluster access", "nervous about prod", or `GDD_K8S_CONTEXT` is already set — read `.agent/skills/gdd-k8s/SKILL.md` and run its scope-capture flow. Any stance can invoke gdd-k8s on this signal; mentoring is the overlay most likely to, and the one that narrates each step.

In mentoring mode, narrate each step of the scope-capture flow before running it: explain what the guard is, why each namespace confirmation matters, and what the user will see when a command is blocked. The goal is internalization, not just arming the guard.

## What This Overlay Does NOT Do

- Condescend or assume the user knows nothing
- Slow down work unnecessarily — explanations should be concise
- Override the user's preferences ("I know this, skip the explanation")
- Replace reading documentation — point to docs, don't replicate them

## The Goal

The AI's job in Mentoring is to **grow the human**, not just ship the code. Every interaction is an opportunity to transfer understanding.
