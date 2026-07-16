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
| Server/viewer | `server/src/awiwi/` (FastAPI + Pydantic) | JSON API + committed Svelte SPA (T13–T27): config, content/checkbox/search, mdrender, app/routers, `frontend/dist/`. Legacy Jinja template stack and `server.old/` deleted at T27 |

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
| `init.lua`     | façade: journals, links, asset paste, **file-based active-task timer** (`data/task.log`), quickfix TOC, active-task timer resume; bootstraps dirs + log files; reexports leaf-module APIs; wires ftplugin/init; `edit_journal` seeds a brand-new journal file (`open_file`'s `template`/`template_cursor` options) with a `# YYYY-MM-DD` / `## ` header and drops into insert mode on the heading line — existing files are left untouched |
| `cmd.lua`      | subcommand dispatch (`run`) + completion; `show_tasks`, sessions, drawio export; routes through `picker.lua` seam; `:Awiwi search` now via `picker.grep` (ADR D8) |
| `picker.lua`   | unified picker seam: `vim.ui.select` default, telescope auto-upgrade (ADR D7); three types: `select`, `files`, `grep` |
| `asset.lua`    | create/open/link assets under `assets/YYYY/MM/DD/`; owns `M.types` (asset⇄cmd cycle broken); pure-Lua random id; open side-effect-free (ADR D4); injectable deps; `resolve_image_link(target)` maps `/…/YYYY-MM-DD/name` → asset path, nil for relative/URL/non-date targets (init's image open errors on nil instead of spawning the opener on a garbage path) |
| `date.lua`     | parse/normalize dates, journal-relative nav; pure os.date/os.time, narrowed grammar (ADR D3), new `diff_days`; `deps.journal_dates` seam wired by the façade so `prev`/`next` resolve against real journal files (T10.1) |
| `util.lua`     | helpers: link parse/classify (journal misclassification fixed), `match_subcommands`, `input` (vim.ui.input callback), code-block text objects, window-split utilities |
| `hi.lua`       | due-date badges + header rules as extmarks; treesitter structural pass (`headings`/`code_line_mask`, reused by syn); title helpers for `entitlement.nvim`; lazy-requires façade for recipe-title helper (B13) |
| `path.lua`     | path join/split/relativize/canonicalize; native `path.join()` replaces broken `fn#apply`/`fn#spread` dependency (B10 fix) |
| `server.lua`   | viewer control: start/stop/logs/serve via `vim.system`, non-blocking `wait_ready`; launches FastAPI server (`awiwi.app:app` entrypoint pinned in T17, env `AWIWI_HOME=<g:awiwi_home>` threaded via `vim.system`; ADR D5 + D15); config.json, xdg-open |
| `str.lua`      | string helpers (startswith/endswith/contains/is_empty); case-sensitive (intentional per ADR D2); leaf, widely used |
| `syn.lua`      | treesitter/extmark syntax layer: markdown+markdown_inline queries, link conceal, marker/redaction/Redmine line patterns outside code mask; typos fixed (ADR D6); wired via ftplugin FileType autocmd (T10), repainted on `BufEnter`/`BufModifiedSet` like `hi`'s horizontal lines (ADR D16); paints awiwi *extras* only — base markdown styling (headings/fences/emphasis) comes from `vim.treesitter.start(buf, "markdown")` in the ftplugin (T10.1) |
| `markers.lua`  | marker vocabulary (TODO/FIXME/ONHOLD/DUE/@due/@incident/…); rg/vim escaping; `g:awiwi_custom_*_markers` overrides |
| `img.lua`      | optional inline-image rendering via snacks.nvim `image` (silent auto-upgrade, ADR D7 seam pattern): `attach(buf)` no-ops false without snacks or when `g:awiwi_inline_images` is `false`/`0`; registers `markdown` treesitter lang for awiwi filetypes (load-bearing for snacks' doc scan); chains (never clobbers) `snacks.image.config.resolve` so `/assets/YYYY-MM-DD/name` embeds resolve to the asset tree via `asset.resolve_image_link` |

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
(+`_opts` for entitlement.nvim title decoration), `awiwi_custom_<type>_markers` (marker overrides),
`awiwi_inline_images` (default enabled; `false`/`0` forces plain-link fallback even with snacks.nvim installed).

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

`server/` is a FastAPI + Pydantic app (Python ≥3.13, uv-managed) serving a JSON API (`/api/*`)
plus a committed Svelte SPA (`/_app/`, no Node at serve time). Entrypoint: `awiwi.app:app`
(pinned in `lua/awiwi/server.lua` T17, env `AWIWI_HOME` threaded via `vim.system`; ADR D15).
The legacy Flask + Jinja server (`server.old/`) and template stack (`templates/`, `static/`,
`routers/pages.py`, `routers/assets.py`, `routers/actions.py`, `templating.py`) were deleted at
T27. All shipped behavior (markdown rendering, task tracking, secret gating) is preserved via
backend-side Markdown rendering + client-side Shiki syntax highlighting (ADRs D13, D18), live
filesystem sync (ADR D19), and committed-dist SPA (ADR D20).

### Config, auth, dev/serve

**Config** (`config.py`): env `AWIWI_HOME`, permissive `config.json` (keys: `search_engine`,
`home`, `screensaver`, `link_color`, per-marker lists), loaded at lifespan, boot never fails (T17).

**Auth**: localhost-only (403 for non-localhost) unless `AWIWI_ALLOW_REMOTE=1` (ADR D14); per-route
re-derivation for WebSocket (HTTP middleware doesn't cover ASGI `websocket` scope).

**Development**: `cd server && uv sync && uv run uvicorn awiwi.app:app` (live reload); `cd frontend && npm run dev` proxies `/api` → `localhost:5823` over WebSocket.

**Production**: `cd server && uv run uvicorn awiwi.app:app` (cwd `server/`, no Node); the committed
`frontend/dist/` is served as part of the app.

### Module map (`server/src/awiwi/`)

- `config.py` — `Settings` (pydantic-settings, env `AWIWI_HOME`), `PluginConfig` (permissive JSON)
- `content.py` — date parsing + aliases, `normalize_asset_path()` (S33.1: asset URL alias canonicalization), journal prev/next nav, path safety, dir listing, breadcrumbs
- `checkbox.py` — line hashing (MD5, legacy-compatible), in-place toggle with domain-specific errors
- `search.py` — ripgrep arg building, output parsing, hit sorting
- `mdrender.py` — `RenderedDoc`, `render_markdown` with pre-filters (redaction, checkbox,
  `@tag`/`@@mention`/`#tag` inline-markup spans (T28.0), ordinal sup); fenced code as plain
  `<pre><code class="language-x">` (client-side Shiki highlights,
  per ADR D18; CodeHilite dropped T23); `guess_language(path, text)` ext-map + vim-modeline hint;
  redacted blocks stay in HTML obscured (`span.redacted`, click-to-reveal in SPA), except remote
  (D23 no-sanitization stance)
- `schemas.py` — SPA API Pydantic models: `DocPayload` (kind: markdown|text|image|drawio|binary,
  `watch_path` = WS key, secret blanking), `DirPayload`/`DirEntry`, `NavPayload`, `BreadcrumbPayload`,
  `SearchHit`
- `docs.py` — payload builders `build_doc_payload`/`build_journal_payload`/`build_dir_payload` on
  `content`/`mdrender`
- `httputil.py` — `is_localhost`, `get_home` (relocated from deleted `templating.py`)
- `app.py` — app factory, lifespan (config + watcher startup), localhost 403 middleware; mounts
  `/_app` StaticFiles + registers routers (`api` → `redirects`); `FileNotFoundError` → JSON 404
- `routers/api.py` — `/api/*` JSON routes: `/journal/{date}`, `/todo`, `/doc/{path}`, `/dir[/{path}]`,
  `/meta`, `/raw/{path}` (ETag conditional), `/ws` (WebSocket), `PATCH /checkbox` (relpath),
  `/search?q=&mode=&scope=` (ripgrep)
- `routers/redirects.py` — legacy 302 redirects (bare-date/`.md`/ymd-asset forms + asset-alias redundant-dashed-segment form per S33.1) + SPA catch-all
  `GET /{path:path}` → `index.html` no-cache (T26)
- `watch.py` — `DocWatcher`: in-memory `watch_path → {socket}` subscriptions (single-process only —
  never `--workers`); `broadcast(path)` rebuilds payload + pushes `doc`/`deleted` messages; `run()`
  over `watchfiles.awatch(home)` filtering dotfiles/`config.json`; checkbox PATCH triggers broadcast
  (deterministic, not fs-watch-dependent)

### API route table (T23–T26, frozen contract)

All responses JSON except `/api/raw/{path}` (bytes). Registration order: `/_app` mount → `api.router`
(`/api/*` routes + JSON catch-all) → `redirects.router` (legacy 302s + SPA catch-all); Starlette
matches in order, so `/api/*` is checked before the SPA catch-all. Comprehensive spec:
`handovers/done/server-rewrite/T23.2-api-routes.md`.

| Method | Path | Behavior |
|---|---|---|
| mount | `/_app` | StaticFiles over `frontend/dist` (hashed assets, long-cacheable) |
| GET | `/api/journal/{date_str}` | Journal day as `DocPayload`; `date_str` = ISO date or `today`/`yesterday`/`prev`/`previous` |
| GET | `/api/todo` | `journal/todos.md` as `DocPayload` |
| GET | `/api/doc/{path:path}` | Any doc by relpath, kind-dispatched (markdown/text/image/drawio/binary); asset paths may use alias forms (`assets/YYYY-MM-DD/name` or `assets/YYYY/MM/DD/YYYY-MM-DD/name`) which normalize to disk shape before resolution (S33.1) |
| GET | `/api/dir[/{path:path}]` | Directory listing as `DirPayload` |
| GET | `/api/meta` | Metadata: `{today, home, version}` |
| GET | `/api/raw/{path:path}` | Raw bytes; ETag `{mtime_ns}-{size}`/304 on If-None-Match; `?download=1` → attachment; asset paths support alias forms (S33.1, same as `/api/doc/{path}`) |
| GET | `/api/ws` | WebSocket (see WS protocol below) |
| PATCH | `/api/checkbox` | Relpath-addressed toggle: `{path, line_no, line_hash, checked}` → `{success, line_hash, mtime_ns}` |
| GET | `/api/search?q=&mode=&scope=` | Ripgrep search: `q` (required), `mode=fixed\|regex` (default `fixed`), `scope=journal,assets,recipes` |
| — | `/{y}/{m}/{d}/{file}`, `/journal/{y}/{m}/{file}`, `/journal/{date}.md`, `/{d}.md`, `/assets/{y}/{m}/{d}/{YYYY-MM-DD}/{file}`, etc. | 302 redirects (legacy URLs + asset-alias redundant-dashed-segment form per S33.1) → canonical SPA paths |
| GET | `/{path:path}` | **SPA catch-all (last)**: `frontend/dist/index.html` no-cache; client router resolves `/`, `/dir/*`, `/todo`, `/journal/:date`, `/assets/:date/:file`, `/recipes/*`, `/search`, `/*` notfound |
| — | `/api/{rest:path}` | JSON 404 catch-all (within `api` router, last among its routes) |
| exc | `FileNotFoundError` | → JSON `{"detail": "not found"}`, status 404 |

**Checkpoint secrets**: `/api/doc/{path}` and `/api/raw/{path}` blank secret files off-localhost
(regex `\b(secret|credential)s?\b$` on stem). On localhost, content is visible; `is_secret` field
set in payload.

### WebSocket protocol (T24, single-process only)

Endpoint: `GET /api/ws` (upgrade). Client → server messages are JSON `{type, ...}`:

| `type` | Fields | Effect |
|---|---|---|
| `"subscribe"` | `"path"`: relpath | Subscribe to that doc (idempotent) |
| `"unsubscribe"` | `"path"`: relpath | Unsubscribe (no-op if not subscribed) |
| `"ping"` | — | Server replies `{type: "pong"}` |

Server → client messages:

| `type` | Fields | When |
|---|---|---|
| `"doc"` | `"path"`: relpath, `"payload"`: `DocPayload` JSON | Doc changed, still exists (rebuilt fresh, not a diff) |
| `"deleted"` | `"path"`: relpath | Doc no longer exists |
| `"pong"` | — | Reply to `"ping"` |
| `"error"` | `"detail"`: string | Client message malformed (socket stays open) |

**Expectations**: subscriptions exist only while connected; on reconnect, client must re-subscribe.
Broadcasts only fire from live fs events or checkbox PATCHes; disconnected clients miss intervening
changes. On (re)connect/(re)subscribe, client should independently re-fetch via `GET /api/doc/{path}`
for current state (WS is live-update atop REST snapshot). Atomic-write handling: broadcasts decide
`"doc"` vs `"deleted"` from live `is_file()`, so nvim's rename-based safe writes never emit spurious
deletes. Checkbox PATCH broadcasts deterministically, not fs-watch-dependent. **Single-process
constraint**: `DocWatcher._subs` is in-memory, in-process dict; running with `--workers > 1` breaks
live sync (each worker has empty registry). Comprehensive spec: `handovers/done/server-rewrite/T24-live-sync.md`.

### Frontend (Svelte 5 + Vite, committed-dist policy)

**Structure** (`server/frontend/`):
- `index.html` — entry; inline pre-mount theme script (sets `data-theme` on `<html>` before Svelte),
  mounts `main.ts`
- `vite.config.ts` — base `/_app/`, dev proxy `/api` → `localhost:5823` (WebSocket), vitest config
- `src/app.css` — Noir-Deco design tokens (ink/paper/smoke/brass scales + neon accents), ported from
  mockups (ADR D21 theme choice); presentation mode overlay styles (`.pm-overlay`, `.pm-stage`, `.pm-slide`, `.pm-controls`, `.pm-arrows`, `.pm-exit`)
- `src/main.ts` — mounts `App.svelte`, imports `app.css`
- `src/App.svelte` — shell: header (Breadcrumbs, SearchBar, ConnectionDot, ThemeToggle) + route switch
- `src/lib/theme.svelte.ts` — reactive theme store (`dark`/`light`), persists to `localStorage['awiwi.theme']`
- `src/lib/router.svelte.ts` — hand-rolled runes router (path-mode URLs): `/`, `/dir/*`, `/todo`,
  `/journal/:date`, `/assets/:date/:file`, `/recipes/*`, `/search`, `/*` notfound; exports
  `RouterState` interface (extends `Route` with reactive `search` and `hash` fields, updated on
  every navigation including query/hash-only updates); hash-scroll behavior (scrolls to hash-target
  element via `requestAnimationFrame` after navigation, incl. same-path hash links); global same-origin
  `<a>` click interception (preventDefault + navigate with hash/search preserved)
- `src/lib/api.ts` — typed `/api` fetchers (no runes, ordinary TypeScript)
- `src/lib/components/` — reusable components: `Breadcrumbs` (path trail + special root case "home | today"; S31.1), `DirPage` (folder listing; root renders branding title "awīwī /awi:ˈi:/" + italic subtitle + today quick-link breadcrumbs per S31.1), `DocPage` (document viewer with optional TOC rail; supports asset-only opt-in presentation mode via `PresentationMode` component — full-screen slideshow with `<h1>` boundaries, direction-aware arrow navigation, mousemove-revealed controls), `SearchBar`, `ThemeToggle`, `ConnectionDot`, `PresentationMode` (full-screen overlay slideshow component wired from `DocPage` for assets; clones `.markdown-body` DOM, renders per-slide inert HTML, direction-clamped arrow nav, mousemove-driven control visibility)
- `src/lib/presentation/slides.ts` — pure utilities for presentation mode: `splitSlides()` (partition rendered HTML by top-level `<h1>`), `step()` (clamped navigation), `arrowOpacity()` (visual feedback at slide edges)
- `src/lib/enhance/` — pipeline for rendered markdown: Shiki dual-theme (lazy singleton, CSS-var
  theme flip, `textContent` read for unknown-lang fallback; ADR D18), mermaid (lazy, re-themed on
  toggle), checkbox wiring (PATCH relpath, 409 → refetch), copy buttons on `<pre>`, table export
  (markdown/CSV/HTML via `tableExport.ts`), image rewrite + lightbox (lazy), drawio-inline (S31.2:
  enhance pass that replaces `.drawio` links in doc bodies with inline-rendered diagrams via shared
  `loadDrawioViewer()` singleton, graceful fallback to original link on error, idempotent). Language
  hint from backend `guess_language` (ext map + vim-modeline).
- `src/lib/drawioViewer.ts` — singleton lazy-loader for vendor drawio viewer script (shared by DrawioView component + drawio-inline enhance pass; S31.2)
- `src/routes/` — route views (Home, Dir, Todo, Journal, Asset, Recipes, Search, NotFound); **JournalPage** features a collapsible TOC rail with sticky positioning; layout uses `.layout-with-rail { grid-template-columns: minmax(0, 1fr) 310px; }` to prevent wide content (`<pre>`, `<table>`) from pushing the rail off-screen (S30.1: overflow-x rules on `.markdown-body pre`/`table`, rail default-collapsed below 700px viewport)
- `public/vendor/drawio/` — pinned `viewer-static.min.js` (lazy-loaded by `drawioViewer.ts` singleton, no app.diagrams.net ever contacted; ADR D22)

**Build**: `npm run build` produces byte-identical `frontend/dist/` (reproducible, no Node at serve
time). **Committed-dist policy** (ADR D20): dist is force-added to git (`.gitignore` ignores it but
file is tracked); future rebuilds show as normal diffs. On merge conflict: rebuild, never manually
resolve (documented in `.gitattributes` `linguist-generated -diff` + this architecture note). New
dist files need `git add -f` (wart of not un-ignoring `.gitignore`).

**No sanitization** (ADR D23): `{@html}` in `MarkdownView` injects server-rendered HTML directly,
then `enhance()` post-processes. Scope: localhost-only own notes (auth gate + secret blanking in
backend); if remote access is ever enabled seriously, HTML/JS injection becomes a vector and needs
front-end sanitization (DOMPurify or similar).

**Build/dev workflow**:
```bash
cd server/frontend
npm install                     # once
npm run dev                     # local dev (proxies /api to backend at 5823)
npm run build                   # ci/deploy; produces frontend/dist/
npx vitest run                  # tests
npx svelte-check               # type check (Svelte components)
```

Backend must be running at `localhost:5823` for `/api` proxy to work in dev.

### Markdown rendering semantics

Python-markdown + local extensions, byte-identical per ADR D13:
- Built-ins enabled: `fenced_code`, `def_list`, `footnotes`, `nl2br`, `sane_lists`, `toc`, `tables`,
  `attr_list`
- Local extensions: `_MermaidExtension`, `_StrikethroughExtension` (replace unmaintained third-party)
- Fenced code: pre-rendered as plain `<pre><code class="language-x">` (no server-side
  syntax highlight; CodeHilite removed T27). Shiki highlights client-side (ADR D18) — language hint
  via `guess_language` (ext-map + vim-modeline), unknown langs show unhighlighted.
- Redaction (D23, D24): two forms, both click-to-reveal in the SPA:
  - **Inline redaction** `[~secret~]` → `<span class="redacted">` with HTML-escaped raw value
    embedded (D24: stays unchanged from S23.4). Revealed secrets read back character-exact (critical
    for passwords, API keys, where markdown punctuation like `pass*word*123` must preserve asterisks);
    inline markers are stripped. Always plain text on reveal (no markdown rendering).
  - **Heading-section redaction** `!!redacted` heading → `<div class="redacted">` with **rendered HTML**
    of the hidden section (D24 change from S23.4; previously raw-escaped). The section's heading
    (marker stripped) + body are re-run through pre-filters (checkboxes, tags/mentions, ordinals) and
    markdown rendering, then embedded. Nested `!!redacted` inside the section are stripped, staying
    hidden even after reveal. Checkbox `data-line-nr`/`data-hash` use real file offsets, so PATCH
    `/checkbox` works correctly on embedded checkboxes.
  - **Shared mechanism**: Both use inert-token substitution — content stashed behind
    `awiwiredacted<uuid>n<i>` tokens, planted in filtered output, substituted *after* outer
    `md.convert` so embedded content never travels through python-markdown a second time. Non-embed
    mode (legacy, `embed_redacted=False`) byte-identical to stripping behavior: `!!redacted` elided,
    no trace in HTML.
  - **Scope**: localhost-only (403 off-localhost per D14); no HTML sanitization (D23). On localhost,
    revealed sections show rendered markdown (links, lists, tables, syntax-highlighted code via
    Shiki); revealed inline values show raw text
- **GFM task-list checkboxes** (S32.1–S32.2, widened to full GFM semantics): recognized on lines
  with bullets `*`/`-`/`+` or ordered items (`1.`/`1)`) followed by one-or-more spaces and a box
  `[ ]`/`[x]`/`[X]` (uppercase `X` also renders checked), optionally with no trailing text. Toggle
  writes lowercase `x`; hashes for legacy single-space `* `/`- ` forms unchanged. Blockquote-nested
  checkboxes (`> - [ ]`) are deliberately not recognized (remain plain text). Rendered as
  `<input type="checkbox" ... data-line-nr=... data-hash=...>` with PATCH endpoint wiring at
  `/api/checkbox` (relpath, line_no, expected_hash → success + new hash + mtime).
- Inline tag/mention markup (T28.0, `mdrender._filter_body`'s `_INLINE_MARKUP_RE`, applied
  line-by-line before python-markdown conversion): `@bug`/`@change`/`@incident`/`@issue` →
  `<span class="awiwi-{type}">`; `@@word` (full token, e.g. `@@lars`) →
  `<span class="awiwi-mention">`; `#word` / `#path/style-tag` (e.g. `#project-awiwi`,
  `#recipes/sourdough-starter`) → `<span class="awiwi-tag">`. The class contract is server-driven —
  `frontend/src/app.css` styles `.awiwi-tag`/`.awiwi-mention` (visuals copied from the T22 mockups'
  `.tag`/`.mention` in `mockups/tokens.css`, selector renamed to match). `#tag` never fires on a
  heading marker (`# `/`## ` always have a space after the last `#`, so the "immediate word char"
  requirement excludes it structurally) or a markdown link href (`](#anchor)`); none of the three
  patterns fire inside an inline code span (`` `...` ``) or a fenced code block (```` ``` ````,
  including ```` ```mermaid ```` diagram source). Inline code and fences are tracked with exact state
  (not toggled naively): **fence-state tracking mirrors FencedCodeExtension**, accepting both backtick
  and tilde delimiters (3+ consecutive chars, column 0). A fence opener enters state only if an exact
  closer exists later in the document (scan-ahead check); the state persists until a line matches the
  opener's exact delimiter (same char, same run length, column 0, trailing spaces only). Known divergence:
  scan-ahead examines raw document lines, so a closer hidden inside a redacted section can diverge from
  what FencedCodeExtension observes (corner case accepted, was never in sync before either). This exact
  tracking prevents false "in fence" states that would otherwise skip checkbox/tag/mention injection on
  ordinary text incorrectly labeled fenced.

### Toolchain

**Tests**: `cd server && uv run pytest` (testpaths=`tests/`, no external service deps).
**Lint/format**: `uv run ruff check .` (line-length 90, double quotes), `uv run ruff format .`.
**Type check**: `uv run basedpyright` (0 errors/warnings/notes).
**Visual-regression harness**: `server/tests/visual/shoot.mjs` (dep-free CDP screenshot
harness: chromium headless, full-page capture, ImageMagick RMSE + band slices). Rerunnable;
fixture tree at `server/tests/visual/fixture/home/`, manifest at `pairs.json`; used for
SPA↔mockup parity loop (T28), mockups are ground truth. See `handovers/done/visual-parity/`
for run results and exclusion lists.
**Git/pre-commit**: `scripts/kb-detect.sh` (rules in `.claude/kb/rules.tsv`) gates changes to
`server/src` or `server/pyproject.toml` against fresh knowledge layers (`docs/architecture.md` or
`docs/INDEX.md`); `DOCS_OK=1 git commit` to escape if docs are unchanged.
