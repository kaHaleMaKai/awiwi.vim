"""Pydantic response models for the JSON API layer (the Svelte SPA).

Originally additive: nothing here was imported by the legacy template
routers (`routers/pages.py`, `routers/assets.py`, `routers/actions.py`,
deleted in T27), so the old Jinja page routes and their tests stayed
untouched by this module's existence at the time.

`docs.py`'s payload builders (`build_doc_payload`, `build_dir_payload`,
`build_journal_payload`) are the only producers of these models, exposed as
`/api/*` endpoints by `routers/api.py`.

Kept intentionally minimal: these models mirror exactly what the former
page routes used to compute (see `docs.py`'s docstrings for the byte-for-byte
correspondence), not a speculative superset.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel

DocKind = Literal["markdown", "text", "image", "drawio", "binary"]
"""How a doc's *content* should be presented -- drives which of
`DocPayload.html`/`text`/`raw_url` is populated. Mirrors the dispatch the
former `routers/pages.py:render_content_file` used to perform on
extension/mime type (see `docs.py:build_doc_payload`'s kind-dispatch
table)."""

DocType = Literal["journal", "asset", "recipe", "other"]
"""Which doc-type hierarchy (see `CLAUDE.md` §Doc types) a path belongs to,
derived from its top-level directory under `home` (`journal/`, `assets/`,
`recipes/`; anything else is `other`)."""


class BreadcrumbPayload(BaseModel):
    """One `/dir/...`-style trail entry. Mirrors `content.Breadcrumb`
    (`name`/`target`) field-for-field -- a JSON-serializable copy, not a
    redesign (`content.Breadcrumb` is a plain dataclass, not a pydantic
    model, and stays that way; it's a pure leaf-module type outside this
    subtask's boundary)."""

    name: str
    target: str


class NavPayload(BaseModel):
    """Prev/next journal-day ISO date strings, mirroring
    `content.get_prev_and_next_journal`'s `(prev, next)` return shape.
    Either may be `None` (no earlier/later journal entry exists)."""

    prev: str | None
    next: str | None


class DocPayload(BaseModel):
    """A single rendered/described document, for a future `GET /api/doc/...`
    (or similar) endpoint. See `docs.py:build_doc_payload` /
    `build_journal_payload` for the exact construction rules and
    `handovers/server-rewrite/T23.1-payload-builders.md` for the kind
    dispatch table and secret-gate behavior.
    """

    kind: DocKind
    doc_type: DocType

    html: str | None
    """Server-rendered markdown body (`kind == "markdown"` only)."""

    toc: str | None
    """The `markdown` `TocExtension`'s rendered TOC block (same string
    `mdrender.RenderedDoc.toc` produces), or `None` when empty/not
    applicable. `kind == "markdown"` only."""

    text: str | None
    """Raw text for `kind == "text"`, or the raw XML for `kind == "drawio"`.
    `None` for every other kind."""

    language: str | None
    """Best-effort Shiki-style language id (`mdrender.guess_language`),
    `kind == "text"` only. `None` is a valid, expected outcome (no language
    guessed) -- the frontend sniffs too."""

    raw_url: str | None
    """`/api/raw/{watch_path}` for `kind in ("image", "binary")`; `None`
    otherwise. The literal route this resolves to is a future S23.2 concern
    -- this module only builds the URL string."""

    watch_path: str
    """Home-relative POSIX relpath of the underlying file. This is both the
    future websocket subscription key and the future checkbox-PATCH `path`
    field -- stable identity for "this document", independent of whichever
    URL was used to fetch it."""

    breadcrumbs: list[BreadcrumbPayload]

    journal_date: str | None
    """For assets only: the ISO date of the owning journal day (enables a
    "back to journal" link). `None` for every other doc_type."""

    nav: NavPayload | None
    """Prev/next journal-day navigation, journal pages only (a journal-type
    doc whose stem parses as an ISO date). `None` otherwise."""

    mtime_ns: int
    """`Path.stat().st_mtime_ns` of the underlying file at build time."""

    is_secret: bool
    """Whether the doc's filename stem matches the secret/credential regex.
    When `True` and the request isn't from localhost, `html`/`toc`/`text`/
    `language`/`raw_url` are all blanked to `None` -- see the T23.1 handover
    for the exact gate."""


class DirEntry(BaseModel):
    """One entry in a directory listing. Mirrors the former
    `routers/pages.py:_build_dir_index`'s per-entry doc-type-aware naming
    (month names, journal/asset date entries, recipe path segments), but
    reports a home-relative `relpath` instead of a template `href`, and
    normalizes date entries to ISO strings instead of `datetime.date`
    objects (no server-side `beautify_if_date` dependency -- the frontend
    formats/labels them). Decorative week-banding (`entry["class"]` in the
    legacy dict) is presentation-only and intentionally dropped."""

    name: str
    relpath: str
    is_dir: bool
    doc_type: DocType


class DirPayload(BaseModel):
    """A directory listing: breadcrumbs + entries, for a future
    `GET /api/dir/...` endpoint. See `docs.py:build_dir_payload`."""

    breadcrumbs: list[BreadcrumbPayload]
    entries: list[DirEntry]


class SearchHit(BaseModel):
    """One parsed ripgrep match, mirroring `search.SearchHit` (the pure
    dataclass `search.py` already produces) field-for-field as a
    JSON-serializable copy. No builder in `docs.py` produces this yet --
    it's provided for the future search-endpoint router (S23.2) to
    construct directly from `search.parse_search_output`/`sort_hits`
    results (`SearchHit(**dataclasses.asdict(hit))` or field-by-field)."""

    target: str
    name: str
    line: int
    col: int
    type: str
    text: str
