# lua-port / util

**Responsibility:** Grab-bag of stateless(ish) helpers used across the plugin: pattern-escaping,
subcommand-completion matching (3 search engines), a resource-file cache for `resources/db/*.sql`,
timestamp/epoch getters, an `input()` wrapper, markdown-link parsing/classification, code-block
text objects, and a `path#relativize` convenience wrapper. **Roughly 8 of ~20 functions in this
file exist solely to serve `dao.vim`/`task.vim`** (the two competing, unreachable-from-`:Awiwi`
SQLite backends — see architecture.md → "Dead code, WIP & known bugs"). See "Scope recommendation"
below before implementing everything literally.

Matches `docs/architecture.md` row (`util.vim`, 369 LOC, active) but that row undersells how much
of the file is dead-caller-only; this brief corrects that.

**Dependencies (already ported):** `require('awiwi.str')` (`startswith`), `require('awiwi.path')`
(`join`, `absolute`, `relativize`). Do not re-derive their logic — call them.

---

## Scope recommendation (read first)

Grouping the 20 public functions by who actually reaches them from the *shipped* command surface
(`:Awiwi ...`, buffer mappings in `ftplugin`/`ftdetect`):

**A. Live — port fully & correctly in T4** (real callers in `awiwi.vim`, `cmd.vim`, `asset.vim`,
`ftdetect/awiwi.vim`, all of which are active/shipped):
`escape_pattern`, `get_search_engine`, `get_argument_number`, `match_subcommands`, `input`,
`window_split_below`, `get_link_under_cursor`, `as_link`, `determine_link_type`,
`relativize`, `get_code_block_lines`, `select_code_block`.

**B. Standalone dead code — zero callers anywhere in the repo, not dao/task-related.**
Recommend **dropping** in the port (KISS/DRY, no speculative code) unless the human/ADR wants a
generic helper kept for a future feature:
`join_nonempty` (0 callers), `copy_code_block` (0 callers — `get_code_block_lines` is used only via
`select_code_block`), `get_visual_selection` (0 callers, and is doubly broken — see Bugs).

**C. dao.vim/task.vim-only — both callers are dead/unreachable from `:Awiwi`** (per
architecture.md: `task.vim` is unloadable, `dao.vim` is WIP/unreachable). Recommend **deferring**
these out of T4 entirely; they have no live behavior to preserve today. Document contracts below
for the record in case a future `sql`/`dao` ADR revives them, but do not spend TDD budget on them
now: `get_resource`, `empty_resources_cache`, `get_iso_timestamp`, `get_epoch_seconds`, `is_null`,
`id_or_null`, `unique`, `has_element`.

If the orchestrator disagrees and wants group B or C ported anyway, the behavior contracts below
are complete enough to do it — just be aware you'd be porting dead code forward.

---

## Behavior contract (group A — live surface)

1. **`escape_pattern(pattern: string) -> string`** — `escape(pattern, " \t.*\\[]")`: backslash-
   escapes space, tab, `.`, `*`, `\`, `[`, `]`. No other chars touched. Pure. Example:
   `escape_pattern('a.b*c[d]')` -> `'a\.b\*c\[d\]'`.

2. **`get_search_engine() -> 'plain'|'regex'|'fuzzy'`** — reads `g:awiwi_search_engine`; returns it
   verbatim if it is `'regex'` or `'fuzzy'`, else always returns `'plain'` (this is also the
   default when the global is unset). Reads global `g:awiwi_search_engine`.

3. **`get_argument_number(expr: string) -> number`** — counts how many "words" `expr` splits into
   on `[[:space:]]+` **with `keepempty=true`**, minus 1. Used by cmd-line completion to know which
   `:Awiwi` argument position the cursor is in. Verified outputs (nvim 0.12):
   - `''` -> `0`
   - `'Awiwi'` -> `0`
   - `'Awiwi '` -> `1` (trailing space bumps the count — this is the whole point: cursor is now
     positioned to start a new argument)
   - `'Awiwi journal'` -> `1`
   - `'Awiwi journal '` -> `2`
   - `'Awiwi  journal'` (double space) -> `1` (the `+` quantifier collapses runs of whitespace, so
     no phantom empty field between the two spaces)
   Pure, no side effects.

4. **`match_subcommands(subcommands: string[], ArgLead: string) -> string[]`** — completion
   filter/sort, behavior depends on `get_search_engine()`:
   - `ArgLead == ''` -> returns `subcommands` unchanged (copy).
   - `'plain'` -> `filter(subcommands, startswith(v, ArgLead))`, order preserved.
   - `'regex'` -> `filter(subcommands, match(v, ArgLead) > -1)`, order preserved (`ArgLead` used
     directly as a Vim regex pattern — not escaped).
   - `'fuzzy'` -> subsequence-fuzzy match: build pattern from `ArgLead`'s chars joined by
     `.\{-}` (each char individually `escape_pattern`d), run `matchstrpos()` per candidate, drop
     non-matches, score = `match_end - match_start` (shorter matched span ranks first — a real
     "fuzziness" score, not just presence), stable-ish tie-break by ascending lexicographic name.
   Verified (nvim 0.12), candidates `['journal','jump','asset']`:
   - `get_search_engine()='plain'`, `ArgLead='j'` -> `['journal', 'jump']`
   - `get_search_engine()='regex'`, `ArgLead='^j'` -> `['journal', 'jump']`
   - `get_search_engine()='fuzzy'`, `ArgLead='jn'` -> `['journal']` (`jump` has no `j...n`
     subsequence, `asset` has no `j`)
   - `get_search_engine()='fuzzy'`, `ArgLead=''` -> `['journal', 'jump', 'asset']` (unchanged,
     short-circuited before scoring)
   Pure except reading `g:awiwi_search_engine` via `get_search_engine()`.

5. **`input(prompt: string, opts?: dict) -> string`** — wraps built-in `input()`. Sets
   `opts.prompt = prompt` (mutates/creates the opts dict), and if `opts.completion` is set and
   doesn't already start with `'customlist'`, rewrites it to `'customlist,' .. opts.completion`
   (convenience so callers can pass a bare function name). Wrapped in `inputsave()` /
   `try input() catch /Interrupted/ finally redraw + inputrestore()`. **Only ever called with a
   plain string `default`/no `completion`/`highlight` from the live surface** — `completion`/
   `highlight` opts are exercised only by `view.vim` (dead/WIP, not ported per architecture.md).
   See **Bugs B-util-1 (Ctrl-C)** and **Port notes** for the async-inversion discussion — this is
   the one function in this module that needs a real design decision, not just a straight port.

6. **`window_split_below() -> boolean`** — `winwidth('%') / (1.0 * winheight('%')) < 3`. True when
   the current window's width is less than 3x its height (i.e. "tallish" window) — signal to the
   caller to prefer a horizontal split ("below") over vertical ("right"). Pure read of current
   window dims; no args, no way to target another window.

7. **`get_link_under_cursor() -> {target, type, anchor}`** (a "link" table/dict, see `as_link`):
   - First checks `<cWORD>` for a redmine-issue pattern `#\zs[0-9]\{5,}` (i.e. a `#`-prefixed run of
     5+ digits anywhere in the WORD under the cursor). If found, short-circuits to a **hardcoded**
     `https://redmine.pmd5.org/issues/<N>` link, type resolved via `determine_link_type` (always
     `'browser'` in practice, since it's an `https://` URL). Note: hardcoded internal hostname,
     not configurable — flag for the human if this needs to become a `g:awiwi_*` setting.
   - Otherwise scans the current line for a markdown link `[text](target)` that brackets the
     cursor column: finds nearest `[` at/before cursor (falls back to one column right if none
     found at cursor col exactly), then nearest matching `]( ... )` after it. Returns an "empty"
     link (`as_link('')`) if brackets aren't found/don't bracket correctly (`open_bracket >
     closing_bracket`, no `(` immediately after `]`, or `)` before `]`).
     `![...]` (bang immediately before `[`) sets `type = 'image'` pre-emptively (this short-
     circuits `determine_link_type`'s classification, see #9).
   - Splits `target` on `#` via `as_link`'s helper to separate `target`/`anchor`, then runs
     `determine_link_type`.
   - Side effect: reads current buffer/cursor only (`expand('<cWORD>')`, `getline('.')`,
     `col('.')`, `line('.')`). No writes.

8. **`as_link(link: string|dict) -> {target: string, type: string, anchor: string}`** — if `link`
   is already a dict, returns a shallow copy. If it's a string, splits on the **first and only**
   `#` via the internal `split_link_and_anchor` helper and returns `{target, type: '', anchor}`.
   Examples (verified): `as_link('https://example.com')` -> `{target: 'https://example.com',
   type: '', anchor: ''}`; `as_link('foo#bar')` -> `{target: 'foo', type: '', anchor: 'bar'}`;
   `as_link('')` -> `{target: '', type: '', anchor: ''}`. **See Bug B-util-2** — a target with zero
   or 2+ `#` characters throws instead of degrading gracefully.

9. **`determine_link_type(link: dict) -> dict`** (copies input, doesn't mutate) — classifies
   `link.target` by trying, in order (first match wins):
   - already `type == 'image'` (set by caller, e.g. `get_link_under_cursor`'s `![...]` check) ->
     unchanged.
   - `^https?://` -> `'browser'`.
   - `^mailto:` -> `'mail'`.
   - `^[a-z]+://` (any other URL scheme) -> `'external'`.
   - target contains `\..*/recipes/.*` -> `'recipe'`.
   - target contains `\..*/assets/.*` -> `'asset'`.
   - **else, intended to be:** target matches
     `/(journal/)?([0-9]{4}/)?([0-9]{2}/)?\d{4}-\d{2}-\d{2}.md$` -> `'journal'`.
     **See Bug B-util-3** — as shipped this branch is missing the `> -1` comparison, so it
     actually fires almost unconditionally (see bug for exact truth table). Net practical effect:
     any link that isn't http(s)/mailto/other-scheme/recipe/asset ends up typed `'journal'`
     regardless of whether it looks like one — verified: `determine_link_type(as_link(
     'random-non-matching-target'))` -> `{type: 'journal', ...}`.
   - If none of the above sets a type, `link.type` stays `''` (only reachable today via the
     journal-branch's own inverted-logic edge case, see Bug B-util-3).
   Anchor handling (only when `link.anchor` is non-empty):
   - `type` in `['browser','mail','external']` -> anchor is re-appended verbatim:
     `link.target = target .. '#' .. anchor` (so browser/mail/external round-trip the anchor as a
     literal URL fragment).
   - any other type (`recipe`/`asset`/`journal`/`''`/`'image'`) -> anchor is turned into a loose
     "fuzzy heading search" pattern: strip a leading markdown heading marker (`^#+\s+`) **and** any
     non-`[a-zA-Z0-9_]` character from the anchor, then interleave literal `.*` after every
     remaining character, then prefix the whole result with a literal `.*`. Verified:
     anchor `'some-heading'` -> `'.*s.*o.*m.*e.*h.*e.*a.*d.*i.*n.*g.*'`. (Net formula:
     `'.*' .. fuzzy(strip_non_alnum(anchor))` — the `.*` prefix is applied *after* the substitute
     chain, not before; get the operator precedence right, `->` binds tighter than `..`.)

10. **`relativize(path: string, other?: string) -> string`** — thin wrapper:
    `path#relativize(path, path#absolute(other or expand('%')))`. i.e. relativizes `path` against
    `other` (or, if omitted, the **current buffer's** file path) after making `other` absolute
    first. Delegates entirely to the already-ported `path` module; no independent logic to test
    beyond "calls path.absolute then path.relativize with the right args in the right order",
    and the current-buffer default (`vim.api.nvim_buf_get_name(0)` in Lua, not `expand('%')`
    verbatim, to avoid relying on the current-window's buffer if this is ever called from a
    non-current-window context — flag as behavior-preserving equivalent, not identical
    implementation).

11. **`get_code_block_lines(inclusive: boolean) -> [number, number]`** — assumes cursor is inside
    a fenced code block (triple backtick, ` ``` `, matched via `str.startswith`, not full
    treesitter fence detection). Scans backward from `line('.')-1` for the opening fence, forward
    from `line('.')+1` for the closing fence. Returns `[-1, -1]` (with `echoerr`, non-throwing —
    `echoerr` inside a function without `abort`-triggered propagation just prints an error message
    unless caught) in three cases: current line itself starts with the fence (i.e. cursor is *on*
    a fence line, not inside the block), no opening fence found above, or no closing fence found
    below. Otherwise returns `[open+offset, close-offset]` where `offset = inclusive ? 0 : 1`
    (`inclusive=true` includes the fence lines themselves in the range, `false` excludes them).
    Reads current buffer lines (`getline`) and cursor position only.

12. **`select_code_block(inclusive: boolean)`** — calls `get_code_block_lines`; if `start == -1`
    (i.e. any of the three "not in a code block" cases above), silently returns (the `echoerr` from
    step 11 already fired). Otherwise runs `normal! <start>ggV<end>gg` to visually select
    (linewise) from `start` to `end`. **Live**: wired to `aP`/`iP` operator-pending and visual
    text-object mappings in `ftdetect/awiwi.vim:5-8`. Side effect: changes mode to Visual, moves
    cursor.

---

## Behavior contract (group C — dao/task-only, deferred, documented for completeness)

13. **`get_resource(path: string, ...extra: string[]) -> string`** — joins
    `<plugin-root>/resources/<path>/<extra...>` via `path.join`, memoizes file contents (joined
    with `\n`, `readfile(path, '')`) in a script-local cache keyed by the full resolved path.
    Throws (see **Bug B-util-4**) if the file doesn't exist. Only called by `task.vim` (unloadable)
    and `dao.vim` (unreachable) to load `resources/db/*.sql` query text.

14. **`empty_resources_cache()`** — clears the cache dict. Only called by `dao.vim:456` (dead).

15. **`get_iso_timestamp() -> string`** — `strftime('%F %T')` (`YYYY-MM-DD HH:MM:SS`, local TZ).
    **Defined twice, byte-identically** (lines 95 and 100) — see **Bug B-util-5**. Only called by
    `dao.vim` (dead).

16. **`get_epoch_seconds() -> number`** — `str2nr(strftime('%s'))`, i.e. Unix epoch seconds as a
    number. Only called by `task.vim` (unloadable).

17. **`is_null(obj) -> boolean`** — `type(obj) == type(v:null)`, i.e. "is this vimscript `v:null`".
    Only called by `dao.vim`.

18. **`id_or_null(el) -> id|v:null`** — `is_null(el) ? v:null : el.id`. Only called by `dao.vim`.

19. **`unique(list, ...moreLists) -> list`** — **named `unique`, does not deduplicate** — see
    **Bug B-util-6**. Only called by `dao.vim:511` (dead).

20. **`has_element` / `s:has_element`** — **the public `awiwi#util#has_element` that `dao.vim:395`
    calls does not exist** — only a script-local `s:has_element(list, el)` is defined, and it is
    itself dead (never called from within `util.vim`, superseded inline by `unique`'s — broken —
    set logic). Calling `awiwi#util#has_element` today throws `E117: Unknown function`. See
    **Bug B-util-7**.

---

## Call sites

Live surface (group A):

- `escape_pattern` — `autoload/awiwi.vim:192` (dead-code comment also at `:211`)
- `get_search_engine` — internal only, called from `match_subcommands` (util.vim:37)
- `get_argument_number` — `autoload/awiwi/cmd.vim:340`
- `match_subcommands` — `autoload/awiwi/cmd.vim:342,347,376,399,412,416,420,423,436,440,446,450,
  453,456,459`
- `input` — `autoload/awiwi/asset.vim:74,90,109`; `autoload/awiwi.vim:785,801`;
  `autoload/awiwi/cmd.vim:762`; (also `autoload/awiwi/view.vim:155,170,181,204,215,223,251` —
  dead/WIP, not in scope)
- `window_split_below` — `autoload/awiwi.vim:222,282`; `autoload/awiwi/cmd.vim:278`
- `get_link_under_cursor` — `autoload/awiwi.vim:642`; `autoload/awiwi/cmd.vim:505`
- `as_link` — `autoload/awiwi.vim:640` (also internally by `get_link_under_cursor`)
- `determine_link_type` — `autoload/awiwi.vim:640`; internally by `get_link_under_cursor`
- `relativize` — `autoload/awiwi/asset.vim:117,135`; `autoload/awiwi.vim:251,253,713,728`
- `get_code_block_lines` — internally by `copy_code_block` (dead) and `select_code_block` (live)
- `select_code_block` — `ftdetect/awiwi.vim:5,7` (`aP`), `:6,8` (`iP`)

Standalone dead (group B) — no call sites found anywhere in the repo:
`join_nonempty`, `copy_code_block`, `get_visual_selection`.

dao.vim/task.vim-only (group C):

- `get_resource` — `autoload/awiwi/task.vim:63,96,137,224,235,241`;
  `autoload/awiwi/dao.vim:280,328,361,433`
- `empty_resources_cache` — `autoload/awiwi/dao.vim:456`
- `get_iso_timestamp` — `autoload/awiwi/dao.vim:502,632`
- `get_epoch_seconds` — `autoload/awiwi/task.vim:115,172`
- `is_null` — `autoload/awiwi/dao.vim:21,109,162,529,534,548,556`
- `id_or_null` — `autoload/awiwi/dao.vim:523` (x2 in same call)
- `unique` — `autoload/awiwi/dao.vim:511`
- `has_element` (missing impl) — `autoload/awiwi/dao.vim:395`

---

## Callers of `awiwi#util#input` — resolving the async-inversion question

Enumerated every live (non-`view.vim`) call site:

1. **`autoload/awiwi/asset.vim:74`** (inside `s:create_asset`, url-asset branch) — single prompt
   (`'url: '`), result used immediately in the same statement group (`empty(url)` check, then
   `awiwi#download_file(path, url)`). No dependency on a prior/later prompt.
2. **`autoload/awiwi/asset.vim:90`** (inside `awiwi#asset#create_asset_link`) — prompt for
   `'asset name: '`; result (`name`) feeds into computing `default_filename` (slugified from
   `name`), which is then used as the **default** for the *next* prompt at line 109. **Genuinely
   sequential/dependent** — two prompts in a row where prompt #2's default depends on prompt #1's
   answer.
3. **`autoload/awiwi/asset.vim:109`** (same function, continued) — prompt for `'asset file: '`
   with the computed default; result feeds into `awiwi#asset#get_asset_path`, file creation, and
   link insertion further down the same function.
4. **`autoload/awiwi.vim:785`** (inside `awiwi#edit_meta_info`, per-column edit branch) — prompt
   for a single meta value; result flows into JSON decode/mutate/encode and (further down the
   function, not shown in this excerpt) a `setline()` buffer write.
5. **`autoload/awiwi.vim:801`** (same function, whole-meta-line branch) — prompt for the whole
   `{...}` JSON blob; result flows into `json_decode`/`due`-date normalization/`json_encode`, then
   a buffer write.
6. **`autoload/awiwi/cmd.vim:762`** (inside `awiwi#cmd#export_drawio_diagram`) — prompt for
   `'output: '` with a computed default; result is validated (`empty()` check) then used to build
   an argv for `jobstart(['drawio', ...])`.

**Every single one of the six** follows the same shape: prompt -> use the string result to drive
non-trivial follow-up logic (validation, JSON manipulation, buffer writes, or spawning an external
process). None of them are "fire and forget". This matters because it means there is no caller
where a naive synchronous shim buys you anything architecturally — all six need their post-prompt
logic to live somewhere that runs *after* the answer is available, whether that's "the rest of a
synchronous function" (current shape) or "an `on_confirm` callback" (nvim-idiomatic shape).

**Recommendation: `awiwi.util.input(opts, on_confirm)` — async callback, mirroring `vim.ui.input`'s
own signature exactly** (do not invent a bespoke shape). Rationale:

- `vim.ui.input(opts, on_confirm)` is *the* nvim ≥0.11 idiom for this, and it is **overridable** —
  plugins like `dressing.nvim`/`snacks.nvim`/`telescope`'s input picker replace the default
  floating/cmdline behavior with a nicer UI, entirely transparently, *if and only if* awiwi calls
  `vim.ui.input` itself rather than shelling straight to `vim.fn.input`.
  Confirmed by reading nvim's own default implementation (`$VIMRUNTIME/lua/vim/ui.lua`,
  `M.input`): the **default**, unoverridden implementation is itself just
  `local ok, input = pcall(vim.fn.input, opts); on_confirm(ok and input or nil)` — i.e. it is
  synchronous today out of the box (blocks exactly like vimscript's `input()` does), and only
  becomes truly async if the user has an overriding plugin installed. So porting to
  `vim.ui.input` costs nothing in the common case (no override installed: behaves identically to
  today, blocking) and gains real UX if the user does have one installed — there is no downside to
  taking the idiomatic path here.
  - Implication for `opts.completion`/`opts.highlight`: since the default impl forwards `opts`
    straight to `vim.fn.input`, the vimscript `input()`-dict-style `completion`/`highlight` keys
    keep working *by default*. They will stop working if an overriding UI plugin ignores them —
    document as a known limitation, not a regression to fix.
- The `awiwi.util.input(prompt, opts)` -> string **synchronous return-value** shape cannot be
  faithfully preserved once `vim.ui.input` is overridden (that's the whole point of overriding it —
  the UI becomes non-blocking, e.g. a floating window the user fills in later). Shimming with
  `vim.fn.input` directly instead of `vim.ui.input` would preserve the sync signature perfectly but
  permanently forecloses the override story and isn't "the nvim way" for a ≥0.12-targeted rewrite.
- **Action item for T5 (asset) and the façade (T9/T10), not T4**: `s:create_asset`'s url-branch
  (#1) and `create_asset_link`'s two-prompt sequence (#2+#3) need to become nested callbacks
  (`M.input(o1, function(name) ... M.input(o2, function(file) ... end) end)`), and
  `edit_meta_info` (#4/#5) and `export_drawio_diagram` (#6) need their tail logic moved into the
  `on_confirm` callback. This is real, non-trivial control-flow surgery — call it out explicitly
  in those modules' port briefs so it isn't missed; **T4 itself only needs to ship the `input`
  primitive**, not fix up every caller (those live in modules not yet ported).
- `util_spec.lua` for T4 should test `M.input` by stubbing `vim.ui.input` (it's a plain global
  function, trivially replaceable in a test) and asserting: (a) `opts.prompt` gets set to the
  first positional arg, (b) a bare `opts.completion` value gets the `'customlist,'` prefix added
  exactly like the vimscript version, (c) an already-`'customlist,...'` value is left untouched,
  (d) the callback receives whatever the stub passes to `on_confirm`, including `nil` (cancel).

---

## Bugs found

- **B-util-1 — `input()`, Ctrl-C leaves `text` unset, mis-reported error** (`util.vim:160-168`).
  The `catch /Interrupted/` branch is empty (intentionally swallows the interrupt) but the
  `let text = input(opts)` assignment never completed, so `return text` on the next line hits
  `E121: Undefined variable: text` — **confirmed by repro** (structurally identical harness):
  a Ctrl-C during the prompt produces a confusing "undefined variable" error instead of a clean
  cancel-return. **Recommendation: fix in port.** `vim.ui.input`'s `on_confirm` already receives
  `nil` on abort/cancel (see quoted doc comment: "`input` is what the user typed ... or `nil` if
  the user aborted") — so the Lua port gets this right "for free" as long as `on_confirm` is
  called with whatever `vim.ui.input` passes through, without trying to coerce `nil` into `''`
  first. Do not add a bespoke try/catch translating a cancel into an error.

- **B-util-2 — `split_link_and_anchor` throws on 0 or 2+ `#` in target** (`util.vim:227-232`,
  reachable via both `as_link` and `get_link_under_cursor`). `let [link, anchor] =
  a:link->split('#')` requires the split to produce **exactly 2** elements. Confirmed by repro:
  a target with a trailing/leading `#` and nothing on the other side (e.g. `'a#'`, `'#b'`, `'#'`)
  splits to a 1-or-0-element list -> `E688: More targets than List items`; a target with 2+ `#`
  characters (e.g. `'a#b#c'`) splits to 3+ elements -> `E687: Less targets than List items`. Only
  the single-`#`-with-non-empty-both-sides case (`'foo#bar'`) works. **What was intended:** split
  on the *first* `#` only, defaulting anchor to `''` when there is no `#` at all. **Recommendation:
  fix in port** — implement as "find first `#`, if none return `{target, ''}`, else return
  `{target[:idx-1], target[idx+1:]}`" (Lua: `string.find(target, '#', 1, true)` then two
  `string.sub` calls) — this also naturally handles 0-`#` and multi-`#` inputs without throwing,
  which is unambiguously better behavior and matches what a caller building a markdown link
  `[text](path#anchor)` would expect.

- **B-util-3 — `determine_link_type`'s journal branch is missing `> -1`** (`util.vim:249`):
  `elseif match(link.target, '...')` uses the raw integer return of `match()` as a boolean instead
  of comparing it, unlike every other branch in the same `elseif` chain (which all correctly write
  `match(...) > -1`). Vimscript truthiness treats any non-zero integer as true, so:
  - no match -> `match()` returns `-1` -> **truthy** -> branch **fires** (wrong: non-journal-
    looking targets get mislabeled `'journal'`). Confirmed:
    `determine_link_type(as_link('random-non-matching-target')).type == 'journal'`.
  - match found starting at index 0 -> `match()` returns `0` -> **falsy** -> branch **does not
    fire** (wrong: a target like `/2024-01-01.md` that *does* match the journal pattern right at
    the start is left unclassified, `type == ''`). Confirmed via direct repro.
  - match found at index > 0 -> returns a positive int -> truthy -> fires (this is the only case
    that "accidentally" behaves as intended).
  Net practical effect on the shipped path: since this is the last `elseif` in the chain, almost
  every link that isn't http(s)/mailto/other-scheme/recipe/asset gets typed `'journal'` today —
  i.e. the classifier is much closer to "default everything else to journal" than "only journal
  paths are journal". **Recommendation: fix in port** — this is a one-token fix (`> -1`) with an
  unambiguous, clearly-more-correct target behavior, and no caller is observed relying on the
  broken behavior (both `awiwi.vim` call sites just consume `link.type` to decide how to open/
  insert the link — `'journal'` vs `''` change which branch of `awiwi#open_file`-adjacent code
  runs, which is exactly the kind of behavior change that deserves an ADR sign-off since it's
  user-visible; flag it, don't silently ship a different classification without the human
  noticing). Preserve the *default*-to-journal *fallback* concept if desired, but do it
  explicitly (an actual `else` clause), not via an unguarded `match()` truthiness bug.

- **B-util-4 — `get_resource`'s error path calls an undefined function** (`util.vim:82`):
  `throw s:AwiwiTaskError(...)` — no `s:AwiwiTaskError` is defined anywhere in `util.vim` (it's a
  copy-paste leftover, presumably from `task.vim`'s equivalent helper). The file *does* define an
  unused `s:AwiwiUtilError` right above it (`util.vim:62-71`) that was clearly meant to be called
  here instead. As shipped, hitting a missing resource throws `E117: Unknown function:
  s:AwiwiTaskError` instead of the intended `"AwiwiUtilError: resource does not exist: ..."`
  message. **Recommendation: fix in port** (trivial — use the error-formatting helper that's
  already there), but low priority since `get_resource` itself is group-C (dao/task-only, deferred
  — see Scope recommendation).

- **B-util-5 — `get_iso_timestamp` defined twice** (`util.vim:95` and `:100`), both bodies
  byte-identical (`return strftime('%F %T')`). Vimscript's `fun!` (bang) allows silent
  redefinition, so **the second definition (line 100) wins** at runtime per last-definition-wins
  semantics — but since the two bodies are identical, this has **zero observable effect** on
  behavior either way. **Recommendation: fix in port** — collapse to a single function
  (`os.date('%Y-%m-%d %H:%M:%S')` in Lua), no behavior decision needed, just dedupe the source.

- **B-util-6 — `unique()` never deduplicates** (`util.vim:120-136`): the `set` dict is declared
  (`let set = {}`) but **never populated** — no `set[el.id] = 1`-style write exists anywhere in the
  function body. `has_key(set, el.id)` is therefore always `false`, so every element from every
  input list is appended to the result, duplicates and all. Confirmed by repro:
  `unique([{id:1},{id:1},{id:2}], [{id:1},{id:3}])` -> `[{id:1},{id:1},{id:2},{id:1},{id:3}]` (5
  elements, 3 unique ids — no dedup happened at all). **Recommendation: fix in port if/when
  revived** (populate `set[el.id] = true` right after each `add()`), but this is group-C
  (dao.vim-only, deferred) — not required for T4.

- **B-util-7 — `awiwi#util#has_element` (public) doesn't exist; only script-local `s:has_element`
  does** (`util.vim:110-117`), yet `dao.vim:395` calls `awiwi#util#has_element(...)`. This throws
  `E117: Unknown function` on the only call site that exists. `s:has_element` itself is otherwise
  dead within `util.vim` (the logic it implements was reimplemented, badly — see B-util-6 — inline
  in `unique` instead of delegating to it). **Recommendation: drop** — group-C/dao-only, and even
  dao.vim's own call to it is already broken, so there is nothing "shipped" to preserve. If a
  future `dao` ADR revives this, decide then whether `has_element` should exist as a real public
  fn or stay `unique`'s private helper.

- **Already tracked in `docs/architecture.md`** (not repeated in full here, just cross-referenced):
  the `get_visual_selection` invalid-tuple-syntax bug and the duplicate `get_iso_timestamp` — both
  resolved above (B-util-5 and the next paragraph).

- **`get_visual_selection` — invalid tuple syntax + always-firing `echoerr`** (`util.vim:277-303`,
  architecture.md-flagged, **zero call sites anywhere in the repo** — group B). Two independent
  problems:
  1. `let line0, col0 = getpos("'<")[1:2]` (`util.vim:282`) is not valid vimscript at all — the
     correct destructuring syntax needs brackets: `let [line0, col0] = ...`. Confirmed by repro:
     sourcing/parsing this exact line raises `E121: Undefined variable: line0` immediately followed
     by `E488: Trailing characters: , col0 = [1,2]` — i.e. vimscript parses `let line0` as a
     (failing) variable-print statement and treats `, col0 = ...` as garbage, it does **not**
     parse as multi-assignment. Because vimscript function bodies aren't fully validated until the
     line actually executes, this only surfaces the moment `get_visual_selection` is actually
     called while `mode() ==? 'v'` — which never happens today (no caller). What was intended:
     `let [line0, col0] = getpos("'<")[1:2]` and `let [line1, col1] = getpos("'>")[1:2]` (matching
     the working pattern used elsewhere in the codebase, e.g. `get_code_block_lines`'s `let
     [start, end] = ...`).
  2. `echoerr mode()` (`util.vim:278`) fires **unconditionally on every call**, before the
     `mode() !=? 'v'` guard even runs — this looks like a leftover debug statement; as shipped it
     means even a "successful" call (real visual selection, correct mode) still raises/prints an
     error with the current mode as its message.
  Also note the function only handles `mode() ==? 'v'` (charwise visual) explicitly-ish, and
  checks `mode == 'V'` for linewise — but `mode` there is the *builtin function* `mode()`, not a
  local variable (no parens!), so that comparison is comparing a `funcref`/function value to the
  string `'V'`, which is always false — linewise visual selection would silently fall through to
  the "else" (block/mixed) branch instead of the intended whole-line branch. **Recommendation:**
  since there are **zero callers**, this is dead weight either way (see Scope recommendation,
  group B) — default to **dropping** the function from the port. If the human wants a general
  "get visual selection text" helper kept for future mappings, then **fix in port**: correct the
  tuple syntax, remove the stray `echoerr`, and fix the `mode == 'V'` bareword comparison to
  `mode() ==# 'V'`. Do not port the function as-is under either name — it cannot be exercised
  without throwing.

---

## Port notes

- **`jobstart`/`system()`** — none in this module (the only external process anywhere near `util`
  is the redmine-issue URL hardcode in `get_link_under_cursor`, which doesn't shell out). No
  `vim.system` work needed for T4.
- **`luaeval`** — not used in this module.
- **`get_search_engine`/`match_subcommands`** — straightforward, pure, easy TDD targets; the
  `'fuzzy'` engine's scoring (`match_end - match_start`, ascending tie-break) is worth a couple of
  explicit table-driven tests since it's the one non-obvious algorithm in the file.
- **`get_link_under_cursor`/`as_link`/`determine_link_type`** — these are exactly the kind of
  "regex over markdown structure" the skill's idiom table flags for a possible
  `vim.treesitter`/markdown-parser upgrade later, but note the parsing here is over a *single
  line*'s raw text around the cursor (bracket/paren scanning), not block/document structure — a
  treesitter markdown-link node lookup (`inline_link` in the `markdown_inline` grammar, if
  installed) would be strictly more robust than the manual `strridx`/`stridx` bracket-matching, but
  that's a real behavior change (treesitter would reject/accept different malformed-link edge
  cases than the manual scan does) — call it out as an opportunity, not a requirement, and only
  take it if an ADR explicitly signs off on the behavior delta.
- **`input`** — see the dedicated section above; this is the one place in this module where the
  vimscript idiom (`input()`, synchronous) and the nvim-idiomatic replacement (`vim.ui.input`,
  callback-shaped) genuinely diverge in control-flow shape, not just API surface.
- **`get_resource`'s resource-root path** (`fnamemodify(s:script, ':h:h:h')`, i.e. climb from
  `autoload/awiwi/util.vim` up to the plugin root) — if group C is ever revived, the Lua
  equivalent is `vim.fs.dirname` chained 2-3x from `debug.getinfo(1, 'S').source`, or better, have
  the caller pass the plugin root down explicitly (avoids the fragile self-path-sniffing pattern
  entirely) — but again, out of scope for T4.
- **`escape_pattern`/`match_subcommands`** — `vim.startswith`/`vim.pesc`(-ish, though `vim.pesc`
  escapes for *Lua* patterns, not Vim regex — do **not** reach for it here, this module's regex
  targets are Vim's `matchstrpos`-style patterns, which the completion caller (`cmd.vim`, future
  T9) still needs; keep `escape_pattern`'s exact escape-set (`" \t.*\\[]"`) rather than assuming
  `vim.pesc`'s Lua-pattern escape-set matches it (it doesn't — different metachar sets).

---

## Suggested acceptance tests

Group A only (group B dropped, group C deferred — see Scope recommendation):

1. `escape_pattern('a.b*c[d]')` == `'a\.b\*c\[d\]'`; `escape_pattern('')` == `''`.
2. `get_search_engine()` with `vim.g.awiwi_search_engine` unset/`'plain'`/`'bogus'` all -> `'plain'`;
   `'regex'` -> `'regex'`; `'fuzzy'` -> `'fuzzy'`.
3. `get_argument_number('')` == 0; `('Awiwi')` == 0; `('Awiwi ')` == 1; `('Awiwi journal')` == 1;
   `('Awiwi journal ')` == 2; `('Awiwi  journal')` == 1 (double space).
4. `match_subcommands({'journal','jump','asset'}, 'j')` under `search_engine='plain'` ==
   `{'journal','jump'}`; under `'regex'` with `ArgLead='^j'` == `{'journal','jump'}`; under
   `'fuzzy'` with `ArgLead='jn'` == `{'journal'}`; `ArgLead=''` returns all 3 unchanged regardless
   of engine.
5. `input`: stub `vim.ui.input`; assert `opts.prompt` set from first arg; `opts.completion='foo'`
   becomes `'customlist,foo'`; `opts.completion='customlist,foo'` unchanged; `on_confirm(nil)`
   (simulated cancel) is forwarded as `nil`, not coerced to `''` (this is the fix for B-util-1,
   test it explicitly).
6. `window_split_below()` — hard to unit test without controlling window dims; acceptable to test
   the formula directly (`width/height < 3`) against a couple of `nvim_win_get_width/height` stubs
   or real scratch splits of known size.
7. `get_link_under_cursor` — build a scratch buffer with a line `see [text](target#anchor) here`,
   place cursor inside `[text]`, assert `{target='target', type=..., anchor='anchor'}` (with the
   anchor transform applied per #9); also test the `#12345` redmine-WORD short-circuit on a line
   like `see issue #12345 please` with cursor on that word.
8. `as_link('https://example.com')` == `{target='https://example.com', type='', anchor=''}`;
   `as_link('foo#bar')` == `{target='foo', type='', anchor='bar'}`; **post-fix (B-util-2)**:
   `as_link('foo')` == `{target='foo', anchor=''}` (no throw); `as_link('a#b#c')` == `{target='a',
   anchor='b#c'}` or documented equivalent (first-`#`-split, no throw) — pick one and test it,
   whichever the port implements (first-# rule recommended above).
9. `determine_link_type`: `https://x#sec` -> `{type='browser', target='https://x#sec'}`;
   `mailto:a@b.com` -> `{type='mail'}`; `ssh://foo` -> `{type='external'}`;
   `./recipes/foo.md` -> `{type='recipe'}`; `./assets/2024/01/01/foo.md` -> `{type='asset'}`;
   `./journal/2024/01/2024-01-01.md` -> `{type='journal'}`; `./journal/2024/01/2024-01-01.md#some-
   heading` -> `{type='journal', anchor='.*s.*o.*m.*e.*h.*e.*a.*d.*i.*n.*g.*'}`. **Post-fix
   (B-util-3)**: `'random-non-matching-target'` -> `{type=''}` (NOT `'journal'` — this is the
   behavior-change test that proves the fix; flag to human/ADR since it's user-visible).
10. `relativize`: given a fake `path.absolute`/`path.relativize` (stub the dependency, don't
    re-test path's own logic here), assert `relativize('a/b', 'c/d')` calls
    `path.relativize('a/b', path.absolute('c/d'))` in that order; assert the no-`other`-arg case
    uses the current buffer's name.
11. `get_code_block_lines`: scratch buffer with a fenced block; cursor on the fence line itself ->
    `{-1,-1}`; cursor inside with matching open/close fences -> correct `[start,end]` for both
    `inclusive=true` and `inclusive=false`; cursor inside with no closing fence -> `{-1,-1}`.
12. `select_code_block`: same buffer setup, assert visual selection spans the expected lines after
    calling it (check `getpos("'<")`/`getpos("'>")` or mode()).

status: done | blocked: none — full behavioral spec complete; scope split (A live / B drop / C
defer) is a recommendation for the orchestrator to confirm, not a blocker on writing this brief.

---

## Ported

**Lua module:** `lua/awiwi/util.lua` — `local M = {} … return M` shape, `require("awiwi.str")`
(`startswith`) and `require("awiwi.path")` (`absolute`, `relativize`) for the deps already ported
(DRY per SKILL.md — not re-derived). Spec: `tests/util_spec.lua` (52 `it` cases across 11
`describe` blocks). Full suite green: `nvim --clean --headless -l tests/run.lua` → 162 passed, 0
failed (5 files).

**Public API — the 12 group-A (live) functions only, orchestrator-confirmed scope:**
- `M.escape_pattern(pattern) -> string`
- `M.get_search_engine() -> 'plain'|'regex'|'fuzzy'`
- `M.get_argument_number(expr) -> number`
- `M.match_subcommands(subcommands, ArgLead) -> string[]`
- `M.input(opts, on_confirm)` — see signature deviation below
- `M.window_split_below() -> boolean`
- `M.get_link_under_cursor() -> {target, type, anchor}`
- `M.as_link(link: string|table) -> {target, type, anchor}`
- `M.determine_link_type(link) -> table` (copy, not mutating)
- `M.relativize(path, other?) -> string`
- `M.get_code_block_lines(inclusive) -> {number, number}`
- `M.select_code_block(inclusive)`

**Dropped (11 functions, per binding orchestrator directive — not ported):**
- Group B, zero callers anywhere: `join_nonempty`, `copy_code_block`, `get_visual_selection`
  (the last also invalid vimscript syntax — see brief's Bugs section).
- Group C, dao.vim/task.vim-only (both dead/unreachable from `:Awiwi`): `get_resource`,
  `empty_resources_cache`, `get_iso_timestamp` (also a duplicate-definition bug in the vimscript
  source, B-util-5 — moot now, dropped entirely rather than deduped), `get_epoch_seconds`,
  `is_null`, `id_or_null`, `unique`, `has_element` (the public `awiwi#util#has_element` referenced
  by dead `dao.vim` never existed in the first place — B-util-7).

**Bugs fixed in port:**
- **B-util-1** (`input`, Ctrl-C leaves `text` undefined) — moot by construction: `M.input` forwards
  `on_confirm` straight through to `vim.ui.input`, which already calls back with `nil` on
  abort/cancel. No bespoke try/catch added. Regression-tested explicitly (`on_confirm(nil)` is
  forwarded as `nil`, not coerced to `''`).
- **B-util-2** (`as_link`/`get_link_under_cursor` throw on 0 or 2+ `#` in target) — local
  `split_link_and_anchor` now finds the *first* `#` only (`string.find(..., 1, true)` + two
  `string.sub` calls); no `#` → empty anchor, 2+ `#` → only the first splits, rest stay in the
  anchor. Never throws. Tested: `as_link('foo')`, `as_link('a#b#c')`.
- **B-util-3** (`determine_link_type`'s journal branch missing `> -1`, mislabeled almost everything
  'journal') — fixed to `vim.fn.match(...) > -1`, matching every other branch in the chain.
  **User-visible behavior change**, flagged per the brief: a target like `'random-non-matching-
  target'` now correctly stays `type=''` instead of being mislabeled `'journal'`. Regression-tested
  explicitly, and confirmed by temporarily re-breaking the fix during review — the test caught it.
- **B-util-4/-5/-6/-7** — all group-C (dao/task-only), not applicable: the functions they live in
  were dropped wholesale rather than fixed, since there is no reachable caller to preserve behavior
  for.

**`input` signature deviation from the vimscript original (binding orchestrator ruling):**
`awiwi#util#input(prompt, opts)` (positional prompt string + optional dict, synchronous return) is
**not** preserved. The Lua port is `M.input(opts, on_confirm)`, mirroring `vim.ui.input`'s own
signature exactly — `opts.prompt` is set by the *caller* (no separate positional prompt arg), and
the result is delivered async via `on_confirm` rather than returned synchronously. Rationale (full
derivation in the brief's "Callers of `awiwi#util#input`" section): `vim.ui.input` is nvim's
overridable idiom (dressing.nvim/snacks.nvim/etc. can replace the blocking prompt with a UI-driven
one, transparently, only if awiwi calls `vim.ui.input` itself); the default unoverridden
implementation is itself synchronous (`vim.fn.input` under the hood), so this costs nothing in the
common case and gains real UX when an override is installed. `M.input` still applies the
`completion`-bare-value → `'customlist,...'` rewrite convenience.

**Migration pattern for T5 (asset) and T9/T10 (cmd façade) — required control-flow surgery, not
done in T4:** every live call site of `awiwi#util#input` (`asset.vim:74,90,109`, `awiwi.vim:785,
801`, `cmd.vim:762`) is currently synchronous ("call input(), then keep using the result in the
rest of the function"). Porting them means moving the post-prompt logic into the `on_confirm`
callback:
```lua
-- before (vimscript-shaped, synchronous):
-- let name = awiwi#util#input('asset name: ', {})
-- let default_filename = slugify(name)
-- let file = awiwi#util#input('asset file: ', {'default': default_filename})
-- ... use file ...

-- after (Lua, nested on_confirm):
util.input({ prompt = "asset name: " }, function(name)
  if not name then return end -- cancelled
  local default_filename = slugify(name)
  util.input({ prompt = "asset file: ", default = default_filename }, function(file)
    if not file then return end
    -- ... use file ...
  end)
end)
```
`asset.vim`'s `create_asset_link` (prompts #2+#3) is the one genuinely *sequential* case (prompt
#2's default depends on prompt #1's answer) — it needs exactly this nested shape. The other four
call sites (single prompt each) just need their tail logic (JSON manipulation, buffer writes,
`jobstart` argv construction) moved inside a single `on_confirm`. Every site must also now treat
`nil` (not `''`) as the cancel signal, per the B-util-1 fix.

**Other deviations from a literal transliteration:**
- `get_link_under_cursor`'s manual bracket/paren scanning (`strridx`/`stridx`) is preserved as-is
  rather than upgraded to a treesitter `inline_link` node lookup — per the brief's Port notes, this
  is flagged as a future opportunity requiring an explicit ADR (different malformed-link edge
  cases would be accepted/rejected), not taken here. Local `strridx`/`stridx` helpers replicate
  vimscript's 0-indexed byte-offset semantics exactly (verified against a worked example with
  `[text](target#anchor)`) rather than reasoning about Lua's 1-indexed `string.find` inline at
  every call site.
- `determine_link_type`'s scheme/recipe/asset/journal checks use `vim.fn.match` with the original
  Vim-regex pattern strings verbatim (not hand-translated to Lua patterns) — the journal pattern's
  optional groups (`\(journal/\)\?...`) have no clean Lua-pattern equivalent (Lua patterns lack
  group-level quantifiers), so reusing Vim's own regex engine via `vim.fn.match` avoids a
  translation-risk rewrite for a single-line/non-structural match; `mailto:` uses
  `str.startswith` (pure, no regex needed for a literal prefix).
- The anchor "fuzzy heading search" transform collapses the vimscript original's two chained
  `substitute()` calls (one with a redundant/functionally-inert alternation branch, one
  interleaving `.*`) into a single `gsub("[^%w_]", "")` + `gsub(".", "%0.*")` pair — verified
  functionally identical (the character-class branch already strips every non-alnum char one at a
  time under global substitution, making the `^#+\s+`-prefix alternative a no-op in practice).
  Verified against the brief's worked example (`'some-heading'` →
  `'.*s.*o.*m.*e.*h.*e.*a.*d.*i.*n.*g.*'`).
- `get_code_block_lines`'s `echoerr` (non-throwing, prints-only outside an `abort`-propagated catch)
  becomes `vim.api.nvim_err_writeln` — closest idiomatic non-throwing error surface, preserves the
  "prints a message but doesn't interrupt control flow" behavior.
- `window_split_below` uses `vim.api.nvim_win_get_width/height(0)` rather than `vim.fn.winwidth('%')
  /winheight('%')` — equivalent for the current window, more idiomatic nvim API surface, easily
  stubbable in tests (both are plain Lua table fields).
- `relativize`'s no-`other`-arg default uses `vim.api.nvim_buf_get_name(0)` rather than
  `expand('%')`, per the brief's explicit behavior-preserving-equivalent note (avoids relying on
  the current *window's* buffer if ever called from a non-current-window context).

**Test count:** 52 `it` cases (escape_pattern: 4, get_search_engine: 5, get_argument_number: 6,
match_subcommands: 4, input: 4, window_split_below: 2, as_link: 6, determine_link_type: 9,
get_link_under_cursor: 4, relativize: 2, get_code_block_lines/select_code_block: 6).

status: done | commit: (pending — see task-runner commit step)
