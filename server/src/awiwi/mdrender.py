"""Markdown rendering pipeline: pre-filters + python-markdown + Pygments.

Pure module: no FastAPI imports, no filesystem-path policy (that's
`content.py`'s job, see T14 handover). Everything here takes text in and
returns a `RenderedDoc` out; `render_file` additionally takes an optional
filename/path *hint* for Pygments lexer lookup, but never touches the
filesystem itself.

Ported and *assessed* from `server.old/app.py` (Flask) + its dropped
`nomnoml_extension.py`/`md_mermaid`/`markdown_strikethrough` dependencies,
per the design brief (`~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`,
T15 entry). Notable divergences are called out on the relevant docstring and
summarized in the handover.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import override

from markdown import Markdown
from markdown.extensions import Extension
from markdown.extensions.attr_list import AttrListExtension
from markdown.extensions.codehilite import CodeHiliteExtension
from markdown.extensions.def_list import DefListExtension
from markdown.extensions.fenced_code import FencedCodeExtension
from markdown.extensions.footnotes import FootnoteExtension
from markdown.extensions.nl2br import Nl2BrExtension
from markdown.extensions.sane_lists import SaneListExtension
from markdown.extensions.tables import TableExtension
from markdown.extensions.toc import TocExtension
from markdown.inlinepatterns import SimpleTagInlineProcessor
from markdown.preprocessors import Preprocessor
from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexer import Lexer
from pygments.lexers import (
    get_lexer_by_name,  # pyright: ignore[reportUnknownVariableType]
    get_lexer_for_filename,  # pyright: ignore[reportUnknownVariableType]
)
from pygments.util import ClassNotFound

from awiwi.checkbox import hash_line

# --- pre-filter patterns (ported from server.old/app.py) -------------------

_HEADING_RE = re.compile(r"^(?P<marker>##+) ")
_CHECKBOX_LINE_RE = re.compile(r"^(\s*\* )(\[[x ]\])( .*$)")
_TAG_PATTERN = re.compile(r"@(?P<type>bug|change|incident|issue)\b")
_PERSON_TAG_PATTERN = re.compile(r"@(@[^\s,;.)}\]])")
_ORDINAL_RE = re.compile(r"\b([0-9]{1,2})(st|nd|rd|th)\b")
_REDACTION_MARKER = "!!redacted"

# vim-modeline sniff for source rendering, e.g. "-- vim: ft=pgsql." -> pgsql.
_MODELINE_RE = re.compile(r"(?:vim: ft=)(\S+?)([\s.])")
LEXER_MAP = {"pgsql": "sql"}


@dataclass(frozen=True)
class RenderedDoc:
    """Result of a render call. Templates/routers (T16) read `html` as the
    page body, `toc` as the (possibly empty) table-of-contents block, and
    `title` as the derived-or-passed-through document title."""

    html: str
    toc: str
    title: str | None


def _extract_title(lines: list[str]) -> tuple[str | None, int]:
    """If `lines[0]` is an H1 (`# ...`), pull it out as the title and report
    that the body starts at index 1; otherwise no title, body starts at 0.

    Ported from `server.old/app.py:format_markdown`. Legacy additionally
    tried parsing the title as an ISO date (journal pages' H1 is the date)
    and passed a `datetime.date` object to the template if it succeeded.
    That's presentation logic for the journal template (T16) to apply if it
    wants to — this module always returns a plain string.
    """
    if lines and lines[0].startswith("# "):
        title = re.sub(r"^[#\s]+", "", lines[0]).strip()
        return title, 1
    return None, 0


def _replace_date_ordinal(text: str) -> str:
    return _ORDINAL_RE.sub(r"\1<sup>\2</sup>", text)


def _filter_body(lines: list[str], offset: int) -> list[str]:
    """Apply the legacy line-level pre-filters, in order: `!!redacted`
    section hiding, checkbox -> `<input>` injection (hash from
    `awiwi.checkbox.hash_line`), `@tag`/`@@mention` spans, ordinal
    superscripts.

    `offset` is the 0-indexed line number of `lines[0]` in the *original,
    untouched* file (0, or 1 if a title line was consumed by
    `_extract_title`) -- this is what ends up in `data-line-nr`, so it lines
    up with `awiwi.checkbox.toggle_checkbox`'s 0-indexed `line_nr` contract.

    Ported verbatim from `server.old/app.py:filter_body` (same control flow,
    same regexes), minus the final `.replace("\\n", "")` -- callers here pass
    lines without trailing newlines to begin with (`str.splitlines()`).
    """
    out: list[str] = []
    hide = False
    marker_depth = 7  # deeper than any real heading (# .. ######)
    for line_no, line in enumerate(lines, start=offset):
        if hide:
            m = _HEADING_RE.match(line)
            if m:
                if len(m.group("marker")) <= marker_depth:
                    hide = False
                else:
                    continue
            else:
                continue
        elif _REDACTION_MARKER in line:
            m = _HEADING_RE.match(line)
            if m:
                marker_depth = len(m.group("marker"))
                hide = True
                line = f'{m.group("marker")} _…redacted…_'
            else:
                rem = line.split(_REDACTION_MARKER)[-1].strip()
                out.append(f" --- redacted (cause: {rem}) --- " if rem else " --- redacted --- ")
                continue
        else:
            m = _CHECKBOX_LINE_RE.match(line)
            if m:
                box = m.group(2)
                checked = "checked" if "x" in box else ""
                digest = hash_line(line)
                line = (
                    f'{m.group(1)}<input type="checkbox" id="checkbox-line-{line_no}" '
                    f'{checked} data-line-nr="{line_no}" class="awiwi-checkbox" '
                    f'data-hash="{digest}"> '
                    f'<label for="checkbox-line-{line_no}"><span>{m.group(3)}</span></label>'
                )
        line = _TAG_PATTERN.sub(r'<span class="awiwi-\1">\g<0></span>', line)
        line = _PERSON_TAG_PATTERN.sub(r'<span class="awiwi-mention">\1</span>', line)
        out.append(_replace_date_ordinal(line))
    return out


# --- local replacements for the dropped third-party extensions -------------


class _MermaidPreprocessor(Preprocessor):
    """```mermaid fenced blocks -> raw `<div class="mermaid">` blocks that
    mermaid.js (loaded client-side by the templates) renders in place.

    Must run at a higher priority than `FencedCodeExtension`'s preprocessor
    (registered at 25), or fenced_code/codehilite would swallow the block as
    an ordinary (and unrecognized-language) code fence first.
    """

    _FENCE: re.Pattern[str] = re.compile(r"^```mermaid\s*$")

    @override
    def run(self, lines: list[str]) -> list[str]:
        out: list[str] = []
        in_block = False
        for line in lines:
            if not in_block and self._FENCE.match(line):
                in_block = True
                out.extend(["", '<div class="mermaid">'])
            elif in_block and line.strip() == "```":
                in_block = False
                out.extend(["</div>", ""])
            else:
                out.append(line)
        return out


class _MermaidExtension(Extension):
    @override
    def extendMarkdown(self, md: Markdown) -> None:
        md.preprocessors.register(_MermaidPreprocessor(md), "awiwi-mermaid", 30)


class _StrikethroughExtension(Extension):
    """`~~text~~` -> `<del>text</del>`, replacing the unmaintained
    `markdown_strikethrough` package with python-markdown's own
    `SimpleTagInlineProcessor` helper -- the same mechanism the library uses
    internally for `**strong**`/`*em*`."""

    @override
    def extendMarkdown(self, md: Markdown) -> None:
        md.inlinePatterns.register(
            SimpleTagInlineProcessor(r"(~~)(.+?)\1", "del"), "awiwi-del", 70
        )


def _new_markdown() -> Markdown:
    """A fresh `Markdown` instance per render call.

    Legacy reused one module-level instance across every request without
    ever calling `.reset()` (which `.convert()` does *not* do implicitly) --
    a latent cross-request state leak (htmlStash/footnotes/toc) in a
    single-process Flask app. Building fresh here is simpler than threading
    a reset through, avoids the leak outright, and is safe under FastAPI's
    concurrent request handling (a shared `Markdown` instance is not
    thread-safe).
    """
    return Markdown(
        # "html5" (legacy's setting) and "html" normalize to the same
        # serializer (`Markdown.set_output_format` strips trailing digits) --
        # spelled "html" here so it matches the stub's `Literal["html",
        # "xhtml"]`.
        output_format="html",
        extensions=[
            FencedCodeExtension(),
            CodeHiliteExtension(css_class="highlight", guess_lang=False),
            DefListExtension(),
            FootnoteExtension(),
            Nl2BrExtension(),
            SaneListExtension(),
            TocExtension(),
            TableExtension(),
            AttrListExtension(),
            _MermaidExtension(),
            _StrikethroughExtension(),
        ],
    )


def render_markdown(
    text: str, *, title: str | None = None, add_toc: bool = True
) -> RenderedDoc:
    """Render a markdown document's `text` to HTML.

    If `title` isn't given, it's extracted from a leading H1 line (see
    `_extract_title`); either way the title line (if consumed) is excluded
    from the rendered body.

    `add_toc` controls whether `RenderedDoc.toc` is populated from the
    `TocExtension`-produced `md.toc` attribute after conversion -- *not* the
    legacy `[TOC]`-token-injection + rendered-HTML line-scanning dance
    (`server.old/app.py:format_markdown`). The `TocExtension` always runs (it
    also assigns heading ids used for internal anchors); `add_toc=False`
    just means the caller doesn't want the standalone TOC block surfaced
    (e.g. the `/todo` page).
    """
    lines = text.splitlines()
    if title is None:
        title, start = _extract_title(lines)
    else:
        start = 0
    body = _filter_body(lines[start:], offset=start)
    md_text = "\n".join(body)

    md = _new_markdown()
    html = md.convert(md_text)
    # `TocExtension` sets `toc` on the `Markdown` instance dynamically (it's
    # not part of the base class's declared attributes), hence `getattr`.
    toc: str = getattr(md, "toc", "") if add_toc else ""
    return RenderedDoc(html=html, toc=toc, title=title)


def render_file(text: str, filename: str | Path | None = None) -> RenderedDoc:
    """Syntax-highlight a non-markdown source file's `text` via Pygments.

    Mirrors `server.old/app.py:render_non_journal`'s fallback branch: sniff a
    vim modeline (`vim: ft=<lang>`) first -- the legacy convention for files
    whose extension alone doesn't reveal the language (`LEXER_MAP` maps a
    couple of aliases, e.g. `pgsql` -> `sql`) -- else guess from `filename`'s
    extension. Falls back to the raw, unhighlighted text (unescaped, exactly
    like legacy) if no lexer can be determined either way.

    `filename` is a hint only, used solely for `pygments.lexers.
    get_lexer_for_filename` -- this function never touches the filesystem.

    `toc` is always `""` and `title` always `None`: source files have
    neither.

    Divergence: legacy calls `get_lexer_by_name(...)` unguarded once a
    modeline matches, so an unrecognized modeline language crashes the
    request (uncaught `ClassNotFound` -> 500). Here that's caught and falls
    through to the filename-based guess (then the plain-text fallback)
    instead.
    """
    lexer: Lexer | None = None
    m = _MODELINE_RE.search(text)
    if m:
        lexer_name = m.group(1)
        try:
            lexer = get_lexer_by_name(LEXER_MAP.get(lexer_name, lexer_name))
        except ClassNotFound:
            lexer = None
    if lexer is None and filename is not None:
        try:
            lexer = get_lexer_for_filename(str(filename))
        except ClassNotFound:
            lexer = None

    html: str
    if lexer is not None:
        html = highlight(
            text, lexer, HtmlFormatter(style="solarized-light", cssclass="highlight")
        )
    else:
        html = text
    return RenderedDoc(html=html, toc="", title=None)
