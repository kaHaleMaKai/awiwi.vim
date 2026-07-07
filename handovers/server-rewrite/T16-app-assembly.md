# T16 S16.1 — app assembly (app.py, templating, routers, templates+static copy)

## Responsibility

Assemble the bootable FastAPI viewer from the T13–T15 leaf modules: the
Jinja wiring (`templating.py`), the three routers (`routers/pages.py`,
`assets.py`, `actions.py`), the app factory + module-level ASGI app
(`app.py`), plus the mechanical copy of the legacy templates and (pruned)
static assets. Routers are thin glue over the pure leaf modules — no domain
logic reimplemented here. Strict acceptance-first (red) TDD.

Entrypoint: **`awiwi.app:app`** (module `server/src/awiwi/app.py`, module-level
`app = create_app()`). Boots with `uv run uvicorn awiwi.app:app` and
`AWIWI_HOME` set. This is the name T17 must pin in
`lua/awiwi/server.lua`'s `default_cmd_builder` (replacing the `app:app`
placeholder), threading `env={AWIWI_HOME=vim.g.awiwi_home}`.

## Boundary

Created/edited only:

- `server/src/awiwi/app.py` (new)
- `server/src/awiwi/templating.py` (new)
- `server/src/awiwi/routers/{__init__,pages,assets,actions}.py` (new package)
- `server/templates/` (copied from `server.old/html/`)
- `server/static/` (copied+pruned from `server.old/static/`)
- `server/tests/test_acceptance.py` (new)
- `server/tests/conftest.py` (added `acceptance_home` + `client` fixtures;
  `notes_home` untouched, per brief)

Nothing outside `server/`. No `lua/`, `docs/`, `server.old/`, `pyproject.toml`.
No commit made.

## What downstream needs (T17 + curator)

- **Entrypoint module path:** `awiwi.app:app`. Verified boot:
  `AWIWI_HOME=<tree> uv run uvicorn awiwi.app:app --port 5823` →
  `GET /todo`, `/`, `/journal/<date>`, `/static/css/common.css` all 200.
- **Lifespan** reads `Settings()` (env `AWIWI_HOME`) once and stashes
  `app.state.home: Path` + `app.state.plugin_config: PluginConfig`
  (`PluginConfig.load(home)`). No reload machinery.
- **Localhost-only guard** (replaces legacy login/session, per user
  decision): an HTTP middleware returns **403** for non-localhost requests.
  `is_localhost` keys off the `Host` header (loopback name) OR a loopback
  client peer — matching legacy `is_localhost`. Tests/clients must use
  `base_url="http://localhost"`; real localhost access (curl to
  `localhost:5823`) passes. There is **no** config toggle for "allow remote"
  (see Divergences); if one is ever wanted it belongs in `Settings`
  (config.py), out of this subtask's boundary.

### Route table (as implemented)

Registration order matters; the catch-all is last. Routers included in
`create_app()` as: `assets` → `actions` → `pages`.

| Method | Path | Handler / behavior |
|---|---|---|
| GET | `/assets/{year}/{month}/{day}/{file}` | 302 → `/assets/{y}-{m}-{d}/{file}` |
| GET | `/assets/{date}/{file}` | asset serve; invalid ISO date → 404; `application/*` (bar sql) → download (`Content-Disposition: attachment`); else `render_content_file` |
| PATCH | `/checkbox` | JSON `{line_nr,path,check,hash}` → `toggle_checkbox`; 200 `{success:true}`; 404 (missing file/line, unknown endpoint); 409 (hash mismatch / already-in-state / not-a-checkbox) |
| POST | `/search/content` | form `search-content`; empty → 400; else spawn `rg` (cwd=home) → `parse_search_output` → `sort_hits` → `search-content.html.j2` |
| GET | `/change-mode` | re-set (not toggle) theme cookie w/ long max-age, 302 → `Referer` or `/` |
| GET | `/` | dir index of home root |
| GET | `/dir/{dirs:path}` | dir index + breadcrumbs |
| GET | `/todo` | render `journal/todos.md`, `title="TODO"`, `add_toc=False` |
| GET | `/journal/{year}/{month}/{file}` | 302 → `/journal/{file-sans-.md}` |
| GET | `/journal/{date_str}` | journal render (`.md` suffix → 302 strip); aliases via `parse_date`; None → 404; TOC + prev/next |
| GET | `/{date_str}.md` | 302 → `/journal/{date_str}` |
| GET | `/{month:int}/{date_str}.md` | 302 → `/journal/{date_str}` |
| GET | `/{year:int}/{month:int}/{date_str}.md` | 302 → `/journal/{date_str}` |
| GET | `/recipes/{path:path}` | `render_content_file(home/recipes/path)` |
| GET | `/{path:path}` | **CATCH-ALL, LAST**: `safe_resolve` under home (traversal/absolute → 404), then `render_content_file` |
| mount | `/static` | `StaticFiles(server/static)` (added before routers) |
| exc | `FileNotFoundError` | → `404.html`, status 404 |

`render_content_file` (in `pages.py`, shared with `assets.py`) ports
`server.old/app.py:render_non_journal`: `.md` → `render_markdown`; `.drawio`
→ raw xml; images → inline bytes; extension-less → raw text; else
`render_file` (pygments, raw-text fallback). Secret-named files
(`\b(secret|credential)s?\b$` on the stem) blank their body off-localhost.

### Template / static copy inventory

`server/templates/` (7 files, copied from `server.old/html/`):
`base.html.j2`, `dir.html.j2`, `journal.html.j2`, `non-journal.html.j2`,
`search-content.html.j2`, `todo.html.j2`, `404.html`. **Not copied:**
`login.html.j2` (auth dropped) and `main.html.j2` (dead — unreferenced by any
route, uses a stale `dark_mode` var). HTML/CSS/JS content unchanged; the only
"wiring" adaptation is at the Jinja-*environment* level (autoescape off, see
below) — no per-template edits were needed.

`server/static/` — **4.5 MB** total (`css` 284K, `img` 164K, `js` 4.1M).
Pruned via `rsync --exclude node_modules --exclude npm --exclude npm-test`.
Kept: `common.js`, `custom-reveal.js`, `sortable-tables.js`, `graphre.js`,
`nomnoml.js`, `mermaid.js`, `mermaid-module.js`, the `mermaid/` dist (minus
its 68 MB `npm-test/`), all `css/`, all `img/`. Excluded the ~137 MB of
`js/node_modules/`, `js/npm/` (gitignored as `/server/static/npm`), and
`js/mermaid/npm-test/`. (An empty `js/nomnoml/` shell remains after its only
child `node_modules/` was pruned — harmless.)

## Inputs consumed

- Design brief `~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`
  (§Context, §User decisions, §Assessment route table, §Proposed structure,
  key design decisions, T16 entry) — authoritative.
- `handovers/server-rewrite/T13-scaffold-config.md` — `Settings`/`PluginConfig`
  API + `notes_home` fixture shape.
- `handovers/server-rewrite/T14-leaf-modules.md` — `content` (parse_date,
  make_breadcrumbs, get_prev_and_next_journal, safe_resolve), `checkbox`
  (toggle_checkbox + exception taxonomy), `search` (build_rg_args,
  parse_search_output, sort_hits).
- `handovers/server-rewrite/T15-mdrender.md` — `render_markdown` /
  `render_file` / `RenderedDoc`.
- `server.old/app.py` + `server.old/html/*` (read-only) — route behavior,
  template context vars, cookie/redirect/secret semantics.

## Tests

`server/tests/test_acceptance.py` — **26 tests**, each drives a real HTTP
request through a booted `TestClient` (10-item acceptance contract):

1. journal render + TOC + prev/next nav
2. today/yesterday aliases (fixture writes journal files for the real current
   date so aliases resolve regardless of run date)
3. legacy date redirects (`/<d>.md`, `/<m:int>/<d>.md`, `/<y>/<m>/<d>.md`) +
   `/journal/<d>.md` — asserted 3xx, `Location == /journal/<d>`, kept relative
4. `/todo` renders checkboxes, no TOC
5. PATCH `/checkbox` on-disk flip (+ 409 hash mismatch, 404 missing line,
   404 missing file)
6. dir index at `/` and `/dir/<path>` + breadcrumbs (month-name + link)
7. asset mime (image inline), `application/*` download disposition, y/m/d →
   dashed redirect
8. recipe markdown render + pygments source render (`.sql` via modeline)
9. `!!redacted` section hidden
10. POST `/search/content` rg ordering (`skipif shutil.which("rg") is None`)
    + empty-pattern 400
11. `/change-mode` cookie re-set + Referer redirect (+ default `/`), path
    traversal blocked (404), catch-all serves an arbitrary file,
    non-localhost → 403

Red confirmed first: the whole module errored (`No module named awiwi.app`)
before implementation, then green after.

Full gate (`cd server`):
- `uv run pytest` → **114 passed** (26 acceptance + 88 from T13–T15)
- `uv run ruff check .` → clean (exit 0)
- `uv run basedpyright` → **0 errors, 0 warnings** (exit 0)
- Smoke: `AWIWI_HOME=<tree> uv run uvicorn awiwi.app:app --port 5823` boots;
  `GET /todo` → 200 (also `/`, `/journal/<date>`, `/static/...` → 200).

## Divergences (assessed, flagged)

1. **Jinja autoescape OFF** (`templating.py`). Flask's default
   `select_autoescape` does *not* escape the `.j2` extension, so the legacy
   templates render `{{ content }}`/`{{ toc }}`/`beautify_if_date` as raw
   HTML. `Jinja2Templates` defaults autoescape ON, which would escape the
   rendered markdown into visible tag-soup — so it's turned off to reproduce
   shipped behavior. This is the single load-bearing "adaptation" of the
   copied templates.
2. **`/change-mode` redirects to the raw `Referer` header** (or `/`), not
   `urlparse(request.referrer)` — legacy passed a `ParseResult` object to
   Flask's `redirect()` (latent bug). Cookie is re-set to the *current*
   (client-flipped) value with `max_age=9999999999`, faithfully non-toggling.
3. **`journal_date` omitted from the non-journal template context when it's
   `None`** (non-asset files), so the footer's `{% if journal_date is
   defined %}` link doesn't fire and point at `/journal/None`. Legacy always
   passed it (defined-but-None) → broken link. Wiring adaptation, not a
   redesign.
4. **Asset downloads add `Content-Disposition: attachment; filename=...`.**
   Legacy relied on `content_type=application/octet-stream` alone; the
   explicit disposition is the acceptance contract's "download disposition".
5. **No "allow remote" config toggle.** Brief says "reject non-localhost
   (403) unless explicitly configured otherwise"; the enforcement is present
   (403 via `Host`/client loopback check) but the *override* is not wired,
   since it would require a new `Settings` field (config.py is out of
   boundary). Left for a follow-up if ever needed.
6. **Dir listings do NOT filter secret-named files.** Brief wording said
   "hide secret|credential files as legacy did", but legacy `dir_index` never
   did — only `render_non_journal` blanks secret *content* off-localhost
   (ported faithfully). Under localhost-only enforcement this path is moot.
   No dir-listing filter added (would diverge from actual legacy behavior).
7. **`login.html.j2` / `main.html.j2` not copied** (auth dropped; `main` dead).
8. **`_build_dir_index` root listing avoids the legacy double-slash** (`/dir//journal`);
   otherwise the doc-type presentation (month names, journal date entries +
   week banding, asset/recipe target rewriting) is ported branch-for-branch
   from `server.old/app.py:dir_index`.

## What T17 needs

- Pin `awiwi.app:app` in `lua/awiwi/server.lua` `default_cmd_builder`, with
  `env={AWIWI_HOME=vim.g.awiwi_home}`. Boot verified.
- `config.json` is read once at lifespan into `app.state.plugin_config`;
  `plugin_config` is loaded but not yet *consumed* by any route (link_color /
  markers / screensaver are template/render concerns not exercised by the
  copied templates). No action needed for T17 beyond entrypoint pinning +
  doc sync; note it as available-but-unused state if the KB tracks it.
- `docs/architecture.md` §Server should be refreshed to reflect: localhost
  403 (no login/session), checkclock dropped, entrypoint `awiwi.app:app`,
  the route table above.

## Status

status: done, updated 2026-07-07T18:33:37Z

## Orchestrator addendum (S16.2, 2026-07-07)

The "no allow-remote toggle" divergence above is resolved: orchestrator added
`Settings.allow_remote` (env `AWIWI_ALLOW_REMOTE`, default false) stashed on
`app.state` by the lifespan; the 403 middleware honors it. Red/green:
`test_allow_remote_env_admits_non_localhost`. Suite 115 green, ruff +
basedpyright clean. Localhost-only-unless-configured now matches the user
decision exactly.
