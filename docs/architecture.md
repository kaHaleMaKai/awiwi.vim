# Architecture (authoritative spec)

Spec of what awiwi does today. Doubles as the **target for the Lua rewrite**: the Lua port should
reproduce the *shipped* behavior module-for-module (and can drop the dead subsystems — see below).
Keep this truthful — when behavior changes, this file changes in the same commit.

**Runtime: Neovim only.** Uses `nvim_*` APIs (virtual text, namespaces), `jobstart`, `luaeval`,
`pyx`/`py3`. Not portable to plain Vim.

## Components

| component     | location                                | status                                       |
| ------------- | --------------------------------------- | -------------------------------------------- |
| Plugin        | `lua/awiwi/`, `ftplugin/awiwi.lua`, `ftdetect/awiwi.lua` | ported to Lua (T10 switchover complete) |
| Lua modules   | `lua/awiwi/*.lua`                       | complete (str, path, date, util, asset, hi, server, syn, markers, cmd, picker, init — all modules ported by T10) |
| Server/viewer | `server/` (FastAPI + Pydantic)          | in progress, replacing `server.old/`         |
| Legacy server | `server.old/` (Flask + Jinja)           | reference only                               |

There is **no `plugin/` directory**. `:Awiwi` and all mappings are registered per-buffer in
`ftplugin/awiwi.lua`, gated by `ftdetect/awiwi.lua`.

## Loading & entry points

1. **`ftdetect/awiwi.lua`** (Neovim autocmd) sets filetype by path under `g:awiwi_home`: `journal/**/*.md`→`awiwi`,
   `assets/**`→`awiwi.asset`, `recipes/*`→`awiwi.recipe`, `todos/*.md`→`awiwi.todo`; plus
   `g:awiwi_external_dirs`→`awiwi`. Also adds `aP`/`iP` code-block text objects on every `BufRead *.md`.
2. **`ftplugin/awiwi.lua`** (Neovim per-buffer, requires `g:awiwi_home`): calls `require('awiwi')` to initialize,
   defines `:Awiwi` command (`-nargs=+`, completion and dispatch through `awiwi.cmd`), all buffer mappings,
   autocommands (autosave, due-date/horizontal-line redraw, delete-old-tasks, optional `entitlement.nvim` titles),
   folding via Lua `foldexpr`, abbreviations, optional server autostart.
3. **`lua/awiwi/init.lua`** — public API façade. On `require('awiwi')`, derives subpaths under `g:awiwi_home`
   (`journal/ todos/ assets/ recipes/ data/ cache/`), `mkdir`s them, ensures `data/task.log` (JSON format)
   and `data/awiwi.log` exist, resumes any active task from log, rebinds module dependencies.

Load-bearing chain: `:Awiwi <sub>` → `ftplugin/awiwi.lua` user command → `lua/awiwi/cmd.lua:run()`
(subcommand dispatch); completion via `lua/awiwi/cmd.lua:get_completion()`; central file opener
`lua/awiwi/init.lua:open_file()`; active-task timer via `lua/awiwi/init.lua:activate_current_task()` /
`deactivate_current_task()`; server control via `lua/awiwi/server.lua`.

## Module map (`lua/awiwi/`)

Lua modules are the primary implementation (T10 switchover complete). Public functions are
`require('awiwi.<mod>').<fn>`. Vimscript modules (`autoload/awiwi*.vim`, `syntax/awiwi.vim`)
were deleted in T10; this table reflects the current Lua state.

| module         | responsibility |
| -------------- | -------------- |
| `init.lua`     | façade: journals, links, asset paste, **file-based active-task timer** (`data/task.log`), quickfix TOC, active-task timer resume; bootstraps dirs + log files; reexports leaf-module APIs; wires ftplugin/init |
| `cmd.lua`      | subcommand dispatch (`run`) + completion; `show_tasks`, sessions, drawio export; routes through `picker.lua` seam; `:Awiwi search` now via `picker.grep` (ADR D8) |
| `picker.lua`   | unified picker seam: `vim.ui.select` default, telescope auto-upgrade (ADR D7); three types: `select`, `files`, `grep` |
| `asset.lua`    | create/open/link assets under `assets/YYYY/MM/DD/`; owns `M.types` (asset⇄cmd cycle broken); pure-Lua random id; open side-effect-free (ADR D4); injectable deps |
| `date.lua`     | parse/normalize dates, journal-relative nav; pure os.date/os.time, narrowed grammar (ADR D3), new `diff_days`; `deps.journal_dates` seam wired by the façade so `prev`/`next` resolve against real journal files (T10.1) |
| `util.lua`     | helpers: link parse/classify (journal misclassification fixed), `match_subcommands`, `input` (vim.ui.input callback), code-block text objects, window-split utilities |
| `hi.lua`       | due-date badges + header rules as extmarks; treesitter structural pass (`headings`/`code_line_mask`, reused by syn); title helpers for `entitlement.nvim` |
| `path.lua`     | path join/split/relativize/canonicalize; native `path.join()` replaces broken `fn#apply`/`fn#spread` dependency (B10 fix) |
| `server.lua`   | viewer control: start/stop/logs/serve via `vim.system`, non-blocking `wait_ready`; launches FastAPI server (ADR D5; `app:app` placeholder until `server/` gains app module); config.json, xdg-open |
| `str.lua`      | string helpers (startswith/endswith/contains/is_empty); case-sensitive (intentional per ADR D2); leaf, widely used |
| `syn.lua`      | treesitter/extmark syntax layer: markdown+markdown_inline queries, link conceal, marker/redaction/Redmine line patterns outside code mask; typos fixed (ADR D6); wired via ftplugin FileType autocmd (T10); paints awiwi *extras* only — base markdown styling (headings/fences/emphasis) comes from `vim.treesitter.start(buf, "markdown")` in the ftplugin (T10.1) |
| `markers.lua`  | marker vocabulary (TODO/FIXME/ONHOLD/DUE/@due/@incident/…); rg/vim escaping; `g:awiwi_custom_*_markers` overrides |

## Command surface

`:Awiwi <sub> [args…]` → `lua/awiwi/cmd.lua:run()`. Subcommand keywords defined in `cmd.lua`;
completion via `cmd.lua:get_completion()`.

| subcommand | behavior |
| ---------- | -------- |
| `journal [flags] <date\|today\|next\|previous\|todos>` | open/create journal; bare → picker (`vim.ui.select` default, telescope auto-upgrade) |
| `todo [name]` | open a todo file |
| `continue` | insert task continuation into today's journal |
| `activate` / `deactivate` | file-based active-task timer (writes `data/task.log` in JSON format) |
| `asset [create [url\|paste\|copy]\|paste\|<date:name>] [flags]` | create/open/paste assets |
| `recipe <name> [flags]` | open recipe; bare → picker |
| `link <journal\|recipe\|asset> …` | insert a link instead of opening (`link … #<heading>` completes headings) |
| `search <pattern>` | fuzzy rg search via `picker.grep` (ADR D8; was `fzf#vim#grep`) |
| `tags [all\|due\|urgent\|onhold\|question\|todo\|filter <pat>]` | rg+picker marker/task search (`show_tasks`) |
| `entries` | rg headings → picker |
| `toc [date]` | quickfix table of contents |
| `meta <edit [col]\|delete>` / `due <spec>` | edit `{…}` JSON line-meta / due date |
| `redact` | toggle `!!redacted` |
| `serve` / `server <start [host]\|stop\|logs [stdout\|stderr\|exit]>` | note viewer (FastAPI per ADR D5) |
| `paste` | top-level alias for `asset paste` (shipped but long undocumented) |
| `save` / `restore` | session `mksession` / source |
| `export` | drawio → PDF (async) |

Flags (journal/asset/recipe): `+create`, `+new`, `+hnew`, `+vnew`, `-new`, `+tab`, `+height=`,
`+width=`, `!bookmark`, `#anchor`.

**Fixed in T10:** the `<F12>` mapping now correctly calls `:Awiwi tags` (not the old vimscript typo `tasks`).

## Buffer mappings (`ftplugin/awiwi.lua`, buffer-local)

`gf` / `<leader>gft` / `<leader>gfn` open link (window/tab/window); `gC` continue; `gT` todo;
`ge` journal today; `gn`/`gp` journal next/prev; `<F12>` tags (fixed from vimscript typo); `o`/`O`/`<Enter>`/`<C-j>`
list-/checkbox-aware insert + due-date redraw; `<C-y>` checkbox; `<C-f>` time; `<C-q>` redact;
`<C-v>` paste; i_`<C-s>` `Awiwi link `; i_`<C-b>` `Awiwi asset create`; `gj` asset→journal;
`A` todo append (`.todo` filetype). Abbreviations: `:shrug: :arrow: :check: :cross:` (buffer-local iabbrevs).

## Data & persistence

Two backends; **the shipped one is file-based**.

- **Documents** — journals / assets / recipes / todos are markdown files under `g:awiwi_home`
  (layout in `CLAUDE.md`). The filesystem hierarchy is the model. Todo checkboxes carry `{…}` JSON
  meta (`due`, `created`).
- **Active-task timer (shipped)** — a JSON-formatted log at `data/task.log` (ADR D8; format changed from vimscript
  `string()` in T10), driven by `lua/awiwi/init.lua:activate_current_task()` / `deactivate_current_task()`;
  feeds `g:awiwi_active_task` and the airline section. Log stores task records with activity timestamps.
- **SQLite task DB (WIP, not reachable from `:Awiwi`)** — `<g:awiwi_home>/task.db` (not ported; per ADR D1).
  An in-progress replacement for the file log. Schema + drift notes: `docs/data-model.md`.
- **Other files** — `data/awiwi.log` (append-only activity log), `cache/bookmarks`, `session.vim`, `config.json`
  (written for the server).
- **Markers** — line-classification keywords (`TODO`, `FIXME`/`CRITICAL`/`URGENT`, `ONHOLD`, `DUE`,
  `@incident`, `@change`, `@issue`, `@bug`, `@@` delegate, `QUESTION`, …) defined in `lua/awiwi/markers.lua`,
  extended by `g:awiwi_custom_<type>_markers`. Drive highlighting (`lua/awiwi/hi.lua`) and rg-based task search.
  Marker semantics are behavior.

## Configuration (globals)

**Required:** `g:awiwi_home`.

**Optional:** `g:awiwi_history_length` (currently a no-op — log never rotates; ADR D10),
`awiwi_server_port` (5823), `awiwi_autostart_server` (host), `awiwi_jump_to_end`, `awiwi_image_opener`
(`['xdg-open']`), `awiwi_external_dirs` (dict of external markdown dirs), `awiwi_use_entitlement`
(+`_opts` for entitlement.nvim title decoration), `awiwi_custom_<type>_markers` (marker overrides).

**Removed/deprecated:** `awiwi_search_engine` (no longer used — all search via `picker.lua`),
`awiwi_screensaver`, `awiwi_task_update_frequency` (removed in Lua port).

**Syntax/highlight globals** (now in `lua/awiwi/syn.lua`): `awiwi_conceal_links`,
`awiwi_conceal_link_*`, `awiwi_highlight_links`, `awiwi_link_color`, `awiwi_link_style`,
`awiwi_domain_color`.

**State:** `g:awiwi_active_task` (current active task record).

## External dependencies

**Binaries (shipped):** `rg` (ripgrep, used for task search), `curl` (asset download), `xclip` (clipboard),
`file` (MIME type guessing), `xdg-open` (external links/images), `date` (no longer used — Lua uses `os.time`),
`drawio` (export to PDF).

**Binaries (optional):** `sqlite3` (not ported; per ADR D1), `telescope.nvim` (auto-upgrade from `vim.ui.select`,
via picker.lua seam).

**Python/Lua:** Lua `os.date`/`os.time` (pure, no subprocess). Removed: `pyx`/`pyxeval` (asset id — pure Lua
now), `py3` (delete-old-todos — pure Lua per ADR D6 fix).

**External Neovim plugins (optional):** `entitlement.nvim` (title decoration, gated), `vim-airline` (active-task
display, gated).

**Removed VimL plugins:** `fn#apply`/`fn#spread` (broken deps, now native Lua `path.join()` per B10 fix);
`fzf.vim` (replaced by picker.lua seam); `path#` (not used in Lua modules).

## Status of vimscript subsystems (T10 switchover)

Vimscript files (`autoload/awiwi*.vim`, `ftplugin/awiwi.vim`, `ftdetect/awiwi.vim`, `syntax/awiwi.vim`)
were deleted in T10. Known issues in the original code that are **fixed or dropped** in the Lua port:

- **SQLite task impls (`dao.vim`, `task.vim`)** — both unreachable and broken. Dropped per ADR D1
  (not ported; SQLite task DB is WIP, not a shipped feature).
- **`view.vim`, `bookmarks.vim`** — dead/non-functional code. Dropped (not ported).
- **Bugs in shipped vimscript** — numerous issues including `path.vim`'s broken `fn#apply` dependency (B10, fixed
  in `lua/awiwi/path.lua`), task.log format now JSON (B10, ADR D8), syntax group typos (ADR D6), stale window
  number in ToC refresh (B-INIT-5, fixed in Lua), global `updatetime` mutation (B8, dropped), off-by-one in
  delete-old-tasks (B6, fixed in Lua), and others — all remedied in the Lua port.
- **Query/schema drift** — `resources/db/get-*.sql` references columns absent from `init.sql`. Not ported (per ADR D1).
  See `docs/data-model.md` for schema notes.

## Server (viewer)

`server/` is a fresh FastAPI + Pydantic app (Python ≥3.13, uv-managed) rendering awiwi notes,
replacing `server.old/` (Flask + Jinja). Reference feature set from the old app: markdown render
with TOC / internal links / mermaid; journal prev/next nav; asset serving (binary + downloadable);
auth with localhost bypass; breadcrumbs; search. `lua/awiwi/server.lua` (T7, ADR D5) drives the
FastAPI app via `uv run uvicorn app:app ...` (cwd=`server/`); `app:app` is a placeholder entrypoint
until `server/` lands its app module. The live toolchain is ruff + basedpyright + pytest.
