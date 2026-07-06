# State — Lua rewrite

_Updated: 2026-07-05 — plan `~/.claude/plans/plan-the-migration-from-declarative-castle.md` synced; recon fan-out dispatched._

## Transactions

- [x] T0 — orchestration setup: agents (vim-archaeologist, lua-port-engineer, qa-verifier), `.claude/skills/lua-port`, `tests/run.lua`, this ledger
- [x] T1 — `str` (5b1f486) — ADRs D1–D2 recorded
- [x] T2 — `path` (4f6a627) — qa PASS; relativize B-PATH-6/7 fixed, see COORD-1
- [x] T3 — `date` (86a9f1a) — qa PASS; ADR D3 (narrowed grammar), `diff_days` ready for T6a
- [x] T4 — `util` (ba1ca75) — qa PASS; 12 live fns ported, 11 dropped; input is now callback-style (T5/T9 callers must adapt, pattern in brief)
- [x] T5 — `asset` (3a5ad89) — qa PASS; cycle broken (`M.types`), B4/B-new-1/B-new-2 fixed, B5 dropped; ADR D4
- [x] T6a — `hi` (<pending>) — qa PASS; B9/hi-1/hi-3 fixed, structural pass `hi.headings`/`hi.code_line_mask` ready for T6b
- [x] T6b — `syn` + `markers` (a2ec467) — qa PASS; built+headless-tested, NOT wired (T10 activates); B1/B2/B3/B10/B11-syn fixed, ADR D6; exposed test-hygiene bugs B11/B12 (fixed 9a9f8ab, c0fef93)
- [x] T7 — `server` (71f0195) — qa PASS; all 7 brief bugs fixed; launches FastAPI (ADR D5); `app:app` entrypoint placeholder must be pinned when server/ gains its app module
- [x] T9 — `cmd` + `picker` (<pending>) — qa PASS (354 green ×2, all 38 flows covered); ADR D7 picker seam (vim.ui.select default, telescope auto-upgrade — user decision); brief bugs B1–B7 handled; NOT wired (`:Awiwi` still vimscript)
- [ ] T10 — façade + switchover (dep: all; opus; worktree + user dogfood sign-off; deletes vimscript) ◀ NEXT — **user asked to start T10 in a fresh session.** T10 must: port awiwi.vim façade (939 ln; incl. `get_recipe_subpath` natively, B10) + ftplugin/ftdetect (py3 todo-cleanup → Lua, verify B6 off-by-one; drop B8 global updatetime mutation; B7 foldexpr), define `:Awiwi` via nvim_create_user_command → `require('awiwi.cmd').run`, fill every `M.deps` (inventories in cmd.md and asset.md `## Ported`), rewire `<F12>`→`:Awiwi tags`, teach `open_file` about `options.width` (B3 note in cmd.md), activate syn (`vim.treesitter.start` + attach, see syn.md `## Ported` activation notes), then DELETE `autoload/*.vim`, `syntax/awiwi.vim`, old ftplugin logic. Worktree + real-session dogfood + user sign-off gate the merge.
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
- [ ] B10 — `awiwi#get_recipe_subpath` is unreachable end-to-end in shipped vimscript (pre-existing `fn#spread` breakage in `awiwi#path#join`); hi_spec stubs it — T10 must port it natively (found in T6a)
- [x] B11 — `tests/asset_spec.lua` — `with_write_spy` "restored" the startup buffer that `:edit` had renamed in place, leaking a `2026-07-05`-dated asset buffer as current into later spec files; `open_asset_sink` spec silently depended on that leaked buffer for its `:write`. Masked while wall-clock date == 2026-07-05; broke the suite on rollover. Fixed inline by orchestrator (park on fresh scratch buffer + wipe asset buffers; swallow stubbed sink write) — found in T6b's full-suite run
- [x] B12 — `tests/server_spec.lua` — config.json spec leaked `g:awiwi_link_color`/`search_engine`/`screensaver` into later spec files, breaking syn's default-color assertions. Fixed inline by orchestrator (c0fef93) — found in T6b's full-suite run
- (new bugs found during implementation are appended here by any agent: `- [ ] B<n> — <file:line> — <one-liner> — found in T<x>; fix-in-port|post-port`)

## What the next session needs

- Plan: `~/.claude/plans/plan-the-migration-from-declarative-castle.md` (design decisions D1 treesitter arch, asset⇄cmd break, telescope pickers, dropped modules, bug policy).
- Per-module handovers at `handovers/lua-port/<module>.md` (archaeologist writes, engineer appends `## Ported`, verifier judges in `.claude/progress/qa-verifier-<module>.md`).
- Engineers serialize through the verify gate; archaeologists/verifiers parallelize.

## Tooling gaps noted (non-critical)

- telescope.nvim (+ plenary.nvim) must be present by T9 — probe `nvim --headless` `require('telescope')` at T9 start; pause T9 if absent.
