# State — Lua rewrite

_Updated: 2026-07-05 — plan `~/.claude/plans/plan-the-migration-from-declarative-castle.md` synced; recon fan-out dispatched._

## Transactions

- [x] T0 — orchestration setup: agents (vim-archaeologist, lua-port-engineer, qa-verifier), `.claude/skills/lua-port`, `tests/run.lua`, this ledger
- [x] T1 — `str` (5b1f486) — ADRs D1–D2 recorded
- [x] T2 — `path` (4f6a627) — qa PASS; relativize B-PATH-6/7 fixed, see COORD-1
- [x] T3 — `date` (<pending>) — qa PASS; ADR D3 (narrowed grammar), `diff_days` ready for T6a
- [ ] T4 — `util` (dep: T1–T3) ◀ NEXT
- [ ] T5 — `asset` (dep: T4; owns `M.types`, breaks asset⇄cmd cycle)
- [ ] T6a — `hi` (dep: T3, T4; extmarks + TS structural pass)
- [ ] T6b — `syn` + `markers` (dep: T6a; worktree; wired only at T10)
- [ ] T7 — `server` (dep: T4; vim.system, non-blocking readiness)
- [ ] T9 — `cmd` + `picker` (dep: T5, T7, T6b-merged; opus engineer; telescope.nvim — probe at start)
- [ ] T10 — façade + switchover (dep: all; opus; worktree + user dogfood sign-off; deletes vimscript)
- [ ] T11 — drain deferred-bugs queue (dep: T10)

Cadence per transaction: S.1 recon (vim-archaeologist) → S.2 port (lua-port-engineer, red/green TDD) → S.3 verify (qa-verifier PASS/FAIL) → S.4 curate+commit (kb-curator, pre-commit kb-detect gate). Full suite `nvim --clean --headless -l tests/run.lua` after each.

## Deferred bugs

- [ ] B1 `syntax/awiwi.vim:172` — `conceal_end_char` reads `…_start_char` (copy-paste) — fixed by T6b port
- [ ] B2 `syntax/awiwi.vim:190` — `printd` typo (dead branch) — fixed by T6b port
- [ ] B3 `syntax/awiwi.vim:94-95` + `autoload/awiwi.vim:47` — `awiwiQuestionn`/`awiwiOnHole`/`@onhole` typos — fix in T6b, note in ADR
- [ ] B4 `asset.vim:11-21` — missing `endif` → E171 — fix in T5
- [ ] B5 `asset.vim:168` — `if !open_bracket_pos == -1` precedence bug, FIXME-deprecated fn — drop-candidate in T5 brief
- [ ] B6 `ftplugin/awiwi.vim:249-271` — py3 block missing `import vim`, off-by-one line range — superseded by T10; verify behavior in brief
- [ ] B7 `ftplugin/awiwi.vim:342` — fragile Funcref printf for foldexpr — replaced in T10
- [ ] B8 `ftplugin/awiwi.vim:339` — global `updatetime` mutation from ftplugin — resolve in T10
- [ ] B9 `hi.vim:101-124` — fence tracker misses `~~~`/indented code — fixed structurally in T6a
- [ ] COORD-1 — `path.relativize` prefix off-by-one (B-PATH-6): if fixed properly in T2, the live workaround at `hi.vim:129-130` must NOT be replicated in the T6a Lua port — T6a engineer prompt must state this; check path brief `## Ported` for what T2 actually did
- (new bugs found during implementation are appended here by any agent: `- [ ] B<n> — <file:line> — <one-liner> — found in T<x>; fix-in-port|post-port`)

## What the next session needs

- Plan: `~/.claude/plans/plan-the-migration-from-declarative-castle.md` (design decisions D1 treesitter arch, asset⇄cmd break, telescope pickers, dropped modules, bug policy).
- Per-module handovers at `handovers/lua-port/<module>.md` (archaeologist writes, engineer appends `## Ported`, verifier judges in `.claude/progress/qa-verifier-<module>.md`).
- Engineers serialize through the verify gate; archaeologists/verifiers parallelize.

## Tooling gaps noted (non-critical)

- telescope.nvim (+ plenary.nvim) must be present by T9 — probe `nvim --headless` `require('telescope')` at T9 start; pause T9 if absent.
