"""Action routes: checkbox toggle (PATCH), content search (POST), theme
cookie (GET).

Ported from `server.old/app.py`'s `update_checkbox` / `search_content` /
`change_mode`. The checkbox route maps the distinct `awiwi.checkbox`
exceptions onto 404/409 (instead of the legacy single catch-all); search
shells out to ripgrep here (the one impure step — `awiwi.search` only builds
the argv and parses the output); change-mode reproduces the legacy
non-toggling cookie re-set + referrer redirect exactly.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import JSONResponse, PlainTextResponse, RedirectResponse, Response
from pydantic import BaseModel

from awiwi.checkbox import (
    AlreadyInStateError,
    HashMismatchError,
    LineNotFoundError,
    NotACheckboxLineError,
    toggle_checkbox,
)
from awiwi.search import build_rg_args, parse_search_output, sort_hits
from awiwi.templating import THEME_MODE_KEY, get_home, render, theme_from_cookie

router = APIRouter()

_COOKIE_MAX_AGE = 9999999999  # legacy value (server.old/app.py:change_mode)


class CheckboxPatch(BaseModel):
    """Body of a PATCH /checkbox request (matches the legacy JSON shape)."""

    line_nr: int
    path: str
    check: bool
    hash: str


def _file_for_endpoint(endpoint: str, home: Path) -> Path | None:
    """Map a rendered page endpoint back to its source file on disk.

    Ported from `server.old/app.py:get_file_for_endpoint`.
    """
    if endpoint.startswith("/journal"):
        _, date_part = endpoint.rsplit("/", 1)
        year, month, _day = date_part.split("-")
        return home / "journal" / year / month / f"{date_part}.md"
    if endpoint.startswith("/todo"):
        return home / "journal" / "todos.md"
    return None


@router.patch("/checkbox")
def update_checkbox(request: Request, body: CheckboxPatch) -> JSONResponse:
    home = get_home(request)
    path = _file_for_endpoint(body.path, home)
    if path is None:
        return JSONResponse(
            {"success": False, "msg": f"unknown endpoint {body.path!r}"},
            status_code=404,
        )
    try:
        toggle_checkbox(path, body.line_nr, body.check, body.hash)
    except (FileNotFoundError, LineNotFoundError) as exc:
        return JSONResponse({"success": False, "msg": str(exc)}, status_code=404)
    except (HashMismatchError, AlreadyInStateError, NotACheckboxLineError) as exc:
        return JSONResponse({"success": False, "msg": str(exc)}, status_code=409)
    return JSONResponse({"success": True})


@router.post("/search/content")
def search_content(
    request: Request,
    pattern: Annotated[str, Form(alias="search-content")] = "",
) -> Response:
    if not pattern:
        return PlainTextResponse("no pattern given", status_code=400)
    home = get_home(request)
    proc = subprocess.run(
        build_rg_args(pattern),
        cwd=str(home),
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    hits = sort_hits(parse_search_output(proc.stdout))
    return render(
        request,
        "search-content.html.j2",
        {"title": "search content", "content": hits},
    )


@router.get("/change-mode")
def change_mode(request: Request) -> Response:
    """Persist the (client-flipped) theme cookie and redirect to the referrer.

    Not a server-side toggle: the JS already flipped the cookie client-side;
    the server just re-sets whatever it now is with a long max-age and bounces
    back. Ported from `server.old/app.py:change_mode`.
    """
    mode = theme_from_cookie(request)
    target = request.headers.get("referer") or "/"
    resp = RedirectResponse(target, status_code=302)
    resp.set_cookie(key=THEME_MODE_KEY, value=mode, max_age=_COOKIE_MAX_AGE)
    return resp
