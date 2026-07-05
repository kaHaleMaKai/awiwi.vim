# lua-port / asset

**Responsibility:** Create, name, link, and open "asset" files (images, drawio diagrams,
pasted clipboard content, arbitrary downloads) stored under
`<g:awiwi_home>/assets/{year}/{month}/{day}/{name}`, and insert markdown links to them
into the current buffer at the cursor.

**Source:** `autoload/awiwi/asset.vim` (246 lines). `docs/architecture.md` row (line 48):
"create/open/link assets under `assets/YYYY/MM/DD/`; clipboard image paste; drawio template
(`pyx` for random id)" — confirmed accurate.

## Public surface (`awiwi#asset#*`)

1. `awiwi#asset#create_asset_here_if_not_exists(type, [opts={}]) -> filename:string|nil`
   - `type` is one of the three string constants owned by this module (see Port notes:
     cycle break). `opts` forwarded to `create_asset_link` (currently only `name` is read
     by callers; `suffix` is force-set to `.png` when `type == 'paste'`).
   - Computes `[name, filename, link]` via `create_asset_link(opts)` (prompts user twice —
     see below). Computes target path via `get_asset_path(date.get_own_date(), filename)`.
   - If the file does not already exist (`filereadable`), creates it (see
     `s:create_asset` below); on failure, `echoerr`s and returns `nil` (early return, no
     filename).
   - If `filename` matches `\.(jpe?g|gif|png|bmp)$` (case-sensitive apart from the `e?`
     optionality, no `i` flag — `.JPG` does NOT match), overwrites `link` with an absolute
     markdown-image embed: `![name](/assets/{date}/{filename})` where `date` is
     `awiwi#date#get_own_date()` re-evaluated at this point (not the date baked into
     `path`). Non-image / non-matching files instead keep the *relative* link produced by
     `create_asset_link`.
   - Always calls `awiwi#insert_link_here(link)` (skipped only if the user aborted naming,
     in which case `link == ''` and an empty string is inserted at the cursor — see Bugs).
   - Returns `filename` (may be `''` if the user aborted).
   - **Errors:** any exception from `awiwi#date#get_own_date()` propagates uncaught — this
     throws `AwiwiDateError` ("not on journal or asset page") whenever the current buffer
     is not a journal file or an asset file. Effectively: this command only works when
     invoked from a journal or an existing asset buffer.

2. `awiwi#asset#create_asset_link([opts={}]) -> [name, filename, link_text]:string,string,string`
   - Reads `opts.name`; if empty, blockingly prompts the user via `awiwi#util#input('asset
     name: ')` (wraps Vim's synchronous `input()`).
   - If the (possibly-prompted) name is still empty, `echo`s `[INFO] no asset created` and
     returns `['', '', '']` — this is the "user aborted" sentinel throughout the module.
   - Derives a default filename by lower-casing runs of uppercase letters, collapsing
     whitespace runs to `-`, then stripping every character not in
     `[-a-z0-9.:+]` — see exact regex chain below, this is NOT a generic slugify (it does
     not strip already-lowercase symbols like `_`, does not collapse repeated `-`, does
     not trim leading/trailing `-`).
   - Prompts again: `awiwi#util#input('asset file: ', {default = default_filename ..
     opts.suffix})` — a second blocking prompt, pre-filled, editable by the user. If the
     user clears it (empty string), aborts with the same `['', '', '']` sentinel + info
     message.
   - Computes `date = date.get_own_date()`, `asset_file = get_asset_path(date, filename)`,
     `rel_path = util.relativize(asset_file, expand('%:p'))` (relative to the *current
     buffer's* path, not necessarily the eventual journal it's linked from).
   - Returns `[name, filename, "[escaped_name](rel_path)"]` where `name` has `[` and `]`
     backslash-escaped (`\[`, `\]`) in the link text only; the returned `name` itself is
     unescaped.

3. `awiwi#asset#get_journal_for_current_asset() -> filepath:string`
   - Assumes the current buffer path is `.../assets/{year}/{month}/{day}/{file}`. Takes
     `path.split(expand('%:p:h'))[-3:]` (the 3 path segments directly above the asset file:
     day, but actually `:h` strips the filename first, so the last 3 segments of the
     *directory* are `{year}/{month}/{day}`), joins with `-` to build `{year}-{month}-{day}`,
     and returns `awiwi#get_journal_file_by_date(date)` (delegates to the top-level
     façade, which re-parses the date and builds
     `<journal_subpath>/{year}/{month}/{date}.md`).
   - No existence check — returns a path that may not exist on disk.
   - Bound to buffer-local mapping `gj` in `ftplugin/awiwi.vim:360` (asset -> journal
     navigation), invoked as `:execute 'e ' . awiwi#asset#get_journal_for_current_asset()`.

4. `awiwi#asset#insert_asset_link(date, name, [opts={}]) -> nil`
   - `path = util.relativize(get_asset_path(date, name))` (relative to current buffer,
     single-arg form).
   - `anchor = opts.anchor` (default `''`). If empty: link text is
     `[asset {name}, {date}]({path})`. If present: link text is
     `[asset {name}: {anchor}, {date}]({path}#{anchor})`.
   - Calls `awiwi#insert_link_here(link)` — side effect on current buffer (see below), no
     return value.
   - Called from `cmd.vim:535` for `:Awiwi link asset <date>:<name> [#anchor]`.

5. `awiwi#asset#get_asset_path(date, name) -> path:string`
   - `date` MUST already be in canonical `YYYY-MM-DD` form (this function does `split(date,
     '-')` directly — no parsing/validation; a non-conforming date silently produces a
     malformed or wrong-length path, or an `E688`/index error if the split doesn't yield
     exactly 3 parts consumed by `let [year, month, day] = ...`).
   - Returns `path.join(get_asset_subpath(), year, month, day, name)`, i.e.
     `<g:awiwi_home>/assets/{year}/{month}/{day}/{name}`. Pure function, no I/O.

6. `awiwi#asset#open_asset(name, [opts={}]) -> nil`
   - `date = date.get_own_date()` (current-buffer-derived, throws if not on a journal/asset
     page — see #1). Delegates to `open_asset_by_name(date, name, opts...)`.

7. `awiwi#asset#open_asset_by_name(date, name, [opts={}]) -> nil`
   - `date = date.parse_date(date)` (normalizes relative forms like `'today'`, `'prev'`,
     etc. — unlike `get_own_date`, this one *parses* rather than reads-from-buffer).
   - `path = get_asset_path(date, name)`; ensures parent dir exists
     (`mkdir(dir, 'p')` if `!filewritable(dir)`) — note: **creates the directory even when
     only opening/reading**, not just when creating.
   - `awiwi#open_file(path, options)` — opens (`:edit`/split/tab per `options.new_window`
     etc; if extension is in `s:xdg_open_exts`, shells out to `xdg-open` via `jobstart`
     instead of opening a Vim buffer, and returns without further action).
   - Then unconditionally runs bare `write` — **writes/creates the file on disk on every
     open**, even for a pure read (see Bugs: this means every "open" of a
     not-yet-existing asset silently creates an empty file; for an existing file it's a
     no-op re-save unless `nomodifiable`/readonly, in which case it errors).
   - Called from `cmd.vim:522` (`asset create ... +new` etc., after creating) and
     `cmd.vim:537` (`link/open asset <date>:<name>`, no `link` flag).

8. `awiwi#asset#open_asset_sink(expr) -> nil`
   - `expr` is `"date:name"` (colon-joined, e.g. from an fzf source line). Splits on `:`
     and delegates to `open_asset_by_name(date, name)`. Currently **only wired in a
     commented-out fzf sink** (`cmd.vim:501-502`) — dead in the shipped binary today, but
     the function itself is exported/live and will become the telescope picker's `sink`
     callback in T9 (see `plan-the-migration…`: "Pickers … new lua/awiwi/picker.lua …").
     Keep it; do not drop.

9. `awiwi#asset#get_all_asset_files() -> [{date: "Y-M-D", name: string}, ...]`
   - `glob('<g:awiwi_home>/assets/2*/**', nosuf=false, list=true)`, filtered to
     `filereadable` entries only (directories excluded).
   - **Reads `g:awiwi_home` directly** rather than via `awiwi#get_asset_subpath()` (see
     Bugs — currently equivalent in value since `s:asset_subpath = path.join(g:awiwi_home,
     'assets')`, but it's a duplicated/hardcoded assumption).
   - Each match path is split on `/` and the last 4 segments taken: `[year, month, day,
     name]`; result `{date = "year-month-day", name = name}`. Implicitly assumes the asset
     tree is always exactly 3 levels deep (`year/month/day/file`) with no further
     subdirectories or the mapping silently produces a wrong date/name.
   - Sorted via `s:compare_asset_files(f1, f2, reverse=false)`: **ascending by date
     (lexicographic string compare, which is correct for zero-padded `Y-M-D`), then
     ascending by name**, both purely by Lua/Vimscript string `>`/`<` (lexicographic, not
     locale-aware).
   - Called from `cmd.vim:388` (asset name completion) and the commented-out fzf source at
     `cmd.vim:501`.

### Script-local (non-exported) helpers — behavior only, not part of the public surface

- `s:get_random_string(length)` — see Bugs B4. On the *first* invocation per Neovim
  session, evaluates a Python 3 (`pyx`) snippet defining `get_random_string(length)` (uses
  `base64.encodebytes(random.randbytes(length))` then truncates the base64 *text* to
  `length` **characters**, not `length` random bytes worth of entropy — the truncation
  happens after encoding, so the effective entropy is less than `6*length` bits and the
  charset is base64's `A-Za-z0-9+/=` plus embedded newlines every 76 chars (`encodebytes`
  wraps lines) which can leak a literal `\n` into the "random string" for `length > 76`).
  Only call site: `s:get_file_template('drawio')` uses `s:get_random_string(20)` to build a
  drawio `<diagram id="...">` attribute.
- `s:get_file_template(extension)` — returns a list of lines: for `extension == 'drawio'`,
  a minimal single-page drawio XML skeleton with a random `id`; for anything else, `[]`
  (empty file).
- `s:create_asset(type, path)` — ensures parent dir exists; dispatches on `type`:
  - `empty` (`get_cmd('empty_asset')`): `writefile(get_file_template(ext), path)` where
    `ext = fnamemodify(path, ':e')`.
  - `url` (`get_cmd('url_asset')`): blockingly prompts `awiwi#util#input('url: ')`; if
    empty, returns `false` (abort, no error message); else shells out to
    `awiwi#download_file(path, url)` (`curl --no-progress-meter <url> -o <path>`,
    `v:shell_error`-gated, `echoerr`s and returns `false` on failure).
  - `paste` (`get_cmd('paste_asset')`): `awiwi#paste_file(path)` — guesses the X clipboard
    MIME type via `xclip -selection clipboard -o -t <type> | file --mime-type -` (probing
    `text/plain`, `image/jpg`, `image/png`, `image/gif`, `image/bmp` in order, first
    non-empty wins), then `xclip -selection clipboard -t <type> -o > <path>` via a
    **string-joined `system()` call** (shell redirection `>` embedded in the command
    string — requires a real shell, uses `shellescape` only on the filename).
  - any other `type`: returns `true` (no-op "success" — silently does nothing, is treated
    by the caller as "file created OK").
- `s:get_asset_under_cursor(accept_date)` — see Bugs B5. **Dead code** (verdict below).
- `s:compare_asset_files(f1, f2, reverse)` — three-way string comparator described under
  `get_all_asset_files` above.

## Reads/writes

- **Globals:** `g:awiwi_home` (read, in `get_all_asset_files` only — everywhere else via
  `awiwi#get_asset_subpath()`), `g:autoloaded_awiwi_asset` (source-guard), script-local
  `s:get_random_string_is_defined` (guards one-time `pyx` snippet definition; this is the
  root of B4).
- **Files:** creates asset files under `<g:awiwi_home>/assets/{Y}/{M}/{D}/{name}` (via
  `writefile`, `curl -o`, `xclip … > file`, or a bare `write` in `open_asset_by_name`);
  creates directories with `mkdir(dir, 'p')`.
- **Buffers/windows:** `awiwi#insert_link_here` mutates the current buffer's current line
  and cursor position directly (`getline`/`setline`/`setpos`, no undo-block wrapping of
  its own — relies on Vim's normal undo grouping); `awiwi#open_file` may `:new`/`:vnew`/
  `:tabnew` a window; `open_asset_by_name` always issues a bare `write` after opening.
- **Registers:** none directly (clipboard access is via the external `xclip` binary, not
  Vim's `+`/`*` registers).

## External

- **Binaries shelled to:** `curl` (download), `xclip` (paste — reads clipboard twice: once
  to probe MIME type, once to pipe into the file), `file` (MIME sniffing), `xdg-open`
  (opening non-editable asset types, via `awiwi#open_file`/`jobstart`, not in asset.vim
  itself but reachable through `open_asset_by_name`).
- **Python:** `pyx`/`pyxeval` (`awiwi.vim:13-20` region) for `get_random_string` — see B4
  and Port notes (must become pure Lua).
- **Other awiwi modules called:** `awiwi#util#input`, `awiwi#util#relativize`,
  `awiwi#date#get_own_date`, `awiwi#date#parse_date`, `awiwi#path#join`, `awiwi#path#split`,
  `awiwi#get_asset_subpath`, `awiwi#get_journal_file_by_date`, `awiwi#insert_link_here`,
  `awiwi#download_file`, `awiwi#paste_file`, `awiwi#open_file`. All of these live in
  `autoload/awiwi.vim` / `autoload/awiwi/{util,date,path}.vim` — none is `cmd.vim`.
- **VimL plugin deps:** none directly (no `fzf#`/`telescope` calls inside asset.vim itself
  — those live in `cmd.vim`, which *calls into* asset.vim, not the reverse, except for the
  4 `get_cmd` calls below).

## Call sites (asset -> cmd, the cycle to break)

Exactly 4 calls from `asset.vim` into `awiwi#cmd#get_cmd(...)`, all returning bare string
constants (verified against `cmd.vim`'s `s:*_cmd` table):

| asset.vim line | call | resolves to (cmd.vim) |
|---|---|---|
| `asset.vim:41` | `awiwi#cmd#get_cmd('paste_asset')` | `s:paste_asset_cmd = 'paste'` |
| `asset.vim:69` | `awiwi#cmd#get_cmd('empty_asset')` | `s:empty_asset_cmd = 'empty'` |
| `asset.vim:73` | `awiwi#cmd#get_cmd('url_asset')` | `s:url_asset_cmd = 'url'` |
| `asset.vim:79` | `awiwi#cmd#get_cmd('paste_asset')` | `s:paste_asset_cmd = 'paste'` (2nd use) |

`awiwi#cmd#get_cmd(name)` itself (`cmd.vim:181-187`) is a trivial lookup:
`get(s:, name .. '_cmd')`, throwing `AwiwiCmdError` if undefined — i.e. it's a namespaced
string-constant table, nothing more. Confirms the task's premise: safe to hoist these 3
constants (`empty`, `url`, `paste`) into asset's own module table.

### Call sites INTO asset.vim (for the engineer's regression-test surface, not part of the contract)

- `ftplugin/awiwi.vim:360` — `gj` mapping -> `awiwi#asset#get_journal_for_current_asset()`
- `autoload/awiwi.vim:745` — `awiwi#asset#create_asset_here_if_not_exists(awiwi#cmd#get_cmd('paste_asset'))` (a `<C-v>`-style insert-mode paste mapping, per architecture.md line 96)
- `autoload/awiwi/cmd.vim:318` — `awiwi#asset#get_asset_path(date, name)`
- `autoload/awiwi/cmd.vim:388` — `awiwi#asset#get_all_asset_files()` (name completion)
- `autoload/awiwi/cmd.vim:498,514,516` — `awiwi#asset#create_asset_here_if_not_exists(...)`
- `autoload/awiwi/cmd.vim:520` — `call('awiwi#asset#create_asset_here_if_not_exists', args)`
- `autoload/awiwi/cmd.vim:522` — `awiwi#asset#open_asset(filename, {'new_window': v:true})`
- `autoload/awiwi/cmd.vim:535` — `awiwi#asset#insert_asset_link(date, file, options)`
- `autoload/awiwi/cmd.vim:537` — `awiwi#asset#open_asset_by_name(date, file, options)`
- `autoload/awiwi/cmd.vim:501-502` — `awiwi#asset#get_all_asset_files()` /
  `awiwi#asset#open_asset_sink` — **commented out**, dead in the shipped `:Awiwi` command
  today; do not treat as a live acceptance-test surface, but keep the functions (T9 wires
  a telescope picker to them).

## Behavior contract (numbered, testable)

1. `get_asset_path('2026-07-05', 'foo.png')` returns
   `<g:awiwi_home>/assets/2026/07/05/foo.png` (pure function, no filesystem access).
2. `get_asset_path` with a malformed date (not exactly 2 `-` separators) errors (mirrors
   vimscript's list-destructure error) rather than silently producing a wrong path.
3. `create_asset_link({})` on an empty user input for "asset name" returns `('', '', '')`
   and does not touch the filesystem or the buffer.
4. `create_asset_link({name = 'My Recipe Notes'})` derives default filename
   `my-recipe-notes` (uppercase runs lowered, whitespace runs -> `-`, everything outside
   `[-a-z0-9.:+]` stripped) before prompting the user to accept/edit it.
5. `create_asset_link({name = 'Foo [bar]'})` produces link text with the brackets escaped:
   `[Foo \[bar\]](...)`; the returned `name` is untouched (`'Foo [bar]'`).
6. `create_asset_here_if_not_exists('empty', {name=...})` for a not-yet-existing target:
   creates parent directories, writes the file (drawio template if extension is `drawio`,
   else empty file), inserts a relative link at the cursor, and returns the filename.
7. Same as #6 but the target file already exists (`filereadable` true): skips creation
   entirely (no `s:create_asset` call, no "asset created" message), still inserts the
   link, still returns the filename.
8. `create_asset_here_if_not_exists('paste', {name=...})` where the resulting filename
   matches `\.(jpe?g|gif|png|bmp)$` inserts an **embed** link
   `![name](/assets/{date}/{filename})`, not the relative link from step 6/7's `link`
   value; a resulting filename that does *not* match an image extension keeps the relative
   markdown link.
9. `create_asset_here_if_not_exists` invoked outside a journal/asset buffer throws (via
   `date.get_own_date()`) and creates nothing.
10. `insert_asset_link('2026-07-05', 'foo.png')` inserts
    `[asset foo.png, 2026-07-05](<relative-path-to-foo.png>)`.
11. `insert_asset_link('2026-07-05', 'foo.png', {anchor='intro'})` inserts
    `[asset foo.png: intro, 2026-07-05](<relative-path>#intro)`.
12. `open_asset_by_name('2026-07-05', 'foo.png', {})` creates the parent directory if
    missing, opens the file in the current window, and always issues a `write` afterward
    — even if the file did not exist before the call (net effect: an empty file is
    created on disk for a "read"/"open" of a nonexistent asset).
13. `get_all_asset_files()` returns entries sorted ascending by `date` then by `name`;
    each entry is `{date = 'Y-M-D', name = <basename>}`; directories in the glob result
    are excluded.
14. `get_journal_for_current_asset()` called while the current buffer is
    `.../assets/2026/07/05/foo.png` returns the same path as
    `awiwi#get_journal_file_by_date('2026-07-05')`, i.e.
    `<journal_subpath>/2026/07/2026-07-05.md`.
15. `M.types.empty == 'empty'`, `M.types.url == 'url'`, `M.types.paste == 'paste'`
    (see Port notes) — these three values are load-bearing: `cmd.vim`'s existing
    `s:empty_asset_cmd`/`s:url_asset_cmd`/`s:paste_asset_cmd` currently equal exactly
    `'empty'`/`'url'`/`'paste'`; T9 must read them from this table, not redefine them.

## Bugs found

- **B4** — `asset.vim:11-21`, `s:get_random_string`: `if !s:get_random_string_is_defined`
  has no matching `endif` before `endfunction`. **Verified runtime behavior** (repro'd the
  exact if/no-endif/endfunction pattern in isolation against Neovim): sourcing the file is
  fine (Vim does not eagerly validate block balance across the whole function body at
  definition time). The function itself works correctly exactly **once per Neovim
  session** — on the first call the guard is `false` (`!false` = true) so the `if` body
  executes as a straight-line fall-through into `endfunction` with no need to search for a
  closing `endif`. On the **second and every subsequent call** in the same session, the
  guard is now `true` (set at the end of the first call), so `!true` = false, and Vim must
  skip forward looking for a matching `else`/`elseif`/`endif` — finds none before
  `endfunction` — and throws `E171: Missing :endif`, aborting the call (and therefore
  aborting `s:get_file_template('drawio')`, and therefore aborting
  `s:create_asset('empty', <drawio path>)`, and therefore
  `create_asset_here_if_not_exists`, with an unhandled Vim error, not a clean `echoerr`).
  **Net shipped behavior: creating a second `.drawio` asset in the same Neovim session
  throws and fails.** Recommendation: **fix in port** — this is unambiguously a bug, not
  intended behavior, and trivially avoided in Lua (no such block-skipping semantics
  exist). New Lua RNG must not reproduce the "works once" behavior.
- **B5** — `asset.vim:168`, inside `s:get_asset_under_cursor` (marked `FIXME likely
  deprecated` by the original author, line 152): `if !open_bracket_pos == -1`. Vimscript
  unary `!` binds tighter than `==`, so this parses as `(!open_bracket_pos) == -1`. Since
  `open_bracket_pos` is always either `-1` (not found) or a `>= 0` index, `!open_bracket_pos`
  is always `0` (Vim's `!` on any non-zero number, including `-1`, yields `0`; `!0` yields
  `1`... concretely: `!(-1)` = 0, `!(any index >= 0)` = 0 too, since only literal `0` is
  falsy). So the left side is always `0`, and `0 == -1` is always `false` — **the "no open
  bracket found" early-return never fires**, regardless of whether a `[` was actually
  found on the line. Correct intent was presumably `open_bracket_pos == -1`. This function
  is called from **nowhere** — grepped the entire repository, zero call sites (not even
  self-referential), and it is `s:`-local so nothing outside `asset.vim` could call it
  either. **Verdict: dead code.** Recommendation: **drop it in the port** — no caller
  exists today (not `ftplugin/awiwi.vim`, not `cmd.vim`, not any mapping), so nothing
  breaks; if a "jump to asset link under cursor" feature is wanted later it should be
  rewritten (ideally via treesitter markdown-link node lookup at cursor, not manual
  bracket-scanning) rather than un-deprecating buggy code.
- **B-new-1** (not in the plan's pre-assigned list; flagging for `docs/decisions.md` /
  next available `B<n>` slot) — `open_asset_by_name` (`asset.vim:211-212`) always calls
  bare `write` after `awiwi#open_file`, unconditionally, even for a pure "open existing
  asset" call with no edits made. Effect: opening a not-yet-existing asset by name
  silently creates an empty file on disk as a side effect of "opening" it; opening an
  existing read-only/`nomodifiable` asset would error on the `write`. Recommend
  **fix in port**: only write if the buffer didn't already exist / was just created,
  mirroring `create_asset_here_if_not_exists`'s explicit `filereadable` check, or drop the
  auto-write entirely and let normal Vim/Neovim buffer-write semantics apply.
- **B-new-2** (minor, non-behavior-changing) — `get_all_asset_files` (`asset.vim:240`)
  reads `g:awiwi_home` and hardcodes `'assets'` directly in the glob, instead of using
  `awiwi#get_asset_subpath()` like every other function in this module. Currently
  value-identical (`s:asset_subpath = path.join(g:awiwi_home, 'assets')`, fixed at load
  time), so **no observed behavioral divergence today**, but it's a latent inconsistency:
  if a future config layer made `asset_subpath` independently configurable, this function
  would silently ignore the override. Recommend **fix in port**: route through the same
  subpath accessor as everything else (trivial, zero test-visible change expected).
- **Not a bug, but load-bearing edge case to test explicitly**: the image-extension check
  in `create_asset_here_if_not_exists` (`asset.vim:55`) is case-sensitive
  (`\.\(jpe\?g\|gif\|png\|bmp\)$` with no `\c`) — `photo.PNG` does **not** get the embed
  treatment, only the relative link. Preserve this exactly (do not "fix" to
  case-insensitive without an ADR — it changes shipped rendering behavior).

## Port notes

- **Cycle break (binding):** `lua/awiwi/asset.lua` owns
  `M.types = { empty = 'empty', url = 'url', paste = 'paste' }`. Every internal
  `type == awiwi#cmd#get_cmd('empty_asset')`-style comparison becomes
  `type == M.types.empty`, etc. `lua/awiwi/asset.lua` must have **zero** `require`
  of `awiwi.cmd`. T9's `cmd.lua` will `require('awiwi.asset').types` instead of owning its
  own asset-type constants — do not duplicate the strings in cmd.lua.
- **Random string (binding):** replace the `pyx`/`pyxeval` round-trip
  (`asset.vim:13-20`) with pure Lua. Exact contract to preserve for the drawio template's
  `id` attribute: a `length`-character string. It does **not** need to reproduce the exact
  base64-then-truncate algorithm (that was never a meaningful entropy/charset contract —
  see B4 note on base64 newline leakage) — pick a clean charset,
  e.g. `math.random` indexing into `"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"`
  (62 chars, alphanumeric, safe inside an XML attribute with no escaping needed), producing
  exactly `length` characters, called once per `drawio` asset creation (no longer
  "once per session" — that was bug B4, not a contract). Document this exact charset/length
  contract in the Lua module's doc-comment so a future reader doesn't need to diff against
  vimscript. Seed via `math.randomseed(os.time())` once at module load if determinism
  isn't required (nothing in the contract requires reproducibility across runs — only
  uniqueness within a drawio file, which a single `<diagram id>` needs).
- **Async/blocking input — flag for the engineer, not pre-decided here:** `create_asset_link`
  and `s:create_asset`'s `url` branch both call `awiwi#util#input`, which wraps Vim's
  **synchronous, blocking** `input()`. Neovim has both `vim.fn.input()` (same blocking
  semantics, trivial 1:1 port) and `vim.ui.input()` (async, callback-based, the more
  "idiomatic" nvim ≥0.12 choice, and needed if `util.lua`'s T4 port standardizes on it for
  UI consistency with future telescope pickers). **This module's public functions
  currently return synchronously** (`create_asset_link` returns `[name, filename, link]`
  directly). If `util.lua` (T4, a dependency of this module) adopts `vim.ui.input`, every
  asset function in this chain (`create_asset_link` -> `create_asset_here_if_not_exists`
  -> the `url` branch of `s:create_asset`) must invert to callback/coroutine style, which
  changes their **signatures**, not just their implementation. Check `handovers/lua-port/util.md`
  / the shipped `lua/awiwi/util.lua` for the actual decision before starting T5
  implementation — do not decide it here in isolation, since it's a whole-module (T4)
  concern that this module merely inherits.
- **Clipboard paste (`s:create_asset`'s `paste` branch, `awiwi#paste_file` in
  `awiwi.vim:491-504`):** shells out to `xclip` via `vim.system` (not `jobstart`/`system()`
  — per the plan's idiom table). Two sequential external processes (`xclip -o -t <mime> |
  file --mime-type -` for probing, then a second `xclip -o` piped via shell redirection
  into the target file) — this is Linux/X11-only (`xclip`), no Wayland (`wl-paste`) or
  macOS (`pbpaste`) fallback in the vimscript; preserve as Linux/X11-only in the port
  unless the human explicitly wants cross-platform clipboard support added (that would be
  a feature add, not a port, and needs its own ADR).
- **Treesitter opportunity:** `get_journal_for_current_asset` and
  `get_asset_under_cursor` (dead, see B5) both manually parse markdown-link-like syntax
  or infer structure from the buffer path. Not treesitter-relevant themselves (they're
  path/date arithmetic, not buffer content parsing) — no treesitter win here. The
  `[name](path)` link-insertion helpers (`insert_link_here`, upstream in `awiwi.vim`) are
  plain text manipulation via `getline`/`setline`; could use `nvim_buf_set_text` for
  precision instead of full-line rewrite, worth a note for whoever ports
  `awiwi#insert_link_here` (not this module, but a shared dependency called by 3 of this
  module's public functions) — flag for the `awiwi.vim`-façade port brief (T10), not
  actionable here.
- **Ownership boundary:** `awiwi#insert_link_here`, `awiwi#download_file`,
  `awiwi#paste_file`, `awiwi#open_file`, `awiwi#get_journal_file_by_date`,
  `awiwi#get_asset_subpath` all currently live in the `awiwi.vim` façade
  (`autoload/awiwi.vim`), not in `asset.vim`. This brief assumes they'll be ported
  alongside/before the façade (T10) and exposed as e.g. `require('awiwi').insert_link_here`
  etc.; `asset.lua` depends on them but should not re-implement them. If T10 hasn't landed
  by the time T5 executes, stub these as injected dependencies (module-level fields the
  engineer can override in tests) rather than blocking on T10.
- **Module dependency order:** depends on already-ported `str`, `path`, `date`, `util`
  (T1-T4). No dependency on `hi`, `cmd`, `server`, or any dead module.

## Suggested acceptance tests

- `get_asset_path('2026-07-05', 'photo.png')` ==
  `<home>/assets/2026/07/05/photo.png` (with a fixture `g:awiwi_home` / injected config).
- `create_asset_link` with injected `name = 'My Recipe Notes'`, no `suffix` in opts, and a
  stubbed input-provider that echoes the *default* prompt value back: expects derived
  filename `my-recipe-notes` reached the second prompt as the default, and final returned
  `filename == 'my-recipe-notes'`.
- `create_asset_link` with injected empty name (stub declines to provide one): returns
  `('', '', '')`, no filesystem writes, no buffer mutation asserted.
- `create_asset_here_if_not_exists(M.types.empty, {name='drawio test', suffix='.drawio'})`
  against a scratch `g:awiwi_home`: asserts a file is created at the expected path
  containing the drawio XML skeleton with a 20-character `id` attribute value drawn from
  the alphanumeric charset (regex assertion, not exact-string, since it's random).
- Regression test for B4's *fixed* behavior: call the empty-drawio-asset creation flow
  **twice** in the same test process (two different target filenames) and assert **both**
  succeed (this is the regression guard that the vimscript could never pass, since the
  second call throws `E171` in the original).
- `create_asset_here_if_not_exists(M.types.paste, {name='screenshot'})` with `paste_file`
  stubbed to succeed and produce `screenshot.png`: assert the inserted link is the
  `![screenshot](/assets/{date}/screenshot.png)` embed form, not a relative link.
- `create_asset_here_if_not_exists(..., {name='notes.txt'})` (non-image extension): assert
  the inserted link is the plain relative markdown link, not an embed.
- `get_all_asset_files()` against a fixture tree with files inserted out of order on disk:
  assert the returned list is sorted ascending by `date` then `name`.
- `open_asset_by_name` against a nonexistent target: assert parent dir is created; decide
  (per B-new-1's fix-in-port recommendation) whether the acceptance test asserts "no file
  written until actual buffer save" (fixed behavior) rather than the vimscript's
  auto-write — this needs the human's ADR call recorded in `docs/decisions.md` before
  locking the test in as `fix in port` vs `preserve`.
- `insert_asset_link` with and without `anchor`: assert exact link text against the two
  templates in behavior-contract items #10/#11.
- `M.types.empty == 'empty'`, `M.types.url == 'url'`, `M.types.paste == 'paste'` — a
  direct, trivial regression guard against T9 accidentally renaming these.

status: done

---

## Ported

**Lua module:** `lua/awiwi/asset.lua` — `local M = {} … return M`, requires only
`awiwi.path`, `awiwi.date`, `awiwi.util` (T1-T4, already ported). **Zero** `require`
of `awiwi.cmd` — cycle broken per the binding directive. Spec: `tests/asset_spec.lua`
(26 `it` cases across 9 `describe` blocks). Full suite green:
`nvim --clean --headless -l tests/run.lua` → 188 passed, 0 failed (6 files).

**Public API:**
- `M.types = { empty = "empty", url = "url", paste = "paste" }` — owned here (cycle
  break). T9's `cmd.lua` must `require('awiwi.asset').types` rather than redefining
  these strings.
- `M.get_asset_path(date, name) -> path:string` — pure; throws `AwiwiAssetError` on a
  malformed `date` (not exactly 3 `-`-separated parts), mirroring the vimscript
  original's list-destructure `E687`/`E688`.
- `M.create_asset_link(opts, on_done)` — **signature deviation**, see below.
  `on_done(name, filename, link_text)`, all `''` on the "user aborted" sentinel.
- `M.create_asset_here_if_not_exists(type, opts, on_done)` — **signature deviation**.
  `on_done(filename)`: `''` if the user aborted naming, `nil` if asset creation
  itself failed, else the created/existing filename.
- `M.get_journal_for_current_asset() -> filepath:string`
- `M.insert_asset_link(date, name, opts)`
- `M.open_asset(name, opts)`
- `M.open_asset_by_name(date_expr, name, opts)` — B-new-1 fixed, see below.
- `M.open_asset_sink(expr)` — kept live (future telescope-picker sink), throws
  `AwiwiAssetError` on a malformed `"date:name"` expr.
- `M.get_all_asset_files() -> [{date, name}, ...]` — B-new-2 fixed, see below.
- `M.deps` — table of overridable dependency functions (see "Ownership boundary
  stub" below): `get_asset_subpath`, `get_journal_file_by_date`, `insert_link_here`,
  `download_file`, `paste_file`, `open_file`.

**Dropped:** `s:get_asset_under_cursor` (B5) — confirmed dead (zero call sites,
`s:`-local, marked `FIXME likely deprecated` by the original author). Not ported.

**Bugs fixed in port:**
- **B4** (`s:get_random_string`'s missing `endif` — worked once per Neovim session,
  then `E171` on every subsequent `.drawio` asset creation): moot by construction —
  the `pyx`/`pyxeval` round-trip is replaced with a pure-Lua `math.random` draw from a
  62-char alphanumeric charset (`math.randomseed(os.time())` once at module load), a
  fresh `length`-character string on **every** call, no "define once" state at all.
  Regression-tested explicitly: two `.drawio` assets created in the same test process
  both succeed (`asset.create_asset_here_if_not_exists` "B4 regression" test) — a test
  the original vimscript could never pass.
- **B5** (`s:get_asset_under_cursor`'s inverted `!open_bracket_pos == -1` check) —
  moot: the function is dropped entirely (dead code, zero callers).
- **B-new-1** (`open_asset_by_name` always ran a bare `write` after opening,
  unconditionally — silently creating empty files on a pure "open" and erroring on a
  read-only/`nomodifiable` existing asset): **fixed**, per binding orchestrator
  directive. `write` now only runs when the asset did **not** already exist before the
  call (checked via `vim.fn.filereadable` before `M.deps.open_file` runs) — opening an
  existing asset never rewrites it; creating a new one via `open_asset*` is still an
  explicit write, just conditional rather than unconditional. **User-visible behavior
  change — flag for `docs/decisions.md`.** Regression-tested both paths (spy on
  `vim.cmd("write")` via a wrapped `vim.cmd`, confirmed to actually fail without the
  fix by temporarily reverting it during review — the "not-yet-existing" test also
  caught a real bug in that revert, a scratch-buffer `E382` when the fix is missing
  and `open_file` is stubbed, see gotcha below).
- **B-new-2** (`get_all_asset_files` hardcoded `g:awiwi_home .. 'assets'` in its glob
  pattern instead of going through `get_asset_subpath()` like every other function in
  the module): fixed — now calls `M.deps.get_asset_subpath()`. Non-behavior-changing
  (the two were always value-identical), pure consistency fix, no ADR needed.
- **Preserved as-is (load-bearing edge case, not a bug):** the image-extension check
  in `create_asset_here_if_not_exists` stays case-sensitive (`.JPG` does NOT get embed
  treatment) — regression-tested explicitly per the brief's instruction not to "fix"
  this without an ADR.

**Signature deviations from the vimscript original — input-callback restructuring
(binding, inherited from `util.md`'s `M.input(opts, on_confirm)` decision):**
Every vimscript function in this module that (transitively) calls `awiwi#util#input`
returned its result **synchronously**. Since the ported `awiwi.util.input` is
callback-shaped (mirrors `vim.ui.input`, overridable by UI plugins), the two live call
chains had to invert to nested `on_confirm` callbacks:
- `create_asset_link(opts) -> [name, filename, link]` (sync) became
  `create_asset_link(opts, on_done)` where `on_done(name, filename, link)` is called
  once both prompts (or an abort) resolve. This is the module's one genuinely
  *sequential* prompt pair (prompt #2's default depends on prompt #1's answer via
  `derive_default_filename`), so it nests one `util.input` call inside the other's
  callback exactly per the `util.md` migration pattern:
  ```lua
  util.input({ prompt = "asset name: " }, function(name)
    if not name or name == "" then ... return end
    local default = derive_default_filename(name) .. suffix
    util.input({ prompt = "asset file: ", default = default }, function(filename)
      ...
      on_done(name, filename, link_text)
    end)
  end)
  ```
- `create_asset_here_if_not_exists(type, opts) -> filename` (sync) became
  `create_asset_here_if_not_exists(type, opts, on_done)` where `on_done(filename)` is
  called after `create_asset_link`'s callback resolves and (if needed) the internal
  `create_asset` helper's own callback resolves (its `url` branch also prompts via
  `util.input`, for the download URL).
- The internal (non-exported) `create_asset(type, path, on_done)` helper mirrors
  `s:create_asset`, callback-shaped for the same reason (`url` branch prompts).
- **For T9 (cmd façade):** any `:Awiwi asset create ...`/`:Awiwi link asset ...`
  command handler calling into these two functions must pass an `on_done` callback and
  move its post-creation tail logic (e.g. echoing a status line, chaining into another
  command) inside that callback, exactly per the pattern above — there is no
  synchronous return value to fall back on.
- All other public functions (`get_asset_path`, `get_journal_for_current_asset`,
  `insert_asset_link`, `open_asset`, `open_asset_by_name`, `open_asset_sink`,
  `get_all_asset_files`) never touch `util.input` and keep their **synchronous**
  vimscript-shaped signatures unchanged.

**Ownership-boundary stub (`M.deps`) — not part of this module's behavior contract:**
`insert_link_here`, `download_file`, `paste_file`, `open_file`, `get_journal_file_by_date`
and `get_asset_subpath` all live in the not-yet-ported `awiwi.vim` façade (T10). Per the
brief's explicit instruction ("stub these as injected dependencies... rather than
blocking on T10"), `M.deps.*` holds minimal, standalone-usable default implementations:
- `get_asset_subpath`/`get_journal_file_by_date` — pure `path.join` arithmetic against
  `vim.g.awiwi_home`, functionally equivalent to the façade's own versions.
- `insert_link_here` — a byte-faithful port of `awiwi#insert_link_here`'s
  `getcurpos`/`getline`/`setline`/`setpos` dance onto `nvim_win_get_cursor`/
  `nvim_get_current_line`/`nvim_set_current_line`/`nvim_win_set_cursor`.
- `download_file`/`paste_file` — `vim.system` (not `jobstart`/`system()`, per the
  idiom table), same `curl`/`xclip`/`file` external-process shape as the vimscript
  original, but using `vim.system`'s piping instead of a shell-redirection string join
  for the `xclip -o | file --mime-type -` and `xclip -o > path` steps.
- `open_file` — deliberately minimal (`:edit path` only); the vimscript original's
  richer split/tab/position/anchor/`xdg-open` option handling is explicitly out of
  scope here (façade's job, T10) — overriding this field is expected once T10 lands.
Tests stub these fields directly (`asset.deps.insert_link_here = function(...) ... end`,
restored after each test) rather than exercising the real subprocess/buffer defaults,
per the brief's guidance to keep TDD budget on this module's own contract.

**Deviation not flagged as a "Bug found" in the brief:** when `create_asset_link`
returns its `''`/`''`/`''` "user aborted" sentinel, `create_asset_here_if_not_exists`
now short-circuits immediately (insert the empty link, `on_done('')`) rather than
continuing on — as the vimscript original unconditionally does — to compute
`get_asset_path(get_own_date(), '')`/`filereadable`/`s:create_asset` with an empty
filename. This unflagged latent quirk isn't covered by any brief bug entry or
contract item (`create_asset_link`'s own contract calls `''`/`''`/`''` "the user
aborted sentinel throughout the module"); the port keeps that sentinel's meaning
consistent everywhere rather than reproducing the unexercised original code path.
Low-risk, but noting for the record since it's a behavior delta from a literal
transliteration.

**Test count:** 26 `it` cases across 9 `describe` blocks (`asset.types`,
`get_asset_path`, `create_asset_link`, `create_asset_here_if_not_exists`,
`insert_asset_link`, `get_journal_for_current_asset`, `open_asset_by_name`,
`open_asset_sink`, `get_all_asset_files`). Uses `vim.fn.tempname()`-backed
`g:awiwi_home` fixtures for every filesystem-touching test (never the real home);
`with_named_buffer`/`with_home` helpers isolate buffer/window/global state per test.

**Gotcha for future test-writers on this module:** stubbing `M.deps.open_file` to a
no-op while leaving `open_asset_by_name`'s "not-yet-existing asset" write path live
will try to `:write` whatever buffer happens to be current at the time (since the real
`open_file` default is what makes `:write` target the right buffer) — if that's a
`buftype=nofile` scratch test buffer, Neovim raises `E382`. Either let the default
`open_file` run for real (isolate with save/restore of the current window+buffer), or
pre-create the target file so the no-write ("already exists") branch is taken.

status: done | commit: (pending — see task-runner commit step)
