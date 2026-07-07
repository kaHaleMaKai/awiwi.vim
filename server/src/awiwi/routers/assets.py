"""Asset routes: date-normalizing redirect + mime-aware serving.

Ported from `server.old/app.py`'s `asset` / `asset_redirect`: the
`y/m/d` path form redirects to the canonical dashed-date form, and
`application/*` (bar sql) assets are served as downloads; everything else is
rendered by the shared `render_content_file`.
"""

from __future__ import annotations

import mimetypes
from datetime import date

from fastapi import APIRouter, Request
from fastapi.responses import RedirectResponse, Response

from awiwi.routers.pages import render_content_file
from awiwi.templating import get_home

router = APIRouter()


@router.get("/assets/{year}/{month}/{day}/{file}")
def asset_ymd_redirect(year: str, month: str, day: str, file: str) -> RedirectResponse:
    return RedirectResponse(f"/assets/{year}-{month}-{day}/{file}", status_code=302)


@router.get("/assets/{date_str}/{file}")
def asset(request: Request, date_str: str, file: str) -> Response:
    try:
        _ = date.fromisoformat(date_str)
    except ValueError as exc:
        raise FileNotFoundError(f"not a valid date: {date_str!r}") from exc
    home = get_home(request)
    path = home / "assets" / date_str.replace("-", "/") / file
    mime_type = mimetypes.guess_type(str(path))[0]

    if mime_type and "application" in mime_type and "sql" not in mime_type:
        # Downloadable binary (e.g. .pdf/.ods/.odt): force a save dialog.
        headers = {"Content-Disposition": f'attachment; filename="{file}"'}
        return Response(path.read_bytes(), media_type=mime_type, headers=headers)
    return render_content_file(request, path, home)
