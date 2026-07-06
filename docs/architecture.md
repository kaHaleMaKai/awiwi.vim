# Architecture (authoritative spec)

Spec of what awiwi does today. Doubles as the **target for the Lua rewrite**: the Lua port should
reproduce the *shipped* behavior module-for-module (and can drop the dead subsystems — see below).
Keep this truthful — when behavior changes, this file changes in the same commit.

**Runtime: Neovim only.** Uses `nvim_*` APIs (virtual text, namespaces), `jobstart`, `luaeval`,
`pyx`/`py3`. Not portable to plain Vim.

## Components

| component     | location                                | status                                       |
| ------------- | --------------------------------------- | -------------------------------------------- |
| Plugin        | `autoload/`, `ftplugin/`, `ftdetect/`, `syntax/` | active (vimscript) → being ported to Lua |
| Lua rewrite   | `lua/`                                  | in progress (str, path, date, util, asset, hi, server, syn, markers, cmd, picker complete — only the T10 façade/switchover remains) |
| Server/viewer | `server/` (FastAPI + Pydantic)          | in progress, replacing `server.old/`         |
| Legacy server | `server.old/` (Flask + Jinja)           | reference only                               |

There is **no `plugin/` directory**. `:Awiwi` and all mappings are registered per-buffer in
`ftplugin/awiwi.vim`, gated by `ftdetect/awiwi.vim`.

## Loading & entry points

1. **`ftdetect/awiwi.vim`** sets filetype by path under `g:awiwi_home`: `journal/**/*.md`→`awiwi`,
   `assets/**`→`awiwi.asset`, `recipes/*`→`awiwi.recipe`, `todos/*.md`→`awiwi.todo`; plus
   `g:awiwi_external_dirs`→`awiwi`. Also adds `aP`/`iP` code-block text objects.
2. **`ftplugin/awiwi.vim`** (requires `g:awiwi_home`): sources `ftplugin/markdown.vim`, defines
   `:Awiwi` (`-nargs=+`, completion `awiwi#cmd#get_completion`, dispatch `awiwi#cmd#run`), all
   buffer mappings, autocommands (autosave, due-date/horizontal-line redraw, delete-old-todos via
   `py3`, optional `entitlement.nvim` titles), folding, abbreviations.
3. **`autoload/awiwi.vim`** — public API façade. On load derives subpaths under `g:awiwi_home`
   (`journal/ todos/ assets/ recipes/ data/ cache/`), `mkdir`s them, sets up `data/awiwi.log` +
   `data/task.log`.

Load-bearing chain: `:Awiwi` → `ftplugin/awiwi.vim:21` → `awiwi#cmd#run` (`cmd.vim:466`);
completion `cmd.vim:339`; central file opener `awiwi.vim:271` (`awiwi#open_file`); SQLite driver
`sql.vim:291`; DB init `dao.vim:445`; server `server.vim:76`.

## Module map (`autoload/`)

`awiwi.vim` is the façade; `awiwi/*.vim` are modules; public fns are `awiwi#<mod>#<fn>`.

| module         | LOC | status | responsibility |
| -------------- | --- | ------ | -------------- |
| `awiwi.vim`    | 939 | active | façade: journals, links, asset paste, **file-based active-task timer** (`data/task.log`), quickfix TOC, markers |
| `cmd.vim`      | 780 | ported to `lua/awiwi/cmd.lua` + `lua/awiwi/picker.lua` (**not wired** — `:Awiwi` still dispatches to vimscript until T10) | subcommand dispatch (`run`) + completion + `show_tasks`, sessions, drawio export; all picker UI behind `picker.lua` seam (vim.ui.select default, telescope auto-upgrade — ADR D7); façade calls via `M.deps` until T10; fzf gone |
| `sql.vim`      | 378 | active | shells out to `sqlite3` binary; typed param binding (`?` placeholders, `col@type` result hints), transactions. Self-contained (no awiwi deps) |
| `asset.vim`    | 246 | ported to `lua/awiwi/asset.lua` | create/open/link assets under `assets/YYYY/MM/DD/`; owns `M.types` (asset⇄cmd cycle broken); pure-Lua random id (pyx gone); open no longer silently creates files (ADR D4); façade deps via `M.deps` until T10 |
| `date.vim`     | 168 | ported to `lua/awiwi/date.lua` | parse/normalize dates, journal-relative nav; pure os.date/os.time, narrowed grammar (ADR D3), new `diff_days` |
| `util.vim`     | 369 | ported to `lua/awiwi/util.lua` (12 live fns; 11 dead fns dropped per ADR D1) | helpers: link parse/classify (journal misclassification fixed), `match_subcommands`, `input` (vim.ui.input callback style), code-block text objects |
| `hi.vim`       | 147 | ported to `lua/awiwi/hi.lua` | due-date badges + header rules as extmarks (deprecated virtual-text API gone); treesitter structural pass (`headings`/`code_line_mask`, reused by syn); title helpers for `entitlement.nvim` |
| `path.vim`     |  82 | ported to `lua/awiwi/path.lua` | path join/split/relativize/canonicalize; B-PATH bugs fixed in port |
| `server.vim`   | 131 | ported to `lua/awiwi/server.lua` | viewer control: start/stop/logs/serve via `vim.system`, non-blocking `wait_ready`; launches the FastAPI server (ADR D5; `app:app` entrypoint is a placeholder until `server/` gains its app module), config.json, xdg-open |
| `str.vim`      |  33 | ported to `lua/awiwi/str.lua` | string helpers (startswith/endswith/contains/is_empty); leaf, widely used |
| `syntax/awiwi.vim` | 214 | ported to `lua/awiwi/syn.lua` + `lua/awiwi/markers.lua` (**built, not wired** — activation is T10) | treesitter/extmark repaint replaces regex `:syntax`: markdown+markdown_inline queries, link conceal, marker/redaction/Redmine line patterns outside the code mask (B10); marker vocab + rg/vim escaping in `markers.lua`; group typos fixed (ADR D6) |
| `dao.vim`      | 667 | **WIP, unreachable** | OOP-prototype SQLite ORM (`task.db`): Task/Project/Tag/Urgency/ChecklistEntry/… Not reachable from `:Awiwi`. Has stray-colon typos that throw (see bugs) |
| `task.vim`     | 402 | **dead** | abandoned parallel SQLite task manager. Unloadable: syntax error `task.vim:11`, references undefined `s:Entity`/`s:db`/`s:states` |
| `view.vim`     | 286 | **dead/WIP** | interactive DAO prompts. Load has side effects (`awiwi#dao#init_test_data('/tmp/awiwi-test.db')`, `echo new_task(...)` at `view.vim:286`). Not wired to `:Awiwi` |
| `bookmarks.vim`|  70 | **dead** | errors on load (`awiwi#join` undefined, `bookmarks.vim:19`); dispatch branch commented out in `cmd.vim:484` |
| `ask.vim`      |   0 | stub | planned "ask" feature; `ask` constant exists but no impl |

## Command surface

`:Awiwi <sub> [args…]` → `awiwi#cmd#run`. Subcommand keywords are `s:*_cmd` constants
(`cmd.vim:6`); `s:subcommands` (`cmd.vim:42`) is the completion list.

| subcommand | behavior |
| ---------- | -------- |
| `journal [flags] <date\|today\|next\|previous\|todos>` | open/create journal; bare → fzf picker |
| `todo [name]` | open a todo file |
| `continue` | insert task continuation into today's journal |
| `activate` / `deactivate` | file-based active-task timer (writes `data/task.log`) |
| `asset [create [url\|paste\|copy]\|paste\|<date:name>] [flags]` | create/open/paste assets |
| `recipe <name> [flags]` | open recipe; bare → fzf |
| `link <journal\|recipe\|asset> …` | insert a link instead of opening (`link … #<heading>` completes headings) |
| `search <pattern>` | fuzzy rg search |
| `tags [all\|due\|urgent\|onhold\|question\|todo\|filter <pat>]` | rg+fzf marker/task search (`show_tasks`) |
| `entries` | rg headings → fzf |
| `toc [date]` | quickfix table of contents |
| `meta <edit [col]\|delete>` / `due <spec>` | edit `{…}` JSON line-meta / due date |
| `redact` | toggle `!!redacted` |
| `serve` / `server <start [host]\|stop\|logs [stdout\|stderr\|exit]>` | note viewer (FastAPI since ADR D5; vimscript still points at the dead Flask paths) |
| `paste` | top-level alias for `asset paste` (shipped but long undocumented) |
| `save` / `restore` | session `mksession` / source |
| `export` | drawio → PDF (async) |

Flags (journal/asset/recipe): `+create`, `+new`, `+hnew`, `+vnew`, `-new`, `+tab`, `+height=`,
`+width=`, `!bookmark`, `#anchor`.

**Known mismatch:** the `<F12>` mapping calls `:Awiwi tasks` but the dispatcher keyword is `tags`;
`tasks` is not in `s:subcommands`. Reconcile in the rewrite.

## Buffer mappings (`ftplugin/awiwi.vim`, `<buffer>`)

`gf` / `<leader>gft` / `<leader>gfn` open link (window/tab/window); `gC` continue; `gT` todo;
`ge` journal today; `gn`/`gp` journal next/prev; `<F12>` tasks; `o`/`O`/`<Enter>`/`<C-j>`
list-/checkbox-aware insert + due-date redraw; `<C-y>` checkbox; `<C-f>` time; `<C-q>` redact;
`<C-v>` paste; i_`<C-s>` `Awiwi link `; i_`<C-b>` `Awiwi asset create`; `gj` asset→journal;
`A` todo append. Abbreviations: `:shrug: :arrow: :check: :cross:`.

## Data & persistence

Two backends; **the shipped one is file-based**.

- **Documents** — journals / assets / recipes / todos are markdown files under `g:awiwi_home`
  (layout in `CLAUDE.md`). The filesystem hierarchy is the model. Todo checkboxes carry `{…}` JSON
  meta (`due`, `created`).
- **Active-task timer (shipped)** — a plain-text time log at `data/task.log`, driven by
  `awiwi#activate_current_task` / `#deactivate_active_task` in `awiwi.vim`; feeds `g:awiwi_active_task`
  and the airline section.
- **SQLite task DB (WIP, not reachable from `:Awiwi`)** — `<g:awiwi_home>/task.db`, created by
  `awiwi#dao#init` from `resources/db/init.sql` via `sql.vim` (shells out to `sqlite3`; no native
  driver). This is an in-progress replacement for the file log. Schema + drift notes:
  `docs/data-model.md`.
- **Other files** — `data/awiwi.log`, `cache/bookmarks`, `session.vim`, `config.json` (written for
  the server).
- **Markers** — line-classification keywords (`TODO`, `FIXME`/`CRITICAL`/`URGENT`, `ONHOLD`, `DUE`,
  `@incident`, `@change`, `@issue`, `@bug`, `@@` delegate, `QUESTION`, …) in `awiwi.vim`, extended
  by `g:awiwi_custom_<type>_markers`. Drive highlighting (`hi.vim`) and rg-based task search. Marker
  semantics are behavior.

## Configuration (globals)

**Required:** `g:awiwi_home`.

**Optional:** `g:awiwi_history_length` (log size, 10000), `awiwi_search_engine` (plain|regex|fuzzy),
`awiwi_screensaver` (gnome|cinnamon|kde|freedesktop), `awiwi_server_port` (5823),
`awiwi_autostart_server` (host), `awiwi_task_update_frequency` (30s), `awiwi_jump_to_end`,
`awiwi_image_opener` (`['xdg-open']`), `awiwi_external_dirs` (dict), `awiwi_use_entitlement`
(+`_opts`), `awiwi_custom_<type>_markers`. Syntax-only (`syntax/awiwi.vim`): `awiwi_conceal_links`
& `awiwi_conceal_link_*`, `awiwi_highlight_links`, `awiwi_link_color`, `awiwi_link_style`,
`awiwi_domain_color`. State: `g:awiwi_active_task`, `g:awiwi#dao#{Task,…}`, `g:autoloaded_*` guards.

## External dependencies

Binaries: `sqlite3`, `rg` (ripgrep), `fzf` + fzf.vim, `curl`, `xclip`, `file`, `xdg-open`, `date`,
`drawio` (export), `dbus-send` (screensaver, dead task.vim), `flask` + a venv at `server/.venv`.
Python: `pyx`/`pyxeval` (asset id), `py3` (delete-old-todos). Neovim-only APIs (above). External
VimL plugins: `fn#` (`fn#apply`/`fn#spread`, used by `path.vim` & `cmd.vim`) and a separate `path#`
(bare `path#join` in `dao.vim`) — distinct from awiwi's own `awiwi#path#`; optional `entitlement.nvim`,
optional `airline`.

## Dead code, WIP & known bugs (for the rewrite)

The Lua port should **not** carry these forward — fix or drop them, and record decisions in
`docs/decisions.md`.

- **Two competing SQLite task impls** — `dao.vim` (OOP `.subclass`) vs `task.vim`
  (`s:Entity.__prototype__`). `task.vim` is unloadable (syntax error `task.vim:11`); `dao.vim` has
  stray-colon typos `g:awiwi#dao#:TaskState` (lines 569,572,589,593,602,604,612) that throw. Neither
  is reachable from `:Awiwi`.
- **`view.vim`** — guard commented out; sourcing has side effects (writes `/tmp/awiwi-test.db`,
  `echo new_task(...)` at line 286). Not wired in.
- **`bookmarks.vim`** — `awiwi#join` undefined (line 19); `!bookmark` flag parsed but branch
  commented out (`cmd.vim:484`).
- **Bugs in shipped paths** — `awiwi#get_cache_subpath` returns undefined `s:cache_subpath`
  (`awiwi.vim:108`; var is `s:cache_dir`); `awiwi#util#get_visual_selection` has invalid tuple
  syntax (`util.vim:282`); `awiwi#util#get_iso_timestamp` defined twice (`util.vim:95` & `:100`);
  `path.vim:4` sets wrong guard `g:autoloaded_path`; `s:format_search_result` (`awiwi.vim:234`)
  looks truncated.
- **Query/schema drift** — `resources/db/get-*.sql` reference columns absent from `init.sql`
  (`task.state`, `task.issue_id`, `task_log.change` vs actual `task_state_id`, `issue_link`,
  `task_log.state_id`). See `docs/data-model.md`.

## Server (viewer)

`server/` is a fresh FastAPI + Pydantic app (Python ≥3.13, uv-managed) rendering awiwi notes,
replacing `server.old/` (Flask + Jinja). Reference feature set from the old app: markdown render
with TOC / internal links / mermaid; journal prev/next nav; asset serving (binary + downloadable);
auth with localhost bypass; breadcrumbs; search. `server.vim` currently drives the *old* Flask app
via `server/.venv/bin/flask` — this coupling must be reworked for the FastAPI server.
`pyproject.toml` still carries template Django/mypy config; the live toolchain is ruff +
basedpyright + pytest.
