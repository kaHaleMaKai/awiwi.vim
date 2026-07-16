# State — Lua rewrite

_Updated: 2026-07-15 (36th run) **T29–T34 stakeholder-feedback round 1 CLOSED** (plan
`tasks/feedback-round-1-plan.md`, source `tasks/feedback.md`): T29 reactive router
query/hash + search UX (`67b3a76`), T30 TOC-rail overflow fix + collapsible rail
(`425ca1e`), T31 index branding "awīwī /awi:ˈi:/" + inline drawio in doc bodies
(`caf3ab3`), T32 dash-bullet checkboxes + RENDERED redaction reveal — ADR **D24**
(`a67a3ae`), T33 asset URL alias mappings (`c246fcc`), T34 close-out (fresh dist per
ADR D20, ledger, handovers archived). Backend 263 green, frontend 140 green,
svelte-check 0. Two feedback items were interpreted (garbled source, flagged to user):
"quick link right of home" → `home | today` crumb linking to today's journal;
"drawio link … sub text" → inline-rendered diagram with the link as figcaption.
Env note: `/home` hit 100% disk — `uv cache prune` freed ~1.7G; `~/.cache/podman`
(4.4G) is the next reclaim candidate, left for the user._

_Previous (35th run) — **T28 visual-parity flow CLOSED** (plan
`the-new-web-version-graceful-sparrow.md`): T28.0 mdrender tag/mention root-cause fix
(`ec907a4`, backend 237 green), T28.1 committed visual fixture + pairs manifest (`e55e2bb`),
T28.2 dep-free CDP screenshot harness `server/tests/visual/shoot.mjs` (`22494ed`), T28.3 two
comparator→fixer iterations (13 haiku comparators/round, sonnet fixer batches `7526d75` +
`7ea8010`; frontend 123 green), **T28.4 kb close-out complete**: .gitignore fix (`2c9d5b5`,
fresh dist committed), final independent sweep of 8 batch-2 pages (all PARITY), harness note
added to architecture.md §Toolchain, handovers/visual-parity/ archived to handovers/done/.
**13/13 pages verified PARITY within documented exclusions.** Escalated (not fixed): drawio
"Open in draw.io" button (security), mockup factual errors (MIME claim, stray back-link),
G6 fixture-limited chip-state residual (won't-fix, documented)._

_Previous (34th run) — **T28 visual parity SPA↔mockups, stopped-by-user after batch 2
(plan `the-new-web-version-graceful-sparrow.md`)**: T28.0 mdrender tag/mention root-cause fix
(`ec907a4`, backend 237 green), T28.1 committed visual fixture + pairs manifest (`e55e2bb`),
T28.2 dep-free CDP screenshot harness `server/tests/visual/shoot.mjs` (`22494ed`), T28.3 two
comparator→fixer iterations (13 haiku comparators/round, sonnet fixer batches `7526d75` +
`7ea8010`; frontend 123 green) — 5 pages haiku-verified PARITY, 8 pages fixed+fixer-verified.
**Global handover: `handovers/visual-parity/T28.3-parity-loop.md` — read its "Open items"
first**: (1) CRITICAL root `.gitignore:17 dist/` conflicts with ADR D20, committed dist is still
the pre-fix T26 bundle → decide ignore-fix, rebuild, commit dist; (2) final independent sweep of
the 8 batch-2 pages; (3) T28.4 kb close-out (architecture.md harness note, archive handovers);
(4) G6 fixture-limited chip-state residual. Escalated, not fixed: drawio "Open in draw.io"
button (security), mockup factual errors (MIME claim, stray back-link)._

_Previous (33rd run) — **Server re-imagining phase CLOSED (plan
`re-imagne-the-server-completely-wild-parnas.md`, T22–T27 complete)**: Noir-Deco mockups
(T22 d5d62f8, 4 feedback rounds) + full SPA backend (JSON API, redaction embed, live sync,
T23–T24) + Svelte 5 SPA frontend (T25 99535a0/6e582e7/0639b1d/0919430, 110 tests) + cutover
(T26 25cc8fe, SPA live, legacy templates dropped) + cleanup (T27 2f31c9e, legacy stack deleted)
+ knowledge-base close-out (S27.2, this run): `docs/architecture.md` §Server fully rewritten
(module map, API route table, WS protocol, SPA layout, build policy), ADRs D18–D23 recorded
(SPA-over-JSON, client-side Shiki+Drawio, WS live sync + single-process, committed-dist,
no-sanitization localhost-only, theme), `docs/INDEX.md` ADR high-water D17→D23, `handovers/STATE.md`
header + transaction ledger (T26–T27 entries + completion marks), `handovers/server-rewrite/*.md`
archived to `handovers/done/server-rewrite/`. All code complete. Backend 229 green (T27 −5
deleted tests), frontend 110 green, kb-detect passes. **Next: user manual verification** checklist
(`:Awiwi serve` + dogfood: checkbox live-flip across tabs, save→re-render, search modes, copy
buttons, image lightbox, draw.io viewer) per plan §Verification._

_Previous (31st run) — **T18–T20 inline images complete (plan
`implement-inline-image-rendering-robust-pnueli.md`)**: kitty inline-image rendering via
snacks.nvim as optional auto-upgrade dependency (ADR D17, same seam pattern as D7 telescope).
T18 extracted `asset.resolve_image_link` + tightened `open_link`'s image branch (garbage paths now
error instead of spawning the opener); T19 built `lua/awiwi/img.lua` (enabled/resolve/attach,
resolver chained never clobbered, fake-backend specs) + verified headless against a real snacks
clone; T20 wired one attach line into ftplugin (red/green spec) + ADR D17 + docs. Suite 484 green.
**Remaining: T21 manual kitty dogfood** (checklist in "What the next session needs")._

_Previous (30th run) — **T17.1 dogfood fix**: user's first live `:Awiwi serve` crashed at
lifespan — PluginConfig rejected the real config.json (`screensaver` is a *name* string like
"cinnamon", not bool; markers were pipe-joined strings). Root cause twofold: B14, a T10 façade
regression (`init.lua` rebind dropped legacy `join = false`, so the plugin wrote joined strings
instead of arrays), fixed red/green; and server-side, `screensaver: str | bool` + `PluginConfig.load`
now truly permissive (unparseable config → warning + defaults, boot never fails). Plugin 462 green,
server 118 green, boot verified against the user's exact failing config. Re-dogfood pending._

_Previous (29th run) — **T13–T17 server rewrite complete, FastAPI viewer live**: kb-curator
closed out knowledge base end-to-end. Architecture.md §Server rewritten comprehensive (module map,
route table, config protocol, auth/localhost, markdown pipeline). ADRs D13–D15 recorded (python-markdown
+local extensions, localhost-only auth+AWIWI_ALLOW_REMOTE escape hatch, AWIWI_HOME env+entrypoint
pinned). Entrypoint `awiwi.app:app` pinned in lua/awiwi/server.lua with env threading; plugin suite
461 green (3 new specs). Only user-side remains: `:Awiwi serve` dogfood + real-world testing._

_Previous (28th run) — **dogfood verified, ledger reconciled**: user confirmed the live plugin in
their real config. Resolved: `<C-v>` clipboard image paste works (X11+xclip) — the earlier "no mapping"
was a `--clean` artifact (plugin not on rtp, `g:awiwi_home` unset → `ftdetect/awiwi.lua:6-8` bails →
ft stays markdown; in-config ft is `awiwi` and the map at `ftplugin/awiwi.lua:100` fires);
airline/entitlement and telescope pickers work; drawio export and `:Awiwi serve` deferred by user;
settings.json allowlist already committed. No transactions remain._

_Previous (27th run) — **T12 CLOSED, flow complete**: user resolved PENDING-ADR D11 by directing
"correct the inverted split_screen mapping". Fixed red/green: spec flipped to intended behavior
(`:Awiwi` cmdlines get no split flag) → red → `lua/awiwi/init.lua` guard `== 1` → `== 0` → 458 green.
ADR D12 recorded (supersedes D11's preservation clause); architecture.md mappings section documents
the corrected guard. No transactions remain._

_Previous (26th run) — **T11 UNBLOCKED and CLOSED**: user added the nvim allowlist entries to `.claude/settings.json`; test gate alive again (baseline 458 green). B13 landed via its scripted red/green plan (spec de-stubbed → E117 red → lazy `require("awiwi")` in `hi.lua` → 458 green), committed `a7edcdc` through the kb-detect gate (architecture.md hi row updated by kb-curator). That was the last vimscript interop in `lua/`. **No transactional task remains — only user-side items** (PENDING-ADR D11 decision, dogfood gaps, drafts fate), so `task.done` touched per the outer-loop protocol._

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
- [x] T10 — façade + switchover (474fb50 on branch `worktree-lua-port-t10`) — qa PASS; suite 454 green (14 files); brief `handovers/done/lua-port/init.md` (84-item contract, 100 new specs); façade `lua/awiwi/init.lua` + `ftplugin/awiwi.lua` + `ftdetect/awiwi.lua`; all 16 tracked vimscript files deleted; B6/B7/B8/B10 + B-INIT-1..5 + cmd-B3 (`options.width`) fixed; syn activated; `<F12>`→`:Awiwi tags`; ADRs D8–D11. **MERGED to master 2026-07-06** after 3-round user dogfood (fixes: T10.1, T10.2)
- [x] T10.1 — dogfood round-1 fixes (85df511) — user findings `handovers/done/T10-dog-food.md`; two root causes fixed inline (orchestrator, red/green, 3 new specs, suite 457 green): (1) `date.deps.journal_dates` seam wired to `get_all_journal_files` — `:Awiwi journal previous|next`/`gn`/`gp` threw AwiwiDateError because nothing ever injected `options.files`; (2) `vim.treesitter.start(buf, "markdown")` in ftplugin — port had deleted `syntax/awiwi.vim` without starting any base markdown layer ("fences/markers don't work"). "redacted only after set ft" NOT reproduced headlessly — re-check in dogfood round 2 (details in init.md `## Dogfood round 1`)
- [x] T10.2 — dogfood round-2 fix (2878c5f) — round 2 confirmed gn/gp/ge + syntax fixed; one new finding: links rendered raw instead of concealed `▶name (…)`. Conceal extmarks were correct but nothing set `'conceallevel'` (legacy relied on user's global config, syn.md Port notes). Fix: window-local `conceallevel=2` in ftplugin (user-sanctioned improvement); spec + headless screen-scrape verify (`▶pancakes …`); suite 458 green (details in init.md `## Dogfood round 2`)
- [x] T11 — drain deferred-bugs queue (a7edcdc) — COORD-1 closed (clean), B13 fixed red/green (last vimscript interop in `lua/` removed), suite 458 green. PENDING-ADR (D11) carried out of T11 as a user-decision item — the queue holds nothing else automatable
- [x] T12 — split_screen guard corrected (2026-07-07) — user resolved D11 ("correct the inverted mapping"); red/green: spec flipped to intended behavior → red → `init.lua` guard `== 1`→`== 0` → 458 green; ADR D12 recorded, architecture.md mappings updated
- [x] T13 — server scaffold + config (2026-07-07, S13.1 sonnet) — `server/src/awiwi/` package with Settings (pydantic-settings, env `AWIWI_HOME`), PluginConfig (permissive JSON); 7 tests; pyproject.toml cleaned (deps added, dead Django/mypy blocks removed); gates all green (pytest/ruff/basedpyright); handover at `handovers/server-rewrite/T13-scaffold-config.md`; commit hash bdc9afb
- [x] T14 — server domain leaf modules (2026-07-07, S14.1 sonnet) — `content.py` (parse_date aliases, journal nav, breadcrumbs, traversal guard, dir listing), `checkbox.py` (hash_line contract, toggle_checkbox with domain errors), `search.py` (rg args, search output parse, hit sorting); 61 tests green (30/14/17 new); gates all green (pytest/ruff/basedpyright); 6 legacy crash-bugs fixed (see handover); handover at `handovers/server-rewrite/T14-leaf-modules.md`; commit b63dc1b
- [x] T15 — server markdown pipeline (2026-07-07, S15.1 sonnet) — `mdrender.py` (RenderedDoc, render_markdown, render_file w/ Pygments + vim-modeline sniff); python-markdown kept with trimmed extensions + tiny local mermaid/strikethrough replacing dropped third-party pkgs; legacy pre-filters (redaction, checkbox via hash_line, @tag/@@mention, ordinal sup); `;match(N);` non-ASCII hack deleted (unicode round-trip test); 27 new tests, 88 total green, gates all green; handover at `handovers/server-rewrite/T15-mdrender.md`; commit 3da3072
- [x] T16 — server app assembly (2026-07-07, S16.1 opus + S16.2 orchestrator) — app.py/templating.py/routers/, templates+static copied pruned (141MB→4.5MB), acceptance-first TDD, 27 acceptance tests, 115 total green, uvicorn boot smoke OK; allow_remote escape hatch added (AWIWI_ALLOW_REMOTE); entrypoint `awiwi.app:app` ready for T17 pinning; handover handovers/server-rewrite/T16-app-assembly.md; commit 01dc9d7
- [x] T17 — plugin integration + kb close-out (2026-07-07, S17.1 sonnet + S17.2 kb-curator) — `lua/awiwi/server.lua` entrypoint pinned `awiwi.app:app` + env `AWIWI_HOME=vim.g.awiwi_home` threaded via `vim.system`, 3 new specs → 461 green; docs: `architecture.md` §Server rewritten (module map, route table, config protocol, auth localhost-only + AWIWI_ALLOW_REMOTE, markdown pipeline), ADRs D13–D15 recorded (python-markdown+local extensions, auth dropped+localhost-only, AWIWI_HOME env+entrypoint pin), `docs/INDEX.md` ADR high-water mark D15, `handovers/STATE.md` ledger T16 hash filled + T17 entry + header updated; `kb-detect` passes; server rewrite T13–T17 complete, FastAPI viewer live, user-side only remaining (`:Awiwi serve` dogfood); handover `handovers/server-rewrite/T17-entrypoint-pin.md`; commit 4cc3b97.
- [x] T17.1 — dogfood config fix (2026-07-07, orchestrator inline, red/green both sides) — B14: `init.lua` get_markers rebind wraps `{ join = false }` so config.json carries marker arrays again (new façade-wiring spec, plugin 462 green); server: `screensaver: str | bool`, `PluginConfig.load` catches ValidationError/OSError → warning + defaults (3 new tests, server 118 green); booted against the user's exact failing config.json → startup complete + 200; handover `handovers/server-rewrite/T17.1-dogfood-config.md`; commit d1f5d3a

- [x] T18 — shared image-path resolver (d7e2ce5, 2026-07-14) — S18.1 `asset.resolve_image_link(target) -> string|nil` (nil for relative/URL/non-date-dir; `deps.get_asset_subpath` seam; 5 specs); S18.2 `init.lua` image branch delegates to it, unresolvable targets `err()` instead of spawning the opener on a garbage path (1 spec). Suite 472 green. Handovers `handovers/inline-images/S18.{1,2}.md`
- [x] T19 — `awiwi.img` module (fa03247, 2026-07-14) — optional inline images via snacks.nvim (ADR D17): `enabled()` honors `g:awiwi_inline_images`, `attach(buf)` probes snacks through `deps.require` seam, registers markdown treesitter lang for awiwi filetypes (load-bearing), chains `snacks.image.config.resolve` onto `asset.resolve_image_link`; 11 fake-backend specs, suite 483 green; S19.2 headless probe against real snacks clone all green (attach true, chain resolves, `require("snacks.image") == Snacks.image` confirmed). Handovers `handovers/inline-images/S19.{1,2}.md`
- [x] T20 — wiring + ADR + docs (ea17d51, 2026-07-14) — one `require("awiwi.img").attach(buf)` in `ftplugin/awiwi.lua` after `syn.attach` (outside awiwiSynRepaint augroup, by design); red/green ftplugin spec (backend probed, no-snacks stays silent); ADR D17 recorded, `docs/INDEX.md` ADR high-water D15→D17 (was stale), architecture.md img row + `g:awiwi_inline_images` global. Suite 484 green. qa-verifier gate S20.2 over T18–T20
- [x] T22–T24 — server re-imagining phase 1 (see header paragraph: mockups d5d62f8…04159ea, /api layer 1690275/e309150/1a24c25/f3bb1aa, live sync 18bccbe); mockup checkpoint passed (user feedback rounds 1–4 resolved, user continued the flow 2026-07-14)
- [x] T25 — Svelte 5 SPA frontend (2026-07-14, S25.1 sonnet 99535a0 / S25.2 opus 6e582e7 / S25.3 sonnet 0639b1d / S25.4 sonnet 0919430) — `server/frontend/`: vite@7 svelte-ts scaffold (base `/_app/`, dev proxy :5823 ws), Noir-Deco app.css from tokens.css + fonts, runes router + theme (localStorage `awiwi.theme`, pre-mount), typed api.ts (S25.2 fixed scaffold bug line_nr→line_no per frozen contract); enhance pipeline (Shiki dual-theme CSS-var singleton, copy buttons, tableExport md/csv/html + CopyMenu, checkbox PATCH 409-revert+refetch, lazy mermaid data-mermaid-src, media→/api/raw + Lightbox, redaction click-reveal), lang.ts/format.ts pinned to server behavior; route views (DirPage week banding, JournalPage sticky-rail TOC + nav, TodoPage, DocPage kind-dispatch → TextFileView/ImageView/DrawioView/DownloadCard, NotFound, real Breadcrumbs; drawio viewer-static.min.js pinned v30.3.11 in public/vendor/); SearchPage (scope chips, regex toggle, URLSearchParams state) + ws.svelte.ts (backoff+jitter reconnect, reopen re-subscribe+refetch, mtime_ns dedupe incl. own-checkbox suppression, scroll-preserving re-render) + ConnectionDot live states. Frontend gates green each subtask (final: vitest 110, svelte-check 0 errors, build OK); backend untouched, 231 green re-verified at close. Handovers `handovers/server-rewrite/T25.{1-4}-*.md`
- [x] T26 — cutover: SPA live, legacy template routes dropped (2026-07-14, S26.1 sonnet 25cc8fe) — `routers/redirects.py` (new, legacy 302 redirects + SPA catch-all), `app.py` mount `/_app` StaticFiles + router registration, `frontend/dist/` (committed, git add -f, linguist-generated -diff), test_acceptance.py rewritten (30 tests, page-HTML→JSON payloads, redirects asserted, SPA fallback, ETag/304, theme-cookie tests dropped, checkbox relpath PATCH, redaction embed). Backend gates green (234 passed, ruff clean, basedpyright 0). Architecture.md §Server route table + router bullets minimal update only (full rewrite deferred to S27.2). Handover `handovers/server-rewrite/T26-cutover.md`
- [x] T27 — delete legacy template stack + server.old (2026-07-14, S27.1 sonnet 2f31c9e) — deleted: `routers/{pages,assets,actions}.py`, `templates/`, `static/`, `templating.py`, `render_file`+Pygments from `mdrender.py`, `test_mdrender.py::TestRenderFile` (4 tests), entire `server.old/` tree; deps: removed jinja2/pygments/python-multipart; docs: minimal honest updates in architecture.md (components table, module-map bullets, T27 note pointer) + glossary.md viewer/server entry. Backend gates green (229 passed, 234−5 deleted tests). Handover `handovers/server-rewrite/T27.1-cleanup.md`
- [x] S27.2 — knowledge base close-out (2026-07-14, kb-curator) — docs/architecture.md §Server fully rewritten (comprehensive module map, API route table, WS protocol, SPA layout, build/dev workflow); docs/decisions.md ADRs D18–D23 appended (SPA-over-JSON frontend D18, client-side Shiki+drawio D18/D22, WS live sync+single-process D19, committed-dist policy D20, Noir-Deco theme D21, no-sanitization localhost-only D23); docs/INDEX.md ADR high-water D17→D23; handovers/STATE.md header + T26–T27 entries + transaction ledger + completion; handovers/server-rewrite/*.md→handovers/done/server-rewrite/; kb-detect passes, docs-only commit T27.2. PHASE CLOSED.

- [x] T28.0 — mdrender tag/mention root-cause fix (2026-07-15, sonnet ec907a4) — whole-token `@@mention` spans, new `#tag` emission, class contract `awiwi-mention`/`awiwi-tag` (app.css selectors aligned), fence-aware substitution fixed latent `@bug`-in-code-fence bug; backend 229→237 green; handover `handovers/visual-parity/T28.0-tag-mention.md`
- [x] T28.1 — visual-parity fixture + pairs manifest (2026-07-15, sonnet e55e2bb) — committed notes tree `server/tests/visual/fixture/home/` reproducing mockup sample content; `pairs.json` 12 pairs + recipe-audit; per-page comparator exclusion lists; handover `handovers/visual-parity/T28.1-fixture.md`
- [x] T28.2 — CDP screenshot harness (2026-07-15, sonnet 22494ed) — dep-free `server/tests/visual/shoot.mjs` (chromium headless CDP, full-page byte-stability capture, light-theme injection, ImageMagick RMSE + band slices); handover `handovers/visual-parity/T28.2-harness.md`
- [x] T28.3 — comparison+fix loop (2026-07-15, 13× haiku comparators/round + sonnet fixer; 7526d75 batch 1 F1–F21, 7ea8010 batch 2 G1–G11) — 5 pages haiku-verified PARITY (todo, 404, asset-drawio, download, recipe-audit), 8 pages fixed+fixer-verified (journal ×2, dir ×2, search ×2, asset-image, asset-text); frontend 123 green; **all open items 1–4 resolved in T28.4**
- [x] T29 — search stack (2026-07-15, 67b3a76) — RouterState reactive search/hash + hash-scroll (S29.1); SearchBar keystroke-clobber fixed, SearchPage reactive urlState + on-page search field (S29.2-3); frontend 130 green at commit
- [x] T30 — TOC rail (2026-07-15, 425ca1e) — minmax(0,1fr) overflow fix, collapsible rail (aria-expanded), <700px default-collapsed (S30.1)
- [x] T31 — index branding + inline drawio (2026-07-15, caf3ab3) — root h1 "awīwī /awi:ˈi:/" + italic subtext, home|today crumb (S31.1); enhance/drawio.ts inline viewer + figcaption link, shared drawioViewer.ts singleton (S31.2); frontend 140 green
- [x] T32 — dash checkboxes + rendered redaction (2026-07-15, a67a3ae) — `- [ ]` bullets render/toggle (S32.1); section-redaction embeds carry rendered HTML, ADR D24, inline form unchanged (S32.2); backend 263 green
- [x] T33 — asset URL aliases (2026-07-15, c246fcc) — normalize_asset_path() in /api/doc + /api/raw, new dashed-segment 302 (S33.1)
- [x] T34 — feedback-r1 close-out (2026-07-15) — fresh dist (ADR D20), full suites green, handovers archived handovers/done/feedback-r1/
- [x] T28.4 — kb close-out (2026-07-15, kb-curator) — .gitignore fix + fresh dist committed (`2c9d5b5`), final independent sweep all-PARITY (13/13 pages), harness note added to `docs/architecture.md` §Toolchain, `handovers/visual-parity/` archived to `handovers/done/visual-parity/`; kb-detect passes
- [x] **checkbox GFM widening + fence-state desync fix** (inline fix, 2026-07-16) — two complementary fixes for user's observation that checkboxes rendered as literal `[x]` boxes in lists:
  - **GFM regex widening** (follow-up to T32): widened regex to full GFM task-list semantics (`*/-/+` bullets, ordered items `1./1)`, 1+ spaces, `[x]/[X]/ [ ]` states, bare boxes; blockquote-nested forms remain unsupported per spec). Hashes for legacy single-space forms unchanged; toggle writes lowercase `x`. Reverses T32's deliberate `+ [ ]` exclusion (S32.1). 
  - **Fence-state desync root cause** (hidden latent bug): `_filter_body`'s naive fence toggle (`in_fence = not in_fence`, backtick-only, column-0 regex) diverged from python-markdown's FencedCodeExtension (accepts `~~~` fences, requires exact-match closure: same char+run-length, column 0, trailing spaces only). Divergence left the filter stuck "in fence" for indented closers, mixed fence styles, or unclosed fences, silently skipping checkbox/tag/mention injection on visible text. Fixed: `_FENCE_DELIM_RE` now `^(`{3,}|~{3,})`, `in_fence` → `fence_close` (exact delimiter string), scan-ahead verifies an exact closer exists before entering state, state clears only on exact match. Known accepted divergence: scan-ahead examines raw lines, so a closer inside a redacted section can still diverge (corner never in sync before either). 5 new tests in `TestFenceStateTracking`.
  - Backend suite 275 green, ruff clean, basedpyright 0; frontend 140 green; end-to-end headless Chromium verification all checkbox forms render/toggle correctly, even after fence desync triggers. Knowledge base updated: `docs/architecture.md` §Markdown rendering semantics expanded to document exact fence-state tracking (FencedCodeExtension alignment, delimiter matching rules, known divergence). No new ADR needed (this is a bug-fix alignment with existing D13 python-markdown commitment).

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
- [x] COORD-1 — `path.relativize` prefix off-by-one (B-PATH-6): if fixed properly in T2, the live workaround at `hi.vim:129-130` must NOT be replicated in the T6a Lua port — T6a engineer prompt must state this; check path brief `## Ported` for what T2 actually did — **reconciled in T11 (2026-07-06): correct on both sides.** path.md `## Ported` confirms `relativize` fixed (common-prefix counter, `.` for identical paths); `hi.lua:286-291` calls `path.relativize` directly, no `[1:]` workaround (hi.md:478 records it). But the reconciliation found B13 below.
- [x] B13 (fixed a7edcdc, T11) — `lua/awiwi/hi.lua:288` — `get_recipe_title()` still calls `vim.fn["awiwi#get_recipe_subpath"]()` (vimscript interop), but T10 deleted `autoload/awiwi.vim` → **E117 at runtime** whenever a recipe buffer's title is drawn (`ftplugin/awiwi.lua:232` wires it live). Spec masks it by stubbing `vim.fn`. Repo-wide sweep confirms this is the ONLY dead interop: `server.lua:62`'s shim default is rebound by the façade (`init.lua:1210-1212` → `markers.get_markers`), and all 14 `vimshim(...)` deps in `cmd.lua:136-149` are rebound in `init.lua`'s wiring block. **Exact fix (red/green, unapplied — test gate was permission-blocked this session):** (1) RED: in `tests/hi_spec.lua` `describe("hi.get_recipe_title")`, drop the `vim.fn["awiwi#get_recipe_subpath"]` stub entirely — `with_home` already sets `vim.g.awiwi_home`, so just `nvim_buf_set_name(buf, home .. "/recipes/cooking/pasta.md")` and assert `eq("cooking/pasta", hi.get_recipe_title())`; run → E117 red. (2) GREEN: in `hi.lua:288` replace with `local subpath = require("awiwi").get_recipe_subpath()` (lazy require inside the function — `init.lua` requires `hi` at top level, so a top-level require would cycle); update the stale doc comment (`hi.lua:284-285`) that still claims the façade is "not yet ported". Found in T11; fix-in-T11
- [x] B10 — `awiwi#get_recipe_subpath` is unreachable end-to-end in shipped vimscript (pre-existing `fn#spread` breakage in `awiwi#path#join`); hi_spec stubs it — T10 must port it natively (found in T6a)
- [x] B11 — `tests/asset_spec.lua` — `with_write_spy` "restored" the startup buffer that `:edit` had renamed in place, leaking a `2026-07-05`-dated asset buffer as current into later spec files; `open_asset_sink` spec silently depended on that leaked buffer for its `:write`. Masked while wall-clock date == 2026-07-05; broke the suite on rollover. Fixed inline by orchestrator (park on fresh scratch buffer + wipe asset buffers; swallow stubbed sink write) — found in T6b's full-suite run
- [x] B12 — `tests/server_spec.lua` — config.json spec leaked `g:awiwi_link_color`/`search_engine`/`screensaver` into later spec files, breaking syn's default-color assertions. Fixed inline by orchestrator (c0fef93) — found in T6b's full-suite run
- [x] B-INIT-1..5 — five façade bugs found by T10 recon (see `handovers/done/lua-port/init.md` bug ledger) — fixed in T10 port; B-INIT-6 (`g:awiwi_history_length` no-op) documented as ADR D10, deliberately inert
- [x] PENDING-ADR — `split_screen` `<C-x>/<C-v>` inverted guard — **resolved in T12 (2026-07-07)**: user directed correction; guard fixed to `== 0` (ADR D12), spec updated, suite 458 green
- [x] B14 (fixed in T17.1) — `lua/awiwi/init.lua:1211` — T10 façade rebind `server.config.get_markers = markers.get_markers` dropped the shim's `{ join = false }`, so `_write_json_config` wrote pipe-joined marker *strings* into config.json instead of the legacy *arrays* — crashed the FastAPI lifespan on the first live `:Awiwi serve` (PluginConfig expects `list[str]`). Masked because both reset() and the config.json spec stub `get_markers` with list-returning fakes. Fix: rebind wraps `join = false`; new spec reloads the façade and asserts decoded arrays; server hardened in same transaction (screensaver `str | bool`, permissive load fallback). Found in S17.3 dogfood
- (new bugs found during implementation are appended here by any agent: `- [ ] B<n> — <file:line> — <one-liner> — found in T<x>; fix-in-port|post-port`)

## What the next session needs

- **T28 fully closed (2026-07-15)** — visual-parity loop complete, all 13 pages verified PARITY, knowledge base updated, handovers archived.
- **T21 — kitty dogfood checklist for inline images (user, manual, in a real kitty session):**
  1. Get snacks.nvim on the rtp — e.g. `nvim --cmd 'set rtp+=/tmp/snacks.nvim'` (a shallow clone
     from S19.2 sits at `/tmp/snacks.nvim`) or install it properly via the plugin manager.
  2. Open a journal page containing `![name](/assets/YYYY-MM-DD/file.png)` → image should render
     inline (kitty unicode placeholders; capped at snacks defaults `doc.max_width=80`/`max_height=40` cells).
  3. Fallback checks — each must show the plain concealed link exactly as before: (a) no snacks on
     rtp; (b) `:let g:awiwi_inline_images = v:false` before opening; (c) non-kitty terminal / zellij.
  4. Observe: snacks' markdown queries also target ```mermaid/```math fences — it may try to render
     those (needs mermaid CLI/latex). Note behavior; recorded as accepted side effect in ADR D17.
  5. Report findings → new `T20.x` fix transactions if anything's off, else T21 closes the flow.
- **All transactions T0–T20 closed (T18–T20 await T21 dogfood); older remaining items are user-only:**
  1. `.claude/settings.json` nvim allowlist entries — **committed** (handover just wasn't updated at the time).
- Dogfood results (2026-07-07, user's live config):
  - `<C-v>` clipboard image paste — **verified working** (X11+xclip). The earlier "no mapping" was a `--clean` artifact only: `--clean` skips config so the plugin isn't on rtp and `g:awiwi_home` is unset → `ftdetect/awiwi.lua:6-8` bails → ft stays markdown → no buffer maps. In-config ft is `awiwi` and the map at `ftplugin/awiwi.lua:100` → `init.lua:655` → `asset.lua` fires. No code change.
  - airline/entitlement — **verified working**.
  - telescope pickers — **verified working**.
  - drawio export — **deferred** by user.
  - `:Awiwi serve` — **deferred** by user (FastAPI app module still a placeholder, ADR D5 — pin the `uv run uvicorn app:app` entrypoint when it lands).
- Untracked `autoload/awiwi/ask.vim`/`bookmarks.vim` drafts in the main checkout are untouched (dropped modules per skill) — user decides their fate.
- Plan: `~/.claude/plans/plan-the-migration-from-declarative-castle.md` (design decisions D1 treesitter arch, asset⇄cmd break, telescope pickers, dropped modules, bug policy).
- Per-module handovers at `handovers/done/lua-port/<module>.md` (archived at T10 close) (archaeologist writes, engineer appends `## Ported`, verifier judges in `.claude/progress/qa-verifier-<module>.md`).
- Engineers serialize through the verify gate; archaeologists/verifiers parallelize.

## Tooling gaps noted (non-critical)

- ~~CRITICAL (halted T11 for 25 runs, 2026-07-06)~~ — resolved same day: user added `"Bash(nvim --clean:*)"` + `"Bash(nvim --clean --headless:*)"` to `permissions.allow`; T11 completed on run 26.

- ~~telescope.nvim by T9~~ — resolved: probe found no telescope/plenary/fzf; user chose vim.ui.select default + telescope auto-upgrade (ADR D7). Telescope path is fake-injected in specs only — sanity-check with real telescope during T10 dogfooding if available.
- `server/` has no FastAPI app module yet — `server.lua`'s `uv run uvicorn app:app` entrypoint is a documented placeholder (ADR D5); pin it when the app lands.
- ~~Per-module briefs stay in `handovers/lua-port/` until T10 consumes their `## Ported` inventories~~ — archived to `handovers/done/lua-port/` at T10 close (2026-07-06).
