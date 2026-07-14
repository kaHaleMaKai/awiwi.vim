# server-rewrite / T26 (S26.1) — cutover: SPA live, legacy template routes dropped

## Responsibility

The riskiest step of the server re-imagining: retire the Jinja template
pages and serve the committed Svelte SPA from FastAPI instead. After this
unit the app is a **JSON API (`/api/*`) + a single-page app**. No Node runs
at serve time — the build is committed to git.

Written for zero context. Boundary touched (exactly): `server/src/awiwi/app.py`,
`server/src/awiwi/routers/` (new `redirects.py`, dropped registration of
`pages`/`assets`/`actions`, updated `__init__.py`), `server/frontend/dist/`
(committed build), `server/tests/test_acceptance.py` (rewritten),
`docs/architecture.md` (§Server route table, minimal honest update — T27's
kb-curator does the full §Server rewrite).

## What routes exist now

Registration order in `create_app()`: `/_app` StaticFiles mount → `api.router`
→ `redirects.router`. Starlette matches in registration order.

| Method | Path | Behavior |
|---|---|---|
| mount | `/_app` | `StaticFiles` over `frontend/dist` — the hashed SPA assets. Long-cacheable. |
| GET | `/api/*` | JSON API (`routers/api.py`, unchanged, frozen contract in `T23.2-api-routes.md`). Its own `/api/{rest:path}` is a JSON-404 catch-all for unknown `/api/*` GETs. |
| GET (302) | `/assets/{y}/{m}/{d}/{file}` | → `/assets/{y}-{m}-{d}/{file}` |
| GET (302) | `/journal/{y}/{m}/{file}` | → `/journal/{file-sans-.md}` |
| GET (302) | `/journal/{date_str}.md` | → `/journal/{date_str}` |
| GET (302) | `/{d}.md`, `/{m:int}/{d}.md`, `/{y:int}/{m:int}/{d}.md` | → `/journal/{d}` |
| GET | `/{path:path}` | **SPA catch-all, LAST**: serves `frontend/dist/index.html` `no-cache`. |
| exc | `FileNotFoundError` | → JSON `{"detail":"not found"}` 404 |

The SPA's own client router (path-mode) then resolves `/`, `/dir/*`, `/todo`,
`/journal/:date`, `/assets/:date/:file`, `/recipes/*`, `/search`, `/*`. Every
one of those URLs is served the same `index.html` shell.

## Mount layout / dist

- `frontend/dist/` is the committed Vite build (`base: '/_app/'`). Built with
  `cd server/frontend && npm run build`. **Reproducible**: two consecutive
  builds produce byte-identical file trees (verified by aggregate sha256).
- `dist/index.html` references `/_app/assets/index-*.{js,css}` and
  `/_app/favicon.svg` — all served by the `/_app` StaticFiles mount.
- `index.html` itself is served by the SPA catch-all (not the mount) with
  `Cache-Control: no-cache` so a rebuilt dist is picked up on next load; the
  hashed `/_app/*` assets are content-addressed and can be long-cached.
- Path resolution is cwd-independent: `redirects.DIST_DIR =
  Path(__file__).resolve().parents[3] / "frontend" / "dist"` (parents[3] ==
  `server/`), so `:Awiwi serve` (cwd `server/`, `uv run uvicorn awiwi.app:app`)
  and the test client both resolve the same dist.
- **dist is force-added** (`git add -f`): `server/frontend/.gitignore` still
  ignores `dist` (kept from T25.1's dev-time convention). It is now *tracked*;
  future rebuilds show as normal diffs. New files added to dist in a later
  build need another `git add -f` (a wart of not un-ignoring; the committed-
  dist policy tolerates it). `.gitattributes` marks `frontend/dist/**`
  `linguist-generated -diff` — rebuild, never merge-resolve.

## Redirect table (why each survives)

All 302, all Location kept root-relative:

- `/assets/{y}/{m}/{d}/{file}` → `/assets/{y}-{m}-{d}/{file}` — the SPA asset
  route is `/assets/:date/:file` (dashed, 2 segments); the ymd form is 4
  segments and would otherwise hit the SPA catch-all as a bogus route.
- `/journal/{y}/{m}/{file}` → `/journal/{file-sans-.md}` — SPA `/journal/:date`
  is single-segment; the 3-segment legacy form needs canonicalizing.
- `/journal/{date_str}.md` → `/journal/{date_str}` — a `.md` suffix on the
  dashed form would make the SPA read the date as `2026-07-01.md`. (This was
  an in-handler strip inside the old `/journal/{date_str}` route; extracted to
  its own route here so the non-`.md` form falls straight through to the SPA.)
- `/{d}.md`, `/{m:int}/{d}.md`, `/{y:int}/{m:int}/{d}.md` → `/journal/{d}` —
  legacy bare-date URLs; no SPA route matches them.

These are the exact set that lived in the old `pages.py`/`assets.py`. The old
`/journal/{date_str}` render route, `/todo`, `/dir`, `/recipes/*`, the
catch-all file server, and all of `actions.py` (`/checkbox`, `/search/content`,
`/change-mode`) are **gone** — their data equivalents live under `/api/*`.

## What T27 may delete

Confirmed dead after this cutover (nothing imports/registers them):

- `server/src/awiwi/routers/pages.py`, `assets.py`, `actions.py` — no longer
  imported by `routers/__init__.py` or `app.py`. (`assets.py` still imports
  `render_content_file` from `pages.py`, so delete them together.)
- `server/templates/` (all 7 Jinja files) — no route renders a template.
- `server/static/` — the `/static` mount is gone.
- `server/src/awiwi/templating.py` — `render`/`STATIC_DIR`/`theme_from_cookie`
  no longer imported by `app.py`. **Note:** `httputil.py` still re-exports
  nothing *from* templating; but `templating.py` re-exports `get_home`/
  `is_localhost` *from* `httputil` as a back-compat shim. After the cutover
  `app.py` imports those straight from `awiwi.httputil`; grep before deleting
  templating to confirm no remaining `from awiwi.templating import` callers
  (as of T26 there are none in `src/`).
- `jinja2`, `pygments`, `python-multipart` deps (per plan S27.1).
- `server.old/`.

Also for T27's KB pass: `docs/architecture.md` §Server still describes the
render pipeline (`mdrender.render_file` Pygments path, `docs.py` "duplication
dies at cutover") in terms that are now stale — this unit only refreshed the
route table + router bullets, not the full module map. ADRs D18+ pending
(SPA-over-JSON, committed-dist, no-sanitization, client-side Shiki/drawio).

## Serve-smoke evidence

Launch shape (exact plugin shape): `cd server && AWIWI_HOME=<home> uv run
uvicorn awiwi.app:app --port 5824`, fixture = one journal file
`journal/2026/07/2026-07-14.md` + a png asset + config.json.

```
GET /                              200  text/html; charset=utf-8   cache-control: no-cache   body has id="app"
GET /_app/favicon.svg             200  image/svg+xml
GET /api/journal/2026-07-14       200  application/json            {"kind":"markdown","doc_type":"journal",...}
GET /api/nope                     404  application/json            {"detail":"no such API route: /api/nope"}
GET /2026-07-14.md                302  location: /journal/2026-07-14
GET /journal/2026/07/2026-07-14.md 302 location: /journal/2026-07-14
```

## Tests / Gates

- `server/tests/test_acceptance.py` fully rewritten (30 tests): page-HTML
  assertions → `/api/*` JSON payload assertions; surviving redirects asserted
  (5 date forms + asset ymd); checkbox via relpath `PATCH /api/checkbox`
  protocol (`{path,line_no,line_hash,checked}` → `{success,line_hash,
  mtime_ns}`); SPA-fallback tests (`GET /journal/2024-01-01` → 200 text/html
  `id="app"` no-cache; `GET /` → 200 html; `GET /_app/favicon.svg` → 200;
  `GET /api/nope` → 404 JSON); ETag/304 round-trip on `/api/raw`; theme-cookie
  tests deleted. Redaction: on localhost `/api/journal` **embeds** the redacted
  block obscured (`class="redacted"`, click-revealable) rather than stripping
  it — asserted accordingly (do not assert absence of the secret text).
- `cd server && uv run pytest` → **234 passed**.
- `uv run ruff check .` → clean. `uv run basedpyright` → 0 errors/warnings/notes.
- `cd server/frontend && npx vitest run` → **110 passed**. `npm run build` →
  success (pre-existing >500 kB chunk-size warning only; build reproducible).

## Deviations

1. **`FileNotFoundError` handler now returns JSON**, not `404.html`. The
   `/api/*` routes already catch their own `FileNotFoundError` internally, and
   with `pages`/`assets` dropped nothing else raises it to the app — so the
   handler is effectively dead, but kept as a JSON safety net (the app is now
   API+SPA; an HTML 404 template would be wrong, and rendering it would keep an
   otherwise-severed `templating` dependency in `app.py`). No test triggers it.
2. **dist force-added, `.gitignore` left as-is** (see Mount layout / dist) —
   `.gitignore` was out of boundary; documented the force-add wart instead of
   editing it.
3. **`/journal/{date_str}.md` is its own redirect route**, where the legacy
   code did the `.md`-strip inside the single `/journal/{date_str}` render
   route. Necessary because that render route no longer exists (the SPA serves
   `/journal/:date`); a dedicated `.md`-suffix route redirects while the
   bare form falls through to the SPA catch-all.

## Status

status: done, updated 2026-07-14
commit: T26: cutover — SPA live, legacy template routes dropped
