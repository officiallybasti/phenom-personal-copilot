# AGENTS.md — personal vault

Personal product-manager operating system. Cursor, Claude Code, and Codex read this file. It is a router.

## Before substantive work

`99_System/context/` — `00-me.md` through `05-glossary.md`. Markers: `[inferred]`, `[unconfirmed]`, `@team` / `@personal` / `@sensitive`. See `99_System/context/README.md`.

## Behaviour

`.cursor/rules/product-copilot.mdc` is the only always-on rule.

## Rules (`.cursor/rules/`)

| Rule | Use |
|---|---|
| `System/set-me-up.mdc` | First run: `set me up` |
| `Daily/morning-brief.mdc` | `morning brief` |
| `Weekly/weekly-review.mdc` | `plan my week` |
| `Meetings/meeting-sync.mdc` | Sync meetings |
| `Meetings/inbox-meetings.mdc` | 5-day inbox |
| `Meetings/1o1-prep.mdc`, `1o1-review.mdc` | 1:1s |
| `Coaching/strategic-advisor.mdc` | Hard feedback |
| `System/self-improvement.mdc` | Weekly system review |
| `System/improve.mdc` | Audit external AI advice |
| `System/context-promotion.mdc` | Push `@team` facts to Product Copilot |
| `Projects/new-project-structure.mdc` | New project folders |

Shared Phenom product skills live in **Phenom Product Copilot** — add that repo as a second Cursor root. RX CUSP / Jira / PRD: use Copilot, not this vault.

## Loops

Morning brief is interactive. Meeting sync is MCP + markdown. EOD is optional (`extras/eod/`). Health: `./99_System/scripts/healthcheck.sh`.

Friction → `99_System/improvement/friction-log.md` without asking.

## House rules

No secrets. Capture vendor only in `99_System/meetings/sources.json`. Keep context files short.
