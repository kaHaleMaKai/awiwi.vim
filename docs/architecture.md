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
| Server/viewer | `server/src/awiwi/` (FastAPI + Pydantic) | bootable and complete (T13–T17): config, content/checkbox/search, mdrender, app/routers/templating, templates+static copy; replaces `server.old/` |
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
   folding via Lua `foldexpr`, abbreviations, optional server autostart. Sets window-local
   `conceallevel=2` + `concealcursor=nciv` so syn's link conceal renders out of the box (T10.2 —
   deliberate improvement: legacy relied on the user's global config for `conceallevel`), and starts
   the bundled markdown treesitter highlighter for base styling (T10.1).
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
| `hi.lua`       | due-date badges + header rules as extmarks; treesitter structural pass (`headings`/`code_line_mask`, reused by syn); title helpers for `entitlement.nvim`; lazy-requires façade for recipe-title helper (B13) |
| `path.lua`     | path join/split/relativize/canonicalize; native `path.join()` replaces broken `fn#apply`/`fn#spread` dependency (B10 fix) |
| `server.lua`   | viewer control: start/stop/logs/serve via `vim.system`, non-blocking `wait_ready`; launches FastAPI server (`awiwi.app:app` entrypoint pinned in T17, env `AWIWI_HOME=<g:awiwi_home>` threaded via `vim.system`; ADR D5 + D15); config.json, xdg-open |
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
Cmdline c_`<C-x>`/c_`<C-v>` append ` +hnew`/` +vnew` and submit — suppressed when the command
starts with an `:Awiwi` abbreviation (guard inversion fixed per ADR D12).

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

`server/` is a FastAPI + Pydantic app (Python ≥3.13, uv-managed) rendering awiwi notes, replacing
`server.old/` (Flask + Jinja). Bootable entrypoint: `awiwi.app:app` (pinned in `lua/awiwi/server.lua`
T17, env `AWIWI_HOME` threaded via `vim.system`; ADR D15 supersedes D5 placeholder). Config protocol:
env `AWIWI_HOME` set by launcher; `config.json` (from plugin, keys: `search_engine`, `home`,
`screensaver`, `link_color`, per-marker lists) read once at lifespan, permissive (missing file → defaults,
unknown keys ignored). Auth: localhost-only (403 for non-localhost), unless `AWIWI_ALLOW_REMOTE=1`
env var set (ADR D14). Markdown: python-markdown with trimmed built-ins (fenced_code, codehilite,
def_list, footnotes, nl2br, sane_lists, toc, tables, attr_list) + local `_MermaidExtension` /
`_StrikethroughExtension` replacing unmaintained third-party; corpus semantics preserved (nl2br,
no non-ASCII escaping hack; ADR D13).

**Module map** (`server/src/awiwi/`):
- `config.py` — `Settings` (pydantic-settings, env `AWIWI_HOME`), `PluginConfig` (permissive JSON load)
- `content.py` — date parsing + aliases, journal prev/next nav, path safety, dir listing, breadcrumbs
- `checkbox.py` — line hashing (MD5, legacy-compatible), in-place toggle with domain-specific errors
- `search.py` — ripgrep arg building, output parsing, hit sorting (todo → journal → asset → recipe)
- `mdrender.py` — `RenderedDoc`, `render_markdown` (with pre-filters: redaction, checkbox, @tag/@mention, ordinal sup), `render_file` (Pygments + vim-modeline sniff)
- `templating.py` — Jinja2 setup (autoescape off, for legacy template compatibility)
- `app.py` — app factory + module-level `app` (ASGI), lifespan (config load), localhost 403 middleware
- `routers/pages.py` — pages router (journal, recipes, catch-all, dir index, `/todo`, `/change-mode`)
- `routers/assets.py` — assets router (MIME dispatch, download disposition, render or serve binary)
- `routers/actions.py` — actions router (`PATCH /checkbox`, `POST /search/content`)

**Route table** (registration: assets → actions → pages; catch-all last; all routed through
`render_content_file` helper that dispatches on extension: `.md` → `render_markdown`, `.drawio` →
raw XML, images/binaries → inline/download, else `render_file` Pygments + fallback):

| Method | Path | Behavior |
|---|---|---|
| GET | `/assets/{year}/{month}/{day}/{file}` | 302 → `/assets/{date}/{file}` (dash-format) |
| GET | `/assets/{date}/{file}` | asset serve; invalid date → 404; `application/*` (except sql) → download; else render/inline |
| PATCH | `/checkbox` | JSON `{line_nr,path,check,hash}` → toggle file line; 200/404/409 per domain errors |
| POST | `/search/content` | form `search-content`; empty → 400; spawn `rg` (cwd home) → render search results |
| GET | `/change-mode` | set theme cookie, 302 to `Referer` or `/` |
| GET | `/` | dir index (home root) |
| GET | `/dir/{path:path}` | dir index + breadcrumbs |
| GET | `/todo` | render `journal/todos.md`, `title="TODO"`, no TOC |
| GET | `/journal/{year}/{month}/{file}` | 302 → `/journal/{file-sans-.md}` |
| GET | `/journal/{date_str}` | journal render (`.md` stripped if present); aliases (today/yesterday/prev); TOC + prev/next nav |
| GET | `/{d}.md`, `/{m:int}/{d}.md`, `/{y:int}/{m:int}/{d}.md` | legacy date redirects → `/journal/{d}` |
| GET | `/recipes/{path:path}` | render recipe markdown (or source file, Pygments) |
| GET | `/{path:path}` | **catch-all (last)**: safe-resolve under home (traversal/absolute → 404), render/serve |
| mount | `/static` | static files (`server/static/`, pre-mounted before routers) |
| exc | `FileNotFoundError` | → `404.html` with status 404 |

**Templates & static** — `templates/` (7 files, copied from `server.old/html/`): `base.html.j2`,
`dir.html.j2`, `journal.html.j2`, `non-journal.html.j2`, `search-content.html.j2`, `todo.html.j2`,
`404.html` (dropped: `login.html.j2` auth removed, `main.html.j2` dead). `static/` copied+pruned from
`server.old/static/` (141 MB → 4.5 MB): excluded npm test fixtures (68 MB `mermaid/npm-test/`,
137 MB `js/node_modules/`); kept `common.js`, `custom-reveal.js`, `sortable-tables.js`, `graphre.js`,
`nomnoml.js`, mermaid dist, all CSS/img.

**Security** (ADR D14) — HTTP middleware returns 403 for non-localhost requests (checks `Host`
header loopback name OR loopback client peer). Explicit `AWIWI_ALLOW_REMOTE=1` env var overrides,
enabling remote access if needed. No login/session machinery. Secret-named files (regex `secret|credential`
stem) blank their body off-localhost.

**Plugin integration** (`lua/awiwi/server.lua`, T17) — spawns via `uv run uvicorn awiwi.app:app
--host <host> --port <port>` (cwd `server/`, env `AWIWI_HOME` set); config.json written by
`start_server` before spawn.

Toolchain: ruff, basedpyright, pytest (no external service dependencies).
