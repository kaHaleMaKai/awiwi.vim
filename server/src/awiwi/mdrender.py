"""Markdown rendering pipeline: pre-filters + python-markdown.

Pure module: no FastAPI imports, no filesystem-path policy (that's
`content.py`'s job, see T14 handover). Everything here takes text in and
returns a `RenderedDoc` out.

Ported and *assessed* from `server.old/app.py` (Flask) + its dropped
`nomnoml_extension.py`/`md_mermaid`/`markdown_strikethrough` dependencies,
per the design brief (`~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`,
T15 entry). Notable divergences are called out on the relevant docstring and
summarized in the handover.

T23.3 (ADR D13): `render_markdown`'s fenced code blocks no longer go through
`CodeHiliteExtension`/Pygments -- the Svelte SPA highlights code
client-side with Shiki, so the server emits clean, semantic
`<pre><code class="language-x">` markup (HTML-escaped, no Pygments spans)
for `render_markdown`/`build_doc_payload`'s `kind == "markdown"` path. Every
*other* extension and pre-filter is untouched -- byte-identical output.
T27: the Pygments-backed `render_file` (raw source files, `kind == "text"`)
path was retired; the SPA highlights those client-side too, via
`guess_language`'s Shiki-id hint.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass
from pathlib import Path
from typing import override
from uuid import uuid4

from markdown import Markdown
from markdown.extensions import Extension
from markdown.extensions.attr_list import AttrListExtension
from markdown.extensions.def_list import DefListExtension
from markdown.extensions.fenced_code import FencedCodeExtension
from markdown.extensions.footnotes import FootnoteExtension
from markdown.extensions.nl2br import Nl2BrExtension
from markdown.extensions.sane_lists import SaneListExtension
from markdown.extensions.tables import TableExtension
from markdown.extensions.toc import TocExtension
from markdown.inlinepatterns import SimpleTagInlineProcessor
from markdown.preprocessors import Preprocessor

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

# Shiki-style lowercase language ids, keyed by lowercase file extension
# (without the leading dot). Deliberately a short, curated list of the
# source kinds awiwi notes actually link out to, not an exhaustive alias
# table -- the future SPA's `lang.ts` mirrors this exact map, so keep the
# two in sync by hand if either grows.
_EXT_LANG_MAP: dict[str, str] = {
    "py": "python",
    "sh": "bash",
    "bash": "bash",
    "zsh": "bash",
    "lua": "lua",
    "vim": "vim",
    "js": "javascript",
    "mjs": "javascript",
    "cjs": "javascript",
    "jsx": "jsx",
    "ts": "typescript",
    "tsx": "tsx",
    "json": "json",
    "yaml": "yaml",
    "yml": "yaml",
    "toml": "toml",
    "md": "markdown",
    "markdown": "markdown",
    "sql": "sql",
    "html": "html",
    "htm": "html",
    "css": "css",
    "c": "c",
    "h": "c",
    "cpp": "cpp",
    "cc": "cpp",
    "cxx": "cpp",
    "hpp": "cpp",
    "rs": "rust",
    "go": "go",
    "xml": "xml",
    "ini": "ini",
    "cfg": "ini",
    "conf": "ini",
}


def _modeline_language(text: str) -> str | None:
    """Sniff a vim modeline (`vim: ft=<lang>`) language name out of `text`,
    e.g. `-- vim: ft=pgsql.` -> `"pgsql"` (alias resolution, e.g. `pgsql` ->
    `sql`, is the caller's job -- `guess_language` resolves via `LEXER_MAP`
    for a Shiki id). Shared so the sniff regex/logic lives in exactly one
    place.
    """
    m = _MODELINE_RE.search(text)
    return m.group(1) if m else None


def guess_language(path: Path | str, text: str | None = None) -> str | None:
    """Best-effort Shiki-style language id for `path` (+ optional `text`),
    used as the client-side syntax-highlighting hint for non-markdown text
    files (`DocPayload.language`).

    A vim modeline found in `text` (`vim: ft=<lang>`, `LEXER_MAP` alias
    applied, e.g. `pgsql` -> `sql`) wins over a guess from `path`'s
    filename. `Dockerfile`-style filenames (no extension to key off) are
    recognized by name; everything else is looked up in `_EXT_LANG_MAP` by
    lowercase extension.

    Returns `None` when nothing matches -- an explicitly fine, expected
    outcome (the frontend sniffs too), not an error.
    """
    if text is not None:
        modeline_lang = _modeline_language(text)
        if modeline_lang is not None:
            return LEXER_MAP.get(modeline_lang, modeline_lang).lower()

    name = Path(path).name.lower()
    if name.startswith("dockerfile"):
        return "dockerfile"
    ext = Path(path).suffix.lstrip(".").lower()
    return _EXT_LANG_MAP.get(ext)


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


def _filter_body(
    lines: list[str], offset: int, *, embed_redacted: bool = False
) -> tuple[list[str], dict[str, str]]:
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

    `embed_redacted` (S23.4, ADR-pending): when `True`, the original
    redacted content is *kept*, HTML-escaped and wrapped in
    `class="redacted"` markup, right alongside the usual placeholder
    wording -- for the frontend to click-reveal. `False` (the default)
    reproduces the legacy stripping behavior byte-identically: nothing but
    the placeholder text ever reaches the output. See `_flush_hidden`
    (section form) and the inline `<span>` emission below (line form) for
    the exact markup contract.

    Returns `(filtered_lines, embeds)`. `embeds` maps opaque one-shot tokens
    (planted inside the `class="redacted"` wrappers in `filtered_lines`) to
    the HTML-escaped redacted values they stand for; empty unless
    `embed_redacted`. `render_markdown` substitutes each token *after*
    markdown conversion, so hidden values never travel through
    python-markdown at all -- a revealed value must read back
    character-for-character, and inline processors would otherwise
    re-render markdown punctuation inside it (`pass*word*123` ->
    `pass<em>word</em>123`, dropping the asterisks).
    """
    out: list[str] = []
    embeds: dict[str, str] = {}
    # Tokens are alphanumeric-only (inert through every markdown inline and
    # block processor) and carry a per-render uuid so document text can
    # never collide with one.
    run_id = uuid4().hex
    hide = False
    marker_depth = 7  # deeper than any real heading (# .. ######)
    hidden_lines: list[str] = []

    def _stash(value: str) -> str:
        token = f"awiwiredacted{run_id}n{len(embeds)}"
        embeds[token] = html.escape(value)
        return token

    def _flush_hidden() -> None:
        """Emit the buffered body of a just-closed redacted heading section
        (embed mode only) as one raw HTML block: blank-line-delimited so
        python-markdown passes it through untouched rather than wrapping it
        in a `<p>` or trying to parse its contents. The original lines
        (including any blank lines between hidden paragraphs) are joined
        verbatim and stashed as one text blob behind a token -- no markdown
        re-rendering, no per-line pre-filter re-application (tags/mentions/
        checkboxes/ordinals never ran on these lines to begin with, in
        either mode)."""
        if embed_redacted and hidden_lines:
            token = _stash("\n".join(hidden_lines))
            out.append("")
            out.append(f'<div class="redacted">{token}</div>')
            out.append("")
        hidden_lines.clear()

    for line_no, line in enumerate(lines, start=offset):
        if hide:
            m = _HEADING_RE.match(line)
            if m:
                if len(m.group("marker")) <= marker_depth:
                    hide = False
                    _flush_hidden()
                else:
                    hidden_lines.append(line)
                    continue
            else:
                hidden_lines.append(line)
                continue
        elif _REDACTION_MARKER in line:
            m = _HEADING_RE.match(line)
            if m:
                marker_depth = len(m.group("marker"))
                hide = True
                line = f"{m.group('marker')} _…redacted…_"
            else:
                before, _, rest = line.partition(_REDACTION_MARKER)
                cause = rest.strip()
                placeholder = (
                    f" --- redacted (cause: {cause}) --- "
                    if cause
                    else " --- redacted --- "
                )
                if embed_redacted:
                    token = _stash(before.rstrip())
                    out.append(f'<span class="redacted">{token}</span>{placeholder}')
                else:
                    out.append(placeholder)
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
    # EOF while still hiding: a redacted section that runs to the end of the
    # document with no closing same-or-shallower heading still needs its
    # buffered body flushed (embed mode only; a no-op otherwise).
    _flush_hidden()
    return out, embeds


# --- local replacements for the dropped third-party extensions -------------


class _MermaidPreprocessor(Preprocessor):
    """```mermaid fenced blocks -> raw `<div class="mermaid">` blocks that
    mermaid.js (loaded client-side by the templates) renders in place.

    Must run at a higher priority than `FencedCodeExtension`'s preprocessor
    (registered at 25), or fenced_code would swallow the block as an
    ordinary (and unrecognized-language) code fence first.
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
    text: str,
    *,
    title: str | None = None,
    add_toc: bool = True,
    embed_redacted: bool = False,
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

    `embed_redacted` (S23.4): `False` (the default) is the legacy, byte-
    identical stripping behavior -- `!!redacted` lines/sections never leave
    any trace of their original content in `html`. `True` opt-in keeps the
    original content in `html`, HTML-escaped and wrapped in
    `class="redacted"` markup (obscured by CSS, not by this function), for
    a click-to-reveal frontend. See `_filter_body` for the exact markup.
    Callers gate this on their own trust boundary (`docs.py`'s builders
    pass `True` only when the deployment is guaranteed localhost-only) --
    this function has no opinion on when embedding is safe.
    """
    lines = text.splitlines()
    if title is None:
        title, start = _extract_title(lines)
    else:
        start = 0
    body, embeds = _filter_body(
        lines[start:], offset=start, embed_redacted=embed_redacted
    )
    md_text = "\n".join(body)

    md = _new_markdown()
    rendered = md.convert(md_text)
    # Redacted values (already HTML-escaped by `_filter_body`) are planted
    # as inert tokens and substituted only now, *after* conversion -- they
    # must never pass through python-markdown (see `_filter_body`).
    for token, escaped_value in embeds.items():
        rendered = rendered.replace(token, escaped_value)
    # `TocExtension` sets `toc` on the `Markdown` instance dynamically (it's
    # not part of the base class's declared attributes), hence `getattr`.
    toc: str = getattr(md, "toc", "") if add_toc else ""
    return RenderedDoc(html=rendered, toc=toc, title=title)
