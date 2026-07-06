# lua-port / init (the façade + switchover)

**Responsibility:** `autoload/awiwi.vim` is the public API façade — bootstraps
`g:awiwi_home` subdirectories/log files on load, and owns everything that
isn't cleanly one of the leaf modules already ported: journal/todo file
opening, link insertion, the file-based active-task timer, paste/redact/toc
utility commands. `ftplugin/awiwi.vim` wires it to a buffer (`:Awiwi` command,
all mappings/autocmds/folding). `ftdetect/awiwi.vim` assigns the `awiwi`
filetype family by path. T10 replaces all three with `lua/awiwi/init.lua` +
`ftplugin/awiwi.lua` + `ftdetect/awiwi.lua`, wires `:Awiwi` to the already-built
`lua/awiwi/cmd.lua`, activates the already-built `lua/awiwi/syn.lua`, and
deletes every tracked vimscript file this replaces.

**Source:** `autoload/awiwi.vim` (939 lines), `ftplugin/awiwi.vim` (467 lines),
`ftdetect/awiwi.vim` (38 lines). Matches `docs/architecture.md`'s module-map
row (`awiwi.vim | 939 | active | façade: journals, links, asset paste,
file-based active-task timer, quickfix TOC, markers`).

**Port order:** T10, last transaction. Every leaf module it depends on is
already ported and `status: done`: `str`, `path`, `date`, `util`, `asset`,
`hi`, `server`, `syn`+`markers`, `cmd`(+`picker`). `sql`/`dao` were **not**
ported (WIP SQLite store, unreachable from `:Awiwi` — per ADR D1). Any façade
code path that would touch `sql`/`dao`/`task.vim`/`view.vim`/`bookmarks.vim`/
`ask.vim` is out of scope; grep confirms `autoload/awiwi.vim` has zero call
sites into any of them.

---

## 1. Public surface — `autoload/awiwi.vim` inventory

29 `awiwi#*` functions plus one conditionally-defined one
(`awiwi#add_active_task_to_airline`, only inside `if exists('g:airline_section_x')`).
Classified below; **live** = must land in `lua/awiwi/init.lua`, **dead** =
zero live callers post-port (drop per KISS/DRY, no speculative code), **superseded**
= functionally replaced by an already-ported leaf module — rewire callers to
that module, do not re-derive.

### 1a. Live — port into `init.lua`

| vimscript fn (line) | signature | notes |
| --- | --- | --- |
| `awiwi#get_journal_subpath()` (97) | `() -> string` | `path.join(g:awiwi_home,'journal')`. Called by `cmd.lua` deps table today via pure default — rebind to this for single source of truth (optional cleanup, not required for correctness). |
| `awiwi#get_recipe_subpath()` (102) | `() -> string` | **B10** — see Bugs. Port *natively* as `path.join(g:awiwi_home,'recipes')`, do not replicate the vimscript `awiwi#path#join` 2-arg call (which recurses through the unvendored `fn#apply`/`fn#spread` and is broken today). |
| `awiwi#get_asset_subpath()` (92) | `() -> string` | Already duplicated correctly as a pure default in `asset.lua`'s `M.deps.get_asset_subpath` and `cmd.lua`'s `M.deps.get_asset_subpath` — `init.lua`'s copy is the "canonical" one; rebinding the other two is optional (all three are value-identical `path.join` calls). |
| `awiwi#get_journal_file_by_date(date)` (259) | `(date) -> string` | `date.parse_date(date)` → split on `-` → `path.join(journal_subpath, year, month, date..'.md')`. Already duplicated as a pure default in `cmd.lua`'s deps — same rebind-optional note. |
| `awiwi#open_file(file, options)` (271) | `(file, options) -> nil` | Central file opener. See contract §12-18. **B3** (cmd.md) — must learn `options.width` (today only `.height` is read even when `+width=` is requested). |
| `awiwi#edit_journal(date, ...)` (323) | `(date, options?) -> nil` | See contract §19-22. |
| `awiwi#edit_todo(name, options)` (348) | `(name, options) -> nil` | `path.join(todos_subpath, name..'.md')` → `open_file`. |
| `awiwi#get_current_task(only_main)` (370) | `(only_main: boolean) -> {marker,title,tags,cont}` | Walks backward from cursor line to line 1 looking for a task heading (`##`/`###`/`####`, or only `##` if `only_main`). **B-INIT-1** — the "not found" fallback return is invalid syntax; see Bugs. |
| `awiwi#insert_and_open_continuation()` (398) | `() -> nil` (throws) | See contract §26-29. |
| `awiwi#get_all_journal_files(...)` (429) | `(opts?) -> string[]` | glob under journal subpath, optional literal-date filters. |
| `awiwi#insert_link_here(link)` (446) | `(link: string) -> nil` | Cursor-relative text insertion. **Already byte-faithfully ported** as `asset.lua`'s default `M.deps.insert_link_here` (per asset.md) — reuse that implementation (`require('awiwi.asset').deps.insert_link_here`) rather than re-deriving; `insert_recipe_link`/`insert_journal_link` (both façade-owned) call this. |
| `awiwi#download_file(filename, url)` (467) | `(filename, url) -> boolean` | **Already ported** as `asset.lua`'s default `M.deps.download_file` (`vim.system`-based). No other live call sites outside the asset-creation flow — nothing new for `init.lua` to implement. |
| `awiwi#guess_selection_mime_type()` (477) | `() -> string` | **Not** covered by `asset.lua`'s port (that module only folds the mime-sniff into its own `paste_file` default). Still has a live call site *outside* asset creation: `awiwi#handle_paste_in_insert_mode` uses it to decide plain-text-paste vs. asset-paste. Must be ported natively in `init.lua` (or exposed from `asset.lua` and reused — engineer's call, avoid duplicating the `xclip \| file --mime-type` loop twice). |
| `awiwi#paste_file(filename)` (491) | `(filename) -> boolean` | **Already ported** as `asset.lua`'s default `M.deps.paste_file`. Nothing new to implement. |
| `awiwi#activate_current_task()` (543) | `() -> nil` | File-based task timer, writes `data/task.log` + `data/awiwi.log`. See contract §30-34. |
| `awiwi#deactivate_active_task()` (581) | `() -> nil` | See contract §35-37. |
| `awiwi#add_active_task_to_airline()` (610, conditional) | `() -> string` | Pure formatting function, testable headlessly without real `airline`. See contract §38-39; registration side (`g:airline_section_x` etc.) is dogfood-only. |
| `awiwi#open_link(options, ...)` (638) | `(options, link?) -> nil` | See contract §40-44. |
| `awiwi#redact() ` (669) | `() -> nil` | See contract §45-46. |
| `awiwi#copy_file(path)` (688) | `(path) -> boolean` | `xclip -selection clipboard -r <path>` (copies the *file reference*, not text) — echoes status. |
| `awiwi#insert_recipe_link(recipe, ...)` (701) | `(recipe, options?) -> nil` | See contract §47-49. |
| `awiwi#insert_journal_link(date, ...)` (724) | `(date, options?) -> nil` | See contract §50-52. **B-INIT-2** — malformed link title, see Bugs. |
| `awiwi#handle_paste_in_insert_mode()` (738) | `() -> nil` | See contract §53-55. Uses `awiwi#cmd#get_cmd('paste_asset')` — **that function was never ported** (cmd.md: "confirmed superseded by `asset.types`"); rewire to `require('awiwi.asset').types.paste`. |
| `awiwi#edit_meta_info(...)` (751) | `(opts?) -> nil` | JSON `{…}` line-meta editor. See contract §56-62. Calls `awiwi#util#input` twice (now callback-shaped, `util.M.input(opts, on_confirm)`) — needs the same callback-restructuring `asset.lua` already did for its two-prompt sequence; no synchronous return value survives the port. |
| `awiwi#show_toc_in_qlist(...)` (872) | `(opts?) -> nil` | Quickfix ToC. See contract §63-68, including the auto-refresh autocmd machinery (`s:add_toc_aucmd`/`s:update_toc`/`s:delete_toc_aucmds`, lines 910-939). **B-INIT-5** in the auto-refresh wiring, fix-in-port (trivial once expressed as a Lua closure instead of `exe`+`<sid>`-string commands). |

Internal (`s:`-prefixed) helpers that stay **internal** (not exported, but
needed by the live functions above): `s:add_link`, `s:format_tags`,
`s:get_empty_task`, `s:get_epoch`, `s:get_current_timestamp`, `s:log`,
`s:info`, `s:log_task_action`, `s:get_most_recent_task_from_file`,
`s:get_most_recent_task_activty` [sic], `s:get_active_task`,
`s:generate_toc`, `s:chars`, `s:get_toc_title`.

### 1b. Dead or superseded — do NOT port natively

- **`awiwi#get_cache_subpath()`** (107) — reads undefined `s:cache_subpath`
  (the variable is actually named `s:cache_dir`); already documented in
  `docs/architecture.md`'s "Bugs in shipped paths". Zero call sites anywhere.
  **Drop.**
- **`awiwi#get_code_root()`** (82) — `expand('<sfile>:p:h:h')`, the plugin
  repo root. Its only two call sites (`server.vim:89-90`, building the dead
  Flask launch paths) are already superseded: `server.lua` computes its own
  `repo_root` independently (per server.md's Bug #5 fix, `debug.getinfo` +
  `vim.fs`). Zero live callers post-port. **Drop.**
- **`awiwi#get_data_dir()`** (87) — zero call sites anywhere, in or out of
  this repo's vimscript. **Drop** (or keep as a one-line getter for API
  parity with the `get_*_subpath` family — engineer's discretion, genuinely
  free either way, not worth an ADR).
- **`awiwi#get_markers(type, ...)`** (179) — **fully superseded** by
  `markers.lua`'s `M.get_markers(type_, opts)` (already ported, same ten
  vocabularies verbatim, same `g:awiwi_custom_<type>_markers` merge, `@onhole`
  typo preserved as a deliberate alias — see markers.md). Do not re-derive.
  Its one live call site (`ftplugin/awiwi.vim`'s `s:handle_enter`, `awiwi#get_markers('due', {'join': v:false, 'escape_mode': 'vim'})`)
  must be rewired to `require('awiwi.markers').get_markers('due', {join=false, escape_mode='vim'})`.
  `server.lua`'s `M.config.get_markers` field currently call-throughs to the
  legacy vimscript `awiwi#get_markers` (per server.md) — **T10 must rebind
  it to `require('awiwi.markers').get_markers` too.**
- **`s:AwiwiError(msg, ...)`** (70) — defined, zero callers anywhere (all
  throw sites use raw inline `"AwiwiError: ..."` strings instead). Dead.
  **Drop.**
- **`s:escape_rg_pattern(pattern)`** (266) — only caller is the superseded
  `awiwi#get_markers`. Dead once that's gone. **Drop** (markers.lua already
  has its own rg-escaping).
- **`s:warn`/`s:error`** (150, 159) — defined, zero callers (only `s:info`,
  via `s:log_task_action`, is actually used). **Drop.**
- **`s:format_search_result(start, ...)`** (234) — zero callers anywhere;
  also genuinely broken (see Bugs, `docs/architecture.md` already flags it
  as "looks truncated"). **Drop**, no functional loss.
- **`MarkdownToPdfPreConverter(lines, ...)`** (`ftplugin/awiwi.vim:454`) — a
  *global* (not `awiwi#`-namespaced) function with **zero in-repo callers**;
  looks like a hook meant for an external markdown→PDF plugin's config
  (never documented anywhere in this repo). **Drop from the port**, but flag
  for human sign-off in case some external, unlisted vimrc references the
  global function name by convention.

## 2. `ftplugin/awiwi.vim` inventory (467 lines)

### Commands
- `:Awiwi` (`-nargs=+`, `-complete=customlist,awiwi#cmd#get_completion`,
  `call awiwi#cmd#run(<f-args>)`) → **T10 replaces with**
  `vim.api.nvim_create_user_command('Awiwi', function(opts) require('awiwi.cmd').run(unpack(opts.fargs)) end, { nargs = '+', complete = function(ArgLead, CmdLine, CursorPos) return require('awiwi.cmd').get_completion(ArgLead, CmdLine, CursorPos) end })`.
  Note: the vimscript command is buffer-registered inside `ftplugin/awiwi.vim`
  (redefined per buffer); a global `nvim_create_user_command` is safe and
  simpler as long as it's guarded against re-registration (or just always
  called — Neovim allows redefining a user command idempotently).

### Buffer mappings (all `<buffer>`, all preserved 1:1 except `<F12>`)

| lhs | mode | rhs (today) | rhs (port) |
| --- | --- | --- | --- |
| `gf` | n | `:call awiwi#open_link({'new_window': v:true})<CR>` | `open_link({new_window=true})` |
| `<leader>gft` | n | `open_link({new_window:false, new_tab:true})` | same |
| `<leader>gfn` | n | `open_link({new_window:true})` (duplicate of `gf`) | same, preserve duplication |
| `gC` | n | `:Awiwi continue<CR>` | same |
| `gT` | n | `:Awiwi todo<CR>` | same |
| `ge` | n | `:Awiwi journal today<CR>` | same |
| `<F12>` | n | `:Awiwi tasks<CR>` **(broken — `tasks` isn't a subcommand, silent no-op per cmd.md B7)** | **`:Awiwi tags<CR>`** — required rewire, task explicitly calls this out |
| `gn` / `gp` | n | `:Awiwi journal next/previous<CR>` | same |
| `O` / `o` | n | `<sid>handle_enter_on_insert('n', above, false)` + redraw due dates | Lua closures, see §69-73 |
| `<Enter>` | i | `handle_enter_on_insert('i', false, false)` + redraw | same |
| `<C-j>` | i | `handle_enter_on_insert('i', false, true)` + redraw | same |
| `<Enter>` | n | `<sid>handle_enter()` + redraw | see §74-77 |
| `<C-y>` | i | literal `* [ ] ` | same, static abbreviation-style insert |
| `<C-f>` | i | `strftime('%H:%M')` | `os.date('%H:%M')` |
| `<C-q>` | n, i | `:Awiwi redact<CR>` | same |
| `<C-v>` | i | `handle_paste_in_insert_mode()` | same |
| i_`<C-s>` | i | `<C-o>:Awiwi link ` (leaves cmdline open, no `<CR>`) | same — user finishes typing |
| i_`<C-b>` | i | `<C-o>:Awiwi asset create<CR>` | same |
| `gj` | n | only if `&ft` contains `'awiwi.asset'`: `:exe printf('e %s', awiwi#asset#get_journal_for_current_asset())<CR>` | `vim.cmd.edit(require('awiwi.asset').get_journal_for_current_asset())`, gated same way |
| `A` | n | only if `&ft ==# 'awiwi.todo'`: `<sid>append_to_line()` + redraw | see §78 |
| `<C-x>` | c | `<C-r>=<sid>split_screen('h')<CR><CR>` | see §79-80 |
| `<C-v>` | c | `<C-r>=<sid>split_screen('v')<CR><CR>` | same |

Abbreviations (`iabbrev`, buffer-local implied by ftplugin context, actually
**not** `<buffer>`-scoped in the source — global iabbrevs re-declared on every
awiwi buffer load, idempotent no-op re-declaration): `:shrug:` → `` `¯\_(ツ)_/¯` ``,
`:arrow:` → `→`, `:check:` → `✔`, `:cross:` → `✖`.

### Autocmds (augroups)
- `awiwiAutosave`: `InsertLeave,CursorHold *.md` → `silent w`.
- `awiwiDeleteOldTasks`: `BufEnter,BufWritePre */todos/*.md` → `s:delete_old_tasks()` (the `py3` block, §81-84).
- `awiwiTodoDueDates`: `BufEnter,BufLeave,InsertEnter,InsertLeave */todos/*.md` → `awiwi#hi#redraw_due_dates()` → **rewire to `require('awiwi.hi').redraw_due_dates()`** (already fully ported, per hi.md).
- `awiwiHorizontalLines`: `BufEnter *.md` → `awiwi#hi#draw_horizontal_lines()`; `BufModifiedSet *.md` (only `if !&modified`) → same → **rewire to `require('awiwi.hi').draw_horizontal_lines()`**.
- ToC auto-refresh (`AwiwiTocUpdate`, dynamically created per-invocation inside `s:add_toc_aucmd`, not a static augroup in `ftplugin/awiwi.vim` — lives in `autoload/awiwi.vim:910-939`, listed here since it's ftplugin-adjacent autocmd wiring): see §63-68/B-INIT-5.
- `awiwiEntitlement` (only if `g:awiwi_use_entitlement` truthy — default true — **and** `entitlement.nvim` is on `&rtp`): title-decoration autocmds for journal/asset/recipe/todo buffers via `entitlement#add_title`. **Dogfood-only** — `entitlement.nvim` is an external plugin, not vendored, not on this machine's runtimepath (same status as the telescope probe in T9/ADR D7). Not part of the numbered contract; see Dogfood checklist.
- `doautocmd User AwiwiInitPost` (line 384, unconditional, fired once per buffer setup) — preserve as `vim.api.nvim_exec_autocmds('User', { pattern = 'AwiwiInitPost' })` so any user config hooking this event keeps working.

### The py3 todo-cleanup block (**B6**, lines 249-271)
`s:delete_old_tasks()` runs a `py3 << EOF … EOF` block on
`BufEnter,BufWritePre */todos/*.md`. Shipped intent: scan the buffer bottom-up,
skip open checkboxes (`* [ ]` prefix), find lines with a trailing `{...}` JSON
blob, parse it, and if it has a `"created"` date more than 15 days old, delete
that line (`vim.command(f"{line_nr}d")`).

Two shipped bugs, confirmed by reading the block:
1. **Missing `import vim`** — the block calls `vim.eval(...)`/`vim.command(...)`
   without importing the `vim` module that `py3` auto-injects as a builtin in
   real Neovim/Vim `+python3` — actually Neovim's `py3` binding *does* expose
   `vim` as an implicit global in the `pyx`/`python3` sandbox (no import
   needed in practice for `:py3` blocks under recent Neovim/pynvim), so this
   may not error today — **verify empirically is not required for the port**:
   the port is pure Lua, no Python, so this bug is moot by construction.
2. **Off-by-one range** — `max_line_nr = int(vim.eval("line('$')"))` then
   `for line_nr in range(max_line_nr - 1, -1, -1)`. Vim buffer lines are
   1-indexed (`getline('1')` is the first line); this loop's `range` produces
   `max_line_nr-1 … 0`, i.e. it **starts one line short of the last line**
   (never inspects the actual last line) and **includes line 0**, which
   `vim.eval("getline('0')")` returns as `''` (harmless, just wasted work) —
   net effect: **the last line of every todo file is never eligible for
   cleanup**, and one extra always-empty iteration runs.

**Port is pure Lua** — no Python. Contract (§81-84) specs the *intended*
shipped behavior (scan bottom-up, skip open checkboxes, parse trailing JSON,
age-based deletion) as testable Lua behavior; the off-by-one is a **bug
ledger item** (recommend fix-in-port: iterate `nvim_buf_line_count(0)` down to
`1`, no boundary bug possible with 1-indexed `nvim_buf_get_lines` + a plain
`for`).

### Fragile foldexpr (**B7**, line 342)
```vim
exe printf('setlocal foldexpr=%s(v:lnum)', function('s:folding'))
```
`function('s:folding')` returns a `Funcref` value; `printf('%s', <Funcref>)`
stringifies it as literally `function('<SNR>123_folding')` (script-ID-qualified,
fragile across resource order) and splices that string into `foldexpr`, which
Vim then `eval()`s per fold-line. **Intended behavior**: `foldmethod=expr`,
one fold level per markdown heading depth (`s:folding`: blank line → `-1`
(undetermined, defer to neighbours); line matching `^#*` → fold level
`(count of leading '#') - 1` if there's at least one `#`, else `'='` (same
level as previous line)). **Port**: `vim.wo.foldmethod = 'expr'`;
`vim.wo.foldexpr = 'v:lua.require("awiwi").foldexpr(v:lnum)'` (or the
`nvim 0.9+` idiom `vim.wo.foldexpr = "v:lua.awiwi_foldexpr(v:lnum)"` via a
small `_G` shim, or a plain Lua function registered once) calling a pure Lua
reimplementation of `s:folding`'s logic — no `Funcref`/`printf` fragility at
all in Lua. `setlocal nowrap` stays (`vim.wo.wrap = false`).

### Global `updatetime` mutation (**B8**, line 339)
```vim
" don't put too much pressure on the machine
set updatetime=4000
```
This is a **global** option (`set`, not `setlocal`), mutated as a side effect
of opening the *first* awiwi buffer, silently changing `updatetime` for the
entire Neovim session (including non-awiwi buffers) and never restored. The
comment suggests it exists to throttle `CursorHold`-triggered autocmds
(`awiwiAutosave`'s `CursorHold *.md`, `awiwiTodoDueDates`'s
`CursorHold`-adjacent triggers aren't actually CursorHold, re-check: only
`awiwiAutosave` uses `CursorHold`). **Drop this global mutation entirely in
the port** — do not set `vim.o.updatetime` at all; if CursorHold-driven
autosave responsiveness needs throttling, that's an ADR-worthy user-facing
config decision, not a silent global side effect baked into a ftplugin.

## 3. `ftdetect/awiwi.vim` inventory (38 lines)

Two augroup-free helper functions + one `augroup awiwiFtDetect`:

- `s:add_code_block_textobject()` — defines `aP`/`iP` visual+operator-pending
  mappings calling `awiwi#util#select_code_block(inclusive)` (**already
  ported**, `util.lua`'s `M.select_code_block`). Registered on `BufRead *.md`
  — i.e. **every** markdown buffer gets these text objects, not just awiwi
  ones.
- `s:add_awiwi_filetype(type, suffix?)` — sets `&filetype` to `type` (if
  `&ft` is currently empty) or `type` appended after a leading `awiwi.`-style
  compound (if `&ft ==# 'markdown'`, becomes plain `type`); no-ops if `&ft` is
  anything else already (so a user's own ftdetect running first wins).
- `augroup awiwiFtDetect`: for each of `BufNewFile`, `BufReadPost`,
  `BufWinEnter`, registers path-glob-triggered filetype assignment:
  - `<g:awiwi_home>/journal/**/*.md` → `awiwi`
  - `<g:awiwi_home>/assets/**/*` → `awiwi.asset`
  - `<g:awiwi_home>/recipes/*` → `awiwi.recipe`
  - `<g:awiwi_home>/recipes/**/*` → `awiwi.recipe`
  - `<g:awiwi_home>/todos/*.md` → `awiwi.todo`
  - for each `dir` in `values(g:awiwi_external_dirs)` (a user-configured
    dict, default `{}`): `<dir>/*.md` → `awiwi`

Port target: `ftdetect/awiwi.lua`, `vim.api.nvim_create_autocmd({'BufNewFile','BufReadPost','BufWinEnter'}, { pattern = ..., callback = ... })` per glob (or one callback per event with a pattern list), preserving the "only override empty or exactly `'markdown'` filetype" guard logic. The `aP`/`iP` textobjects become a `BufRead *.md` autocmd (or a small ftplugin-agnostic autocommand) calling `require('awiwi.util').select_code_block(...)`.

---

## Behavior contract

Numbered, independently testable statements. Interactive-only items (real
fzf/telescope UI, real `xclip`/`curl`/browser/airline/entitlement rendering)
are explicitly **excluded** here and listed in the Dogfood checklist instead;
every numbered item below must be exercisable in `nvim --clean --headless`
with stubbed/injected `M.deps`-style seams (mirroring `asset.lua`/`cmd.lua`/
`server.lua`'s established pattern).

### Bootstrap (module load)
1. On first `require('awiwi')` (or module load), given `g:awiwi_home = H`,
   the module ensures directories `H/data`, `H/journal`, `H/assets`,
   `H/recipes`, `H/todos`, `H/cache` all exist (create with `mkdir -p`
   semantics if missing/not writable).
2. It ensures `H/data/task.log` exists (create empty if missing).
3. `get_journal_subpath()` returns `H/journal`; `get_asset_subpath()` returns
   `H/assets`; `get_recipe_subpath()` returns `H/recipes` (B10 — computed via
   `path.join`, not the broken vimscript recursive `join`).
4. `get_journal_file_by_date('2024-03-05')` returns
   `H/journal/2024/03/2024-03-05.md` (delegates to `date.parse_date` for
   non-ISO inputs, e.g. `get_journal_file_by_date('today')`).

### `open_file(file, options)`
5. Given `file` with extension in `{ods, odt, drawio}`, opens via
   `xdg-open` (async spawn) and returns without touching any window/buffer.
6. Given `options.new_window = false/nil` and `options.new_tab = false/nil`,
   opens `file` in the current window (`:edit`-equivalent).
7. Given `options.new_tab = true`, opens in a new tab.
8. Given `options.new_window = true` and `options.position` omitted or
   `'auto'`, splits below if `util.window_split_below()` is true, else
   splits right (vertical).
9. Given `options.new_window = true, options.position = 'left'`, opens a
   **left** vertical split. **B-INIT-3** — the vimscript source has
   `let win_cmd == 'vnew'` (comparison operator instead of assignment) in
   this exact branch, an `E15` syntax error that fires the instant a user
   requests `position='left'` (e.g. via `:Awiwi journal today +vnew` or
   similar `-left`-flag path) — never exercised by any repo test, presumably
   never hit in practice or always silently swallowed. **Fix-in-port**:
   `position='left'` must produce the same left-vnew behavior the code
   clearly intends (prefix `'leftabove '`/`'topleft '` equivalent + vertical
   split), byte-for-byte matching what `position='right'` does but mirrored.
10. Given `options.new_window = true, options.position = 'right'`, opens a
    **right** vertical split (`vnew`, no left prefix).
11. Given `options.new_window = true, options.position = 'top'`, opens a
    horizontal split above (`'topleft'`-equivalent + `new`).
12. Given `options.new_window = true, options.position = 'bottom'` (or
    anything not in `{left,right,top}`, after emitting a warning for truly
    unknown values), opens a horizontal split below (`new`, no prefix).
13. Given `options.new_window = true` and `options.height` (or, **after
    B3-fix**, `options.width` when position implies a vertical split), the
    split is sized accordingly (`<N>new`/`<N>vnew`).
14. Given `options.create_dirs = true` and `file`'s parent directory doesn't
    exist, creates it (`mkdir -p`) before opening.
15. Given `options.anchor = 'some heading'` (non-empty), after opening jumps
    to the first case-insensitive match of that text (`+/\c<anchor>`-equivalent).
16. Given `options.last_line = true` and no anchor, jumps to the last line of
    the opened buffer.
17. Given neither anchor nor `last_line`, no post-open jump.

### `edit_journal(date, options?)`
18. Given `date` resolving to the journal already open in the current buffer
    (`date.get_own_date()`), echoes a "already open" message and does not
    reopen/rewrite anything.
19. Given `date == today` (after `date.parse_date`), forces
    `options.create_dirs = true` regardless of caller input.
20. Given a future date (`date > date.get_today()`) with `create_dirs` not
    forced and the target file not writable, raises an error and does not
    open anything (mirrors the "no `+create`" guard).
21. Otherwise, always sets `options.last_line = true` and delegates to
    `open_file(get_journal_file_by_date(date), options)`.

### `edit_todo(name, options)`
22. `edit_todo('groceries', opts)` opens `H/todos/groceries.md` via
    `open_file`, options passed through unchanged.

### `get_current_task(only_main)`
23. Given the cursor is on or below a line matching a task heading
    (`^##` if `only_main`, else `^##`-`####`) followed by non-whitespace
    title text, optionally an `@tag` or `(cont. from ...)` suffix, searching
    **backward from the cursor line to line 1**, returns
    `{marker, title, tags, cont}` for the **nearest such heading at or above
    the cursor**. `tags` is every whitespace-then-`(`-or-`@`-prefixed token
    except a `(cont....)`-shaped one; `cont` holds that one token (or `''`).
24. Given no such heading exists between the cursor line and line 1
    (inclusive), **B-INIT-1**: the vimscript fallback return is
    `{'marker': '', 'title': '', 'tags': [], 'cont'. ''}` — invalid dict
    syntax (`.` instead of `:` before the final value), an `E720` at runtime.
    Every caller (`insert_and_open_continuation`, `activate_current_task`)
    only ever checks `current_task.title == ''` for the "not found" case, so
    the *intended* contract is unambiguous: **fix-in-port**, return
    `{marker='', title='', tags={}, cont=''}` cleanly, never throw.

### `insert_and_open_continuation()`
25. Throws (does not touch the buffer) if the current buffer's own date
    (`date.get_own_date()`) equals today's date (`date.parse_date('today')`)
    — can't continue "into" the journal you're already on.
26. Throws (does not touch the buffer) if `get_current_task(true).title == ''`
    (cursor not inside a top-level task section).
27. Otherwise: appends a `[continued on <today>](<today's journal file, path
    relativized>)` link plus a blank line right after the cursor's line in
    the **current** (own-date) buffer, then **writes that buffer**
    (unconditional `:write`), then opens today's journal in a new top split
    (`edit_journal(today, {new_window=true, position='top'})`), then appends
    to the **end** of that new buffer: a blank line, the task heading
    re-created with `(cont. from <own-date>)` appended, a
    `[started on <own-date>](<own-date journal file, relativized against
    today's file>)` back-link, and a trailing blank line; cursor ends at the
    last line (`normal! G`-equivalent).

### `get_all_journal_files(opts?)`
28. `get_all_journal_files()` returns every `*.md` file under the journal
    subpath (recursive glob), stripped to their basename-without-extension
    (i.e. the date string), sorted ascending.
29. `opts.date = 'YYYY'` or `'YYYY-MM'` narrows the glob to that year/month
    subtree before applying the same basename+sort.
30. `opts.full_path = true` returns full paths instead of basenames (still
    sorted).
31. `opts.include_literals = true` appends the four literal strings
    `'previous day', 'next day', 'yesterday', 'today'` to the end of the
    result (after sorting the real files — the literals are unsorted
    trailing entries, not merged into the sort).

### Active-task timer (`activate_current_task` / `deactivate_active_task`)
32. `activate_current_task()`: if the cursor isn't in a top-level task
    section (`get_current_task(true).title == ''`), errors, no state change.
33. If a task is already active and it's the **same** title as the one under
    the cursor, echoes "already active", no state change, no duplicate log
    entry.
34. If a **different** task is active, errors ("must deactivate the active
    task first"), no state change.
35. Otherwise: resumes the most recent logged activity record for this exact
    task title if one exists in `task.log` (by title match, most recent
    matching entry wins — the file is scanned top-to-bottom, last match
    wins, i.e. `task.log`'s append order is oldest-first), else starts a
    fresh task record; sets state to `active`, appends an `{action='activate',
    ts=<epoch>}` entry to its `activity` list, appends the whole record (one
    JSON/Lua-table-literal-per-line, vimscript `string()` format in the
    original — port can use `vim.json.encode` for the on-disk format, this
    is a **new on-disk format, not required to be byte-compatible with old
    `task.log` lines** since it's an internal cache file, not a
    documented interchange format) to `task.log`, and appends an INFO line
    to `data/awiwi.log` (`[<timestamp>] INFO  - activate task "<title>"`
    shape). Sets `g:awiwi_active_task` to a copy of the record.
36. `deactivate_active_task()`: no-op with an echo ("no task active") if no
    task is currently active. Otherwise computes `duration += now -
    last_activity_ts`, appends a `{action='deactivate', ts=now}` activity
    entry, sets state `inactive`, appends the updated record to `task.log`
    and an INFO line to `awiwi.log`, and clears `g:awiwi_active_task`.
37. On module load, if `task.log`'s most recently-appended record has
    `state == 'active'`, that becomes the initially-active in-memory task and
    `g:awiwi_active_task` is set to it (a crash-recovery / "resume across
    restart" behavior).

### `add_active_task_to_airline()` — pure formatting, testable without airline
38. Given no active task (`g:awiwi_active_task` unset or `state ~= 'active'`),
    returns `''`.
39. Given an active task with elapsed duration `d = task.duration + (now -
    last_activity.ts)` seconds: `d < 60` → `"<d>s"`; `d < 3600` → `"<M>m
    <S>s"`; `d < 86400` → `"<H>h <M>m"`; else `"<D>d <H>h"`; wrapped as
    `"[ <title> (<formatted>) ]"`.

### `open_link(options, link?)`
40. Given an explicit `link` (string or table), resolves it via
    `util.as_link` + `util.determine_link_type` (already ported); given none,
    resolves the link under the cursor via `util.get_link_under_cursor`
    (already ported).
41. `type` in `{browser, external, mail}` → spawns `xdg-open <target>` async,
    no buffer/window change.
42. `type` in `{asset, journal, recipe}` → resolves `target` relative to the
    current buffer's directory, canonicalizes it, forwards any `anchor` into
    `options.anchor`, and calls `open_file(resolved, options)`.
43. `type == 'image'` → resolves to `<g:awiwi_home>/assets/<YYYY>/<MM>/<DD>/<basename>`
    (date parsed out of the target's parent-directory name, hyphen-split then
    joined with `/`) and spawns `g:awiwi_image_opener` (default
    `{'xdg-open'}`) with that path appended, async, no buffer/window change.
44. `type == ''`/unrecognized → error, no side effects (**preserve** the
    existing minor double-error-message quirk where an empty type both
    triggers the "cannot open link" message *and* falls through to "cannot
    open unknown link type ''"  — cosmetic, not worth an ADR; or fix-in-port
    by adding the missing early `return` — engineer's discretion, low
    stakes, note whichever choice is made in `## Ported`).

### `redact()`
45. Given the current line does **not** already contain `!!redacted`,
    appends `' !!redacted'` (or `'!!redacted'` with no leading space if the
    line is empty or already ends in whitespace) and restores cursor
    position.
46. Given the current line **does** contain `!!redacted` (possibly with
    leading spaces, possibly more than one occurrence), removes every
    ` *!!redacted` occurrence and restores cursor position.

### `insert_recipe_link(recipe, options?)`
47. `insert_recipe_link('cooking/pasta.md')` computes the recipe's path
    relative to (and including) the `recipes/` path component (i.e. strips
    everything up to and including the last literal `recipes` path segment,
    keeping subdirectories under it), and inserts
    `[recipe cooking/pasta.md](<relativized path>)` at the cursor.
48. With `options.anchor = 'Ingredients'` (non-empty), inserts
    `[recipe cooking/pasta.md: Ingredients](<relativized path>#Ingredients)`
    instead.
49. Uses the shared `insert_link_here` cursor-insertion primitive (already
    ported, see §1a).

### `insert_journal_link(date, options?)`
50. `insert_journal_link('2024-03-05')` inserts
    `[journal for 2024-03-05](<relativized path>)` at the cursor.
51. With `options.anchor = 'Standup'` (non-empty), the vimscript source
    produces `[journal for 2024-03-05: Standup)](<relativized path>#Standup)`
    — **B-INIT-2**, a stray `)` immediately after the anchor text, inside the
    link's bracketed title, that doesn't belong there (compare
    `insert_recipe_link`'s correctly-formed equivalent in §48). **Fix-in-port**:
    drop the stray `)`, matching `insert_recipe_link`'s shape:
    `[journal for 2024-03-05: Standup](<relativized path>#Standup)`.

### `handle_paste_in_insert_mode()`
52. Given the clipboard's guessed mime type is empty/undetectable, no-op
    (nothing pasted, no error surfaced to the user beyond whatever
    `guess_selection_mime_type` itself reports).
53. Given `text/plain`, pastes the clipboard register (`"+`) as text at the
    cursor (insert-mode paste).
54. Given any other detected type (image formats), creates a paste-type
    asset via `asset.create_asset_here_if_not_exists(asset.types.paste, {},
    on_done)` (callback-restructured per asset.md's signature deviation —
    **not** the dead `awiwi#cmd#get_cmd('paste_asset')` path) and, once the
    asset link has been inserted, moves the cursor past the closing `)` of
    the inserted markdown link (`f)l`-equivalent).

### `edit_meta_info(opts?)`
`opts` defaults: `{delete=false, column='', text=''}` (last field unused by
any branch — dead field, preserve-but-ignore, not worth removing since it's
just an unread default key).
55. No-op if the current line is blank/whitespace-only.
56. If the line has no trailing `{...}` JSON blob and `opts.delete` is true,
    no-op.
57. `opts.delete = true` with an existing trailing `{...}` blob (with or
    without leading whitespace before it): strips the blob (and its leading
    whitespace) from the line, sets it, and calls
    `hi.redraw_due_dates(true)` (force redraw).
58. `opts.column` non-empty (e.g. `'due'`): decodes the existing blob (or
    starts from `{}`), reads `opts.args` (space-joined) as the new value if
    given, else prompts interactively (`util.input`, callback) for
    `"meta info: <column>="`; empty value after trim → echo "no meta info
    specified", no-op; for `column == 'due'`, normalizes `to`/`tom`/…/`tomorrow`-abbreviations
    (any prefix of "tomorrow" starting with "to", matching the vimscript
    `^to\%[mmorow]\+$` pattern **verbatim, including its own typo** —
    `mmorow` not `morrow` — see Bugs) to the literal string `'tomorrow'`,
    then always runs the value through `date.to_iso_date`; other columns
    store the raw trimmed value; re-encodes the JSON blob.
59. `opts.column` empty: prompts interactively for the **entire** `{...}`
    blob (prefilled with the existing one, or `'{}'`), and if the resulting
    JSON has a `due` key, normalizes it through `date.to_iso_date` before
    re-encoding; a JSON parse error (mirrors vimscript's `catch /E474/`)
    surfaces as an error message, no-op, buffer untouched.
60. If the final `meta` string is empty, echo "no meta info specified",
    no-op. If it's unchanged from what was already on the line, no-op (no
    redundant `setline`/redraw).
61. Otherwise, rewrites the line as `"<content before the old blob> <new
    meta>"` and calls `hi.redraw_due_dates(true)`.

### `show_toc_in_qlist(opts?)`
62. `opts.date` empty (default): builds the quickfix list from **every**
    journal file (via `get_all_journal_files({full_path=true})`), title
    `'topics'`.
63. `opts.date` a 4-digit year (`'2024'`): same but filtered to that year's
    files, title `'topics 2024'`.
64. `opts.date` a full `YYYY-MM-DD` date: single file
    (`get_journal_file_by_date(date)`), title `'topics <nice-date>'` (via
    `date.to_nice_date`).
65. `opts.date` a `YYYY-MM` (year+month, not a full date): filtered files,
    title from `strftime('%B %Y', ...)`-equivalent (`os.date` month/year name
    for the 1st of that month).
66. Each journal file is scanned top-to-bottom (skipping fenced-code-block
    lines — a **line-based** `^```` toggle tracker, not the treesitter mask
    `hi.lua`/`syn.lua` use — preserve this simpler heuristic here, it's a
    dedicated ToC generator, not a highlighter) for ATX headings
    (`^#+ +\S.*$`) up to `opts.max_level` (default 6), skipping the buffer's
    own `# <date>` title heading; each produces one quickfix entry
    `{filename, lnum, text = ('..' * (level-2)) .. title, module = date ..
    right-padded-line-number}`.
67. `setqflist` replaces the list wholesale, then a second `setqflist([], 'a',
    {title=...})` call sets just the title without touching entries (two
    separate calls, preserve — not a bug, just how the vimscript does it).
68. `opts.show` (default true): opens the quickfix window (`copen`); if
    `is_single_date`, additionally registers an auto-refresh: on
    `BufWritePost` of the **source journal buffer**, or on entering a window
    showing any `*/journal/*.md` buffer while a listed quickfix window still
    exists, regenerate the ToC silently (`opts.show=false`) for the same
    date; the refresh autocmds self-delete once no listed quickfix buffer
    remains. **B-INIT-5** — the vimscript implementation bakes a **fixed
    window number** (captured once, at registration time, via
    `bufwinnr(a:buffer)`) into the generated `BufWinEnter` autocmd command
    string, so the refresh silently stops firing correctly the moment the
    user moves/resizes windows (the comparison is against a stale window
    number, not the live one). **Fix-in-port**: express this as a Lua
    autocmd callback that re-checks "does a listed quickfix buffer still
    exist" dynamically every time it fires — trivial once it's not
    string-templated `exe`/`<sid>` commands, no stale-capture possible.

### `ftplugin` — list/checkbox-aware Enter handling
(`s:handle_enter_on_insert(mode, above, continue_paragraph)`, the
`O`/`o`/`<Enter>`/`<C-j>` mappings)
69. On a completely blank current line: normal-mode `O`/`o` do exactly that
    (open a line above/below and enter insert mode); insert-mode `<Enter>`/
    `<C-j>` insert a blank line above/below the cursor's line without moving
    existing text, cursor advances by one line for the "below" case.
70. On a list/checkbox line whose marker has **no content after it** (e.g.
    `"* "`, `"  * [ ] "`): if the line has leading whitespace, de-indents by
    2 columns (`line[2:]`); else if it's a list line with no leading
    whitespace, replaces it with a single leading space; else (not a list at
    all) blanks the line entirely — then starts insert mode at that (now
    shorter) line, no new line created.
71. On a list/checkbox/plain line **with** content, cursor at or past the
    end of the line (or invoked from normal mode): for `.todo`-suffixed
    filetypes, the **current** line is left untouched and the **new** line
    is `"<same marker> {\"created\": \"<today, YYYY-MM-DD>\"}"`, cursor lands
    right after the marker (before the JSON blob), insert mode starts
    *before* that position (not appending). For all other filetypes, the new
    line is either the same marker text (continuing a list/checkbox) or, if
    `continue_paragraph` (the `<C-j>` variant), that many spaces of padding
    instead (continuing a paragraph under a list item without repeating the
    bullet) — insert mode starts *appending* at the end of that new line.
72. On a list/checkbox/plain line, breaking **mid-content** (insert-mode
    `<Enter>`/`<C-j>` with the cursor strictly before the end of the line):
    splits the line at the cursor; text from the cursor onward moves to a
    new line, left-padded to align under the original marker's width (or, if
    the cursor was at column 1, the **entire** line moves down unpadded and
    the original line becomes empty); cursor lands right after the marker on
    the new line, unless `g:awiwi_jump_to_end` is truthy and the original
    line was a list item, in which case it lands at the end of the moved
    text instead; insert mode starts *without* appending (mid-line
    position). For performance, `setline` on the original line is skipped
    entirely if its text didn't actually change.

### `ftplugin` — normal-mode `<Enter>` checkbox toggle (`s:handle_enter`)
73. On any line that isn't `<indent>[-*]<space>[ x]...` (a checkbox list
    item), falls through to plain `<CR>` (or, if it's a plain bulleted list
    without a checkbox, starts insert mode instead — preserve this
    asymmetry).
74. On a checkbox line, toggles ` ` ↔ `x` in place.
75. When **checking** a box (` `→`x`): if the line (outside any existing
    `~~...~~` span) contains a due/urgent-marker pattern
    (`markers.get_markers('due', {join=false, escape_mode='vim'})`-derived),
    wraps that matched span in `~~...~~` (markdown strikethrough), adjusting
    the cursor column for the inserted `~~` pairs.
76. When **unchecking** (`x`→` `): if the line contains that same
    marker-pattern **already wrapped** in `~~...~~`, unwraps it (removes the
    `~~` pairs), adjusting the cursor column accordingly.
77. Either way, silently writes the buffer (`sil w`) and moves the cursor
    down one line (`normal! j`) afterward.

### `ftplugin` — todo-append (`A` mapping, `.todo` filetype only, `s:append_to_line`)
78. On a line with a trailing `{...}` meta blob, inserts a single space
    before that blob if one isn't already there (adjusting the match-start
    offset), and enters append-insert-mode (`startinsert!`) positioned right
    before the (possibly now-shifted) blob. On a line with **no** meta blob,
    just enters plain `startinsert!` (append at end of line) without
    touching the line's content.

### `ftplugin` — command-line split-screen helper (`s:split_screen`, `<C-x>`/`<C-v>` in cmdline mode)
79. Only activates while the command-line type is `:` (`getcmdtype() == ':'`)
    and the current command line's first word is **not** an abbreviation of
    `Awiwi` (`Aw`, `Awi`, `Awiw`, `Awiwi`) — i.e. it's a **no-op precisely
    when** the user is mid-typing an `:Awiwi ...` command (so `<C-x>`/`<C-v>`
    keep their normal cmdline-mode meaning there), and otherwise injects
    `' +hnew'` (for `<C-x>`) or `' +vnew'` (for `<C-v>`) into the command
    line before it executes — this looks like dead/vestigial functionality
    for a `:Awiwi`-flag shortcut that predates the current flag syntax
    (`+hnew`/`+vnew` **are** real flags per `docs/architecture.md`'s command
    surface table, so this may be a convenience for **non**-`:Awiwi` Ex
    commands, e.g. turning `:e file<C-x>` into `:e file +hnew`, which is not
    a valid Ex-command suffix for anything except `:Awiwi`... unclear intent).
    **Recommendation:** preserve behavior exactly as observed (guard +
    injection), flag for human ADR — this reads as either dead code with an
    inverted guard (the one case it's needed for, `:Awiwi`, is the one case
    it refuses to fire) or a feature nobody uses. Not worth reverse-engineering
    further without the original author; low risk either way since its net
    effect today is "usually a no-op, sometimes appends a flag string to a
    non-Awiwi Ex command line", which is testable as specified.

### `ftdetect` — filetype assignment
80. Opening/creating a file under `<g:awiwi_home>/journal/**/*.md` sets
    `&filetype` to `awiwi` (only if `&ft` was empty or exactly `markdown`).
81. Same for `assets/**/*` → `awiwi.asset`, `recipes/*` and `recipes/**/*` →
    `awiwi.recipe`, `todos/*.md` → `awiwi.todo`.
82. For each directory in `values(g:awiwi_external_dirs)` (default `{}`),
    `<dir>/*.md` → `awiwi` (same empty-or-markdown guard).
83. Any `.md` buffer (regardless of the above) gets `aP`/`iP`
    visual+operator-pending mappings bound to
    `require('awiwi.util').select_code_block(inclusive)`.

### py3 todo-cleanup, ported to pure Lua (**B6**)
84. On `BufEnter`/`BufWritePre` of any `*/todos/*.md` buffer, scans **every**
    line of the buffer from the **last line down to the first** (inclusive
    of both ends — fixing B6's off-by-one, which today skips the true last
    line and wastes one iteration on a nonexistent line 0): any line
    starting with `"* [ ]"` (an open checkbox) is skipped; any line with no
    trailing `{...}` JSON blob is skipped; any line whose blob parses and
    has a `"created"` key whose date is more than 15 days before "today" is
    **deleted from the buffer** (in-place, no undo-block guarantees beyond
    whatever a normal buffer-line-delete gives); everything else is left
    alone.

---

## Bug ledger

| id | location | description | recommendation |
| --- | --- | --- | --- |
| B3 (cmd.md) | `autoload/awiwi.vim:279` (`open_file`) | `+width=` flag (already fixed in `cmd.lua`, per cmd.md) writes `options.width`, but `open_file` only ever reads `.height`, falling back to `.width` **only** via `get(options,'height', get(options,'width',0))` — so width IS read today, just as a fallback when height is absent, not as an independent axis (a vertical split's *width* and a horizontal split's *height* are conflated into one `height` local var used for both). | **fix-in-port** — give vertical splits (`left`/`right`) their own width sizing from `options.width`, horizontal splits (`top`/`bottom`) their own from `options.height`; do not conflate. See contract §13. |
| B6 | `ftplugin/awiwi.vim:249-271` | py3 block, off-by-one range skips the true last line, wastes an iteration on line 0; import-vim concern is moot (Lua port, no Python). | **fix-in-port** (moot by construction — Lua reimplementation per contract §84 has no such boundary bug). |
| B7 | `ftplugin/awiwi.vim:342` | `printf('setlocal foldexpr=%s(v:lnum)', function('s:folding'))` — fragile `Funcref`-to-string splice. | **fix-in-port** — plain Lua `foldexpr` function, no stringified-funcref indirection. |
| B8 | `ftplugin/awiwi.vim:339` | Global (not `setlocal`) `updatetime=4000` mutation, permanent, session-wide, on first awiwi buffer. | **drop** — do not port this global mutation at all. |
| B10 | `autoload/awiwi.vim:102-104` + `path.vim:22` (`awiwi#get_recipe_subpath`) | `s:recipe_subpath` (and every other `s:*_subpath`!) is computed via `awiwi#path#join(g:awiwi_home, '<seg>')` — a 2-arg call — which **always** recurses through `fn#apply('awiwi#path#join', p, fn#spread(a:000[1:]))` regardless of arg count (see `path.vim:6-22`); `fn#apply`/`fn#spread` are an **unvendored external plugin** (per path.md's B-PATH-2, confirmed absent from a clean `nvim` runtimepath) — so in an environment without that plugin, **every** module-load-time subpath assignment in `autoload/awiwi.vim:8-14` would throw `E117` and abort loading the whole façade. In practice this apparently doesn't happen in the shipped/dogfooded environment (implying `fn.vim` **is** present there, just never committed to this repo) — but it's not something the Lua port should ever depend on. | **fix-in-port** (moot by construction) — `init.lua`'s subpath getters use `path.lua`'s already-fixed native-varargs `join`, no recursion, no external plugin dependency, ever. |
| B-INIT-1 | `autoload/awiwi.vim:394` (`get_current_task`) | `return {'marker': '', 'title': '', 'tags': [], 'cont'. ''}` — `.` instead of `:`, invalid dict-literal syntax, `E720` at runtime the first time this fallback path is actually reached (cursor not inside any task section). | **fix-in-port** — see contract §24. |
| B-INIT-2 | `autoload/awiwi.vim:732` (`insert_journal_link`) | `printf('[journal for %s: %s)](%s#%s)', ...)` — stray `)` inside the link's bracketed title when an anchor is given. | **fix-in-port** — see contract §51. |
| B-INIT-3 | `autoload/awiwi.vim:286` (`open_file`, `position == 'left'` branch) | `let win_cmd == 'vnew'` — `==` instead of `=`, `E15` syntax error the first time `position='left'` is actually requested. | **fix-in-port** — see contract §9. |
| B-INIT-4 | `autoload/awiwi.vim:644-646` (`open_link`) | Missing `return` after the `empty(link.type)` `echoerr` — falls through to the `elseif` chain and (for an empty type) hits the final `else` too, emitting a second, redundant error message. | **preserve or fix-in-port, engineer's discretion** — cosmetic double-message only, no state corruption. Note the choice made in `## Ported`. |
| B-INIT-5 | `autoload/awiwi.vim:910-939` (`s:add_toc_aucmd`/`s:update_toc`) | ToC quickfix auto-refresh bakes a **stale window number** (captured once at registration time via `bufwinnr(a:buffer)`) into a string-templated `BufWinEnter` autocmd command, so the refresh silently stops matching once window layout changes. | **fix-in-port** — trivial as a Lua closure that re-checks state dynamically each firing; see contract §68. |
| B-INIT-6 | `autoload/awiwi.vim:38-39` | `g:awiwi_history_length` is read into `s:log_file_size`, and `s:history = []` is declared, but **neither is ever used anywhere else in the file** — `data/awiwi.log` grows unbounded forever; the documented config option (`docs/architecture.md`'s config table: "log size, 10000") is a complete no-op today. | **preserve** (no behavior change; the option was already inert) — drop the two dead local vars in the port, but do not implement new log-rotation behavior that never shipped (KISS/DRY — no speculative features). Worth a one-line note in `docs/architecture.md` that this config key is currently a no-op, if not already implied. |
| (doc'd, not new) | `autoload/awiwi.vim:107-109` | `awiwi#get_cache_subpath` returns undefined `s:cache_subpath` (should be `s:cache_dir`). Already flagged in `docs/architecture.md`'s "Bugs in shipped paths". Zero live callers. | **drop** the function entirely (see §1b) — moot by construction, nothing calls it. |
| (doc'd, not new) | `autoload/awiwi.vim:234-246` | `s:format_search_result` is missing its final `endif`/`return` (`docs/architecture.md`: "looks truncated"). Zero callers anywhere. | **drop** the function entirely (see §1b) — moot by construction. |
| (observed, low-value) | `autoload/awiwi.vim:792` (`edit_meta_info`, `due` column) | `val =~# '^to\%[mmorow]\+$'` — the vimscript `%[...]` "optional tail" construct here is typo'd (`mmorow` not `morrow`), matching `to`, `tom`, `tomm`, `tommo`, ... but via a slightly different character set than "tomorrow" would suggest (double-`m` in the optional tail, no double-`m` requirement — actually still matches literal `"tomorrow"` fine since `%[mmorow]` means "these chars, in this order, each individually optional-tail", so `to`+`m`+`o`+`r`+`o`+`w` all still optionally present in order — it degrades gracefully, matches the common cases users would type: `to`, `tom`, `tomorrow`). | **preserve** — reproduce the exact `to[m][m][o][r][o][w]`-shaped optional-tail acceptance set (contract §58 specs it precisely enough to test); not worth "fixing" a typo that doesn't actually change which real inputs match, per the brief's "don't fix what isn't broken" guidance. |

---

## Reads/writes

**Globals read (`vim.g`):** `awiwi_home` (required), `awiwi_history_length`
(read but inert, B-INIT-6), `awiwi_jump_to_end`, `awiwi_image_opener`,
`awiwi_external_dirs`, `awiwi_use_entitlement` (+`_opts`), `airline_section_x`
(existence check only), `awiwi_custom_<type>_markers` (indirectly, via
`markers.lua`, not read directly by the façade anymore).

**Globals written:** `g:awiwi_active_task` (set/cleared by
activate/deactivate), `g:airline_section_b/x/y` (only inside the
`entitlement`-adjacent airline-registration block, dogfood-only),
`g:autoloaded_awiwi` (module-load guard — becomes a moot `require` cache hit
in Lua, no explicit guard var needed).

**Files:** `<home>/data/awiwi.log` (append-only INFO log lines),
`<home>/data/task.log` (append-only task-activity records), journal/asset/
recipe/todo markdown files (read + write via buffer open/edit/write),
`<home>/{journal,assets,recipes,todos,data,cache}/` (created on bootstrap).

**Buffers/windows:** heavy use of `getline`/`setline`/`append`/`getcurpos`/
`setpos` (current-buffer text + cursor mutation) throughout the Enter/
checkbox/redact/meta-info/link-insertion functions; window splits via
`open_file`; quickfix list via `show_toc_in_qlist`.

**Registers:** `"+`(system clipboard) read in `handle_paste_in_insert_mode`'s
plain-text branch (`normal! "+p`).

## External

**Binaries shelled to:** `xdg-open` (async, via `jobstart`/`vim.system` —
open_link's browser/external/mail/image branches, open_file's
xdg-open-extension branch), `xclip` (`copy_file` — already the only
**new**, not-yet-ported shell-out left in this module; `download_file`/
`paste_file`/mime-guessing are already covered by `asset.lua`'s port).

**Other awiwi modules called (all already ported, `require` directly, never
re-derive):** `awiwi.path` (`join`), `awiwi.date` (`parse_date`,
`get_own_date`, `get_today`, `to_iso_date`, `to_nice_date`), `awiwi.str`
(`endswith`), `awiwi.util` (`window_split_below`, `get_link_under_cursor`,
`as_link`, `determine_link_type`, `relativize`, `input`, `select_code_block`),
`awiwi.hi` (`redraw_due_dates`, `draw_horizontal_lines`), `awiwi.asset`
(`create_asset_here_if_not_exists`, `types`, `deps.insert_link_here`,
`deps.download_file`, `deps.paste_file`, `get_journal_for_current_asset`),
`awiwi.markers` (`get_markers`), `awiwi.cmd` (`run`, `get_completion` —
wired from `ftplugin`), `awiwi.server` (`server_is_running`, `start_server` —
wired from `ftplugin`'s autostart block), `awiwi.syn` (`attach`, `detach`,
`setup_highlights` — wired from `ftplugin`'s FileType handling, net-new for
T10, not called by the vimscript original at all since `syntax/awiwi.vim`
self-activated via `:syntax` conventions).

**VimL plugin deps eliminated by the port:** `fn#apply`/`fn#spread` (B10,
never vendored, path.lua's native varargs replace it entirely), `fzf#vim#grep`
(fuzzy_search — superseded by `picker.lua`'s `M.grep`, already the pattern
`cmd.lua`'s `entries`/`tags`/asset-picker commands use; **T10 should route
`fuzzy_search`/`:Awiwi search` through `picker.grep` rather than
reintroducing a bespoke fzf.vim call** — flag as an ADR-worthy behavior
upgrade, matching cmd.md's C12 "revived richer asset picker" precedent).

**Dogfood-only external deps (not exercised by any numbered contract item):**
`entitlement.nvim` (optional title decoration), `vim-airline` (optional
statusline section) — both gated behind existence checks in the vimscript
original and should stay that way in the port (`pcall(require, ...)` or
`vim.fn.exists`-equivalent guards).

## Files to delete (switchover)

Tracked files (`git ls-files autoload syntax`), delete all of them in the
same commit that lands `lua/awiwi/init.lua` + the new `ftplugin`/`ftdetect`:

```
autoload/awiwi.vim
autoload/awiwi/asset.vim
autoload/awiwi/cmd.vim
autoload/awiwi/dao.vim
autoload/awiwi/date.vim
autoload/awiwi/hi.vim
autoload/awiwi/path.vim
autoload/awiwi/server.vim
autoload/awiwi/sql.vim
autoload/awiwi/str.vim
autoload/awiwi/task.vim
autoload/awiwi/util.vim
autoload/awiwi/view.vim
syntax/awiwi.vim
```

`autoload/awiwi/ask.vim` and `autoload/awiwi/bookmarks.vim` exist in this
worktree's working tree but are **untracked** (`git status` shows `??`) — not
part of this repo's history; leave them alone (not this brief's problem to
clean up, and deleting untracked files a previous session created without
committing is out of scope for a "delete tracked files" switchover — flag for
human judgement, do not `git rm` or `rm` them as part of this transaction).

`ftplugin/awiwi.vim` and `ftdetect/awiwi.vim` are **replaced in place**
(content rewritten to Lua-dispatch shims or deleted in favor of
`ftplugin/awiwi.lua`/`ftdetect/awiwi.lua` — Neovim loads `ftplugin/<ft>.lua`
for every dot-separated component of `&filetype`, so `ftplugin/awiwi.lua`
alone already covers `awiwi`, `awiwi.todo`, `awiwi.asset`, `awiwi.recipe`
exactly like the current single `ftplugin/awiwi.vim` does — no per-compound-type
file needed). **Delete** the old `.vim` versions once the `.lua` ones land and
are verified (same commit).

## Port notes

- **`M.deps` seam, same pattern as every prior module.** `init.lua` shells
  out to `xclip`/`xdg-open`/`curl` (indirectly, via already-ported
  `asset.lua` calls) and touches real files (`mkdir`, `writefile`,
  `task.log`, `awiwi.log`) — mirror `asset.lua`/`server.lua`'s
  `M.deps`/`M.config` injection-table pattern so `init_spec.lua` never
  touches the real filesystem/clipboard outside `vim.fn.tempname()`.
- **Do not re-derive `insert_link_here`/`download_file`/`paste_file`.** They
  already exist as `asset.lua`'s `M.deps.*` defaults, byte-faithfully ported.
  `init.lua` should call through `require('awiwi.asset').deps.<fn>` (or
  whatever the engineer decides is the cleanest re-export shape) rather than
  writing a second copy — this is the single biggest DRY trap in this
  transaction given how much of `autoload/awiwi.vim`'s file-IO surface
  overlaps what T5 already shipped.
- **Rewiring, not re-deriving, is most of this module's actual new work.**
  Most of `autoload/awiwi.vim`'s complexity (link parsing, date math, path
  math, highlighting, asset creation, marker vocab, session/drawio/picker UI)
  already lives in already-ported leaf modules; `init.lua`'s job is mostly
  the *remaining* glue: file-opening policy (`open_file`), the active-task
  timer, and a handful of small link/toc/redact/meta-info editing functions
  that never had a natural home in any leaf module.
- **syn activation** (per syn.md's own "What T10 needs to activate module"
  section): call `require('awiwi.syn').attach(bufnr)` from a `FileType`
  autocmd matching `awiwi,awiwi.todo,awiwi.asset,awiwi.recipe` (the full
  compound-filetype family, not just the two syn.md's own note calls out —
  double check against `ftdetect`'s actual filetype list, §3 above, which
  assigns four distinct types, not two) instead of any `:syntax`/`runtime
  syntax/awiwi.vim` sourcing (there is none to source anymore — the file is
  deleted); call `require('awiwi.syn').detach(bufnr)` on `BufUnload`/
  filetype-change away from the awiwi family. `M.setup_highlights()` can be
  called once at plugin-load time too (idempotent) so highlight groups exist
  before the first buffer attaches, and again on `ColorScheme` if the
  project wants highlight groups to survive a colorscheme change (not a
  contract requirement, `attach()` already calls it per-buffer-attach, which
  is sufficient to satisfy every numbered behavior item above — treat a
  `ColorScheme` refresh as a dogfood nicety, not a contract item).
- **`:Awiwi` registration:** a single global `nvim_create_user_command` call
  (from `ftplugin/awiwi.lua`, or from a top-level plugin-load point — either
  works since Neovim allows idempotent redefinition) replaces the
  per-buffer `command!` in the vimscript original; no functional difference
  since `-nargs`/`-complete` don't vary per-buffer today.
- **`options.width` (B3):** teach `open_file` two independent size axes
  (`options.height` for horizontal splits, `options.width` for vertical
  ones) rather than the vimscript original's single conflated `height` local
  used for both — see contract §13 and the B3 ledger entry above (a
  correction to cmd.md's own note, which slightly overstated the bug: width
  IS read today, just only as a same-slot fallback for height, not as an
  independent vertical-split axis).
- **`fuzzy_search`/`:Awiwi search`** — recommend routing through
  `picker.lua`'s `M.grep` (already built, already used by `cmd.lua`'s
  `entries`/`tags`/asset-list commands) instead of reintroducing `fzf.vim`.
  This is a behavior upgrade (consistent picker backend across every
  fuzzy-pick surface, telescope-upgradeable per ADR D7) — flag for
  `docs/decisions.md`, mirroring the precedent cmd.md's C12 already set for
  the asset picker.
- **Treesitter parser availability** is a **dogfood-only** concern (not
  testable/enforceable headlessly beyond "the query compiles against
  whatever markdown parser `nvim --clean` ships with" — already covered by
  `syn_spec.lua`'s existing green suite) — nothing new for T10 to verify
  beyond wiring the `attach`/`detach` autocmds correctly.

## Suggested acceptance tests

(Illustrative subset — one or two per contract cluster; qa-verifier should
expect roughly one test per numbered contract item, mirroring the existing
module specs' density of ~1.5-2 `it`s per numbered brief item.)

- Bootstrap: `vim.fn.tempname()` as `g:awiwi_home`, require the module,
  assert all six subdirectories + `data/task.log` now exist.
- `open_file`: stub `vim.cmd`/window-count checks; assert `position='left'`
  produces a vertical split with the cursor's new window to the *left* of
  the original (B-INIT-3 regression — this must have been unreachable/untested
  before, since it was a syntax error).
- `get_current_task`: cursor several lines below a `## Title` heading with no
  intervening heading → returns that heading's parsed fields; cursor at line
  1 of a buffer with zero headings → returns the empty-fields table without
  erroring (B-INIT-1 regression).
- `insert_journal_link` with a non-empty anchor → assert the inserted text
  has **no** stray `)` before the closing `]` (B-INIT-2 regression).
- `activate_current_task`/`deactivate_active_task`: fake clock (`os.time`
  stub or injected `now` dep), assert `task.log` gains one line per call,
  `awiwi.log` gains one INFO line per call, `g:awiwi_active_task` is set/unset
  correctly, and the "already active, same title" / "different title active"
  guard paths never write anything.
- `add_active_task_to_airline`: four duration buckets (`<60s`, `<1h`, `<1d`,
  `>=1d`) each produce the documented format string; no active task → `''`.
- `show_toc_in_qlist` auto-refresh: register it against a fake "quickfix
  buffer exists" predicate, move a fake "current window", assert the
  refresh still fires correctly after the "window" changes (B-INIT-5
  regression — this is exactly the scenario the stale-window-number bug
  breaks).
- ftdetect: `BufNewFile` under `<home>/journal/2024/03/2024-03-05.md` with
  `&ft` empty beforehand → `&ft == 'awiwi'`; same path with `&ft` pre-set to
  something unrelated → unchanged (guard preserved).
- py3-cleanup-ported-to-Lua: buffer with N lines, last line matching the
  age/blob criteria → **is** deleted (B6 regression — the vimscript original
  would have left it untouched).
- `<F12>` mapping: assert the registered buffer-local mapping's rhs is
  `:Awiwi tags<CR>`, not `:Awiwi tasks<CR>` (cmd.md's B7 rewire, explicitly
  required by the T10 task brief).

## Dogfood checklist (human tester, real interactive session — not headless)

- [ ] `:Awiwi journal today`, `gC`, `gT`, `ge`, `gn`/`gp`, `<F12>` all behave
      as documented against a real `g:awiwi_home` with real journal files.
- [ ] Real fzf/telescope pickers (`:Awiwi journal` bare, `:Awiwi recipe`
      bare, `:Awiwi tags`, `:Awiwi entries`, `:Awiwi asset` picker) — confirm
      whichever backend `picker.lua` selects (vim.ui.select fallback vs. real
      telescope if installed) actually opens/jumps correctly.
- [ ] Real clipboard paste (`<C-v>` in insert mode) with an actual image and
      actual plain text on the system clipboard — confirm
      `guess_selection_mime_type` + asset creation + link insertion all work
      end-to-end against real `xclip`/`file`.
- [ ] Real syntax/highlighting: open a journal page with headings, links,
      markers (`TODO`, `FIXME`, `@due`), redacted lines, task checkboxes —
      confirm `syn.lua`'s extmark painting matches what `syntax/awiwi.vim`
      used to render, now activated via the new `FileType` autocmd (this is
      the first real-session exercise of syn's activation wiring — T6b only
      built+headless-tested it).
- [ ] Real folding: confirm heading-based folds collapse/expand correctly
      after the `foldexpr` rewrite (B7).
- [ ] `updatetime` is **not** silently changed session-wide after opening an
      awiwi buffer (B8 — confirm via `:set updatetime?` before/after).
- [ ] If `vim-airline` is installed: confirm the active-task section renders
      and updates live.
- [ ] If `entitlement.nvim` is installed: confirm journal/asset/recipe/todo
      title decorations still appear.
- [ ] `:Awiwi serve` / real server start — confirm against whatever the
      `server/` FastAPI app looks like once it exists (per server.md's ADR
      D5 placeholder note — likely still blocked on the app module landing).
- [ ] Drawio export (`:Awiwi export`) against a real `.drawio` file and a
      real `drawio` binary, if available.
- [ ] Confirm no regression in plain markdown buffers **outside**
      `g:awiwi_home` (the `aP`/`iP` textobjects fire on `BufRead *.md`
      globally — make sure that's still true and harmless for non-awiwi
      markdown files).

## Ported

**Lua surface:** `lua/awiwi/init.lua` (façade), `ftplugin/awiwi.lua`,
`ftdetect/awiwi.lua`. Specs: `tests/init_spec.lua` (87 `it`),
`tests/ftplugin_spec.lua` (13 `it`). Full suite
`nvim --clean --headless -l tests/run.lua` -> **454 passed, 0 failed (14 files)**
AFTER the vimscript deletion. Plugin loads headlessly from a clean nvim:
`require('awiwi')` works, `:Awiwi` exists, `awiwi` filetype fires on a journal
path, foldexpr wired.

### `init.lua` public API
- Subpaths/paths: `get_journal_subpath`, `get_asset_subpath`,
  `get_recipe_subpath`, `get_journal_file_by_date` (all B10-native via `path.join`).
- `bootstrap()` (idempotent; ensures dirs+task.log, then `resume_active_task`),
  `resume_active_task()` (§37).
- `open_file(file, options)` — B-INIT-3 (`position='left'` now a real left
  vnew via `leftabove`) + B3 (independent `options.width` for vertical splits,
  `options.height` for horizontal) fixed. Ex command built via `M.deps.exec`.
- `edit_journal`, `edit_todo`, `get_current_task` (B-INIT-1: clean
  `{marker='',title='',tags={},cont=''}`, never throws),
  `insert_and_open_continuation`, `get_all_journal_files`.
- Active-task timer: `activate_current_task`, `deactivate_active_task`,
  `add_active_task_to_airline`. On-disk `task.log`/`awiwi.log` written via `io`;
  records are `vim.json.encode`d (new internal format, not byte-compatible with
  the old vimscript `string()` lines — allowed per §35). `M._active_task` is the
  in-memory state; `M.now()` is the injectable clock.
- `open_link` (B-INIT-4: early return after the empty-type error — the
  redundant second message is dropped; noted below), `redact`, `copy_file`,
  `insert_recipe_link`, `insert_journal_link` (B-INIT-2: stray `)` dropped),
  `handle_paste_in_insert_mode`, `guess_selection_mime_type` (ported natively;
  asset.lua keeps its own private copy), `edit_meta_info`, `show_toc_in_qlist`
  (+ `_add_toc_aucmd`, `_toc_should_refresh` — B-INIT-5 dynamic re-check
  replaces the stale window number), `fuzzy_search` (routed through
  `picker.grep` — ADR-flag, see below).
- ftplugin logic (kept in init.lua so it's headlessly testable, wired from
  `ftplugin/awiwi.lua`): `handle_enter_on_insert`, `handle_enter`,
  `append_to_line`, `split_screen`/`_split_screen_result`, `delete_old_tasks`
  (§84 B6 fix — pure Lua, scans last→first line inclusive), `foldexpr` (B7).
- `M.deps` = `{system, exec}`; `M.now`. All injectable; specs never touch the
  real filesystem/clipboard/xdg outside `vim.fn.tempname()`.

### Wiring done at load (require('awiwi'))
- Rebinds every `cmd.deps.*` T10 injection point (all 14 vimshims + the 4
  subpath/journal-file helpers) to the corresponding `init.lua` function.
- `asset.deps.open_file = M.open_file` (asset's default was a bare `:edit`).
- `server.config.get_markers = markers.get_markers` (its default pointed at the
  now-deleted `awiwi#get_markers` VimL — server.md's flagged loose end, closed).
- Bootstraps if `g:awiwi_home` is set.

### ftplugin/awiwi.lua & ftdetect/awiwi.lua
- ftplugin: `:Awiwi` (global, idempotent user command), all buffer mappings 1:1
  (`<F12>` rewired to `:Awiwi tags<CR>` per cmd.md B7), buffer options
  (concealcursor, foldmethod=expr + Lua foldexpr, nowrap), the four autocmd
  groups (autosave, delete-old-tasks, todo-due-dates, horizontal-lines),
  syn activation (`setup_highlights` + per-buffer `attach`, `detach` on
  BufUnload — net-new for T10), iabbrevs, optional server autostart + optional
  entitlement (both dogfood-gated), `doautocmd User AwiwiInitPost`. **B8**: no
  `set updatetime` mutation anywhere.
- ftdetect: filetype-detection autocmds (§80-83, empty-or-markdown guard
  preserved) + aP/iP text objects on every `BufRead *.md`.
- `ftplugin/awiwi.lua` covers all compound filetypes (`awiwi`, `awiwi.todo`,
  `awiwi.asset`, `awiwi.recipe`) since Neovim loads it per `.`-component.

### Deviations from the brief / decisions
- **B-INIT-4 fixed (not preserved)**: added the missing early `return` after the
  empty-type error; only one error message now (engineer's discretion per §44).
- **`fuzzy_search` -> `picker.grep`** (ADR-worthy, mirrors cmd.md C12): the
  bespoke `fzf#vim#grep` call is gone; `:Awiwi search` now uses the same picker
  backend as every other fuzzy surface (`--color=never`, telescope-upgradeable).
  Flag for `docs/decisions.md`.
- **B-INIT-6 (`g:awiwi_history_length` inert log-rotation)**: preserved as inert
  — the two dead locals are simply not ported; no new rotation behavior added.
- **`edit_journal`**: dropped the vimscript's stray `echo "hello"` debug line in
  the `get_own_date` catch (clearly debug junk, not a contract behavior).
- **`add_active_task_to_airline`**: durations computed arithmetically (matches
  §39 exactly) instead of the vimscript's timezone-sensitive `strftime(dur)`.
- **task.log on-disk format** is now JSON (`vim.json`) rather than vimscript
  `string()` dict literals — allowed per §35 (internal cache file). Old lines
  fail to decode and are ignored gracefully.

### Preserved quirks (with in-code comments)
- `open_file`'s double space before the filename when there is no jump modifier
  (`printf('%s %s %s', cmd, '', file)`) — faithful; harmless to `:edit`.
- `split_screen`'s inverted `<C-x>`/`<C-v>` cmdline guard (`match(...)==1` never
  fires, so the split flag is injected even for `:Awiwi ...`) — reproduced
  verbatim per the task's "preserve + human ADR" instruction. `_split_screen_result`
  isolates the pure logic for testing.
- `edit_meta_info`'s `^to\%[mmorow]\+$` tomorrow-abbreviation typo — verbatim.
- `hi.get_meta_and_pos` (and therefore `append_to_line`) only recognizes the
  `{...}` blob on an open `* [ ] ` checklist line — faithful to the vimscript gate.
- Two `setqflist` calls (entries, then title-only) in `show_toc_in_qlist`.

### Edits outside the core boundary
- **None** to other `lua/awiwi/*.lua` modules or their specs. The B3
  `options.width` fix landed inside `init.lua`'s own `open_file` (the façade
  owns file-opening policy; the opener is init's). `cmd.deps`/`asset.deps`/
  `server.config` are rebound at load-time via their public injection tables
  (not source edits).

### Gotchas for the dogfooder
- Entitlement wiring (`ftplugin/awiwi.lua`) is dogfood-only and untested; it
  passes ported `hi.*` Lua functions as `fn` in the entitlement opts. If
  `entitlement#add_title` needs a vimscript funcref, pass your own
  `g:awiwi_use_entitlement_opts`.
- `:Awiwi serve` / `server start` still depend on the FastAPI entrypoint
  placeholder (server.md ADR D5) — unchanged by T10.
- Real clipboard/xdg/fzf/telescope/airline/folding paths are in the Dogfood
  checklist above (headless can't exercise them).

### Files deleted (git rm, switchover)
```
autoload/awiwi.vim
autoload/awiwi/asset.vim
autoload/awiwi/cmd.vim
autoload/awiwi/dao.vim
autoload/awiwi/date.vim
autoload/awiwi/hi.vim
autoload/awiwi/path.vim
autoload/awiwi/server.vim
autoload/awiwi/sql.vim
autoload/awiwi/str.vim
autoload/awiwi/task.vim
autoload/awiwi/util.vim
autoload/awiwi/view.vim
syntax/awiwi.vim
ftplugin/awiwi.vim   (replaced by ftplugin/awiwi.lua)
ftdetect/awiwi.vim   (replaced by ftdetect/awiwi.lua)
```
Untracked `autoload/awiwi/ask.vim` + `autoload/awiwi/bookmarks.vim` left alone
(not tracked, out of scope — flagged for human judgement).

### For kb-curator / sync-docs (I did not edit docs)
- Flip `docs/architecture.md` module-map row for `awiwi.vim` (939 / active) to
  ported, and record the T10 switchover (all autoload/*.vim + syntax + ftplugin
  + ftdetect now Lua).
- ADR: `:Awiwi search` fuzzy backend now `picker.grep` (was `fzf#vim#grep`).
- Doc note: `g:awiwi_history_length` is currently a no-op (log never rotates).

status: done
commit: 474fb50 + dogfood fixes 85df511 (T10.1), 2878c5f (T10.2) — signed off and merged to master 2026-07-06 after 3-round dogfood

## Dogfood round 1 → T10.1 fixes (2026-07-06)

User findings in `handovers/done/T10-dog-food.md`. Three symptoms, two root causes,
both fixed inline as transaction T10.1 (strict red/green; 3 new specs):

1. **`:Awiwi journal previous|next` / `gn`/`gp` threw `AwiwiDateError`.**
   Root cause: the port broke the legacy `date.vim → awiwi#get_all_journal_files()`
   cycle by dependency-injecting `options.files` into `date.parse_date` — but no
   caller was ever updated to inject it, so the list was always empty. Fix:
   `date.deps.journal_dates` provider seam (defaults to `{}`, keeping the module
   filesystem-free), wired to `M.get_all_journal_files` in the façade's cmd-deps
   wiring block. Specs: `date_spec` (provider fallback), `init_spec` §18b
   (acceptance: 'previous' resolves against real files).
2. **"fences don't work / markers don't work" (base look missing).**
   Root cause: legacy `syntax/awiwi.vim` layered its extras on *base markdown
   syntax* (`containedin=markdownH1..6`, `syn clear markdownListMarker`); the
   T6b/T10 port painted only the awiwi extras and started no base layer at all.
   Fix: `pcall(vim.treesitter.start, buf, "markdown")` in `ftplugin/awiwi.lua`
   before `syn.attach` — bundled markdown parser supplies headings/fences/
   emphasis. Spec: `ftplugin_spec` (highlighter active on awiwi buffer).
3. **"redacted works only after `:set ft=awiwi`" — NOT reproduced headlessly:**
   extmarks (markers, redacted, links) are provably painted at load
   (`awiwi-syn-markers=9` incl. `awiwiRedacted` right after `:edit`). Likely the
   missing base styling made the page read as "unhighlighted" overall; needs
   re-verification in dogfood round 2 after the T10.1 fixes. If it persists,
   suspect a TUI-only redraw/ordering issue around the FileType autocmd.

Verified end-to-end headlessly: `:Awiwi journal previous` from 2026-07-06 opens
2026-07-05.md, `next` returns, `vim.treesitter.highlighter.active[buf]` truthy.

## Dogfood round 2 → T10.2 fix (2026-07-06)

Round-2 verdict: gn/gp/ge work, syntax rendering smooth. One new finding:
**links rendered as raw markdown** instead of the concealed `▶name (…)` form.
Root cause: syn's conceal extmarks were always correct, but conceal only
renders with `'conceallevel' >= 1`, which legacy never set (it relied on the
user's global config — see syn.md Port notes "Conceal via extmarks"). Fix
(user-sanctioned improvement over shipped behavior): window-local
`conceallevel = 2` in ftplugin/awiwi.lua next to `concealcursor`. Spec:
ftplugin_spec "sets window conceallevel". Verified by headless screen-scrape:
`see [pancakes](../../../recipes/basics/pancakes.md) and` renders as
`see ▶pancakes … and`. Suite 458 green (14 files).
