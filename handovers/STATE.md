# State — Lua rewrite

_Updated: 2026-07-06 — dogfood round 2: nav + syntax confirmed fixed; link-conceal finding → T10.2 landed (suite 458 green, 14 files) on branch `worktree-lua-port-t10` (worktree `.claude/worktrees/lua-port-t10`). **Merge to master gated on user link-conceal re-check + sign-off** — see "next session needs"._

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
- [x] T9 — `cmd` + `picker` (d2159c7) — qa PASS (354 green ×2, all 38 flows covered); ADR D7 picker seam (vim.ui.select default, telescope auto-upgrade — user decision); brief bugs B1–B7 handled; NOT wired (`:Awiwi` still vimscript)
- [x] T10 — façade + switchover (474fb50 on branch `worktree-lua-port-t10`) — qa PASS; suite 454 green (14 files); brief `handovers/lua-port/init.md` (84-item contract, 100 new specs); façade `lua/awiwi/init.lua` + `ftplugin/awiwi.lua` + `ftdetect/awiwi.lua`; all 16 tracked vimscript files deleted; B6/B7/B8/B10 + B-INIT-1..5 + cmd-B3 (`options.width`) fixed; syn activated; `<F12>`→`:Awiwi tags`; ADRs D8–D11. **NOT MERGED — user dogfood + sign-off pending** (checklist in init.md `## Dogfood checklist`)
- [x] T10.1 — dogfood round-1 fixes (85df511) — user findings `handovers/T10-dog-food.md`; two root causes fixed inline (orchestrator, red/green, 3 new specs, suite 457 green): (1) `date.deps.journal_dates` seam wired to `get_all_journal_files` — `:Awiwi journal previous|next`/`gn`/`gp` threw AwiwiDateError because nothing ever injected `options.files`; (2) `vim.treesitter.start(buf, "markdown")` in ftplugin — port had deleted `syntax/awiwi.vim` without starting any base markdown layer ("fences/markers don't work"). "redacted only after set ft" NOT reproduced headlessly — re-check in dogfood round 2 (details in init.md `## Dogfood round 1`)
- [x] T10.2 — dogfood round-2 fix (<pending>) — round 2 confirmed gn/gp/ge + syntax fixed; one new finding: links rendered raw instead of concealed `▶name (…)`. Conceal extmarks were correct but nothing set `'conceallevel'` (legacy relied on user's global config, syn.md Port notes). Fix: window-local `conceallevel=2` in ftplugin (user-sanctioned improvement); spec + headless screen-scrape verify (`▶pancakes …`); suite 458 green (details in init.md `## Dogfood round 2`)
- [ ] T11 — drain deferred-bugs queue (dep: T10 merge)

Cadence per transaction: S.1 recon (vim-archaeologist) → S.2 port (lua-port-engineer, red/green TDD) → S.3 verify (qa-verifier PASS/FAIL) → S.4 curate+commit (kb-curator, pre-commit kb-detect gate). Full suite `nvim --clean --headless -l tests/run.lua` after each.

## Deferred bugs

- [x] B1 `syntax/awiwi.vim:172` — `conceal_end_char` reads `…_start_char` (copy-paste) — fixed by T6b port
- [x] B2 `syntax/awiwi.vim:190` — `printd` typo (dead branch) — fixed by T6b port
- [x] B3 `syntax/awiwi.vim:94-95` + `autoload/awiwi.vim:47` — `awiwiQuestionn`/`awiwiOnHole`/`@onhole` typos — fix in T6b, note in ADR
- [x] B4 `asset.vim:11-21` — missing `endif` → E171 — fix in T5
- [x] B5 `asset.vim:168` — `if !open_bracket_pos == -1` precedence bug, FIXME-deprecated fn — drop-candidate in T5 brief
- [x] B6 `ftplugin/awiwi.vim:249-271` — py3 block missing `import vim`, off-by-one line range — superseded by T10; verify behavior in brief
- [x] B7 `ftplugin/awiwi.vim:342` — fragile Funcref printf for foldexpr — replaced in T10
- [x] B8 `ftplugin/awiwi.vim:339` — global `updatetime` mutation from ftplugin — resolve in T10
- [x] B9 `hi.vim:101-124` — fence tracker misses `~~~`/indented code — fixed structurally in T6a
- [ ] COORD-1 — `path.relativize` prefix off-by-one (B-PATH-6): if fixed properly in T2, the live workaround at `hi.vim:129-130` must NOT be replicated in the T6a Lua port — T6a engineer prompt must state this; check path brief `## Ported` for what T2 actually did
- [x] B10 — `awiwi#get_recipe_subpath` is unreachable end-to-end in shipped vimscript (pre-existing `fn#spread` breakage in `awiwi#path#join`); hi_spec stubs it — T10 must port it natively (found in T6a)
- [x] B11 — `tests/asset_spec.lua` — `with_write_spy` "restored" the startup buffer that `:edit` had renamed in place, leaking a `2026-07-05`-dated asset buffer as current into later spec files; `open_asset_sink` spec silently depended on that leaked buffer for its `:write`. Masked while wall-clock date == 2026-07-05; broke the suite on rollover. Fixed inline by orchestrator (park on fresh scratch buffer + wipe asset buffers; swallow stubbed sink write) — found in T6b's full-suite run
- [x] B12 — `tests/server_spec.lua` — config.json spec leaked `g:awiwi_link_color`/`search_engine`/`screensaver` into later spec files, breaking syn's default-color assertions. Fixed inline by orchestrator (c0fef93) — found in T6b's full-suite run
- [x] B-INIT-1..5 — five façade bugs found by T10 recon (see `handovers/lua-port/init.md` bug ledger) — fixed in T10 port; B-INIT-6 (`g:awiwi_history_length` no-op) documented as ADR D10, deliberately inert
- [ ] PENDING-ADR — `split_screen` `<C-x>/<C-v>` inverted guard: shipped behavior preserved verbatim in `lua/awiwi/init.lua` (recorded as D11); needs a human decision on intended behavior, then fix in T11
- (new bugs found during implementation are appended here by any agent: `- [ ] B<n> — <file:line> — <one-liner> — found in T<x>; fix-in-port|post-port`)

## What the next session needs

- **T10 merge gate (USER), round 3 after T10.2:** re-check link conceal renders as `▶name (…)` (T10.2), then sign off. Round-2 status: gn/gp/ge PASS, syntax rendering PASS. Still never user-tested: clipboard paste (xclip missing on dogfood machine), real fzf/telescope pickers, airline/entitlement, drawio, `:Awiwi serve`. Findings: `handovers/T10-dog-food.md`; fixes: init.md `## Dogfood round 1/2`. Original instructions: dogfood the plugin from worktree `.claude/worktrees/lua-port-t10` (branch `worktree-lua-port-t10`) in a real session — checklist: `handovers/lua-port/init.md` `## Dogfood checklist`. On sign-off: merge to master, fill commit hash into init.md `## Ported`, archive `handovers/lua-port/*.md` → `handovers/done/`, remove worktree. Untracked `autoload/awiwi/ask.vim`/`bookmarks.vim` drafts in the main checkout are untouched (dropped modules per skill) — user decides their fate.
- After merge: T11 drains the queue above (COORD-1 reconciliation + PENDING-ADR decision).
- Plan: `~/.claude/plans/plan-the-migration-from-declarative-castle.md` (design decisions D1 treesitter arch, asset⇄cmd break, telescope pickers, dropped modules, bug policy).
- Per-module handovers at `handovers/lua-port/<module>.md` (archaeologist writes, engineer appends `## Ported`, verifier judges in `.claude/progress/qa-verifier-<module>.md`).
- Engineers serialize through the verify gate; archaeologists/verifiers parallelize.

## Tooling gaps noted (non-critical)

- ~~telescope.nvim by T9~~ — resolved: probe found no telescope/plenary/fzf; user chose vim.ui.select default + telescope auto-upgrade (ADR D7). Telescope path is fake-injected in specs only — sanity-check with real telescope during T10 dogfooding if available.
- `server/` has no FastAPI app module yet — `server.lua`'s `uv run uvicorn app:app` entrypoint is a documented placeholder (ADR D5); pin it when the app lands.
- Per-module briefs stay in `handovers/lua-port/` until T10 consumes their `## Ported` inventories; archive to `handovers/done/` at close.
