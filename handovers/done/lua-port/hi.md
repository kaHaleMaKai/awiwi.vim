# lua-port / hi

**Responsibility:** Buffer-local visual decoration for awiwi markdown buffers via `nvim`
virtual text: (a) due-date/created-date badges on unchecked todo checklist lines, (b) a
horizontal-rule extension drawn after ATX heading lines, and (c) three title-string helpers
consumed by the optional `entitlement.nvim` integration (winbar/statusline titles for journal,
asset and recipe buffers). No persistence, no network, no shelling out.

**Public surface** (`autoload/awiwi/hi.vim`, all exported under `awiwi#hi#`):

- `awiwi#hi#get_meta_and_pos(line: string) -> [meta: dict, start: number, end: number]`
  Extracts the trailing `{...}` JSON metadata blob from a todo checklist line. Returns
  `[{}, -1, -1]` if `line` doesn't look like an unchecked checklist item or has no valid
  trailing JSON. No errors thrown (JSON-decode failure is swallowed).
- `awiwi#hi#draw_due_dates() -> nil` (side effect only)
  Scans the whole current buffer, sets due/created-date virtual-text badges on every
  matching line.
- `awiwi#hi#clear_due_dates() -> nil` (side effect only)
  Clears all extmarks in the due-date namespace for the current buffer.
- `awiwi#hi#redraw_due_dates(force_redraw: bool = false) -> nil` (side effect only)
  Debounced wrapper around clear+draw; see contract §7.
- `awiwi#hi#draw_horizontal_lines() -> nil` (side effect only)
  Clears and redraws the header-rule namespace for the current window's buffer.
- `awiwi#hi#get_recipe_title() -> string`
- `awiwi#hi#get_asset_title() -> string`
- `awiwi#hi#get_journal_title() -> string`
  Three pure(-ish, they read `expand('%:p')`/current buffer path) title formatters, no
  side effects, used only as `fn` callbacks by `entitlement.nvim` config in
  `ftplugin/awiwi.vim`.

Private helpers not exported but behavior-relevant (must be preserved as internal logic,
not part of the public Lua surface): `s:get_date_diff(date1, date2)`, `s:format_days(days)`.

**Reads/writes:**
- Globals: none read/written directly by `hi.vim` itself (autoload guard `g:autoloaded_awiwi_hi`
  only — drop per idiom table, `require` caching replaces it).
- Window-local: `w:last_redraw` (number, unix timestamp) — read and written by
  `redraw_due_dates` as a per-window debounce cache.
- Buffers: reads buffer lines (`getline`/`line('$')`) of the *current* buffer only; never
  writes buffer text, only extmarks.
- Extmark namespaces (module-scoped, created once at load):
  - `awiwi-todo-dates` (`s:ns_todo_dates`) — due/created-date end-of-line badges.
  - `awiwi-horizontal-lines` (`s:ns_hlines`) — header-rule end-of-line decoration.
- Files: reads mtime of the current file via `getftime(expand('%:p'))` (staleness check
  only, never opens/reads file content besides the already-loaded buffer).
- No registers, no other buffers/windows besides the current one (`nvim_win_get_width(0)`,
  bufnr `0` throughout — always "current").

**External:**
- Other awiwi modules: `awiwi#date#to_tuple`, `awiwi#date#to_nice_date`,
  `awiwi#date#get_own_date` (date module — already ported, T3); `awiwi#path#relativize`,
  `awiwi#path#split` (path module — already ported, T2); `awiwi#str#endswith` (str module —
  already ported, T1); `awiwi#get_recipe_subpath()` (still in `autoload/awiwi.vim`, not yet
  ported — façade dependency, deferred to T10; until then the Lua module must call the
  vimscript function via `vim.fn['awiwi#get_recipe_subpath']()` or read the equivalent global
  directly if T10 has exposed it by then — flag this cross-dependency to the T10 façade work).
- VimL plugin deps: none (`fn#`/`path#` not used in this file).
- Binaries: none directly; `s:get_date_diff` shells out indirectly today via `luaeval` calling
  Lua's `os.time` (not an external process — `luaeval` runs in-process). This dependency is
  **killed** in the port (see Port notes) — Lua code calls `os.time` natively, no `luaeval`.
- Optional consumer (not a dependency of this module, but the reason 3 of the 8 public
  functions exist): `entitlement.nvim`, wired only if
  `get(g:, 'awiwi_use_entitlement', v:true) && &rtp =~# 'entitlement.nvim'`
  (`ftplugin/awiwi.vim:409-429`). The port does not need to touch `entitlement.nvim` itself —
  just keep the 3 title functions' signatures (`() -> string`, no args) stable since they're
  passed as `Funcref`/callable values.

## Behavior contract

**Due-date/created-date badges**

1. `get_meta_and_pos(line)`: matches `line` against `^\s*\* \[ \] ` (an *unchecked* `*`-bulleted
   checklist item — checked `[x]`, other bullet chars, or list markers are never matched) AND
   requires a trailing brace-delimited blob at the exact end of the line matching
   `{[^{]\+}$` (i.e. `{...}` with at least one non-`{` byte inside, anchored to `$` — trailing
   whitespace after `}` makes it not match, and an empty `{}` blob does not match either since
   `\+` requires ≥1 inner byte). If either condition fails, returns `[{}, -1, -1]`. If both
   hold, JSON-decodes the matched blob; on decode failure returns `[{}, -1, -1]` (Vim error
   code `E474`, the *only* decode-error case handled — any other exception raised by
   `json_decode` propagates uncaught, see Bug hi-3). On success returns
   `[decoded_dict, start_byte_offset, end_byte_offset]` of the matched `{...}` blob within `line`.
2. `draw_due_dates()`: for every buffer line (1-indexed in vimscript, 0-indexed extmark row),
   calls `get_meta_and_pos`. Lines with empty meta are skipped entirely (no extmark, not even
   a cleared one — clearing is the caller's job, see §5/§7).
3. For a line with non-empty meta and a `due` key: computes `days = due_date - today` in whole
   days (`s:get_date_diff(meta.due, today)`, `today = strftime('%Y-%m-%d')` — **local wall-clock
   date at call time**, not buffer/journal date), then formats via `s:format_days(days)`:
   - `days == 0` → text `"TODAY"`, highlight group `awiwiUrgent`.
   - `days < 0` (overdue): let `n = abs(days)`, `w = n / 7` (floor), `d = n % 7`. Message body is
     `"{w}w, {d}d"` if `w>0 and d>0`, `"{w}w"` if `w>0 and d==0`, `"{d}d"` if `w==0`. Final text
     is `"[ {message} ago ]"`, highlight group **always** `awiwiUrgent` regardless of how
     overdue (no separate "near"/"far" overdue distinction).
   - `days > 0` (future): same message-body rule. Final text is `"[ in {message} ]"`, highlight
     group `awiwiFutureDueDate` if `w > 0` (a week or more away), else `awiwiNearDueDate` (less
     than a week away).
   - If computing/formatting the due date throws any exception, the badge text becomes
     `"bad meta info: {exception string}"` with highlight group `awiwiUrgent` (this replaces the
     due-date badge, it does not additionally show anything else).
4. Else (no `due` key) if meta has a `created` key: text is the raw `meta.created` string
   value, verbatim (no reformatting), highlight group `awiwiCreatedDate`.
5. Else (meta non-empty but neither `due` nor `created` present): an empty virtual-text chunk
   list is set on that line — i.e. effectively a no-op decoration (renders nothing visible).
6. The badge, when non-empty, is rendered as one virtual-text chunk `[text, hl_group]` appended
   at end-of-line (`eol` position) of that buffer line, in namespace `awiwi-todo-dates`.
7. `redraw_due_dates(force_redraw = false)`: redraws (clear + draw) iff `force_redraw` is
   truthy, OR the current buffer is `&modified`, OR the current window's cached
   `w:last_redraw` timestamp (0 if unset) is older than the on-disk mtime
   (`getftime(expand('%:p'))`) of the current file. On redraw, sets
   `w:last_redraw = <current unix time>` (wall clock at redraw time, *not* the file's mtime).
   If none of the three conditions hold, this is a no-op — existing extmarks are left as-is.
   This is a per-*window* cache: switching to another window showing the same buffer forces a
   redraw the first time (its `w:last_redraw` is unset).
8. `clear_due_dates()`: unconditionally clears every extmark in namespace `awiwi-todo-dates` for
   lines `[0, -1]` (whole buffer) of the current buffer.

**Header rules**

9. `draw_horizontal_lines()`: unconditionally clears namespace `awiwi-horizontal-lines` for the
   whole current buffer first, then does a single top-to-bottom scan of every line:
   - A line matching `^```` ` (literal, ≥3 backticks at line start, via `=~#` case-sensitive)
     toggles an `is_code_block` flag and is itself skipped (no rule drawn on it, no further
     processing of that line).
   - While `is_code_block` is true, every line (including further fence lines, which also
     re-toggle) is skipped.
   - Else, a line matching `^#\+\s` (one-or-more `#` then whitespace — an ATX heading; a
     text-only headerless title made of only `#` with no trailing text/space does **not**
     match) triggers a rule: `level = strlen(first_whitespace_delimited_token)` (i.e. count of
     leading `#` characters, via splitting on whitespace and measuring the first token's byte
     length — this is *not* clamped to 6, an ATX heading with 7+ `#` produces `level=7+`);
     `rem = window_width - byte_length(line) - 2`; if `rem <= 0` no rule is drawn for that
     heading. Otherwise the rule text is one leading space followed by `rem` repetitions of a
     fill character: `━` (U+2501, heavy) for `level <= 2`, `─` (U+2500, light) otherwise. The
     rule is set as one virtual-text chunk on that same heading line, `eol` position,
     namespace `awiwi-horizontal-lines`, highlight group `printf('markdownH%d', level)`
     (so `level` > 6 references a nonexistent group and nvim silently no-ops/uses fallback
     highlighting — no error).
   - Any other line (plain text/list/etc., not in a code block) is left untouched — no
     clearing, no rule (clearing already happened for the whole buffer up front in this call).
   - `window_width` is `nvim_win_get_width(0)` measured *once* at the start of the call — it
     does not account for sign column/number column/fold column offsets, and if the same
     buffer is displayed in multiple windows of different widths, only the currently-focused
     window's width is used for all rules that call places into (extmarks are buffer-scoped,
     so the rule length will look wrong in any other window showing that buffer at a different
     width, until that window becomes current and triggers `BufEnter` again).
10. `draw_horizontal_lines()` is wired only via autocmds (`ftplugin/awiwi.vim:300-301`):
    `BufEnter *.md` and `BufModifiedSet *.md` guarded by `if !&modified` (i.e. runs on
    entering a markdown buffer, and again right after a save transitions `modified` back to
    `0`). It is not re-run on every edit — only on buffer-enter and post-save.

**Due-date redraw wiring**

11. `redraw_due_dates()` (no force) is wired via: `BufEnter,BufLeave,InsertEnter,InsertLeave`
    on `*/todos/*.md` (`ftplugin/awiwi.vim:295`); after every `o`/`O`/`<Enter>`/`<C-j>` mapping
    that inserts a new checklist line (`ftplugin/awiwi.vim:275-279`); after the `A`
    (append-to-line) mapping in `awiwi.todo` filetype buffers (`ftplugin/awiwi.vim:405`); and
    once right after `:Awiwi` init (`ftplugin/awiwi.vim:61`, invoked as a generic redraw
    callback `s:redr` for an unrelated timer/callback — same effect).
12. `redraw_due_dates(v:true)` (forced) is wired via `autoload/awiwi.vim:775` and `:823` — both
    inside `:Awiwi`-command-driven task-mutation flows (exact commands out of scope for this
    module; treat as "some other module explicitly forces a redraw after mutating todo
    metadata").

**Title helpers**

13. `get_recipe_title()`: takes `expand('%:p')` (current file's absolute path), relativizes it
    against `awiwi#get_recipe_subpath()`, splits on `/`, drops the first path segment, rejoins
    with `/`, then strips the last 3 bytes (removing a literal `.md` extension). Example: file
    `<recipes_subpath>/cooking/pasta.md` → `"cooking/pasta"`. Assumes the current file is under
    the recipe subpath and ends in `.md`; no guard if not (garbage in, garbage out — e.g. a
    non-`.md` file silently loses its last 3 bytes instead of an extension).
14. `get_asset_title()`: splits `expand('%:p')` on `/`, takes the **last 4** segments
    (`[year, month, day, filename]`, matching the fixed `assets/{year}/{month}/{day}/{name}.md`
    doc-type layout), joins the first 3 with `-` to form a date string, and formats
    `"{name_without_.md} [{yyyy-mm-dd}]"`. Only strips a `.md` suffix from the name if present
    (`awiwi#str#endswith` guard) — a non-`.md` asset filename is kept whole. Example: file
    `.../assets/2026/07/05/my-note.md` → `"my-note [2026-07-05]"`.
15. `get_journal_title()`: `awiwi#date#to_nice_date(awiwi#date#get_own_date())` — pure delegate
    to the (already ported) date module; no logic of its own. Example: on journal file
    `2026-07-05.md`, returns whatever `to_nice_date` produces for that ISO date (e.g.
    `"Sun, Jul 05th 2026"`-shaped string per that module's own format string — see date
    module's brief, not respecified here).

## Call sites

- `awiwi#hi#redraw_due_dates()`:
  - `ftplugin/awiwi.vim:61` (`s:redr`, generic post-action redraw callback)
  - `ftplugin/awiwi.vim:275,276,277,278,279` (after `O`/`o`/`<Enter>`/`<C-j>` insert-mode line
    mappings)
  - `ftplugin/awiwi.vim:295` (autocmd `BufEnter,BufLeave,InsertEnter,InsertLeave */todos/*.md`)
  - `ftplugin/awiwi.vim:405` (after `A` append-to-line mapping, `awiwi.todo` filetype only)
- `awiwi#hi#redraw_due_dates(v:true)` (forced):
  - `autoload/awiwi.vim:775`
  - `autoload/awiwi.vim:823`
- `awiwi#hi#draw_due_dates`, `awiwi#hi#clear_due_dates`: only called internally by
  `redraw_due_dates` (`autoload/awiwi/hi.vim:94-95`); no other call sites found.
- `awiwi#hi#draw_horizontal_lines()`:
  - `ftplugin/awiwi.vim:300` (autocmd `BufEnter *.md`)
  - `ftplugin/awiwi.vim:301` (autocmd `BufModifiedSet *.md`, guarded `if !&modified`)
- `awiwi#hi#get_meta_and_pos`:
  - `ftplugin/awiwi.vim:388` (`s:append_to_line`, to find the insertion column before the
    trailing `{...}` blob when pressing `A`)
  - `autoload/awiwi/hi.vim:64` (internal, from `draw_due_dates`)
- `awiwi#hi#get_journal_title` / `get_asset_title` / `get_recipe_title`:
  - `ftplugin/awiwi.vim:413,418,423` — passed as `function('awiwi#hi#get_*_title')` `Funcref`
    values into `entitlement.nvim` opts tables, only when
    `get(g:, 'awiwi_use_entitlement', v:true) && &rtp =~# 'entitlement.nvim'`
    (`ftplugin/awiwi.vim:409`).

## Port notes

- **Namespaces**: create two namespaces once at module load, matching existing names exactly
  (external tooling/screenshots may reference them by name for debugging, keep identical):
  `vim.api.nvim_create_namespace('awiwi-todo-dates')` and
  `vim.api.nvim_create_namespace('awiwi-horizontal-lines')`. One namespace per concern, as
  today — do not merge them (clearing due-date badges must never clear header rules and vice
  versa, which is already implicitly relied on since `draw_horizontal_lines` does a full-buffer
  clear of its own namespace on every call, and `clear_due_dates` does the same for its own).
- **Extmark API**: replace both `nvim_buf_set_virtual_text(0, ns, lnum0, chunks, {})` call
  sites (hi.vim:81 and hi.vim:121, both deprecated) with
  `vim.api.nvim_buf_set_extmark(0, ns, lnum0, 0, { virt_text = chunks })`. `virt_text_pos`
  defaults to `"eol"` in the extmark API (confirmed against nvim 0.12 `:help
  nvim_buf_set_extmark`), which is the same visual position the old virtual-text API used —
  no explicit `virt_text_pos` needed for parity, but consider setting it explicitly for
  readability/future-proofing. `chunks` stays a `{ {text, hl_group}, ... }` list — identical
  shape works for both old and new API.
- **`luaeval` removal**: `s:get_date_diff` used `luaeval('os.time{...} - os.time{...}')`
  purely to reach `os.time` from vimscript. In Lua this hack disappears entirely — call
  `os.time{year=y, month=m, day=d}` directly. Do **not** route this through the date module
  unless you also add a day-diff primitive there; nothing in the currently-ported `date.lua`
  exposes day arithmetic (checked: only `to_tuple`, `to_nice_date`, `get_own_date`,
  `get_today`, `parse_date`, `is_date`, offset/leap-year internals). Recommend instead
  implementing day-diff as a **pure calendar computation** (proleptic Gregorian day-number
  difference, no `os.time`, no timezone, no DST) — see Bug hi-1 below for why.
- **B9 — treesitter structural pass, designed for reuse by T6b (`syn`)**: replace the manual
  fence-toggle scan (hi.vim:101-124) with a `vim.treesitter.get_parser(bufnr, 'markdown')`
  pass. Verified against nvim 0.12's bundled markdown parser (`nvim --clean`, no user config)
  on a buffer mixing an ATX heading, a backtick fence, a `~~~` fence, and a 4-space-indented
  block — the grammar handles all three code-block forms already, so the port closes the "`~~~`
  and indented blocks not masked" gap for free just by using the parser instead of a regex
  toggle:
  - Heading node: `atx_heading`, always exactly one row wide (`start_row == end_row - 1`, i.e.
    treesitter's half-open `[start,end)` row range spans exactly the one line). Its first child
    is `atx_h1_marker` .. `atx_h6_marker` (level = the digit in the child's node type name);
    heading text (if any) is a child of type `inline`.
  - Code-block nodes to mask (both must be treated as "inside code", including their
    delimiter/marker lines, to match the old behavior of skipping the fence lines themselves):
    `fenced_code_block` (covers both `` ``` `` and `~~~` delimiters — same node type,
    `fenced_code_block_delimiter` child holds the actual marker text if you need to
    distinguish) and `indented_code_block` (the gap the old regex scanner missed entirely).
  - **Design for reuse**: factor this into a small standalone module, e.g.
    `lua/awiwi/mdstruct.lua` (not inside `hi.lua`), so the later `syn` port (T6b) can
    `require('awiwi.mdstruct')` without depending on `hi.lua`'s internals. Suggested exposed
    surface (the two verbs both `hi` and `syn` need):
    - `M.headings(bufnr) -> { {lnum = <0-indexed row>, level = <1..6+>, text = <string|nil>}, ... }`
      — one entry per `atx_heading` node, in document order. (Setext headings — `===`/`---`
      underlines — are a *different* grammar-level construct the old regex never handled
      either; out of scope for this brief, note for `syn`'s brief if it needs them.)
    - `M.code_line_mask(bufnr) -> table` — a `[0-indexed lnum] = true` set (or a dense boolean
      array sized to `nvim_buf_line_count`) covering every line inside a `fenced_code_block` or
      `indented_code_block` node's row range (`start_row` through `end_row - 1` inclusive, i.e.
      including delimiter lines, matching old skip-fence-lines behavior).
    - `draw_horizontal_lines` becomes: `for _, h in ipairs(mdstruct.headings(0)) do if not
      mask[h.lnum] then <draw rule> end end` (the mask lookup replaces the toggle flag; a
      heading line is never itself inside a code block per the grammar, so the mask only needs
      checking, not the heading loop needing special-casing).
  - Keep the awiwi-specific *line* regexes (`^\s*\* \[ \] `, the `{...}` JSON-blob matcher in
    `get_meta_and_pos`) as plain Lua patterns/`string.find` — those are not markdown-grammar
    structure, treesitter would be the wrong tool per the skill doc's guidance.
- **Highlight groups — do not (re)define them here**: `awiwiUrgent`, `awiwiFutureDueDate`,
  `awiwiNearDueDate`, `awiwiCreatedDate` are defined today in `syntax/awiwi.vim` (`hi` commands
  at lines 10, 119-121), not in `hi.vim` — `hi.vim` only *references* the group names as
  strings. `markdownH{1..6}` groups are the bundled/legacy markdown syntax groups, also not
  defined by awiwi. `hi.lua` must reference these four/six group names as byte-identical
  strings (external configs and `entitlement.nvim` opts hardcode `'markdownH1'` directly,
  `ftplugin/awiwi.vim:414/419/424`) — do not rename or namespace them. When `syn.vim` is ported
  in T6b and its group *definitions* move to `nvim_set_hl` calls, the names must stay these
  exact strings so `hi.lua` (already shipped by then) keeps working unchanged. Until T6b lands,
  `syntax/awiwi.vim` keeps defining these groups via legacy `:highlight` as it does today — no
  action needed in this transaction beyond "don't break the reference."
- **Cross-module gap**: `awiwi#get_recipe_subpath()` (used by `get_recipe_title`) lives in
  `autoload/awiwi.vim`, which isn't ported until T10 (façade). Until then, `hi.lua` must call
  it via `vim.fn['awiwi#get_recipe_subpath']()` (vimscript interop) rather than a native Lua
  call. Flag this explicitly in the T10 handover so the façade port doesn't silently drop it.
- Autocmd re-wiring (the `BufEnter`/`BufModifiedSet`/`InsertEnter` etc. calls in
  `ftplugin/awiwi.vim`) is **not** this module's job — this brief only documents the trigger
  conditions (§10-12) as behavior the Lua functions must still support once some later
  transaction (T10 façade/`ftplugin` switchover) rewires the autocmds to call
  `require('awiwi.hi').redraw_due_dates(...)` etc. instead of `awiwi#hi#redraw_due_dates(...)`.

## Bugs found

- **B9** (per `handovers/STATE.md`, fix-in-port): manual fence tracker (hi.vim:101-124) only
  toggles on backtick fences (`^```` `) and has no concept of indented code blocks, so headings
  that are actually inside a `~~~`-fenced or 4-space-indented block still get a horizontal rule
  drawn on them. **Recommendation: fix in port** via the treesitter structural pass above —
  verified the bundled markdown grammar already distinguishes all three forms correctly.
- **hi-1** (latent, low-probability, new finding): `s:get_date_diff` computes day difference as
  `(os.time{due} - os.time{today}) / 86400` using **local wall-clock epoch seconds**. Lua's
  `os.time` table defaults missing `hour` to **12 (noon)**, `min`/`sec` to `0`, which reduces
  but does not eliminate DST-transition error (a day whose local-noon-to-local-noon span isn't
  exactly 86400 seconds, e.g. a date range crossing a DST boundary in a zone that transitions
  at/near noon, or double-DST-shift edge cases) — the integer division would round toward zero
  and could report an off-by-one day count. Also makes the "same" day-diff computation depend
  on the host machine's `$TZ`, which is bad for deterministic CI tests. **Recommendation: fix
  in port** — replace with pure proleptic-Gregorian day-number subtraction (no `os.time`, no
  timezone dependency at all: a date-only diff should never touch wall-clock time). This also
  makes `tests/hi_spec.lua` trivially deterministic regardless of the CI runner's timezone.
- **hi-2** (cosmetic, preserve): `get_meta_and_pos`'s `{[^{]\+}$` regex requires ≥1 byte inside
  the braces and requires the blob to be the literal last bytes of the line (no trailing
  whitespace tolerated); an empty `{}` metadata blob or one followed by trailing whitespace
  silently fails to match (falls through to `[{}, -1, -1]`, same as "no metadata"). No observed
  caller ever emits an empty-or-trailing-space blob today. **Recommendation: preserve** — low
  value to change, and "no metadata" is an already-handled, safe fallback for this input shape.
- **hi-3** (latent, real, preserve unless T10 says otherwise): `get_meta_and_pos`'s
  `catch /E474/` only swallows Vim's "invalid JSON" error; any other exception thrown during
  `json_decode` (or in principle from `matchstrpos`, though that's unlikely to throw) would
  propagate uncaught out of `get_meta_and_pos`, and from there out of `draw_due_dates`'s loop
  (which has no enclosing try/catch around the `get_meta_and_pos` call itself — only the
  `s:get_date_diff` call a few lines later is wrapped) — a single malformed line could abort
  the whole due-date redraw for the buffer with no user-visible error (autocmd-triggered
  exceptions are swallowed by Vim's autocommand runner and typically only show up as a
  `:messages` entry). **Recommendation: preserve the "unrelated exceptions blow up the whole
  redraw" shape is not intentional-looking, but low real-world risk** (JSON decode is close to
  total for any string) — however, since this is a new module in Lua, cheaply wrap the whole
  per-line body in `pcall` in the port (skip that line's badge and continue the loop on error)
  — recommend **fix in port**, it's near-zero cost and removes a whole-redraw failure mode.
- **hi-4** (cosmetic, preserve): `draw_horizontal_lines` uses `strlen(line)` (byte length) to
  compute remaining rule width, not display width — a heading containing multibyte UTF-8 text
  would get a shorter-than-intended (but never longer/wrapping) rule, since byte length ≥
  display width for any non-ASCII text. **Recommendation: preserve unless a specific user
  report justifies switching to `vim.fn.strdisplaywidth`/`vim.str_utfindex`-based width** — the
  rule already errs short/safe (never overflows the window), so this is a purely cosmetic,
  self-correcting-in-the-safe-direction quirk, not worth the extra complexity unless requested.
- **hi-5** (cosmetic, preserve): heading `level` computed from `strlen(first_token)` is not
  clamped to 6 — a 7+ `#` "heading" produces `markdownH7`+ as the highlight group name, which
  doesn't exist, so nvim silently falls back to no highlight for that virtual-text chunk
  (harmless, just an unstyled rule). **Recommendation: preserve** — matches upstream markdown's
  own treatment of >6 `#` as not-really-a-heading; not worth special-casing.

## Suggested acceptance tests

```
-- get_meta_and_pos
get_meta_and_pos('* [ ] buy milk {"due":"2026-07-06"}')
  -> ({due = "2026-07-06"}, <start byte idx of '{'>, <end byte idx after '}'>)
get_meta_and_pos('* [x] buy milk {"due":"2026-07-06"}')      -> ({}, -1, -1)  -- checked box
get_meta_and_pos('- [ ] buy milk {"due":"2026-07-06"}')      -> ({}, -1, -1)  -- wrong bullet
get_meta_and_pos('* [ ] buy milk {"due":"2026-07-06"} ')     -> ({}, -1, -1)  -- trailing space
get_meta_and_pos('* [ ] buy milk {}')                        -> ({}, -1, -1)  -- empty blob
get_meta_and_pos('* [ ] buy milk {not json}')                -> ({}, -1, -1)  -- decode failure
get_meta_and_pos('just prose, no checklist')                 -> ({}, -1, -1)

-- format_days (private, but test via draw_due_dates' visible badge, or export for unit test)
days=0    -> {"TODAY", "awiwiUrgent"}
days=-3   -> {"[ 3d ago ]", "awiwiUrgent"}
days=-10  -> {"[ 1w, 3d ago ]", "awiwiUrgent"}
days=-14  -> {"[ 2w ago ]", "awiwiUrgent"}
days=3    -> {"[ in 3d ]", "awiwiNearDueDate"}
days=10   -> {"[ in 1w, 3d ]", "awiwiFutureDueDate"}
days=14   -> {"[ in 2w ]", "awiwiFutureDueDate"}

-- draw_due_dates (integration, scratch buffer)
given buffer line '* [ ] task {"due":"<today+3d>"}' at lnum 0
  -> exactly one extmark in ns 'awiwi-todo-dates' at row 0, virt_text = {{"[ in 3d ]", "awiwiNearDueDate"}}
given buffer line '* [ ] task {"created":"2026-01-01"}'
  -> virt_text = {{"2026-01-01", "awiwiCreatedDate"}}
given buffer line '* [ ] task {"foo":"bar"}' (no due/created key)
  -> extmark set with empty virt_text (or no visible chunk)
given buffer line 'not a checklist item' -> no extmark set on that line

-- clear_due_dates / redraw_due_dates
after draw_due_dates then clear_due_dates -> zero extmarks remain in the namespace
redraw_due_dates() on an unmodified buffer whose w:last_redraw > file mtime -> no-op,
  extmark set is unchanged (use a spy/counter on draw_due_dates to assert it wasn't called)
redraw_due_dates(true) -> always clears+redraws regardless of modified/mtime state

-- draw_horizontal_lines (integration, scratch buffer, mdstruct pass)
buffer: {"# H1", "some text"} -> one extmark on line 0 in 'awiwi-horizontal-lines',
  hl group 'markdownH1', fill char '━' (level <= 2)
buffer: {"### H3", "text"} -> fill char '─' (level > 2), hl group 'markdownH3'
buffer: {"```", "# not a heading", "```"} -> zero extmarks (fenced, backtick)
buffer: {"~~~", "# not a heading", "~~~"} -> zero extmarks (fenced, tilde — regression test for B9)
buffer: {"    # not a heading (indented code)"} -> zero extmarks (indented block — B9)
buffer: {"# H1"} in a window narrower than len("# H1") + 2 -> zero extmarks (rem <= 0)

-- title helpers (stub expand('%:p') / g:awiwi_home as needed)
get_recipe_title() for file '<recipe_subpath>/cooking/pasta.md' -> "cooking/pasta"
get_asset_title() for file '.../assets/2026/07/05/my-note.md' -> "my-note [2026-07-05]"
get_journal_title() for file '<journal_subpath>/2026/07/2026-07-05.md'
  -> awiwi.date.to_nice_date("2026-07-05")  -- delegate check only, exact string per date module's own tests
```

## Ported

**Lua module:** `lua/awiwi/hi.lua` — `local M = {} … return M` shape, `require("awiwi.date")`
(`get_today`, `diff_days`, `to_nice_date`, `get_own_date`), `require("awiwi.path")`
(`relativize`, `split`), `require("awiwi.str")` (`endswith`) for the deps already ported (DRY per
SKILL.md, none re-derived). Spec: `tests/hi_spec.lua` (39 `it` cases across 10 `describe`
blocks). Per **binding orchestrator override** of this brief's own B9 recommendation, the
treesitter structural pass is **not** factored into a separate `lua/awiwi/mdstruct.lua` module —
it lives inside `hi.lua` as `M.headings`/`M.code_line_mask` (see "Structural-pass API" below) so
T6b (`syn`) can `require('awiwi.hi').headings(...)` / `.code_line_mask(...)` directly, or a later
transaction can extract it verbatim into its own module without behavior change.

**Public API** (namespaces created once at module load, exact names preserved):
- `M.ns_todo_dates` / `M.ns_hlines` — the two `vim.api.nvim_create_namespace` ids
  (`'awiwi-todo-dates'`, `'awiwi-horizontal-lines'`), exposed as module fields so callers/tests
  don't need to re-derive them (namespace lookup by name is idempotent, so this is a convenience,
  not new coupling).
- `M.get_meta_and_pos(line) -> meta, start0, end0`
- `M.draw_due_dates() -> nil`
- `M.clear_due_dates() -> nil`
- `M.redraw_due_dates(force_redraw?) -> nil`
- `M.draw_horizontal_lines() -> nil`
- `M.get_recipe_title() -> string`
- `M.get_asset_title() -> string`
- `M.get_journal_title() -> string`
- `M.headings(bufnr?) -> { {lnum, level, text}, ... }` — structural-pass API, see below.
- `M.code_line_mask(bufnr?) -> { [0-indexed lnum] = true, ... }` — structural-pass API, see below.

**Structural-pass API for T6b (`syn`) reuse (B9 fix):** replaces the manual backtick-only fence
toggle with a single compiled treesitter query over `vim.treesitter.get_parser(bufnr,
'markdown')`'s tree — `(atx_heading) @heading (fenced_code_block) @code (indented_code_block)
@code`, compiled once (module-local `structural_query`, lazily parsed on first use). Verified
empirically (nvim 0.12.2 bundled `markdown` parser, `nvim --clean`) that the grammar already
distinguishes backtick fences, `~~~` fences (both are `fenced_code_block`, same node type) and
4-space-indented blocks (`indented_code_block`) correctly, closing the exact gap B9 flagged.
- `M.headings(bufnr) -> { {lnum = 0-indexed row, level = 1..6, text = string|nil}, ... }`, one
  entry per `atx_heading` node in document order. `level` comes from the marker child's node type
  (`atx_h1_marker`..`atx_h6_marker`); `text` from the `heading_content`-field `inline` child (nil
  for an empty heading). Both `hi.lua`'s own `draw_horizontal_lines` and T6b can call this
  directly; `text` is unused by `hi.lua` itself but kept per the brief's suggested shape for
  `syn`'s TOC-generation needs.
- `M.code_line_mask(bufnr) -> table` — `[0-indexed lnum] = true` for every line inside a
  `fenced_code_block` or `indented_code_block` node's `[start_row, end_row)` half-open range,
  i.e. `start_row` through `end_row - 1` inclusive (delimiter lines included, matching the old
  skip-fence-lines behavior).
- `draw_horizontal_lines` is exactly `for _, h in ipairs(M.headings(0)) do if not mask[h.lnum]
  then <draw> end end`, per the brief's suggested shape.
- Both functions `pcall` the `get_parser` call and gracefully return `{}`/empty mask if the
  buffer can't be parsed as markdown (defensive; not expected to trigger for `awiwi`/`markdown`
  filetype buffers).
- Setext headings (`===`/`---` underlines) are out of scope, as specced — the query only matches
  `atx_heading`.

**Fix-in-port bugs applied:**
- **B9** (fence tracker → treesitter): see above. Verified via acceptance tests that a heading
  inside a `~~~` fence or a 4-space-indented block now correctly draws zero rules (regression
  tests for the exact gap the old regex scanner had).
- **hi-1** (DST-sensitive `luaeval`/`os.time` day-diff → `date.diff_days`): `s:get_date_diff` is
  deleted entirely; `draw_due_dates` calls `require('awiwi.date').diff_days(meta.due, today)`
  directly — pure proleptic-Gregorian day-number subtraction, no `os.time`, no `$TZ` dependence,
  deterministic under any CI timezone.
- **hi-3** (unrelated exception could abort the whole due-date redraw): the entire per-line body
  of `draw_due_dates`'s loop is wrapped in `pcall` (not just the due-date-formatting branch, which
  already had its own inner `pcall` per contract item 3's "bad meta info" behavior) — a line whose
  `get_meta_and_pos` call itself throws (simulated in the test suite via monkey-patching) no
  longer aborts the rest of the buffer's redraw. Regression-tested by monkey-patching
  `M.get_meta_and_pos` to throw for one specific line and asserting the other lines still get
  their badges.

**Preserved-as-documented quirks:**
- **hi-2** (empty `{}` blob or trailing-whitespace-after-blob silently falls through to "no
  meta"): preserved verbatim via the `{[^{]+}$` anchored Lua pattern (`+` requires >=1 inner
  byte, `$` requires the blob to be the literal last bytes of the line). Pinned with two explicit
  tests.
- **hi-4** (rule width computed from byte length `#line`, not display width): preserved — pinned
  with a test using a heading containing a multibyte UTF-8 character (`é`), confirming the fill
  count matches `width - #line - 2` (byte length), not a display-width-aware count.
- **hi-5** (heading level not clamped to 6, so 7+ `#` produced a nonexistent `markdownH7+` group):
  **rendered moot by the B9 treesitter switch**, not by an explicit code change — empirically
  verified (nvim 0.12.2 bundled grammar) that a line with 7+ leading `#` is not parsed as an
  `atx_heading` node at all (CommonMark caps ATX headings at 6 `#`; 7+ falls through to a
  paragraph), so `M.headings` never emits an entry for it and no rule is drawn — a strictly more
  correct outcome than the old "level 7, silently unstyled" quirk, and consistent with hi-5's own
  "matches upstream markdown's own treatment" recommendation. Pinned with a regression test.

**COORD-1 applied (get_recipe_title):** calls `path.relativize(file, subpath)` directly with no
split/drop-first-component/rejoin step. Hand-verified (and pinned in the acceptance test) that
the already-fixed `path.relativize`, given `subpath` as the recipe directory itself (not a file
inside it), naturally produces the exact same common-prefix match through `subpath`'s own last
component (since it's genuinely a path component of `file` too), yielding `up_count = 0` and the
correct `"cooking/pasta"`-shaped result with zero manual stripping — confirmed empirically:
`path.relativize('/home/x/notes/recipes/cooking/pasta.md', '/home/x/notes/recipes')` →
`"cooking/pasta.md"`. `get_recipe_title` then just strips the trailing `.md` (`rel:sub(1, -4)`).

**Cross-module gap confirmed and flagged for T10:** `vim.fn['awiwi#get_recipe_subpath']()`
(vimscript interop, per the brief) is currently **unreachable** in isolation — calling it triggers
`autoload/awiwi.vim`'s script-level `let s:recipe_subpath = awiwi#path#join(g:awiwi_home,
'recipes')`, which itself depends on the still-unvendored `fn#spread` plugin (already-known-dead
per B-PATH-2/path.md) and throws `E117: Unknown function: fn#spread` before `hi.lua` even runs.
This is **not** a regression introduced by this port — the vimscript call chain is broken
independent of `hi.lua` — but it does mean `get_recipe_title()`'s `vim.fn[...]` call site is
currently untestable end-to-end and unusable in a real session until T10 either ports
`get_recipe_subpath` natively or fixes/drops the `fn#spread` dependency in `awiwi#path#join`.
`tests/hi_spec.lua` stubs `vim.fn['awiwi#get_recipe_subpath']` directly (assigning a plain Lua
function to the `vim.fn` table entry, which Neovim allows and dispatches correctly) to exercise
`get_recipe_title`'s own logic in isolation. **Flag for T10:** either port
`awiwi#get_recipe_subpath` to `init.lua` and have `hi.lua` `require` it directly (removing the
`vim.fn[...]` interop entirely), or fix `awiwi#path#join`'s `fn#spread` dependency as part of the
façade cutover — until then, `get_recipe_title()` is dead-in-practice despite being fully
ported and specced here.

**Deviation from the brief, not a regression (documented, not covered by a required acceptance
test but locked with a note for future reference):** the B9 treesitter switch also fixes an
un-flagged, narrower instance of the same class of bug as B9 itself — the old `^#\+\s` Vim regex
required the `#` at column 0 exactly, so a heading indented by 1-3 spaces (CommonMark explicitly
allows up to 3 leading spaces before an ATX marker) was previously invisible to the old scanner
and would incorrectly get no rule; the treesitter-based `M.headings` now correctly recognizes it
as an `atx_heading` and draws a rule. Verified empirically
(`nvim.treesitter` sexpr dump on `" # indented heading"`). Strictly more CommonMark-correct;
flagged here rather than silently absorbed since it's a user-visible rendering change for a (rare)
input shape the brief didn't call out.

**Test count:** 39 (targeted `tests/hi_spec.lua`, across `get_meta_and_pos` (7),
`draw_due_dates` badge-formatting (7), `draw_due_dates` integration (5), `clear_due_dates` (1),
`redraw_due_dates` (4), `draw_horizontal_lines` (9), structural-pass API (2), title helpers (4));
full suite 227 passed, 0 failed (`nvim --clean --headless -l tests/run.lua`), 7 files
(`smoke_spec.lua` + `str_spec.lua` + `path_spec.lua` + `date_spec.lua` + `util_spec.lua` +
`asset_spec.lua` + `hi_spec.lua`).

**Gotchas for T6b (`syn`) and T10 (façade):**
- Scratch buffers created via `nvim_create_buf(false, true)` (the `scratch=true` flag) can never
  report `'modified' = true` — nvim forces it off unconditionally for scratch buffers (verified
  empirically). Any spec exercising `redraw_due_dates`'s `&modified` branch needs a plain,
  non-scratch buffer (`nvim_create_buf(false, false)`); `tests/hi_spec.lua`'s
  `with_scratch_buffer` helper takes an `{ scratch = false }` opt for this.
- `nvim_win_set_width` is a no-op when the target window is the sole window in its tabpage (no
  neighbor to donate/receive the space) — exercise `rem <= 0` in `draw_horizontal_lines` via a
  heading line long enough relative to the window's actual (unchanged) width, not by trying to
  shrink the window.
- `nvim_buf_set_extmark` with `virt_text = {}` (contract item 5's "empty chunk list") creates a
  real extmark (present in `nvim_buf_get_extmarks`), but `virt_text` is entirely absent from that
  extmark's `details` table on readback (not present as an empty list) — assert `nil`, not `{}`.
- `M.headings`/`M.code_line_mask` are safe to call every redraw (treesitter parse results are
  cached/incrementally reparsed by nvim itself); no manual caching added in `hi.lua`.

status: done | commit: (pending — see task-runner commit step)
