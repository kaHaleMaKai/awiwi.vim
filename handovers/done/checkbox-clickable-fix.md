# Handover — SPA checkboxes not clickable (feedback follow-up)

_Session: 2026-07-16. Status: **fixed and committed, awaiting user verification on
real notes.** Archive to `handovers/done/` once confirmed._

## Problem

Follow-up on feedback-r1 item "checkboxes appear as plain text `[ ]` or `[x]`"
(tasks/feedback.md:21). T32 (`a67a3ae`) had added dash-bullet support, but the user
still saw literal boxes — rendered as a normal `<ul>` with `[x]` as text inside the
`<li>`, e.g. `<li>[x] <code>STOP REPLICA</code></li>`.

## Two root causes, two commits

### 1. `a1ecd83` — checkbox GFM widening

`_CHECKBOX_LINE_RE` (mdrender.py) and the hash/toggle regexes (checkbox.py) only
matched `*`/`-` bullets with exactly one space and lowercase `[x]`. Now full GFM
task-list semantics: `*`/`-`/`+` bullets, ordered items (`1.` / `1)`), 1+ spaces,
`[ ]`/`[x]`/`[X]`, bare boxes without trailing text. Blockquote-nested boxes
(`> - [ ]`) deliberately still plain. Hashes for previously supported forms
unchanged; toggle still writes lowercase `x`.

### 2. `37bc564` — fence-state desync (the actual cause of the reported symptom)

`_filter_body` tracked code fences with a naive column-0 backtick toggle, while
`FencedCodeExtension` (a) also accepts `~~~`, (b) closes only on an exact
same-char/same-length column-0 delimiter, (c) treats an opener without a closer as
plain text. An indented closing fence, a ``` inside a `~~~` block, or an unclosed
fence left the filter stuck "in fence" → all later checkbox/tag/mention injection
silently skipped while markdown rendered the lines normally. Fix: tracker remembers
the exact opening delimiter, exits only on an exactly-matching closer, and enters
fence state only if a matching closer exists later (scan-ahead). Known accepted
divergence (commented in code): closers inside redacted sections.

## Verification done

- Backend 275 green (13 new red-first tests: `TestCheckboxInjection` additions,
  `TestFenceStateTracking`, `test_checkbox.py` hash/toggle round-trips), ruff clean,
  basedpyright 0, frontend 140 green.
- Live end-to-end, twice: real uvicorn against a scratch copy of `~/awiwi-dogfood`,
  headless Chromium via CDP (raw WebSocket, pattern borrowed from
  `server/tests/visual/shoot.mjs`). All checkbox forms render as enabled
  `input.awiwi-checkbox`, a click toggles, `PATCH /api/checkbox` succeeds, the file
  on disk flips. Probe script lived in the session scratchpad (gone next session);
  rebuild from shoot.mjs if needed — ~100 lines: createTarget, navigate, evaluate
  `querySelectorAll("input.awiwi-checkbox")`, `input.click()`, re-read file.
- No frontend/dist changes anywhere — the SPA enhancer
  (`frontend/src/lib/enhance/checkbox.ts`) selects `input.awiwi-checkbox`
  generically; T34's committed dist is current.

## Next session: start here

1. **User verifies on real notes** (server restart required — backend change, no
   dist rebuild, no browser-cache concern). If a doc still misbehaves: get its raw
   markdown, especially the fences above the checkbox list, and check
   `render_markdown()` output directly (`uv run python -c ...` from `server/`).
2. If confirmed: archive this file to `handovers/done/`, done.

## Known leftovers (out of scope, noted during the session)

- `ruff format --check .` fails on 6 pre-existing files not touched here
  (app.py, content.py, conftest.py, test_acceptance.py, test_config.py,
  test_content.py) — formatting drift from before this session.
- Blockquote-nested checkboxes unsupported (deliberate; documented in
  architecture.md and asserted by `test_blockquote_checkbox_stays_plain`).
- `server/.venv.bk/` (backup venv) still on disk; `server/.venv` was recreated by
  uv this session. Untracked in repo root: `.serena/`, `auth`, `autoload/` (stale
  vimscript leftovers: empty ask.vim, bookmarks.vim), `logo.png`, `tasks/`.
- Plan file (approved): `~/.claude/plans/checkboxes-still-do-not-vectorized-beaver.md`
  — its Step 1 curl diagnostic is superseded (root cause found), kept for history.
