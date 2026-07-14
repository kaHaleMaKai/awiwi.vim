"""Payload builders for the JSON API layer: `DocPayload`/`DirPayload`
construction over the pure leaf modules (`content.py`, `mdrender.py`), for a
future `/api/*` router (S23.2) to expose.

**Boundary note on "moved, not rewritten":** the design contract for this
subtask asked for `render_content_file`'s and `_build_dir_index`'s logic to
be *extracted* out of `routers/pages.py` so both the old template route and
these new builders share one implementation. This subtask's hard boundary
only permits touching `routers/pages.py` to import relocated helpers
(`is_localhost`/`get_home`, now in `httputil.py`) -- not to restructure its
private functions -- and requires the old routes to stay behaviorally
untouched. Given that conflict, the boundary wins: the dispatch logic below
is a faithful, independently-verified re-implementation (same regex, same
field derivations, same call sequence into `content`/`mdrender`) rather than
a shared helper. `test_api.py` cross-checks several of these builders
against `test_acceptance.py`'s fixture tree and expectations so drift would
show up as a test failure. See the T23.1 handover for the exact
correspondence table and a note for whoever owns the eventual real
extraction (flagged for a later cleanup subtask, not blocking here).
"""

from __future__ import annotations

import calendar
import mimetypes
import re
from datetime import date
from pathlib import Path

from awiwi.content import get_prev_and_next_journal, make_breadcrumbs, parse_date
from awiwi.mdrender import guess_language, render_markdown
from awiwi.schemas import (
    BreadcrumbPayload,
    DirEntry,
    DirPayload,
    DocKind,
    DocPayload,
    DocType,
    NavPayload,
)

# Verbatim copy of routers/pages.py:_SECRET_RE (see module docstring for why
# this isn't a shared import): server.old/app.py:render_non_journal's
# filename-stem-in-secret(s)/credential(s) gate.
_SECRET_RE = re.compile(r"\b(secret|credential)s?\b$")


def _doc_type(path: Path, home: Path) -> DocType:
    """Classify `path` by its top-level directory under `home`, per
    `CLAUDE.md`'s doc-type hierarchy."""
    try:
        rel_parts = path.relative_to(home).parts
    except ValueError:
        return "other"
    if not rel_parts:
        return "other"
    top = rel_parts[0]
    if top == "journal":
        return "journal"
    if top == "assets":
        return "asset"
    if top == "recipes":
        return "recipe"
    return "other"


def _breadcrumbs(
    path: Path, home: Path, *, include_cur_dir: bool = False
) -> list[BreadcrumbPayload]:
    return [
        BreadcrumbPayload(name=b.name, target=b.target)
        for b in make_breadcrumbs(path, home, include_cur_dir=include_cur_dir)
    ]


def _journal_nav_for(path: Path, doc_type: DocType, home: Path) -> NavPayload | None:
    """`nav` for `build_doc_payload`: only for journal-type docs whose stem
    parses as an ISO date (a real `journal/YYYY/MM/YYYY-MM-DD.md` day file,
    as opposed to e.g. `journal/todos.md`)."""
    if doc_type != "journal":
        return None
    try:
        day = date.fromisoformat(path.stem)
    except ValueError:
        return None
    prev, next_ = get_prev_and_next_journal(day, home)
    return NavPayload(prev=prev, next=next_)


def _blanked(
    *,
    kind: DocKind,
    doc_type: DocType,
    watch_path: str,
    breadcrumbs: list[BreadcrumbPayload],
    journal_date: str | None,
    nav: NavPayload | None,
    mtime_ns: int,
) -> DocPayload:
    """The secret-gate outcome: every content-bearing field blanked. Not
    just `html`/`text` (the design contract's literal wording) but also
    `raw_url` -- an un-blanked `raw_url` would hand the SPA a working link
    to the secret bytes despite `is_secret=True`, defeating the point ("the
    SPA is not a trust boundary"). Whatever eventually serves `raw_url`
    (S23.2's `/api/raw/...`) must independently re-check secrecy anyway
    (this payload is not itself a security control over that endpoint), but
    there's no reason to hand out the URL here regardless."""
    return DocPayload(
        kind=kind,
        doc_type=doc_type,
        html=None,
        toc=None,
        text=None,
        language=None,
        raw_url=None,
        watch_path=watch_path,
        breadcrumbs=breadcrumbs,
        journal_date=journal_date,
        nav=nav,
        mtime_ns=mtime_ns,
        is_secret=True,
    )


def build_doc_payload(path: Path, home: Path, *, is_localhost: bool) -> DocPayload:
    """Build a `DocPayload` for an arbitrary file under `home`.

    Dispatch mirrors `routers/pages.py:render_content_file` (kind by
    extension/mime, then content by kind), extended with a `doc_type`
    classification and `nav`/`journal_date` derivation `render_content_file`
    doesn't need (its Jinja context computes those separately per-route).
    See the T23.1 handover for the exact kind-dispatch table.

    Raises `FileNotFoundError` (propagated from the underlying `Path.read_*`
    calls) if `path` doesn't exist -- same as the legacy route's implicit
    contract (caught by the app's `FileNotFoundError` -> 404 handler; a
    future JSON router does the equivalent).
    """
    is_secret = bool(_SECRET_RE.search(path.stem))
    doc_type = _doc_type(path, home)

    assets_root = home / "assets"
    journal_date: str | None = None
    if path.is_relative_to(assets_root):
        journal_date = "-".join(path.parent.relative_to(assets_root).parts)

    breadcrumbs = _breadcrumbs(path, home)
    nav = _journal_nav_for(path, doc_type, home)
    watch_path = path.relative_to(home).as_posix()
    mtime_ns = path.stat().st_mtime_ns

    ext = path.suffix
    mime_type = mimetypes.guess_type(str(path))[0]

    kind: DocKind
    raw_text: str | None = None
    if ext == ".md":
        kind = "markdown"
    elif mime_type and mime_type.startswith("image"):
        kind = "image"
    elif ext == ".drawio":
        kind = "drawio"
    else:
        try:
            raw_text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            kind = "binary"
        else:
            kind = "text"

    if is_secret and not is_localhost:
        return _blanked(
            kind=kind,
            doc_type=doc_type,
            watch_path=watch_path,
            breadcrumbs=breadcrumbs,
            journal_date=journal_date,
            nav=nav,
            mtime_ns=mtime_ns,
        )

    html: str | None = None
    toc: str | None = None
    text: str | None = None
    language: str | None = None
    raw_url: str | None = None

    if kind == "markdown":
        doc = render_markdown(path.read_text(), title=path.stem)
        html = doc.html
        toc = doc.toc or None
    elif kind == "drawio":
        text = path.read_text()
    elif kind == "image":
        raw_url = f"/api/raw/{watch_path}"
    elif kind == "text":
        text = raw_text
        language = guess_language(path, text=raw_text)
    else:  # binary
        raw_url = f"/api/raw/{watch_path}"

    return DocPayload(
        kind=kind,
        doc_type=doc_type,
        html=html,
        toc=toc,
        text=text,
        language=language,
        raw_url=raw_url,
        watch_path=watch_path,
        breadcrumbs=breadcrumbs,
        journal_date=journal_date,
        nav=nav,
        mtime_ns=mtime_ns,
        is_secret=is_secret,
    )


def build_journal_payload(
    date_str: str, home: Path, *, is_localhost: bool, today: date | None = None
) -> DocPayload | None:
    """Build a `DocPayload` for a journal day page (the JSON equivalent of
    `routers/pages.py:journal`'s `/journal/{date_str}` route).

    `date_str` goes through `content.parse_date` (so `today`/`yesterday`/
    `prev`/`previous` aliases and plain ISO dates all resolve the same way
    the template route does); `today` is exposed for deterministic tests,
    mirroring `parse_date`'s own parameter.

    Unlike `build_doc_payload` (which passes `title=path.stem` when
    rendering markdown, matching `render_content_file`'s behavior of
    keeping a leading H1 in the body), this mirrors the `journal` route
    exactly: `render_markdown(text)` with no title override, so a leading
    `# YYYY-MM-DD` H1 is extracted as the title and excluded from `html`
    (see `mdrender._extract_title`). This is a real, deliberate behavioral
    difference between the two builders, not an oversight -- both are
    "moved, not rewritten" faithfully from their respective legacy call
    sites.

    Returns `None` when `date_str` doesn't parse (including an exhausted
    `prev`/`previous` alias with no earlier journal entry) -- a future
    router maps that to 404, matching `parse_date`'s existing contract.
    Raises `FileNotFoundError` if the parsed date is well-formed but no
    journal file exists for it (same propagation as the `journal` route).
    """
    parsed = parse_date(date_str, home, today=today)
    if parsed is None:
        return None

    iso = parsed.isoformat()
    year, month, _day = iso.split("-")
    file = home / "journal" / year / month / f"{iso}.md"

    is_secret = bool(_SECRET_RE.search(file.stem))
    breadcrumbs = _breadcrumbs(file, home)
    prev, next_ = get_prev_and_next_journal(parsed, home)
    nav = NavPayload(prev=prev, next=next_)
    watch_path = file.relative_to(home).as_posix()
    mtime_ns = file.stat().st_mtime_ns

    if is_secret and not is_localhost:
        return _blanked(
            kind="markdown",
            doc_type="journal",
            watch_path=watch_path,
            breadcrumbs=breadcrumbs,
            journal_date=None,
            nav=nav,
            mtime_ns=mtime_ns,
        )

    doc = render_markdown(file.read_text())
    return DocPayload(
        kind="markdown",
        doc_type="journal",
        html=doc.html,
        toc=doc.toc or None,
        text=None,
        language=None,
        raw_url=None,
        watch_path=watch_path,
        breadcrumbs=breadcrumbs,
        journal_date=None,
        nav=nav,
        mtime_ns=mtime_ns,
        is_secret=is_secret,
    )


def build_dir_payload(dirs: str, home: Path) -> DirPayload:
    """Build a `DirPayload` for a directory listing (the JSON equivalent of
    `routers/pages.py:index`/`dir_listing`, i.e. `_build_dir_index`).

    `dirs` is the same `{dirs:path}` shape the `/dir/{dirs:path}` route
    parses (empty string for the home root). Mirrors `_build_dir_index`'s
    doc-type-aware entry naming (month names, journal/asset date entries,
    recipe path segments) exactly, except each entry reports a home-relative
    `relpath` instead of a template `href`/target, dates are ISO strings
    instead of `datetime.date` objects, and the decorative week-banding CSS
    class is dropped (presentation-only, no SPA equivalent needed).
    """
    dirs = dirs.strip("/")
    splits = dirs.split("/") if dirs else [""]
    type_ = splits[0]
    path = home / type_ if type_ else home
    if len(splits) > 1:
        path = path.joinpath(*splits[1:])

    if type_ == "journal":
        doc_type: DocType = "journal"
    elif type_ == "assets":
        doc_type = "asset"
    elif type_ == "recipes":
        doc_type = "recipe"
    else:
        doc_type = "other"

    entries: list[DirEntry] = []
    for name in sorted(p.name for p in path.iterdir()):
        if name.startswith("."):
            continue
        child = path / name
        relpath = child.relative_to(home).as_posix()

        if child.is_dir():
            if type_ in ("journal", "assets"):
                if len(splits) <= 1:
                    display = name
                elif len(splits) == 2:
                    display = calendar.month_name[int(name)]
                else:
                    d = date.fromisoformat("-".join([*splits[-2:], name]))
                    display = d.isoformat()
            else:
                display = name
            entries.append(
                DirEntry(name=display, relpath=relpath, is_dir=True, doc_type=doc_type)
            )
        elif name == "todos.md":
            entries.append(
                DirEntry(name="todo", relpath=relpath, is_dir=False, doc_type="journal")
            )
        elif type_ == "journal":
            basename = name.replace(".md", "")
            d = date.fromisoformat(basename)
            entries.append(
                DirEntry(
                    name=d.isoformat(), relpath=relpath, is_dir=False, doc_type="journal"
                )
            )
        elif type_ == "assets":
            entries.append(
                DirEntry(name=name, relpath=relpath, is_dir=False, doc_type="asset")
            )
        elif type_ == "recipes":
            entries.append(
                DirEntry(name=name, relpath=relpath, is_dir=False, doc_type="recipe")
            )
        else:
            continue

    breadcrumbs = _breadcrumbs(path, home, include_cur_dir=True)
    return DirPayload(breadcrumbs=breadcrumbs, entries=entries)
