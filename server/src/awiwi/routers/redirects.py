"""Legacy URL redirects + the SPA catch-all (T26 cutover).

Two jobs, in this order:

1. **Legacy 302 redirects.** The old template routes exposed a handful of
   non-canonical URL shapes (bare `<date>.md`, `<m>/<date>.md`,
   `<y>/<m>/<date>.md`, `/journal/<y>/<m>/<file>.md`, `/journal/<date>.md`,
   and the `/assets/<y>/<m>/<d>/<file>` asset form) that 302'd to the
   canonical form. Those redirects are preserved here verbatim (moved out of
   `routers/pages.py` / `routers/assets.py`, which the cutover drops) so old
   bookmarks / inbound links keep resolving to a URL the SPA router
   understands (`/journal/<date>`, `/assets/<date>/<file>`).

2. **SPA catch-all.** Any other non-`/api`, non-`/_app` GET serves the built
   `dist/index.html`. The client-side router (path-mode) then resolves the
   actual view (`/`, `/dir/*`, `/todo`, `/journal/:date`, `/assets/:d/:f`,
   `/recipes/*`, `/search`, `/*`). `index.html` is served `no-cache` so a
   rebuilt `dist/` is always picked up on the next load; the hashed
   `/_app/*` assets it references are content-addressed and long-cacheable
   (served by the StaticFiles mount in `app.py`).

Registration: this router is included AFTER `api.router` in `app.py`, so any
`/api/*` path is resolved (or JSON-404'd) by that router first and never
reaches the catch-all here. The catch-all is the LAST route on this router.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse, RedirectResponse

router = APIRouter()

# server/src/awiwi/routers/redirects.py -> parents[3] == server/
_SERVER_ROOT = Path(__file__).resolve().parents[3]
DIST_DIR = _SERVER_ROOT / "frontend" / "dist"
INDEX_HTML = DIST_DIR / "index.html"


# --- Legacy 302 redirects (canonicalize to an SPA-router-navigable URL) -----


@router.get("/assets/{year}/{month}/{day}/{file}")
def asset_ymd_redirect(year: str, month: str, day: str, file: str) -> RedirectResponse:
    return RedirectResponse(f"/assets/{year}-{month}-{day}/{file}", status_code=302)


@router.get("/assets/{year}/{month}/{day}/{_dashed}/{file}")
def asset_ymd_dashed_redirect(
    year: str, month: str, day: str, _dashed: str, file: str
) -> RedirectResponse:
    """`/assets/YYYY/MM/DD/YYYY-MM-DD/file` -- the disk-shape Y/M/D prefix
    with the redundant dashed-date segment repeated in front of the
    filename (S33.1 stakeholder feedback: this is the shape journals/other
    assets actually link with). 302s to the same canonical dashed page URL
    as the plain `/assets/YYYY/MM/DD/file` alias above, regardless of
    whether `dashed` agrees with `year`/`month`/`day` -- the SPA page route
    only understands the canonical `/assets/{date}/{file}` shape, so there
    is no useful "pass through unchanged" fallback at this layer (unlike
    `content.normalize_asset_path`, which has a real disk path to fall back
    to and must not paper over a genuine mismatch)."""
    return RedirectResponse(f"/assets/{year}-{month}-{day}/{file}", status_code=302)


@router.get("/journal/{year}/{month}/{file}")
def journal_full_path_redirect(file: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{file.replace('.md', '')}", status_code=302)


@router.get("/journal/{date_str}.md")
def journal_md_suffix_redirect(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


@router.get("/{date_str}.md")
def redirect_bare_date(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


@router.get("/{month:int}/{date_str}.md")
def redirect_month_date(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


@router.get("/{year:int}/{month:int}/{date_str}.md")
def redirect_year_month_date(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


# --- SPA catch-all (MUST be the last route registered on this router) -------


@router.get("/{path:path}")
def spa_fallback(path: str) -> FileResponse:
    """Serve the SPA shell for any non-/api, non-/_app GET.

    `no-cache` (not `no-store`): the browser may keep the file but must
    revalidate before reuse, so a rebuilt `dist/index.html` is picked up
    immediately while the hashed `/_app/*` assets it points at stay
    long-cacheable.
    """
    _ = path
    return FileResponse(
        INDEX_HTML, media_type="text/html", headers={"Cache-Control": "no-cache"}
    )
