# State — Lua rewrite

_Updated: 2026-07-05 — tooling scaffolded (agents, lua-port skill, test runner); no module ported yet._

## Transactions

- [x] T0 — orchestration setup: agents (vim-archaeologist, lua-port-engineer, qa-verifier), `.claude/skills/lua-port`, `tests/run.lua`, this ledger
- [ ] T1 — port `str` ◀ NEXT (leaf-first order in `.claude/skills/lua-port/SKILL.md`)

## What the next session needs

- Run `/flow:plan` for the next module(s); conventions to adopt are listed in `CLAUDE.md` → "Lua rewrite flow".
- Per-module handovers live at `handovers/lua-port/<module>.md` (archaeologist writes, engineer appends `## Ported`, verifier judges).

## Tooling gaps noted (non-critical)

- none
