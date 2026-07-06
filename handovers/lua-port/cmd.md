# lua-port / cmd

**Responsibility:** `:Awiwi <sub> [args…]` command parsing, dispatch (`run`), and
completion (`get_completion`) for the entire plugin surface; plus three
loosely-related helper entry points bolted onto the same autoload file:
session save/restore (`mksession`), the `show_tasks`/`tags` rg+fzf marker
search, and async drawio→PDF export via `jobstart`.

**Source:** `autoload/awiwi/cmd.vim`, 780 lines. Matches `docs/architecture.md`
module-map row (`cmd.vim | 780 | active | ...`).

**Port order:** T9, last leaf module before the façade (`awiwi.vim` → `init.lua`,
T10). Per `.claude/skills/lua-port/SKILL.md` port order: `str → path → date →
util → asset → hi → server → sql → cmd → façade`. This brief assumes `sql`
(T8) is already ported — **it is not consulted anywhere in `cmd.vim`** (no
`awiwi#sql#`/`awiwi#dao#` call sites found by grep), so `cmd.lua` has no
dependency on `sql.lua` in practice.

---

## Public surface (today, vimscript)

- `awiwi#cmd#get_completion(ArgLead, CmdLine, CursorPos)` — wired via
  `-complete=customlist,awiwi#cmd#get_completion` on the `:Awiwi` user command
  (`ftplugin/awiwi.vim:23`).
- `awiwi#cmd#run(...)` — wired via `command! -nargs=* ... call
  awiwi#cmd#run(<f-args>)` (`ftplugin/awiwi.vim:25`). `<f-args>` means every
  argument arrives as a separate string in `a:000`; the shell-like quoting/
  escaping `<f-args>` does still applies (e.g. `!bookmark`/`#anchor` arrive as
  literal tokens, not specially parsed by Vim).
- `awiwi#cmd#show_tasks(...)` — also called directly via `fn#apply` from
  `run()` for the `tags` subcommand; **not** independently `-complete`-wired,
  so it is only reachable through `:Awiwi tags ...`.
- `awiwi#cmd#store_session()` / `awiwi#cmd#restore_session()` — thin
  `mksession!`/`source` wrappers around `<g:awiwi_home>/session.vim`
  (`s:session_file = awiwi#path#join(g:awiwi_home, 'session.vim')`).
- `awiwi#cmd#export_drawio_diagram(...)` — async drawio→PDF export via
  `jobstart`.
- `awiwi#cmd#get_cmd(name)` — a string-constant registry (`s:<name>_cmd` →
  value), e.g. `get_cmd('paste_asset')` → `'paste'`. **Already fully
  superseded** by `require('awiwi.asset').types` (asset.md's `## Ported`
  section: `M.types = { empty = "empty", url = "url", paste = "paste" }`).
  Confirmed by grep: the only cross-module callers of `awiwi#cmd#get_cmd` are
  `autoload/awiwi.vim:745` (`get_cmd('paste_asset')`, a T10 façade call site —
  see Call sites below) and `autoload/awiwi/asset.vim:41,69,73,79` (all
  `'paste_asset'`/`'empty_asset'`/`'url_asset'`, i.e. exactly the three values
  `asset.lua`'s `M.types` already owns). **`get_cmd` does not need a Lua
  port** beyond what `asset.lua` already provides; do not reintroduce it as a
  general string-constant registry in `cmd.lua`. The one remaining vimscript
  caller (`awiwi.vim:745`) will itself be ported to `require('awiwi.asset').types.paste`
  in T10.

---

## Behavior contract

Numbering: `C<n>`. "Args" below are the tokens *after* the subcommand keyword
in `a:000`/`args`. All subcommands are matched against `s:subcommands`
(`cmd.vim:42-64`): `activate, continue, due, deactivate, export, journal,
entries, asset, link, paste, recipe, redact, meta, restore, save, search,
serve, server, tags, toc, todo`. Note `paste` (`s:paste_asset_cmd`) is a
**top-level alias registered in `s:subcommands`** for `asset paste` — this is
real, shipped behavior, not a typo, but it is **not documented in
architecture.md's "Command surface" table** (`docs/architecture.md:67-84`
lists only `asset [create [url|paste|copy]|paste|<date:name>]`, i.e. `paste`
nested under `asset`, never as its own row). **Mismatch found** — recommend
adding a `paste` row (or a footnote under `asset`) to the table in the same
commit that ports `cmd.lua`.

### `run` dispatch — top-level `if/elseif` chain (`cmd.vim:466-643`)

1. **C1 — no args**: `run()` with zero args throws
   `AwiwiCmdError: Awiwi expects 1+ arguments` (`cmd.vim:467-469`). Unreachable
   in practice since `:Awiwi` requires `-nargs=*` but the ftplugin's mapped
   invocations always pass at least a subcommand; still part of the contract
   for a bare `:Awiwi` (which Vim's `-nargs=*` allows) with 0 args.
2. **C2 — unknown/unimplemented subcommand**: falls through the entire
   `if/elseif` chain silently — **no `else`, no error**. `:Awiwi bogus` (or
   `:Awiwi tasks`, or `:Awiwi ask ...`) is a silent no-op. This is the root
   cause of the F12/`tasks` mismatch (see Bugs).
3. **C3 — `journal` bare** (`a:1 == 'journal'`, `a:0 == 1`): opens
   `fzf#vim#files(<journal_subpath>, fzf#vim#with_preview())` — standard
   fzf.vim file picker over `g:awiwi_home/journal`, default fzf.vim sink
   (`:e`/`:tabe`/`:sp` depending on the fzf.vim action bound key). See
   Pickers §P1.
4. **C4 — `journal <date-expr> [flags]`**: parses via
   `s:parse_file_and_options` (options default
   `{position:'auto', new_window:false, new_tab:false, create_dirs:false,
   bookmark:false}`), then `awiwi#edit_journal(date, options)`. `date-expr` is
   resolved by `awiwi#date#parse_date` inside `edit_journal` (already ported —
   `date.lua`'s `M.parse_date`), so `today`/`next`/`previous`/`YYYY-MM-DD`/etc.
   all work per date.md's contract. `+create` sets `options.create_dirs`;
   opening a **future** date's journal without `+create` and without the file
   already being writable errors (`awiwi#edit_journal`, façade, T10).
5. **C5 — `link journal` bare** (`a:1=='link' and a:2=='journal'`, exactly 2
   args): opens a **different** fzf picker — `fzf#run(fzf#wrap({source:
   <journal files + literals>, sink: insert_journal_link}))`. See Pickers §P2.
   This is the "pick a journal file to *link to*" flow, distinct from C3's
   "pick a journal file to *open*" flow — same subpath, different fzf
   backend call (`fzf#run`+`fzf#wrap` vs `fzf#vim#files`) and different sink.
6. **C6 — `link journal <date-expr> [flags]`**: same parse as C4 but calls
   `awiwi#insert_journal_link(date, options)` (inserts a markdown link at
   cursor) instead of opening a buffer. `options.new_window` defaults to
   `false` here (irrelevant since nothing is opened).
7. **C7 — `export`**: `awiwi#cmd#export_drawio_diagram()` — see §Export below.
8. **C8 — `continue`**: `awiwi#insert_and_open_continuation()` (façade, T10;
   no args consumed).
9. **C9 — `activate`**: `awiwi#activate_current_task()` (façade, T10).
10. **C10 — `deactivate`**: `awiwi#deactivate_active_task()` (façade, T10).
11. **C11 — `paste` (top-level) or `asset paste`**: both routes to
    `awiwi#asset#create_asset_here_if_not_exists(s:paste_asset_cmd)` →
    **already ported**: `require('awiwi.asset').create_asset_here_if_not_exists('paste', opts, on_done)`.
    Note the vimscript call passes only one positional arg (`s:paste_asset_cmd`)
    — `cmd.lua` must supply `opts={}` and a completion callback per asset.lua's
    ported (callback-style) signature.
12. **C12 — `asset` bare** (`a:0==1`): `fzf#vim#files(<asset_subpath>,
    fzf#vim#with_preview())`. A commented-out alternative (`cmd.vim:501-502`)
    shows the *intended* richer picker (`date:name`-labelled fzf source +
    `awiwi#asset#open_asset_sink`) was abandoned in favor of the plain
    file-browser — `asset.lua`'s `M.open_asset_sink` is "kept live (future
    telescope-picker sink)" per asset.md, i.e. the port is expected to
    **revive** this richer picker. See Pickers §P3/§P3'.
13. **C13 — `asset copy`**: reads the link under cursor
    (`require('awiwi.util').get_link_under_cursor()`, already ported), errors
    `[ERROR] no asset file under cursor` if `link.type ~= 'asset'`, else
    resolves the absolute path (`path.canonicalize(path.join(dirname(current
    buffer), link.target))`, both ported) and calls `awiwi#copy_file(dest)`
    (façade, T10 — shells to `xclip -selection clipboard -r <path>`).
14. **C14 — `asset create url`**:
    `require('awiwi.asset').create_asset_here_if_not_exists('url', opts, on_done)`.
15. **C15 — `asset create paste`**: same as C11, via `asset create paste`.
16. **C16 — `asset create <name...>`** (anything else after `create`):
    `require('awiwi.asset').create_asset_here_if_not_exists('empty', {suffix='.md', ...rest_of_args}, on_done)`,
    **then unconditionally `write`s the current buffer**, then
    `require('awiwi.asset').open_asset(filename, {new_window=true})`.
    **Caution**: this `write` happens on the *journal/host* buffer (the one
    the user is editing when they typed `:Awiwi asset create foo`), not on
    the newly created asset — that is intentional (persisting the just-inserted
    asset link before jumping away) and is unrelated to asset.md's B-new-1 fix
    (which was about `open_asset*` no longer auto-writing the *asset* file
    itself). Preserve this `write` as-is.
17. **C17 — `asset <date:name-or-name> [flags]` / `link asset <...>`**: parses
    via `s:parse_file_and_options`; if the file token contains `:` splits into
    `date:file`, else defaults `date = <today's date>` (already-ported
    `require('awiwi.date')`'s "own date" helper — actually `awiwi#date#get_own_date()`,
    façade in `awiwi.vim`... **check**: `get_own_date` is *not* in date.lua's
    ported public surface per date.md (only `get_today`, `to_tuple`, `is_date`,
    `to_iso_date`, `parse_date`, `to_nice_date` are listed) — re-verify with
    the date.lua source before porting; if `get_own_date` was dropped, `cmd.lua`
    needs either a `date.lua` addition (out of scope for this transaction —
    flag back to orchestrator) or a `M.deps.get_own_date` façade injection
    point (T10) as a stopgap). Then: `link asset` →
    `require('awiwi.asset').insert_asset_link(date, file, opts)`; bare `asset`
    → `require('awiwi.asset').open_asset_by_name(date, file, opts)`.
18. **C18 — `recipe` bare / `link recipe` bare**: `fzf#vim#files(<recipe_subpath>, fzf_opts)`
    for bare `recipe`, or the same `fzf#vim#files` call but with a custom
    `sink=insert_recipe_link` for `link recipe`. **Bug**: the bare-`recipe`
    branch also does `let oshell = &shell | set shell=/bin/sh` before the fzf
    call and **never restores** `&shell` — see Bugs §B1.
19. **C19 — `recipe <name> [flags]` / `link recipe <name> [flags]`**: parses
    via `s:parse_file_and_options`; appends `.md` if missing
    (`require('awiwi.str').endswith`, ported); forces `options.create_dirs =
    true` unconditionally (recipes are always creatable, unlike journal/asset
    which require an explicit `+create`); bare `recipe` →
    `awiwi#open_file(recipe_file, options)` (façade, T10); `link recipe` →
    `awiwi#insert_recipe_link(recipe, options)` (façade, T10).
20. **C20 — `tags [subcmd...]`**: `awiwi#cmd#show_tasks(...)` — see §show_tasks
    below (own numbered contract, C-tags-*).
21. **C21 — `search <pattern...>`**: `awiwi#fuzzy_search(...)` (façade, T10) —
    joins remaining args with spaces (not per-arg escaping — see
    `awiwi#fuzzy_search`'s commented-out `escape_pattern` line, dead), builds
    an `rg -i -U --multiline-dotall ...` command, temporarily sets
    `&shell=/bin/sh` **with a `try/finally` that does restore it** (unlike
    C18's recipe picker — contrast for the bug writeup), and feeds it to
    `fzf#vim#grep`.
22. **C22 — `serve`**: `require('awiwi.server').serve()` (already ported, no
    change needed).
23. **C23 — `server` bare** (`a:0==1`): `echoerr 'Awiwi server command needs
    further arguments'`, no-op.
24. **C24 — `server start [host] [port]`**: `require('awiwi.server').start_server(host, port)`
    — `host` defaults to the *literal string* `'localhost'` if omitted
    (`get(a:000, 2, 'localhost')` — NB this is `a:000` not `a:000[2:]`, so
    index `2` is actually the 3rd element of `a:000`, i.e. the first arg
    *after* `server start`; verify this off-by-nothing is correct by reading
    `a:000` layout: `a:000 = ['server', 'start', host?, port?]`, so
    `a:000[2]` is indeed `host` — consistent), `port` defaults to
    `require('awiwi.server').get_default_port()` (ported).
25. **C25 — `server stop`**: `require('awiwi.server').stop_server()` (ported).
26. **C26 — `server logs [stdout|stderr|exit]`**: `require('awiwi.server').server_logs(log_type)`
    (ported) — note the vimscript reads the log-type arg via `get(a:000, 2,
    '')`, i.e. **the same index-2 slot used for `start`'s host** — for `logs`
    this is the first arg after `server logs`, correctly the log-type token.
27. **C27 — `redact`**: `awiwi#redact()` (façade, T10) — toggles a trailing
    `!!redacted` tag on the current line (idempotent add/remove), preserves
    cursor position.
28. **C28 — `due <spec...>`**: `awiwi#edit_meta_info({delete:false,
    column:'due', args: <rest>})` (façade, T10) — writes/updates the `due`
    key in the current line's trailing `{...}` JSON meta blob.
29. **C29 — `meta delete`**: `awiwi#edit_meta_info({delete:true})` — strips
    the trailing `{...}` blob from the current line entirely.
30. **C30 — `meta edit [column]`**: `awiwi#edit_meta_info({column: <col-or-''>})`
    — prompts (via the façade, ultimately `vim.ui.input` post-util-port) for a
    value and sets `json[column] = value` in the line's meta blob.
31. **C31 — `meta <anything-else>`**: `echo 'error: got unknown command:
    "Awiwi meta <x>"'` then return — **note**: uses `echo`, not `echoerr`
    (inconsistent with every other error path in this file, which uses
    `echoerr`). Preserve the distinction (echo vs echoerr) or normalize as a
    port-note decision — flag, don't silently pick one.
32. **C32 — `entries`**: rg-searches all files under `g:awiwi_home` (`-g
    '!awiwi*'` excludes plugin-named files) for markdown ATX headings
    (`^#{2,}[[:space:]]+.*$`), strips the leading `##+ ` marker from each hit,
    filters empty lines, feeds the result into a **sinkless** `fzf#run` — see
    Pickers §P4 and Bugs §B2 (no navigation wired).
33. **C33 — `todo [name] [flags]`**: default open options depend on the
    *current buffer's directory basename* — if editing a file already inside
    a `todos/` directory, defaults to `{new_window:true, position:'top',
    new_tab:false}`; otherwise `{new_window:false, new_tab:true}`. Parses via
    `s:parse_file_and_options(a:000, default_opts)` (note: **passes the full
    `a:000` including the `todo` keyword itself as arg[0]** — unlike every
    other subcommand which slices `a:000[1:]` — this works only because
    `s:parse_file_and_options` treats any non-flag/non-`#anchor` token as
    "the file", and `'todo'` itself gets overwritten by the real filename if
    one follows, or **becomes the file name itself** if no filename is given,
    which is then remapped: `file == 'todo' ? 'inprogress' : file` — i.e.
    `:Awiwi todo` bare defaults to the `inprogress` todo file). Calls
    `awiwi#edit_todo(file, options)` (façade, T10 — opens
    `<todos_subpath>/<file>.md`).
34. **C34 — `save`**: `awiwi#cmd#store_session()` → `mksession!
    <g:awiwi_home>/session.vim`.
35. **C35 — `restore`**: `awiwi#cmd#restore_session()` → `source
    <g:awiwi_home>/session.vim`. Throws Vim's own error if the file doesn't
    exist (no existence check).
36. **C36 — `toc` bare**: `date = require('awiwi.date').get_own_date()` (or
    façade fallback — same caveat as C17), then
    `awiwi#show_toc_in_qlist({date=date})` (façade, T10) — builds a quickfix
    list of headings from the resolved journal file(s) and `copen`s.
37. **C37 — `toc <date-parts...>`**: joins `a:000[1:]` (already
    hyphen-fragment tokens, e.g. `toc 2024 03` → args `['2024','03']`) by
    re-splitting each on `-` and taking only the first two flattened
    components (`...reduce(...)[:1]->join('-')`) — i.e. `toc` only ever
    resolves to a `YYYY` or `YYYY-MM` prefix for the quickfix scope, never a
    full day; passes that string as `date` to `show_toc_in_qlist`, which
    branches on `awiwi#date#is_date(date)` (full-date) vs prefix.
38. **`ask` (dead)**: `s:ask_cmd = 'ask'` constant is defined (`cmd.vim:26`)
    but **absent from `s:subcommands`** (so it never completes) and has **no
    branch in `run()`**. Fully inert. Matches architecture.md's `ask.vim: 0
    LOC, stub` row — one paragraph, not ported: the constant is vestigial
    dead code left over from a planned feature that never got an
    implementation; drop it, do not carry a placeholder branch into
    `cmd.lua`.
39. **`!bookmark` flag (dead at runtime)**: `s:bookmark_cmd = '!bookmark'` is
    a recognized token in `s:journal_options_cmd` and IS parsed by
    `s:parse_file_and_options` into `options.bookmark = true` for
    `journal`/`asset`/`recipe` alike — but **no code path ever reads
    `options.bookmark`** (`cmd.vim:484` has it as a dead `"` comment:
    `" elseif options.bookmark`). This ties to `bookmarks.vim`, which is
    itself dead (`awiwi#join` undefined, per architecture.md). Recommend:
    **drop the flag entirely** from `cmd.lua`'s option-parsing (don't
    silently accept `!bookmark` and do nothing — either wire it to a real
    bookmarks feature if/when `bookmarks.vim` is revived, or reject/ignore it
    loudly). Human/ADR decides; document the current behavior (silently
    accepted, silently ignored) either way.

### `s:parse_file_and_options(args, defaults?)` — shared arg-parser for
`journal`/`asset`/`recipe`/`todo`

40. **C40**: Errors (`echoerr`, non-fatal — vimscript `echoerr` doesn't
    `:return`, so execution **continues** past it, likely into `E731`/nil-index
    errors downstream) if `len(args)` is 0 or `>3`. Preserve or harden — this
    is an unusual "warn but keep going" bug pattern in raw vimscript.
41. **C41**: Recognizes 7 option tokens: `+new` (`position=auto,
    new_window=true`), `+hnew` (`position=bottom, new_window=true`), `+vnew`
    (`position=right, new_window=true`), `-new` (`new_window=false`), `+tab`
    (`new_window=false, new_tab=true`), `+create` (`create_dirs=true`),
    `!bookmark` (`bookmark=true`, dead per #39).
42. **C42**: `+height=N` / `+width=N` (both stored into the **same**
    `options.height` key — vimscript: `let options.height =
    str2nr(split(arg,'=')[-1])` runs for *both* `+height=` and `+width=`
    matches, meaning `+width=40` sets `options.height`, not a separate width
    field). **Bug** — see §B3.
43. **C43**: `#<anchor>` (any token starting with `#`) sets `options.anchor`
    to the remainder.
44. **C44**: any token not matching the above and not a recognized flag is
    the file/date-expr; **last one wins** if multiple non-flag tokens appear
    (no error for extra file tokens, silently overwritten).
45. **C45**: if no explicit height/width was given and
    `require('awiwi.util').window_split_below()` (ported) is true, defaults
    `options.height = 20`.
46. **C46**: if no file token was ever found, `echoerr 'Awiwi journal: missing
    file to open'` — same non-fatal `echoerr` caveat as C40.

### `get_completion` — `customlist` completion function

47. **C47**: `current_arg_pos < 2` → completes subcommand names from
    `s:subcommands` via `require('awiwi.util').match_subcommands` (ported).
    `current_arg_pos` comes from `require('awiwi.util').get_argument_number`
    (ported) applied to `CmdLine[:CursorPos]`.
48. **C48 — `tags` completion**: position 2 → all `s:tags_subcommands`
    (`all,due,filter,urgent,onhold,question,todo,incidents,changes,issues,bugs`).
    Position 3 when arg[2]=='filter' → `[]` (no completion after `filter`,
    since it takes a free-text rg pattern). Otherwise: previously-used tokens
    (deduped) plus `filter` are excluded from the candidate list (so you can't
    pick `todo` twice, but multiple distinct tag categories can be chained:
    `:Awiwi tags urgent due <Tab>` still offers `onhold`/`question`/etc.).
49. **C49 — `journal`/`link journal` completion**: when no file/date token has
    been typed yet (`s:need_to_insert_files`), offers all journal files (basename,
    via the façade `awiwi#get_all_journal_files()` — **not yet given `include_literals`
    here**, unlike run()'s C5 fzf source) with `todos` moved out and
    `['todos','today','next','previous']` prepended (order matters: these 4
    literals always come first in the candidate list). For plain `journal`
    (not `link journal`), also appends the 7 journal window/flag options
    (`s:insert_win_cmds`) once a file token exists position-wise. For
    `link journal ... #` (cursor right after a bare `#`), instead completes
    **markdown heading anchors** from the target file — see §C52 below —
    stripping a leading heading if it looks like a bare `#2024...` numeric
    heading (journal date headers), via regex `^#\s\+2[-0-9]\+\s*$`.
50. **C50 — `asset`/`link asset` completion**: at `asset create` (position
    >2, arg[2]=='create'), completes only `[paste, url, copy]`. At the top
    level (`len(args)==2`, i.e. right after typing `asset`/`link asset `),
    seeds `[create, paste]`. When no file token yet, adds all asset files
    formatted `date:name` (via façade `awiwi#asset#get_all_asset_files()` →
    **should become** `require('awiwi.asset').get_all_asset_files()`, already
    ported) plus `create`/`paste` again (duplicate insert — harmless, fzf/Vim
    completion de-dupes visually but the raw candidate list literally
    contains `create`/`paste` twice when both C50's `len(args)==2` branch and
    this branch fire in the same call — verify with a test whether both
    branches can fire simultaneously; they can, since `len(args)==2` doesn't
    exclude `s:need_to_insert_files`). For `link asset ... #`, same heading
    completion as C49.
51. **C51 — `recipe`/`link recipe` completion**: file-completion lists every
    readable file under `<recipe_subpath>` (`s:get_all_recipe_files`, see
    §B4 — the `prefix_len` bug lives here) plus window-flag completion for
    bare `recipe`; `#` anchor completion same pattern as C49/C50.
52. **C52 — heading/anchor completion** (`s:get_headings_from_file`): shells
    `rg '^#+ ' <file>` and slugifies each match (lowercase, strip leading
    `#+\s+`, strip everything except `[a-zA-Z0-9 -]`, spaces→`-`, drop `/`).
    This is a **hand-rolled markdown-heading-to-anchor-slug** algorithm —
    good treesitter opportunity (see Port notes) but must reproduce this
    *exact* slug algorithm (case fold, character whitelist, space-to-hyphen)
    since it's presumably matched against however headings are rendered as
    anchors elsewhere (likely the server's TOC/anchor logic — cross-check
    with server.lua/server-side markdown rendering before changing the
    algorithm).
53. **C53 — `todo` completion**: offers `s:todo_subcommands`
    (`inprogress,backlog,done,onhold,questions` — **note**: `s:todo_waiting_cmd`
    and `s:todo_onhold_cmd`/`s:todo_questions_cmd` constants exist but
    `s:todo_subcommands` only actually includes 5 of the 6 defined
    `s:todo_*_cmd` constants — `waiting` is defined at `cmd.vim:119` but never
    added to `s:todo_subcommands` at `cmd.vim:123-129`. Minor dead constant,
    same class of bug as `ask` — flag, don't silently "fix" by adding it back
    without an ADR) plus window-flag completions (offset by `+1` — the call
    passes `current_arg_pos+1, args[2:]`, an odd asymmetry vs. every other
    subcommand's `insert_win_cmds` call which uses the raw `current_arg_pos` —
    verify this offset is intentional/necessary before porting verbatim; write
    a completion test that pins the exact candidate list at each cursor
    position for `todo` to catch a regression either way).
54. **C54 — `meta` completion**: position 2 → `[edit, delete]`; position 3
    when arg[2]=='edit' → `[created, due]` (column names).
55. **C55 — `due`/`meta edit due` completion**: position `start` (2 for bare
    `due`, 4 for `meta edit due`) → `[today, tomorrow, next, in, +,
    Mon..Sun]`. If `next`, next position → `[Mon..Sun, day, week, month,
    year]`. If `in`/`+`, position `start+2` → `[day, week, month, year]`,
    pluralized (`+s`) unless the immediately preceding token is literally
    `'1'`.
56. **C56 — `server` completion**: position 2 → `[stop-or-start (whichever
    is NOT currently running, via require('awiwi.server').server_is_running()), logs]`
    — i.e. the completion candidate flips live based on server state (only
    ever offers `start` when stopped, `stop` when running — never both).
    Position 3 after `start` → `[localhost, *]`. Position 3 after `logs` →
    `[stdout, stderr, exit]`.
57. **C57 — `link` (bare)** completion: `[journal, recipe, asset]`.
58. **C58 — no match**: returns `[]` for every other combination (including
    `activate`, `deactivate`, `continue`, `export`, `redact`, `save`,
    `restore`, `search`, `serve`, `entries`, `toc`, `paste` — none of these
    get any argument completion beyond the initial subcommand-name match).

### `show_tasks` (a.k.a. `tags` dispatch)

59. **C-tags-1**: `a:000` defaults to `['todo']` if called with zero args
    (only reachable if someone calls `awiwi#cmd#show_tasks()` directly — via
    `:Awiwi tags` the dispatcher always forwards at least the rest of
    `a:000`, which could itself be empty, e.g. bare `:Awiwi tags` → `a:000[1:]`
    is `[]` → `fn#apply`/`fn#spread` calls `show_tasks()` with 0 args → default
    applies).
60. **C-tags-2**: builds an OR'd rg alternation pattern from
    `require('awiwi.markers').get_markers(<type>)` (ported) for each
    requested category (`urgent` fires on `urgent|all|todo`; `todo` fires on
    `todo|all`; `due` fires on `due|all` and additionally wraps the due
    marker in `\(?(<due>):?( \S+)*\)?` and sets a `has_due` flag; `onhold`,
    `question`, `incidents`→`incident`, `changes`→`change`, `issues`→`issue`,
    `bugs`→`bug` each fire on `<name>|all`).
61. **C-tags-3 — `filter <pattern...>`**: if `args[0] == 'filter'`, throws
    `AwiwiCmdError: missing argument for "Awiwi tasks filter"` if no further
    args, else appends the raw remaining args (each treated as its own
    alternation branch, not escaped) to the marker list.
62. **C-tags-4**: final rg invocation:
    `rg -u --column --line-number --no-heading --color=always -g
    '!awiwi*' <pattern>` piped (**shell string concatenation via `join(...,
    ' ')`**, i.e. a literal `|` token concatenated into the single command
    string later passed to `fzf#vim#grep`) through a second `rg -v
    --color=always <anti_pattern>` **only if `has_due`** (excludes already
    checked-off (`[x]`) or struck-through (`~~...~~`) due-marker lines from
    the due search). Rendered via `fzf#vim#grep(<cmd-string>, 1,
    fzf#vim#with_preview('right:50%:hidden','?'), 0)`. See Pickers §P5 —
    this is the one fzf call in the whole file that's a "real" grep-picker
    (location-aware, standard fzf.vim ripgrep-integration semantics) unlike
    §P4's broken `entries`.
63. **C-tags-5**: `shellescape` is applied to the `-g` glob and the full
    pattern (and the anti-pattern) before joining into the single shell
    command string handed to `fzf#vim#grep` — this only works because
    `fzf#vim#grep`'s first arg is a raw shell command line, run through
    `&shell`. Any Lua port must preserve "run through the user's shell" (or
    deliberately re-architect away from shelling out a compound `rg | rg -v`
    pipeline into two `vim.system` calls chained manually) — flag as a
    port-notes decision (see Port notes).

### `export_drawio_diagram`

64. **C-export-1**: if called with an explicit filename arg, uses it;
    otherwise scans the current line for a `(...\.drawio)` markdown-link-style
    reference (`matchstr(line, '(\zs[^)]*\.drawio\ze)')`); if neither, `echoerr`
    and returns `false`.
65. **C-export-2**: if the resolved input path contains `/assets/`, strips
    everything up to and including that segment (`substitute('^.*/\zeassets/',
    '', '')`) — i.e. converts an absolute path to an `assets/...`-relative
    one. (No corresponding cwd-join happens afterward that's visible in this
    function — the resulting relative path is handed straight to the
    `drawio` CLI as its input arg, so this only works if the editor's cwd
    happens to be `g:awiwi_home` — verify this assumption holds via
    `docs/architecture.md`/`g:awiwi_home` conventions before porting
    verbatim; likely relies on an implicit `:cd` done elsewhere in the
    plugin, not visible in `cmd.vim`.)
66. **C-export-3**: prompts (`require('awiwi.util').input`, ported — but see
    signature-deviation note: this call needs migrating to the new
    `M.input(opts, on_confirm)` callback style) for an output path, default
    `/tmp/<basename-without-ext>.pdf`; aborts with `echoerr` + return `1` if
    the user gives an empty answer.
67. **C-export-4**: spawns `drawio --export --output <output> --crop
    --all-pages <input>` via `jobstart`, tracking per-job state in
    `s:job_data[job_id] = {output, errors:[]}`.
68. **C-export-5**: on stderr, lines containing `'object_proxy.cc'` are
    ignored; lines containing `'Error'` are collected — **but see Bug §B5**,
    this collection is broken (writes to an undefined variable, throws).
69. **C-export-6**: on exit, if no collected errors: `nvim_notify` "converted
    successfully ... (filename copied to clipboard)" at INFO level, and sets
    the `+` register (system clipboard) to the output file path. If errors:
    `nvim_notify` "could not convert to pdf ✖\n\n<errors joined by \n>" at
    ERROR level. Either way, `unlet s:job_data[job_id]` — cleans up job state.
70. **C-export-7**: `jobstart` return `0` (bad arguments) or `-1`
    (non-executable) both produce an `echoerr` — but the `0` branch's message
    is itself broken (undefined `markup_language` var, wrong arg count for
    `printf`) — see Bug §B6.

---

## Call sites

### Who calls `cmd`

- `ftplugin/awiwi.vim:23` — `-complete=customlist,awiwi#cmd#get_completion`
  on the `:Awiwi` user command definition.
- `ftplugin/awiwi.vim:25` — `command! -nargs=* Awiwi call
  awiwi#cmd#run(<f-args>)`.
- `ftplugin/awiwi.vim:34-39` — buffer-local normal-mode maps that shell out to
  `:Awiwi <sub>`: `gC` → `:Awiwi continue`, `gT` → `:Awiwi todo`, `ge` →
  `:Awiwi journal today`, `<F12>` → `:Awiwi tasks` **(mismatch, see Bugs §B7 /
  architecture.md's documented "Known mismatch")**, `gn` → `:Awiwi journal
  next`, `gp` → `:Awiwi journal previous`.
- `ftplugin/awiwi.vim:306-307` — `<C-q>` (normal+insert) → `:Awiwi redact`.
- `ftplugin/awiwi.vim:310-311` — insert-mode `<C-s>` → `Awiwi link ` (leaves
  cursor for the user to keep typing); `<C-b>` → `:Awiwi asset create<CR>`
  (fires C16 immediately, no further args).
- `autoload/awiwi.vim:745` — `awiwi#asset#create_asset_here_if_not_exists(awiwi#cmd#get_cmd('paste_asset'))`
  — a **façade-internal** call into `cmd`'s constant registry, not into `run`/
  `get_completion`. Superseded entirely once T10 ports this line to
  `require('awiwi.asset').types.paste` — `cmd.lua` owes this call site
  nothing.

### What `cmd` calls — already-ported Lua modules (call directly, no `awiwi#…`)

| vimscript call in `cmd.vim` | replace with |
| --- | --- |
| `awiwi#str#endswith`, `awiwi#str#startswith`, `awiwi#str#contains` | `require('awiwi.str')` |
| `awiwi#path#join` | `require('awiwi.path')` |
| `awiwi#util#window_split_below`, `#get_argument_number`, `#match_subcommands`, `#get_link_under_cursor`, `#input` | `require('awiwi.util')` (note `input`'s callback-style migration, see C66) |
| `awiwi#asset#get_asset_path`, `#get_all_asset_files`, `#create_asset_here_if_not_exists`, `#open_asset_by_name`, `#insert_asset_link` | `require('awiwi.asset')` |
| `awiwi#date#get_own_date` — **verify this survived the port**, see C17/C36 caveat | `require('awiwi.date')` (pending verification) |
| `awiwi#server#server_is_running`, `#start_server`, `#stop_server`, `#server_logs`, `#serve`, `#get_default_port` | `require('awiwi.server')` |
| `awiwi#get_markers(<type>)` (defined in `awiwi.vim:179`, called from `cmd.vim`'s `show_tasks`) | `require('awiwi.markers').get_markers(<type>)` |
| `awiwi#path#canonicalize` | `require('awiwi.path')` |

### What `cmd` calls — façade functions NOT yet ported (T10 injection points, `M.deps` pattern per `asset.lua`)

Every non-module `awiwi#<fn>` call site in `cmd.vim`, file:line:

| façade fn | `cmd.vim` call sites | notes |
| --- | --- | --- |
| `awiwi#get_recipe_subpath()` | 191, 192, 196, 315, 546, 549, 559 | also drives `s:get_all_recipe_files`'s glob and the `prefix_len` bug (§B4) |
| `awiwi#get_journal_file_by_date(date)` | 320 | |
| `awiwi#get_all_journal_files(opts?)` | 359, 476 | two different `opts` shapes used (bare vs `{include_literals:true}`) — see C49 vs C5 |
| `awiwi#get_journal_subpath()` | 474 | |
| `awiwi#get_asset_subpath()` | 503 | |
| `awiwi#insert_journal_link(date, opts?)` | 477 (as fzf `sink` funcref), 483 (direct call) | dual use: direct call AND fzf sink — see Pickers §P2 |
| `awiwi#edit_journal(date, opts)` | 486 | |
| `awiwi#insert_and_open_continuation()` | 491 | |
| `awiwi#activate_current_task()` | 493 | |
| `awiwi#deactivate_active_task()` | 495 | |
| `awiwi#copy_file(path)` | 511 | shells to `xclip` |
| `awiwi#insert_recipe_link(recipe, opts?)` | 548 (fzf sink), 562 (direct) | dual use, like journal |
| `awiwi#open_file(file, opts)` | 560 | |
| `awiwi#fuzzy_search(...)` | 568 | own `&shell` save/restore with `try/finally` — contrast with §B1 |
| `awiwi#redact()` | 586 | |
| `awiwi#edit_meta_info(opts)` | 588, 602 | |
| `awiwi#edit_todo(name, opts)` | 628 | |
| `awiwi#show_toc_in_qlist(opts)` | 641 | |

**`M.deps` table for `cmd.lua`** (mirroring `asset.lua`'s pattern per
`asset.md`): every row above becomes a `M.deps.<fn>` default-bound to the
still-vimscript implementation (`vim.fn['awiwi#...']` shim) until T10 lands,
at which point T10 rebinds each to its `init.lua`-ported equivalent. Do not
inline `vim.fn[...]` calls scattered through `cmd.lua`'s body — funnel them
all through `M.deps` for a single swap point, same discipline as `asset.lua`.

### External binaries / other VimL plugins shelled to directly from `cmd.vim`

- `rg` — three independent invocations: `s:get_headings_from_file` (heading
  slugs for anchor completion, C52), `entries` (C32, headings across all
  files), `show_tasks`/`tags` (C-tags-4, the marker/due grep, piped through a
  second `rg -v`).
- `fzf#run` / `fzf#vim#*` — see Pickers section, full inventory below.
- `drawio` (CLI) — via `jobstart`, in `export_drawio_diagram`.
- `xclip` — indirectly, via the façade's `awiwi#copy_file` (not `cmd.vim`
  itself, but reached only through `cmd.vim`'s `asset copy` dispatch, C13).
- `fn#apply` / `fn#spread` — external VimL plugin dependency (`fn.vim`, not
  vendored in this repo), used exactly once: `cmd.vim:566`,
  `call fn#apply('awiwi#cmd#show_tasks', fn#spread(a:000[1:]))` — this is
  just a roundabout `call('awiwi#cmd#show_tasks', a:000[1:])` / in Lua,
  simply `M.show_tasks(unpack(args))`. **Per SKILL.md idiom table**: "drop —
  plain Lua calls; deps on external VimL plugins end here." No Lua
  equivalent needed; this whole indirection disappears in the port.

---

## Pickers

`cmd.lua`'s port must **not** call `fzf#run`/`fzf#vim#*` directly anywhere.
Every fzf usage below gets isolated behind `lua/awiwi/picker.lua`, whose
interface (per the task brief) is: **items + prompt + on_choice callback**.
The concrete backend (fzf-lua, telescope, snacks.nvim picker, or the
guaranteed-available `vim.ui.select` baseline) is being decided by the
orchestrator separately — this brief specs the **seam** (what each picker
needs, not how it renders).

**Baseline guarantee**: `vim.ui.select(items, opts, on_choice)` is always
available in stock Neovim (no plugin dependency) and is a legitimate — if
UX-downgraded, no fuzzy-filter, no preview — implementation of every single
select-one-of-list picker below **except** P1/P3 (file browsers, which need
directory-scoped fuzzy file finding, not a fixed in-memory item list) and P5
(a ripgrep-integrated grep-picker with live preview, which `vim.ui.select`
categorically cannot do — that one needs a real fuzzy-finder backend or a
hand-rolled quickfix-based fallback). Document this distinction in
`picker.lua`'s own module doc: "list pickers" (P2, P4-fixed) vs "file
pickers" (P1, P3) vs "live-grep pickers" (P5).

### P1 — `journal` bare file browser (C3, `cmd.vim:474`)
- **Trigger**: `:Awiwi journal` (no further args).
- **Items source**: all files under `<g:awiwi_home>/journal/**` (fzf.vim's
  own recursive file listing, not `awiwi#get_all_journal_files` — this is a
  raw directory walk, no `.md`-only filter visible at this call site, unlike
  the completion-list version).
- **Selection**: single (fzf.vim default action map — `<CR>`=edit,
  `<C-t>`=tabedit, `<C-x>`=split, `<C-v>`=vsplit, if the user's fzf.vim
  action map is default/unconfigured).
- **Sink**: none explicit — fzf.vim's built-in `:e`-family action.
- **Preview**: yes (`fzf#vim#with_preview()`).
- **Seam type**: file picker (needs `vim.ui.select` fallback documented as
  degraded — no live preview, no recursive fuzzy path matching, just a flat
  `vim.fn.glob` + select).

### P2 — `link journal` bare picker (C5, `cmd.vim:476-478`)
- **Trigger**: `:Awiwi link journal` (exactly 2 args).
- **Items source**: `<journal basenames w/o .md> + [previous day, next day,
  yesterday, today]` (facade `awiwi#get_all_journal_files({include_literals:true})`).
- **Selection**: single (plain `fzf#run`, no `multi:true`).
- **Sink**: `awiwi#insert_journal_link(<selected-string>)` — the selected
  item string is passed straight through as the "date" arg, which
  `insert_journal_link` then feeds to `awiwi#date#parse_date` — so literal
  items like `'today'`/`'yesterday'` must parse correctly through the
  ported `date.lua`'s `M.parse_date` grammar (cross-check against date.md's
  documented grammar: `today`/`prev|previous...`/`next...` are covered;
  `yesterday`/`previous day`/`next day` phrasing needs verifying against
  date.lua's exact accepted strings before wiring this picker's sink).
- **Seam type**: list picker — trivially `vim.ui.select`-able (fixed item
  list, single choice, callback = the sink logic above).

### P3 — `asset` bare file browser (C12, `cmd.vim:503`)
- **Trigger**: `:Awiwi asset` (no further args).
- **Items source**: recursive file walk of `<asset_subpath>` (fzf.vim
  default).
- **Sink**: none explicit (fzf.vim default `:e` action), same class as P1.
- **Seam type**: file picker.

### P3' — richer asset picker (abandoned, `cmd.vim:501-502`, commented out)
- **Not currently reachable** — dead code (commented out), but documents
  clear intent: `source = <asset files formatted 'date:name'>`, `sink =
  awiwi#asset#open_asset_sink` (already ported, kept alive in `asset.lua`
  specifically for this future use per asset.md: `"kept live (future
  telescope-picker sink)"`). **Recommendation**: the port should **revive**
  this as the real P3 implementation (list-picker semantics, not a raw file
  browser) rather than porting the plain `fzf#vim#files` browser verbatim —
  this gives date-grouped, human-labelled asset selection instead of a bare
  file tree. Flag for orchestrator/ADR: behavior upgrade, not purely a
  faithful port. If declined, P3 stays a plain file-picker per above.

### P4 — `recipe` bare file browser (C18, `cmd.vim:546`) / `link recipe` (`cmd.vim:549`)
- **Trigger**: `:Awiwi recipe` bare → file browser (no sink, default `:e`
  action), same class as P1/P3. **Bug**: `&shell` mutated, never restored
  (§B1) — the port drops this shell-mutation entirely (not needed once `rg`/
  fzf backend no longer shells through `&shell=/bin/sh` specifically for
  this call).
- **`link recipe`** (`cmd.vim:548-550`, same file source, different call):
  **Sink**: `awiwi#insert_recipe_link` — same dual-use pattern as P2's
  journal sink.
- **Seam type**: file picker (bare) / could become a list-picker if recipe
  enumeration is cheap enough to pre-materialize (recipe count is presumably
  small — `s:get_all_recipe_files` already globs eagerly for completion, so
  reusing that eager list for a `vim.ui.select`-style picker is plausible;
  flag as an option for `picker.lua`, not a requirement).

### P4-broken — `entries` (C32, `cmd.vim:618`)
- **Trigger**: `:Awiwi entries`.
- **Items source**: rg heading matches across `g:awiwi_home` (`file:line:col:HeadingText`
  format, with the `##+ ` marker stripped but the `file:line:col:` prefix
  intact).
- **Sink**: **none** — `fzf#run(fzf#wrap({source: entries}))` has no `sink`/
  `sink*` key at all. See Bugs §B2 for the "this looks unfinished" writeup.
  **Port recommendation**: fix-in-port — wire a real sink that parses the
  `file:line:col:` prefix (still present in each item) and jumps there
  (`vim.cmd.edit` + cursor position), turning this into a genuine "jump to
  heading" picker; this is a `list picker` with a location-jump `on_choice`,
  trivially `vim.ui.select`-compatible once the sink exists. If the
  orchestrator prefers strict behavior preservation instead, keep it sinkless
  (item selected, nothing happens) and note it as a known no-op in
  `picker.lua`'s doc comment.

### P5 — `tags`/`show_tasks` grep-picker (C-tags-4, `cmd.vim:704`)
- **Trigger**: `:Awiwi tags [subcmd...]`.
- **Items source**: **not** a static list — a **live shell pipeline**
  (`rg ... | rg -v ...` when `has_due`, else a single `rg ...`), executed by
  `fzf#vim#grep` itself (fzf spawns the command and streams results as the
  user types, i.e. `fzf --disabled`-less live-reload semantics through
  fzf.vim's own machinery, not a pre-materialized Lua item list).
- **Sink**: fzf.vim's built-in ripgrep-result sink (parses `file:line:col:`
  and jumps, `--color=always` output rendered via `--ansi`).
- **Preview**: yes, `right:50%:hidden` toggled by `?`.
- **Seam type**: live-grep picker — **cannot** be expressed as a fixed
  `items` list handed to `vim.ui.select`; this is the one picker that
  genuinely needs a fuzzy-finder-with-live-reload backend (fzf-lua's
  `live_grep`-style API, telescope's `live_grep`, or an equivalent). Document
  this as `picker.lua`'s one non-degradable seam — if the chosen backend
  can't do live-reload grep, `Awiwi tags` needs a materialize-then-pick
  fallback (run `rg` once via `vim.system`, pass the full result list as
  static `items` to the generic list-picker path, lose the "live filter as
  ripgrep pattern itself changes" semantics but keep "pick one of these
  matches and jump").

---

## Port notes

- **No `luaeval`/`pyx`/`py3`** anywhere in `cmd.vim` — nothing to strip here
  (unlike `asset.vim`'s `pyxeval` random-id generator). `export_drawio_diagram`
  does use `luaeval('vim.log.levels.INFO')` (`cmd.vim:715,721`) purely as an
  awkward vimscript→Lua bridge to read a Lua global from vimscript — in
  `cmd.lua` this is just `vim.log.levels.INFO`/`ERROR` directly, no bridge
  needed.
- **`jobstart` → `vim.system`**: `export_drawio_diagram`'s `jobstart(cmd,
  {on_stderr, on_exit})` should become `vim.system(cmd, {stdout=..., stderr=...},
  on_exit)` per SKILL.md's idiom table (`io`/`vim.uv.fs_*` for async — this
  is the `vim.system` case specifically, matching `server.lua`'s own
  `M.config.system` injection-point pattern for testability: don't call
  `vim.system` directly in the body, put it behind a `M.deps.system` or
  reuse `server.lua`'s pattern verbatim so both modules are mockable the same
  way).
- **`rg` invocations → `vim.system`**: all three `rg` call sites
  (`s:get_headings_from_file`, `entries`, `show_tasks`'s non-fzf pattern
  construction) that currently use blocking `systemlist(...)` should move to
  `vim.system({...}):wait()` (synchronous is fine here — these are
  completion-function and one-shot list-building contexts, not the
  fzf-live-reload case of P5, which stays a shell string handed to the fzf
  backend, not something `cmd.lua` executes itself).
- **`nvim_create_user_command` is T10's job, not T9's**: `cmd.lua` exposes
  **only** `M.run(...)` and `M.complete(arglead, cmdline, cursorpos)` (plus
  `M.show_tasks(...)`, `M.store_session()`, `M.restore_session()`,
  `M.export_drawio_diagram(...)` if kept as separate public entry points —
  recommend collapsing `store_session`/`restore_session` into `M.run`'s
  dispatch only, not separate public API surface, since nothing outside
  `cmd.vim` calls them directly today per the grep in "Call sites"). Do
  **not** define the `:Awiwi` user command or its buffer mappings from
  `cmd.lua` — that wiring belongs to T10's `init.lua`/`ftplugin` switchover.
- **Treesitter opportunity**: `s:get_headings_from_file`'s hand-rolled
  `rg '^#+ '` + regex-slugify (C52) and `entries`'s `rg '^#{2,}...'` (C32)
  are both "parse markdown heading structure" tasks that `vim.treesitter`
  (markdown `atx_heading` nodes) could replace **for files already loaded in
  a buffer** — but both call sites here operate over **files on disk**,
  potentially not open in any buffer (`entries` scans the whole
  `g:awiwi_home` tree). Per SKILL.md's own guidance ("don't force
  treesitter where a `:match` on one line is honest" / prefer treesitter for
  *loaded-buffer* structural queries): keep these two as `rg`+pattern-match
  over disk files (treesitter has no non-buffer parse-from-string convenience
  worth the complexity here for a one-shot completion/list-building path);
  reserve treesitter for buffer-resident structural work in other modules
  (`hi.lua`'s due-date extmarks, per hi.md, already does this).
- **`s:contains(list, el, ...)` helper** (`cmd.vim:166-178`) — trivial,
  replace with a local `vim.tbl_contains` + varargs loop, or a tiny local
  helper; not worth a shared-module export.
- **Constants**: the large block of `s:*_cmd` string constants
  (`cmd.vim:6-139`) should become plain Lua `local` string constants (or a
  single `local CMD = {journal='journal', ...}` table) inside `cmd.lua` —
  per SKILL.md, `s:` script-locals become module-local Lua locals, no `g:`/
  registry needed except the parts genuinely shared cross-module (already
  extracted: `asset.lua`'s `M.types`, `markers.lua`'s vocab).
- **`get_cmd` is not ported** — see "Public surface" section above; do not
  recreate a runtime string-constant lookup function in `cmd.lua`. If a
  future module needs one of these constants, it should `require('awiwi.cmd')`
  and read the (Lua-native) constant directly, or `cmd.lua` can expose a
  small `M.constants` table mirroring `asset.lua`'s `M.types` precedent —
  engineer's discretion, not mandated by any existing caller (none exist
  post-port, per the grep).
- **Autoload guard** (`if exists('g:autoloaded_awiwi_cmd') | finish |
  endif`) — drop, per SKILL.md: `require` caching replaces this pattern
  entirely.

---

## Bugs found

- **B1 — `oshell` never restored** (`cmd.vim:544-546`, C18): `let oshell =
  &shell | set shell=/bin/sh` before `fzf#vim#files(<recipe_subpath>,
  fzf_opts)`, with **no restore** anywhere in that branch (contrast C21's
  `search`, which wraps the identical pattern in `try/finally`). Every
  `:Awiwi recipe` (bare) invocation permanently leaves the user's `&shell`
  set to `/bin/sh` for the rest of the Neovim session. **Fix in port** —
  trivial: this shell mutation shouldn't exist at all once `cmd.lua` no
  longer needs to coax `fzf`'s underlying shell invocation; if the chosen
  picker backend still needs a shell override for some reason, wrap it in
  `pcall`+restore (or `vim.o.shell` save/restore via a deferred callback),
  never a bare mutate-and-forget.
- **B2 — `entries`'s `fzf#run` has no sink** (`cmd.vim:618`, C32): selecting
  an entry from `:Awiwi entries` does nothing navigable — the
  `file:line:col:` location info baked into each item string is discarded on
  selection since no `sink`/`sink*` is registered. Almost certainly an
  incomplete feature (the data shape strongly implies "jump to this
  heading" was the intent). **Recommend fix-in-port**: wire a sink/on_choice
  that parses the `file:line:col:` prefix and jumps (`vim.cmd.edit` + set
  cursor). Human/ADR decides if strict-preservation ("stays a no-op") is
  preferred instead — this is a genuine behavior *addition*, not just a bug
  fix, so flag explicitly in `docs/decisions.md` either way.
- **B3 — `+width=` silently aliases `+height=`** (`cmd.vim:272-273`, C42):
  `awiwi#str#startswith(arg, s:journal_height_window_cmd) ||
  awiwi#str#startswith(arg, s:journal_width_window_cmd)` both branches into
  `let options.height = str2nr(...)` — there is no `options.width` anywhere
  in the file. `:Awiwi journal today +width=40` sets `options.height`, not a
  width. Whether this is "as designed" (maybe `open_file`'s downstream
  consumer, façade/T10, only ever reads `.height` regardless of split
  orientation, making `+width=` a harmless synonym) needs checking against
  `awiwi#open_file`'s body (`awiwi.vim:271+`, façade, out of this brief's
  scope but worth a one-line check before deciding) — **recommend**: if
  `open_file` genuinely has no width concept, this is dead/misleading syntax
  (accepting `+width=` that behaves identically to `+height=`) — either drop
  `+width=` as a recognized token (simplify) or, if a real width concept is
  wanted, implement it properly. Either way: **preserve current behavior by
  default, flag for ADR** — do not silently "fix" by inventing a width
  concept that never existed.
- **B4 — `prefix_len` gets a boolean, not a length** (`cmd.vim:191-192`,
  flagged during `str` recon, confirmed here): `let prefix_len =
  awiwi#str#endswith(awiwi#get_recipe_subpath(), '/') ? strlen(...) :
  strlen(...)+1` — reads correctly at first glance (it *is* a ternary
  producing a number, not a boolean — re-verify this isn't actually the flagged
  bug). **Re-examination**: the ternary's condition is `str#endswith(...) ?
  strlen(...) : strlen(...)+1`, which *does* look correct on inspection —
  the "result of `endswith` misassigned to `prefix_len`" framing from the
  task brief may refer to a **different, more subtle** issue: if
  `awiwi#get_recipe_subpath()` doesn't actually ever end in `/` (typical for
  a `path#join`-built subpath), the `?:`'s true-branch is dead and
  `prefix_len` is always `strlen(subpath)+1` — functionally fine (correctly
  strips the subpath + its separator from each glob result) **unless**
  `get_recipe_subpath()`'s return value's trailing-slash-ness is
  inconsistent across platforms/configs, in which case `prefix_len` is off
  by one and `s:get_all_recipe_files`'s returned relative paths gain/lose a
  leading `/`. **Action for the engineer**: write a `path.md`-cross-referenced
  acceptance test asserting `get_all_recipe_files` slices exactly the
  subpath+separator regardless of whether the underlying `get_recipe_subpath`
  facade (T10, still vimscript today) happens to return a trailing slash —
  i.e. don't port the ternary verbatim, port the *intent* ("strip the
  recipe-subpath prefix and its one path separator from every glob hit"),
  using `require('awiwi.path').relativize` (already ported, exactly this
  job) instead of hand-rolled `strlen` arithmetic. **Fix in port.**
- **B5 — `s:on_stderr` writes to an undefined `s:job_errors`**
  (`cmd.vim:740`): `call extend(s:job_errors[a:job_id].errors, errors)` — the
  actual per-job state dict is `s:job_data` (`cmd.vim:728,772`), never
  `s:job_errors`; `s:job_errors` is referenced **nowhere else** in the file
  (confirmed by grep). Every time `drawio` writes a stderr line containing
  the literal substring `'Error'` (and not `'object_proxy.cc'`), this throws
  `E121: Undefined variable: s:job_errors`, which — since it's inside a
  `jobstart` callback — silently aborts that callback invocation (Vim
  swallows/echoes callback errors without crashing the job) rather than
  surfacing cleanly; net effect: **the stderr-error-collection feature is
  completely broken**, `export_drawio_diagram`'s "conversion failed, here are
  the errors" path (C-export-6) never actually receives populated
  `errors`, so failed conversions are reported as if they errored with an
  empty list (or the success path fires spuriously) whenever drawio only
  signals failure via stderr text rather than a nonzero exit/immediate death.
  **Fix in port** — trivially `s:job_data[a:job_id].errors` was clearly
  intended.
- **B6 — `job_id == 0` error message references undefined
  `markup_language`** (`cmd.vim:775`): `echoerr printf('[ERROR] could not
  convert file to pdf. reason: bad arguments %s', markup_language, cmd)` —
  `markup_language` is not defined anywhere in this function (or file);
  additionally the `printf` format string has exactly one `%s` but two extra
  args (`markup_language`, `cmd`) are passed, which is `E767: Too many
  arguments to printf()` territory in vimscript proper (though `echoerr`'s
  own error-in-error handling may mask this differently — verify empirically
  if this path is ever exercised, e.g. `jobstart` genuinely returning `0`
  requires malformed job-spec arguments, which given this function's fixed
  argument list is unlikely to occur in practice; still, dead-but-reachable
  buggy code). **Fix in port**: this is purely a diagnostic message, low
  risk — just reference `cmd` (the actual argv list) in the message, drop
  the phantom `markup_language`.
- **B7 — `<F12>` mapping calls `:Awiwi tasks`, dispatcher keyword is `tags`**
  (`ftplugin/awiwi.vim:37` vs `cmd.vim:19,61` / `s:subcommands`): confirmed —
  `tasks` is not a member of `s:subcommands` (so it doesn't even complete)
  and `run()`'s dispatch chain checks `a:1 == s:tags_cmd` (`'tags'`), not
  `'tasks'` — so `<F12>` today silently no-ops (falls through the entire
  `if/elseif` chain per C2). This exactly matches architecture.md's
  documented "Known mismatch" (`docs/architecture.md:89-90`). **Recommend
  resolution**: rename the *mapping* to `:Awiwi tags` (not the dispatcher
  keyword) — `tags` is the more accurate name for what `show_tasks` actually
  filters (markers: todo/urgent/due/onhold/question/incidents/changes/
  issues/bugs — a superset of "tasks"), and it's already the name used
  everywhere else (`s:tags_cmd`, `s:tags_subcommands`, completion). Renaming
  the dispatcher to `tasks` instead would ripple into every `s:tags_*`
  constant/completion-branch for a purely cosmetic gain. This is a
  behavior-visible fix (currently a silent no-op key, would become a working
  one) — flag for `docs/decisions.md` ADR either way, per this task's
  instructions; **recommendation: fix in port** (rewire the `ftplugin`
  mapping to `:Awiwi tags` when T10 ports `ftplugin/awiwi.vim`), since a
  silently-broken keybinding has no defensible "preserve" case — nobody
  could be relying on `<F12>` doing nothing.
- **Architecture.md staleness (not a `cmd.vim` bug, but caught during this
  recon)**: `docs/architecture.md:82` describes `serve`/`server` as "Flask
  viewer" — this is stale post-`server.lua`'s port (server.md's Bug #5 /
  ADR D5: the default `cmd_builder` now launches `uv run uvicorn app:app`,
  not Flask). Recommend updating that table row alongside `cmd.lua`'s land
  (or whenever `docs/architecture.md` is next touched by kb-curator) — not
  blocking for this transaction since it's `server.md`'s finding, just
  re-flagging since this brief's own "Command surface" table cross-reference
  surfaced it again.
- **Architecture.md gap (not a bug, a documentation omission)**: the
  `paste` top-level subcommand alias (C11) is real, shipped, and present in
  `s:subcommands`, but absent from `docs/architecture.md`'s "Command
  surface" table (`docs/architecture.md:67-84`), which shows `paste` only as
  a sub-token of `asset`. Recommend adding a `paste` row (or a clarifying
  footnote) in the same commit that flips `cmd.vim`'s module-map row to
  "ported".

status: done

---

## Ported

**Lua modules:** `lua/awiwi/cmd.lua` + `lua/awiwi/picker.lua` (the UI seam).
Specs: `tests/cmd_spec.lua` (58 `it`), `tests/picker_spec.lua` (9 `it`). Targeted
run 67 passed / 0 failed; full suite `nvim --clean --headless -l tests/run.lua`
354 passed / 0 failed (12 files).

### `cmd.lua` final API

- `M.run(...)` — receives the tokens *after* `:Awiwi` (vimscript `<f-args>` /
  `a:000`), 1-indexed. Dispatch chain covers C1-C37; unknown subcommands fall
  through silently (C2), `run()` with no args throws `AwiwiCmdError` (C1).
- `M.get_completion(ArgLead, CmdLine, CursorPos)` — `customlist` completion
  (C47-C58). `CmdLine` includes the `Awiwi` command word (so its internal
  `args` are the vimscript 0-indexed shape, accessed at `args[k+1]`).
- `M.show_tasks(...)` — the `tags` grep (C-tags-1..5). Reachable via
  `M.run('tags', ...)` too.
- `M.store_session()` / `M.restore_session()` — kept as public entry points
  (T10 may collapse into `run`; nothing external calls them today).
- `M.export_drawio_diagram(input?)` — drawio→PDF (C-export-1..7).
- `M.get_all_recipe_files()` — exposed (used by completion; also handy for a
  future recipe list-picker per Pickers §P4).
- `M.deps` — T10 injection table (see inventory below).

### `picker.lua` final API + backend selection

- `M.select({items, prompt, format_item?, on_choice})` — list picker (P2,
  P4-fixed). Never calls `on_choice` on cancel.
- `M.files({dir, prompt?, on_choice?})` — file picker (P1, P3). `on_choice`
  gets the FULL path (default = `:edit`); callers relativize for name sinks.
- `M.grep({argv, filter_argv?, transform?, prompt?, on_choice?})` — live-grep
  picker (P5, entries C32). Materialize-then-pick: runs `argv` via
  `deps.system`, optionally pipes stdout through `filter_argv` (the due
  anti-pattern `rg -v`, which must see raw colored output — filter runs BEFORE
  ANSI stripping), strips ANSI, drops empty lines, applies `transform` per line,
  then `M.select`. Default `on_choice(file,lnum,col,text)` jumps (B2 fix).
- `M.deps = {require, ui_select, system}` — mock seams.
- **Backend selection:** `load_telescope()` loads `telescope.pickers/finders/
  config/actions/actions.state` through `deps.require`; if all present a
  telescope list picker is built (finder=`new_table`, sorter=`generic_sorter`,
  `select_default:replace` sink), else `vim.ui.select`. This machine has NO
  telescope → suite runs the fallback; the telescope path is smoke-tested with a
  fake telescope injected via `picker.deps.require`. All three picker types
  funnel through `M.select`, so telescope only needs implementing once.

### `M.deps` inventory for T10 (rebind each to the ported façade)

Pure defaults already provided (no shim): `get_journal_subpath`,
`get_asset_subpath`, `get_recipe_subpath` (all `path.join(g:awiwi_home, …)`),
`get_journal_file_by_date` (date.parse + path.join), `system` (`vim.system`).

`vim.fn['awiwi#…']` shims until T10 lands: `get_all_journal_files`,
`insert_journal_link`, `edit_journal`, `insert_and_open_continuation`,
`activate_current_task`, `deactivate_active_task`, `copy_file`,
`insert_recipe_link`, `open_file`, `fuzzy_search`, `redact`, `edit_meta_info`,
`edit_todo`, `show_toc_in_qlist`.

Already-ported modules called directly (NOT via deps): `str`, `path`, `util`,
`asset`, `date` (incl. `date.get_own_date`, which **did** survive the port — the
C17/C36 caveat is resolved, no façade stopgap needed), `server`, `markers`,
`picker`.

### Bugs fixed

- **B1** — recipe `&shell` leak: dropped entirely (no shell under `vim.system`/
  picker). Regression test asserts `vim.o.shell` unchanged after `:Awiwi recipe`.
- **B2** — `entries` sinkless picker: now `picker.grep` with a default
  location-jumping sink; the marker-stripping `transform` keeps `file:line:col:`
  intact. Tested in both `cmd_spec` (transform) and `picker_spec` (default jump).
- **B3** — `+width=` now writes `options.width` (was aliased to `.height`);
  `+height=` writes `options.height`. Regression test pins both. **T10 note:**
  `awiwi#open_file` currently only reads `.height`; if width is to matter, T10
  must teach `open_file` about `.width` (else `+width=` is inert but no longer
  silently mis-sets height). ADR-worthy.
- **B4** — `get_all_recipe_files` uses `path.relativize` (strips subpath +
  separator correctly regardless of trailing slash) instead of `strlen`
  arithmetic.
- **B5** — drawio stderr errors collected into the closure-local `errors` table
  (was the undefined `s:job_errors`). Regression test feeds a stderr `Error:`
  line and asserts it reaches the ERROR notify.
- **B6** — spawn-failure message references the argv (`vim.inspect(cmd)`), drops
  the phantom `markup_language`. `jobstart`'s 0/-1 return maps to `pcall` of
  `vim.system` failing.
- **B7** — dispatcher keyword stays `tags`; `:Awiwi tasks` is a silent no-op
  (C2), pinned by test. **T10 MUST rewire the `<F12>` ftplugin mapping from
  `:Awiwi tasks` to `:Awiwi tags`.**

### Deviations / preserved quirks

- **C11/C14/C15/C16 asset creates** use the callback-style
  `asset.create_asset_here_if_not_exists(type, opts, on_done)`. C16's extra CLI
  name tokens are inert in the vimscript original (name is always prompted), so
  they are not forwarded; the post-create `write` (host buffer) + `open_asset`
  tail logic lives in the `on_done`, guarded against the abort/`''` sentinel.
- **C12 (P3')** revived the abandoned richer asset picker: a `date:name` list
  picker → `asset.open_asset_sink`, not a raw file browser. Behavior upgrade
  (ADR-flag).
- **C31 `meta <unknown>`** uses `nvim_echo` (not `nvim_err_writeln`), preserving
  the vimscript `echo`-vs-`echoerr` distinction.
- **C40/C46 parse errors** use `nvim_err_writeln` (non-throwing) to preserve the
  vimscript "warn but keep going" `echoerr` quirk.
- **`!bookmark` (#39)** preserved as a recognized-but-inert flag (still sets the
  unread `options.bookmark`) — recognizing it avoids it being mis-parsed as the
  file token. ADR-flag: drop vs wire to a revived bookmarks feature.
- **`insert_win_cmds` nested-list latent bug** fixed-in-port: the vimscript
  `insert(li, dim_cmds_list)` put the whole `+height=/+width=` list in as one
  nested element; flattened to individual candidates.
- **drawio export** drops the per-job `s:job_data` dict (KISS — the closure
  holds output path + errors); notify runs inside `vim.schedule` (API-safe from
  `vim.system`'s callback context).
- **show_tasks / entries** no longer shell-escape or build a shell string —
  argv goes straight to `vim.system` (no `&shell`), the `rg | rg -v` pipeline
  becomes a stdin-piped second `vim.system` call in `picker.grep`.

### `get_cmd` — not ported

Confirmed superseded by `asset.types` (used directly). No `M.constants` registry
added (no post-port caller needs one).

### Exactly what T10 must wire

1. `nvim_create_user_command('Awiwi', … , { nargs='*', complete=<customlist
   wrapper around cmd.get_completion>, … })` calling `cmd.run(<f-args>)`.
2. The `customlist` completion adapter (`function(ArgLead, CmdLine, CursorPos)
   return require('awiwi.cmd').get_completion(ArgLead, CmdLine, CursorPos) end`).
3. Buffer mappings (`gC/gT/ge/gn/gp`, `<C-q>`, insert `<C-s>`/`<C-b>`) and
   **`<F12>` → `:Awiwi tags`** (B7 rename, not `:Awiwi tasks`).
4. Rebind all `M.deps.*` vim.fn shims to the ported façade equivalents; teach
   `open_file` about `options.width` if B3's width is to have an effect.
5. Port `autoload/awiwi.vim:745` `awiwi#cmd#get_cmd('paste_asset')` to
   `require('awiwi.asset').types.paste`.

### Docs (kb gate) — flagged, NOT edited here

`docs/architecture.md` needs: module-map `cmd.vim` row flipped to ported; a
`paste` top-level row (or footnote under `asset`) in the Command surface table;
the stale `serve`/`server` "Flask viewer" row refreshed (server.md's ADR D5).
ADR entries for: P3' asset-picker upgrade, B2 entries-sink addition, B3
width/height split, B7 `<F12>`→`tags`, `!bookmark` preserved-inert. Left for
kb-curator/sync-docs.
