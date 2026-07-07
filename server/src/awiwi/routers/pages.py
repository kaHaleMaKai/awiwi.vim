"""Page routes: directory index, journal, todo, recipes, legacy redirects,
and the catch-all file server (registered LAST).

Thin glue over `awiwi.content` (path/date logic) and `awiwi.mdrender`
(rendering). Ported and *assessed* from `server.old/app.py`; the route order
in this module is load-bearing — the `/{path:path}` catch-all must stay the
final route so specific routes win.
"""

from __future__ import annotations

import calendar
import mimetypes
import re
from datetime import date
from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import PlainTextResponse, RedirectResponse, Response

from awiwi.content import (
    get_prev_and_next_journal,
    make_breadcrumbs,
    parse_date,
    safe_resolve,
)
from awiwi.mdrender import render_file, render_markdown
from awiwi.templating import get_home, is_localhost, render

router = APIRouter()

# server.old/app.py:render_non_journal — filename stem ending in secret(s)/
# credential(s).
_SECRET_RE = re.compile(r"\b(secret|credential)s?\b$")


def render_content_file(request: Request, file: Path, home: Path) -> Response:
    """Render a single content file, dispatching on extension/mime type.

    Ported from `server.old/app.py:render_non_journal`: markdown -> full
    render, `.drawio` -> raw xml, images -> inline bytes, extension-less ->
    raw text, everything else -> pygments source render (falling back to raw
    text). Secret-named files blank their body off-localhost.
    """
    is_secret = bool(_SECRET_RE.search(file.stem))
    assets_root = home / "assets"
    journal_date: str | None = None
    if file.is_relative_to(assets_root):
        journal_date = "-".join(file.parent.relative_to(assets_root).parts)
    breadcrumbs = make_breadcrumbs(file, home)
    local = is_localhost(request)

    base_ctx: dict[str, object] = {
        "breadcrumbs": breadcrumbs,
        "title": file.stem,
        "is_secret": is_secret,
        "is_localhost": local,
        "highlight_article": is_secret,
    }
    # Only surface journal_date when it's a real asset date, so the
    # non-journal template's `{% if journal_date is defined %}` footer link
    # doesn't fire (and point at /journal/None) for ordinary files.
    if journal_date is not None:
        base_ctx["journal_date"] = journal_date

    if is_secret and not local:
        return render(
            request,
            "non-journal.html.j2",
            {**base_ctx, "content": "", "toc": ""},
        )

    ext = file.suffix
    mime_type = mimetypes.guess_type(str(file))[0]

    if not ext:
        return PlainTextResponse(file.read_text())
    if ext == ".md":
        doc = render_markdown(file.read_text(), title=file.stem)
        return render(
            request,
            "non-journal.html.j2",
            {**base_ctx, "content": doc.html, "toc": doc.toc},
        )
    if ext == ".drawio":
        return Response(file.read_text(), media_type="application/vnd.jgraph.mxfile")
    if mime_type and mime_type.startswith("image"):
        return Response(file.read_bytes(), media_type=mime_type)

    doc = render_file(file.read_text(), filename=file)
    return render(
        request,
        "non-journal.html.j2",
        {**base_ctx, "content": doc.html, "toc": doc.toc},
    )


def _build_dir_index(dirs: str, home: Path) -> tuple[list[object], list[dict[str, object]]]:
    """Build (breadcrumbs, entries) for a directory listing.

    Ported from `server.old/app.py:dir_index` — the doc-type-aware
    presentation glue (month names, journal date entries + week banding,
    asset/recipe target rewriting) that `content.list_directory` deliberately
    left out. `entries[i]["name"]` may be a `datetime.date` (rendered by the
    `beautify_if_date` filter) or a plain string.
    """
    dirs = dirs.strip("/")
    splits = dirs.split("/") if dirs else [""]
    type_ = splits[0]
    path = home / type_ if type_ else home
    if len(splits) > 1:
        path = path.joinpath(*splits[1:])

    entries: list[dict[str, object]] = []
    first_week: int | None = None
    for name in sorted(p.name for p in path.iterdir()):
        if name.startswith("."):
            continue
        entry: dict[str, object] = {}
        child = path / name
        if child.is_dir():
            entry["target"] = f"/dir/{dirs}/{name}" if dirs else f"/dir/{name}"
            if type_ in ("journal", "assets"):
                if len(splits) <= 1:
                    entry["name"] = name
                elif len(splits) == 2:
                    entry["name"] = calendar.month_name[int(name)]
                else:
                    d = date.fromisoformat("-".join([*splits[-2:], name]))
                    entry["name"] = d
                    week = int(d.strftime("%W"))
                    first_week = week if first_week is None else first_week
                    entry["class"] = f"week{week - first_week}"
            else:
                entry["name"] = name
        elif name == "todos.md":
            entry["name"] = "todo"
            entry["target"] = "/todo"
        elif type_ == "journal":
            basename = name.replace(".md", "")
            d = date.fromisoformat(basename)
            entry["name"] = d
            entry["target"] = f"/journal/{basename}"
            week = int(d.strftime("%W"))
            first_week = week if first_week is None else first_week
            entry["class"] = f"week{week - first_week}"
        elif type_ == "assets":
            _, year, month, day = dirs.split("/")
            entry["name"] = name
            entry["target"] = f"/assets/{year}-{month}-{day}/{name}"
        elif type_ == "recipes":
            parts = list(dirs.split("/", 1)[1:])
            parts.append(name)
            entry["target"] = f"/recipes/{'/'.join(parts)}"
            entry["name"] = name
        else:
            continue
        entries.append(entry)

    breadcrumbs = make_breadcrumbs(path, home, include_cur_dir=True)
    return list(breadcrumbs), entries


@router.get("/")
def index(request: Request) -> Response:
    home = get_home(request)
    breadcrumbs, entries = _build_dir_index("", home)
    return render(request, "dir.html.j2", {"breadcrumbs": breadcrumbs, "entries": entries})


@router.get("/dir/{dirs:path}")
def dir_listing(request: Request, dirs: str) -> Response:
    home = get_home(request)
    breadcrumbs, entries = _build_dir_index(dirs, home)
    return render(request, "dir.html.j2", {"breadcrumbs": breadcrumbs, "entries": entries})


@router.get("/todo")
def todo(request: Request) -> Response:
    home = get_home(request)
    file = home / "journal" / "todos.md"
    doc = render_markdown(file.read_text(), title="TODO", add_toc=False)
    breadcrumbs = make_breadcrumbs(file, home)
    return render(
        request,
        "todo.html.j2",
        {"content": doc.html, "title": "TODO", "breadcrumbs": breadcrumbs},
    )


@router.get("/journal/{year}/{month}/{file}")
def journal_full_path_redirect(file: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{file.replace('.md', '')}", status_code=302)


@router.get("/journal/{date_str}")
def journal(request: Request, date_str: str) -> Response:
    if date_str.endswith(".md"):
        return RedirectResponse(f"/journal/{date_str[:-3]}", status_code=302)
    home = get_home(request)
    parsed = parse_date(date_str, home)
    if parsed is None:
        raise FileNotFoundError(f"no journal entry for {date_str!r}")
    iso = parsed.isoformat()
    year, month, _ = iso.split("-")
    file = home / "journal" / year / month / f"{iso}.md"
    doc = render_markdown(file.read_text())
    prev, next_ = get_prev_and_next_journal(parsed, home)
    breadcrumbs = make_breadcrumbs(file, home)
    return render(
        request,
        "journal.html.j2",
        {
            "content": doc.html,
            "toc": doc.toc,
            "title": doc.title if doc.title else iso,
            "prev": prev,
            "next": next_,
            "breadcrumbs": breadcrumbs,
            "is_localhost": is_localhost(request),
        },
    )


@router.get("/{date_str}.md")
def redirect_bare_date(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


@router.get("/{month:int}/{date_str}.md")
def redirect_month_date(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


@router.get("/{year:int}/{month:int}/{date_str}.md")
def redirect_year_month_date(date_str: str) -> RedirectResponse:
    return RedirectResponse(f"/journal/{date_str}", status_code=302)


@router.get("/recipes/{path:path}")
def recipe(request: Request, path: str) -> Response:
    home = get_home(request)
    return render_content_file(request, home / "recipes" / path, home)


@router.get("/{path:path}")
def serve_file(request: Request, path: str) -> Response:
    """Catch-all: serve any file under home as a raw relative path.

    Registered LAST so every specific route above wins. `safe_resolve`
    confines resolution under home, turning `..`/absolute escapes into a 404.
    """
    home = get_home(request)
    resolved = safe_resolve(path, home)
    if resolved is None or not resolved.is_file():
        raise FileNotFoundError(path)
    return render_content_file(request, resolved, home)
