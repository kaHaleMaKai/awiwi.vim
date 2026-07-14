"""JSON API routes for the future Svelte SPA, all under the `/api` prefix.

Additive: the legacy template routes (`routers/pages.py`, `routers/assets.py`,
`routers/actions.py`) are completely untouched by this module's existence --
same posture as `docs.py`/`schemas.py` (S23.1). Thin glue over the pure leaf
modules (`content.py`, `checkbox.py`, `search.py`) and the S23.1 payload
builders (`docs.py`); no domain logic reimplemented here.

Route registration order matters (see `app.py`): this router must be
included *before* `routers/pages.py` so this module's own `/{rest:path}`
catch-all (last route below) shadows `pages.py`'s app-wide catch-all for
anything under `/api/*` -- otherwise an unmatched `/api/typo` request would
fall through to the legacy catch-all and get served an HTML 404 page (or
worse, an arbitrary file whose relative path happens to start with "api/").

See `handovers/server-rewrite/T23.2-api-routes.md` for the frozen,
field-by-field SPA API contract this module implements.
"""

from __future__ import annotations

import mimetypes
import re
import subprocess
from datetime import date
from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as _pkg_version
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

from awiwi.checkbox import (
    AlreadyInStateError,
    HashMismatchError,
    LineNotFoundError,
    NotACheckboxLineError,
    toggle_checkbox,
)
from awiwi.content import safe_resolve
from awiwi.docs import build_dir_payload, build_doc_payload, build_journal_payload
from awiwi.httputil import get_home, is_localhost
from awiwi.schemas import DirPayload, DocPayload
from awiwi.schemas import SearchHit as SearchHitPayload
from awiwi.search import build_rg_args, parse_search_output, sort_hits

router = APIRouter(prefix="/api")

# Verbatim copy of routers/pages.py:_SECRET_RE / docs.py:_SECRET_RE (see
# docs.py's module docstring for why this isn't a shared import): the
# `/api/raw/...` endpoint must independently re-derive secrecy rather than
# trust a DocPayload's `is_secret` field (that field describes a *different*
# file lookup and isn't itself a security control over this route).
_SECRET_RE = re.compile(r"\b(secret|credential)s?\b$")

_VALID_SCOPES = ("journal", "assets", "recipes")


def _server_version() -> str:
    try:
        return _pkg_version("awiwi")
    except PackageNotFoundError:
        return "0.0.0"


# ---------------------------------------------------------------------------
# /api/journal/{date_str}
# ---------------------------------------------------------------------------


@router.get("/journal/{date_str}")
def api_journal(request: Request, date_str: str) -> DocPayload:
    home = get_home(request)
    try:
        doc = build_journal_payload(date_str, home, is_localhost=is_localhost(request))
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=404, detail=f"no journal entry for {date_str!r}"
        ) from exc
    if doc is None:
        raise HTTPException(status_code=404, detail=f"invalid date {date_str!r}")
    return doc


# ---------------------------------------------------------------------------
# /api/todo
# ---------------------------------------------------------------------------


@router.get("/todo")
def api_todo(request: Request) -> DocPayload:
    home = get_home(request)
    path = home / "journal" / "todos.md"
    try:
        return build_doc_payload(path, home, is_localhost=is_localhost(request))
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="todo file not found") from exc


# ---------------------------------------------------------------------------
# /api/doc/{path:path}
# ---------------------------------------------------------------------------


@router.get("/doc/{path:path}")
def api_doc(request: Request, path: str) -> DocPayload:
    home = get_home(request)
    resolved = safe_resolve(path, home)
    if resolved is None or not resolved.is_file():
        raise HTTPException(status_code=404, detail=f"no such document: {path!r}")

    localhost = is_localhost(request)
    doc = build_doc_payload(resolved, home, is_localhost=localhost)

    # Route-level defense in depth: `build_doc_payload` already blanks every
    # content-bearing field for a secret doc off-localhost -- assert that
    # contract holds here too, rather than trusting the builder silently.
    if doc.is_secret and not localhost:
        assert doc.html is None
        assert doc.toc is None
        assert doc.text is None
        assert doc.language is None
        assert doc.raw_url is None

    return doc


# ---------------------------------------------------------------------------
# /api/dir, /api/dir/{path:path}
# ---------------------------------------------------------------------------


def _dir_payload(request: Request, dirs: str) -> DirPayload:
    home = get_home(request)
    if dirs:
        resolved = safe_resolve(dirs, home)
        if resolved is None:
            raise HTTPException(status_code=404, detail=f"no such directory: {dirs!r}")
    else:
        resolved = home
    if not resolved.is_dir():
        raise HTTPException(status_code=404, detail=f"no such directory: {dirs!r}")
    return build_dir_payload(dirs, home)


@router.get("/dir")
def api_dir_root(request: Request) -> DirPayload:
    return _dir_payload(request, "")


@router.get("/dir/{path:path}")
def api_dir(request: Request, path: str) -> DirPayload:
    return _dir_payload(request, path)


# ---------------------------------------------------------------------------
# /api/meta
# ---------------------------------------------------------------------------


class MetaPayload(BaseModel):
    """Minimal app metadata for the SPA shell. Route-local response model --
    not shared with `docs.py`'s builders, so it lives here rather than in
    `schemas.py`."""

    today: str
    """Today's date, ISO (`YYYY-MM-DD`), server clock."""

    home: str
    """Display name for the notes root (`home.name`, e.g. `"notes"`) -- not
    the absolute filesystem path, which is a server-local implementation
    detail the SPA has no use for."""

    version: str
    """The `awiwi` package version (`pyproject.toml`'s `[project].version`,
    resolved via `importlib.metadata`), or `"0.0.0"` if unresolvable (e.g.
    running from an uninstalled checkout)."""


@router.get("/meta")
def api_meta(request: Request) -> MetaPayload:
    home = get_home(request)
    return MetaPayload(
        today=date.today().isoformat(), home=home.name, version=_server_version()
    )


# ---------------------------------------------------------------------------
# /api/raw/{path:path}
# ---------------------------------------------------------------------------


@router.get("/raw/{path:path}")
def api_raw(
    request: Request, path: str, download: Annotated[bool, Query()] = False
) -> Response:
    home = get_home(request)
    resolved = safe_resolve(path, home)
    if resolved is None or not resolved.is_file():
        raise HTTPException(status_code=404, detail=f"no such file: {path!r}")

    if _SECRET_RE.search(resolved.stem) and not is_localhost(request):
        raise HTTPException(status_code=403, detail="secret file, localhost only")

    stat = resolved.stat()
    etag = f'"{stat.st_mtime_ns}-{stat.st_size}"'
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})

    mime_type = mimetypes.guess_type(str(resolved))[0] or "application/octet-stream"
    headers = {"ETag": etag}
    if download:
        headers["Content-Disposition"] = f'attachment; filename="{resolved.name}"'
    return Response(resolved.read_bytes(), media_type=mime_type, headers=headers)


# ---------------------------------------------------------------------------
# PATCH /api/checkbox
# ---------------------------------------------------------------------------


class CheckboxPatchBody(BaseModel):
    """Body of a `PATCH /api/checkbox` request -- the new relpath-addressed
    protocol (vs. the legacy page-endpoint-addressed `PATCH /checkbox`,
    which stays untouched in `routers/actions.py`). Field names map onto
    `checkbox.toggle_checkbox`'s parameters: `line_no` -> `line_nr`,
    `line_hash` -> `expected_hash`, `checked` -> `check`. The MD5 line-hash
    protocol itself (`checkbox.hash_line`) is unchanged."""

    path: str
    """Home-relative POSIX relpath -- a `DocPayload.watch_path` value."""

    line_no: int
    """0-indexed line number, same numbering `checkbox.toggle_checkbox` (and
    the rendered `data-line-nr` attribute) already uses."""

    line_hash: str
    """MD5 hex digest from `checkbox.hash_line`, as already embedded in
    rendered HTML's `data-hash` attribute."""

    checked: bool


class CheckboxPatchResult(BaseModel):
    success: bool

    line_hash: str
    """Echoes the request's `line_hash` back. Toggling a checkbox never
    changes this hash -- `hash_line` strips the `[ ]`/`[x]` box before
    hashing, precisely so a client can chain further toggles without
    re-fetching. Returned anyway so callers don't have to special-case
    "the hash never changes" and can always read it off the response."""

    mtime_ns: int
    """The file's new `Path.stat().st_mtime_ns` after the toggle."""


@router.patch("/checkbox")
def api_update_checkbox(request: Request, body: CheckboxPatchBody) -> CheckboxPatchResult:
    home = get_home(request)
    target = safe_resolve(body.path, home)
    if target is None:
        raise HTTPException(status_code=404, detail=f"no such file: {body.path!r}")
    try:
        toggle_checkbox(target, body.line_no, body.checked, body.line_hash)
    except (FileNotFoundError, LineNotFoundError) as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (HashMismatchError, AlreadyInStateError, NotACheckboxLineError) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    mtime_ns = target.stat().st_mtime_ns
    return CheckboxPatchResult(success=True, line_hash=body.line_hash, mtime_ns=mtime_ns)


# ---------------------------------------------------------------------------
# GET /api/search
# ---------------------------------------------------------------------------


def _parse_scopes(scope: str | None) -> list[str] | None:
    if not scope:
        return None
    tokens = [s for s in scope.split(",") if s]
    invalid = [s for s in tokens if s not in _VALID_SCOPES]
    if invalid:
        raise HTTPException(
            status_code=422,
            detail=f"invalid scope(s) {invalid!r}, expected any of {_VALID_SCOPES}",
        )
    return tokens or None


@router.get("/search")
def api_search(
    request: Request,
    q: Annotated[str, Query(min_length=1)],
    mode: Annotated[Literal["fixed", "regex"], Query()] = "fixed",
    scope: Annotated[str | None, Query()] = None,
) -> list[SearchHitPayload]:
    home = get_home(request)
    scopes = _parse_scopes(scope)
    args = build_rg_args(q, fixed=(mode == "fixed"), scopes=scopes)
    try:
        proc = subprocess.run(
            args, cwd=str(home), capture_output=True, text=True, timeout=10, check=False
        )
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"search failed: {exc}") from exc

    # rg exit codes: 0 = matches found, 1 = no matches, 2 = usage/pattern
    # error (e.g. malformed regex) -- only the last is a real client error.
    if proc.returncode not in (0, 1):
        raise HTTPException(
            status_code=400, detail=proc.stderr.strip() or "invalid search pattern"
        )

    hits = sort_hits(parse_search_output(proc.stdout))
    return [
        SearchHitPayload(
            target=h.target, name=h.name, line=h.line, col=h.col, type=h.type, text=h.text
        )
        for h in hits
    ]


# ---------------------------------------------------------------------------
# Catch-all: any unmatched /api/* path 404s as JSON. MUST stay the last route
# registered on this router (Starlette matches routes in registration order)
# -- otherwise it would shadow the specific routes above instead of only
# catching genuine typos/unknown paths.
# ---------------------------------------------------------------------------


@router.get("/{rest:path}")
def api_not_found(rest: str) -> JSONResponse:
    return JSONResponse({"detail": f"no such API route: /api/{rest}"}, status_code=404)
