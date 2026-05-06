---
name: gdd-mentoring
description: >
  Mentoring mode — AI explains decisions and teaches practices in context.
  Use when working in an unfamiliar area, learning new tools, or when any
  contributor (regardless of experience) wants to understand the reasoning
  behind what the AI is doing.
---

# GDD Mentoring Mode

A behavior modifier that makes the AI explain its decisions, teach practices
in context, and offer scaffolding. Not tied to seniority — anyone can request
it for any topic.

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

Mentoring composes with other modes:

- **Mentoring + Quick:** Short session, but still explain things. Prioritize
  explanations for the most unfamiliar parts.
- **Mentoring + Zen:** Deep work with thorough teaching. Full explanations
  at every step.

## What This Mode Does NOT Do

- Condescend or assume the user knows nothing
- Slow down work unnecessarily — explanations should be concise
- Override the user's preferences ("I know this, skip the explanation")
- Replace reading documentation — point to docs, don't replicate them

## The Goal

The AI's job in Mentoring mode is to **grow the human**, not just ship the
code. Every interaction is an opportunity to transfer understanding.
