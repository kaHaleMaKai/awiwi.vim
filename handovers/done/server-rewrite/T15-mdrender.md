# T15 S15.1 — mdrender.py (markdown rendering pipeline)

## Responsibility

Implement the markdown rendering pipeline: legacy line-level pre-filters
(redaction, checkbox injection, `@tag`/`@@mention` spans, ordinal
superscripts), a trimmed python-markdown extension set with two tiny local
replacements for dropped third-party extensions (mermaid, strikethrough),
TOC extraction via `md.toc`, and Pygments source-file rendering (with the
legacy vim-modeline lexer sniff). Strict red/green TDD.

## Boundary

Touched only:

- `server/src/awiwi/mdrender.py`
- `server/tests/test_mdrender.py`

Nothing else touched (no `conftest.py` edits needed — the module is pure
text-in/text-out, no filesystem fixture required).

## What downstream (T16) needs from me

```python
from awiwi.mdrender import RenderedDoc, render_markdown, render_file
```

### `RenderedDoc` (frozen dataclass)

| field | type | meaning |
|---|---|---|
| `html` | `str` | rendered page body |
| `toc` | `str` | table-of-contents block (`<div class="toc">...</div>`), or `""` |
| `title` | `str \| None` | derived-or-passed-through document title |

### `render_markdown(text: str, *, title: str | None = None, add_toc: bool = True) -> RenderedDoc`

- If `title` is `None` and `text`'s first line is an H1 (`# ...`), that line
  becomes the title and is excluded from the body; otherwise `title` stays
  `None` and the body is the full text. Passing `title` explicitly (e.g.
  `/todo`'s `"TODO"`) skips extraction and keeps any H1 line in the body.
- Runs, in order: `!!redacted` section hiding -> checkbox -> `<input>`
  injection (hash via `awiwi.checkbox.hash_line`, so it's checkbox.py's
  hash contract wired straight into the render path) -> `@tag`/`@@mention`
  span wrapping -> ordinal (`1st`/`2nd`/...) superscripts -> python-markdown
  conversion.
- Extension set (all built-in except the two local ones): `fenced_code`,
  `codehilite` (Pygments, `guess_lang=False`), `def_list`, `footnotes`,
  `nl2br`, `sane_lists`, `toc`, `tables`, `attr_list`, plus local
  `_MermaidExtension` and `_StrikethroughExtension`. **Dropped** vs. legacy:
  `meta` (never read), the `nomnoml` Python extension (JS-only now, lives in
  templates), third-party `markdown_strikethrough` and `md_mermaid`.
- `add_toc=True` populates `RenderedDoc.toc` from the `TocExtension`'s
  `md.toc` attribute after conversion (a real `<div class="toc">` — empty
  `<ul></ul>` if there are no headings). `add_toc=False` -> `toc=""`. Either
  way the TOC is **never** injected into `html`/the body — there's no
  `[TOC]` token and no HTML line-scanning (legacy's
  `format_markdown` did both; see divergences).
- A fresh `markdown.Markdown` instance is built per call (see divergences).

### `render_file(text: str, filename: str | Path | None = None) -> RenderedDoc`

- For non-markdown source files. Picks a Pygments lexer by: (1) vim-modeline
  sniff (`vim: ft=<lang>` anywhere in `text`, `LEXER_MAP = {"pgsql": "sql"}`
  alias applied), else (2) `filename`'s extension via
  `get_lexer_for_filename`. Falls back to the **raw, unhighlighted** `text`
  (unescaped, byte-for-byte) if neither yields a lexer — matches legacy
  exactly.
- Highlights with `HtmlFormatter(style="solarized-light", cssclass="highlight")`
  when a lexer is found — same style/class as legacy.
- `toc` is always `""`, `title` always `None` (source files have neither).
- `filename` is a **hint only** — this function never touches the
  filesystem; T16/`content.py` own reading the actual file.

## Divergences from `server.old/app.py` (assessed, not migrated as-is)

1. **TOC via `md.toc`, not `[TOC]`-injection + line-scanning.** Legacy
   prepended a literal `\n[TOC]\n` to the markdown source, converted, then
   scanned the *rendered HTML* line-by-line for a `<div class="toc"` ...
   `</div` window to split it back out of the body. Per the brief, this is
   gone entirely — `TocExtension` always runs and its `md.toc` attribute is
   read directly after `.convert()`. Net effect on the *body* HTML is
   identical (no TOC leaks into it either way); the mechanism is just no
   longer stringly-typed and fragile.
2. **`;match(N);` non-ASCII escape hack deleted entirely.** Legacy escaped
   every non-ASCII character to `;match(<pos>);` before `.convert()` and
   un-escaped it afterwards (a workaround for some old markdown/Python 2
   encoding issue, long since irrelevant). Proven unnecessary by
   `TestUnicodeRoundtrip` (umlauts + emoji survive `render_markdown`
   unchanged, and `;match(` never appears in output).
3. **Fresh `Markdown` instance per call, not a shared module-level
   singleton.** Legacy built one `markdown.Markdown(...)` at import time and
   reused it across every request via `md.convert(...)`, **never** calling
   `.reset()` — which `.convert()` does not do implicitly. This is a latent
   cross-request state leak (`htmlStash`, `references`, footnotes, TOC
   heading-id dedup counters) in the legacy single-process Flask app, and
   would be an outright thread-safety bug under FastAPI's concurrent request
   handling if the instance were shared. `_new_markdown()` builds a fresh
   instance every `render_markdown` call instead — simpler than threading a
   `.reset()` call through and removes the leak outright. Not user-visible
   (render is stateless from the caller's perspective either way); flagged
   as a correctness improvement over legacy, not a behavior change.
4. **Local `_MermaidExtension`/`_StrikethroughExtension` replace the
   unmaintained third-party `md_mermaid`/`markdown_strikethrough` packages.**
   Same visible output (`<div class="mermaid">...</div>` around a
   ` ```mermaid ` fence; `<del>...</del>` around `~~text~~`).
   Strikethrough is implemented with python-markdown's own
   `SimpleTagInlineProcessor` helper (the same mechanism the library uses
   internally for `**strong**`) rather than a bespoke postprocessor regex
   over raw HTML — simpler and more idiomatic, same result.
5. **`render_file`'s modeline lexer lookup is now guarded.** Legacy calls
   `get_lexer_by_name(...)` unguarded once a `vim: ft=X` modeline matches, so
   an unrecognized language name crashes the request (uncaught
   `pygments.util.ClassNotFound` -> 500). Here that's caught and falls
   through to the filename-based guess, then the plain-text fallback,
   instead of crashing.
6. **`@@mention` single-character-capture quirk ported verbatim, not
   fixed.** `_PERSON_TAG_PATTERN = r"@(@[^\s,;.)}\]])"` only captures *one*
   character after the leading `@` — e.g. `@@lars.` renders as
   `<span class="awiwi-mention">@l</span>ars.`, not a spanned `@@lars`. This
   is live, shipped rendering behavior (confirmed by running the legacy
   regex directly); the brief's "corpus was authored against these
   semantics" applies here too, so it's preserved exactly rather than
   silently "fixed" — a fix would be a visible rendering change for
   existing notes, out of scope for this subtask. Flagging for whoever
   later decides whether to file this as a real bug.
7. **Title is always a plain `str`, never a `datetime.date`.** Legacy tried
   parsing the extracted H1 title as an ISO date (journal pages' H1 *is*
   the date) and passed a `datetime.date` object to the template in that
   case, enabling template filters like `beautify_if_date`. That's
   presentation logic for whichever template consumes `RenderedDoc.title` —
   T16 can parse `date.fromisoformat(title)` itself if a template needs the
   `date` object; this module keeps to plain strings (pure module, no
   assumptions about caller's presentation needs).

Everything else — the redaction line-hiding state machine (heading-depth
tracking), the checkbox-line regex and `data-*` attribute names/ids, the
`@tag`/ordinal regexes, and the Pygments style/cssclass — is ported
verbatim from `server.old/app.py:filter_body`/`format_markdown`/
`render_non_journal`.

## What T16 needs to know

- Call `render_markdown(text, title=..., add_toc=...)` for every `.md` file
  (journal, todo, recipes, markdown assets) and `render_file(text, filename)`
  for everything else (falls back to raw text if nothing highlights it —
  T16's template must render `RenderedDoc.html` as-is, same as legacy).
- Template variable names (`toc`, `content`/`html`, `title`) don't map 1:1
  to `server.old/html/*.j2`'s existing Jinja variable names — T16 wires
  `RenderedDoc.html` into whatever the copied templates call `content`, etc.
  This module doesn't know about Jinja at all (pure, no template imports).
- `RenderedDoc.title` is a plain string (or `None`). If a template needs
  journal-specific date formatting (`beautify_if_date`), T16 must attempt
  `date.fromisoformat(doc.title)` itself and handle the `ValueError` — this
  module does not do that parsing (see divergence 7).
- Checkbox line numbers in the rendered `data-line-nr`/`id="checkbox-line-N"`
  attributes are 0-indexed against the **original, untouched file** (title
  line, if consumed, still counts as index 0) — this is exactly
  `awiwi.checkbox.toggle_checkbox`'s `line_nr` contract from T14, so the
  PATCH `/checkbox` router can pass the attribute value straight through
  unmodified.
- `render_file`'s `filename` parameter is a hint for lexer lookup only — it
  never opens or reads any path. T16/`content.py` (T14) own actually
  reading file bytes/text off disk.
- No FastAPI/Jinja/filesystem imports anywhere in this module — verified
  clean by inspection and by `ruff`/`basedpyright` (both pass with the
  trimmed dependency footprint: `markdown`, `pygments`, stdlib only, plus
  `awiwi.checkbox` for `hash_line`).

## Inputs I consumed

- Design brief: `~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`
  (§Context, §User decisions, §Assessment of server.old markdown pipeline
  paragraph, §Proposed structure, key design decisions, T15 entry) —
  authoritative.
- `handovers/server-rewrite/T13-scaffold-config.md`,
  `handovers/server-rewrite/T14-leaf-modules.md` — consumed
  `awiwi.checkbox.hash_line`'s contract (0-indexed line numbers, box-glyph
  stripped before hashing) as-is, no changes.
- `server.old/app.py` (read-only) — `hash_line` (cross-checked against
  `awiwi.checkbox.hash_line`, confirmed identical), `filter_body`,
  `format_markdown`, `render_non_journal`'s Pygments/modeline branch,
  `TAG_PATTERN`/`PERSON_TAG_PATTERN`/`ordinal_pattern`, the `markdown.Markdown(...)`
  extension list.
- `server.old/nomnoml_extension.py` (read-only, confirmed dropped per brief
  — JS-only nomnoml rendering stays in templates, no Python-side port).
- `server.old/.venv/.../md_mermaid.py` and
  `server.old/.venv/.../markdown_strikethrough/extension.py` (read-only) —
  read the actual third-party implementations being replaced, to match
  their visible output (`<div class="mermaid">`, `<del>...</del>`) with the
  new local processors.
- `server/src/awiwi/checkbox.py` (read-only, from T14) — `hash_line`'s exact
  signature and stripping behavior, reused directly (not reimplemented).

## Tests

`server/tests/test_mdrender.py` — 27 tests, no fixtures needed (pure
text-in/text-out):

- `TestTitleExtraction` (4): H1 extraction + body exclusion, explicit-title
  override keeps H1 in body, no-H1 -> no title, return type check.
- `TestToc` (3): heading anchors present in `toc`, `add_toc=False` ->
  `toc==""`, TOC never leaks into `html` (no `[TOC]` token, no toc div in
  body).
- `TestRedaction` (3): heading-scoped section hiding (incl. a nested deeper
  heading staying hidden and a same-depth heading ending it), inline
  redaction with a cause message, inline redaction without one.
- `TestCheckboxInjection` (3): unchecked box's `data-hash` matches
  `awiwi.checkbox.hash_line` independently, checked box's own (different)
  hash + `checked` attribute, line numbering correctly accounts for a
  consumed title line.
- `TestMermaid` (3): fence -> div, block not treated as an ordinary code
  fence (no `highlight`/`<code>` residue), unrelated fenced code blocks
  still get Pygments highlighting.
- `TestStrikethrough` (1): `~~old~~` -> `<del>old</del>`.
- `TestUnicodeRoundtrip` (1): umlauts + emoji intact, no `;match(` residue.
- `TestOrdinalSuperscript` (1): 1st/2nd/3rd/4th/23rd all get `<sup>`.
- `TestTagsAndMentions` (3): each of the four recognized `@tag` types wraps
  correctly; `@@mention` wraps per the ported-verbatim single-char-capture
  quirk (asserted explicitly, not accidentally).
- `TestRenderFile` (5): filename-extension lexer pick, modeline sniff
  overriding filename, `LEXER_MAP` alias (`pgsql` -> `sql`), and two
  plain-text-fallback cases (unknown extension; no filename and no
  modeline at all).

Confirmed red-then-green: wrote both files, moved `mdrender.py` aside and
ran the suite (`ModuleNotFoundError: No module named 'awiwi.mdrender'`,
1 collection error), restored it, re-ran to green.

Full gate:

```sh
cd server && uv run pytest && uv run ruff check . && uv run basedpyright
```

Results:
- `uv run pytest` -> **88 passed** (27 new + 61 pre-existing from
  T13/T14)
- `uv run ruff check .` -> **All checks passed!**
- `uv run basedpyright` -> **0 errors, 0 warnings, 0 notes**

Getting basedpyright to 0/0/0 required: `output_format="html"` instead of
legacy's `"html5"` (both normalize to the same serializer internally —
`Markdown.set_output_format` strips trailing digits — but only `"html"`/
`"xhtml"` are in the constructor's `Literal` stub); `@typing.override` on
the three `Extension`/`Preprocessor` method overrides
(`reportImplicitOverride`); an explicit `re.Pattern[str]` annotation on
`_MermaidPreprocessor._FENCE` (`reportUnannotatedClassAttribute`); a typed
local (`toc: str = getattr(md, "toc", "")`) to read the `TocExtension`'s
dynamically-set `md.toc` attribute, which isn't declared on `Markdown`'s
stub (`reportAttributeAccessIssue`); an explicit `Lexer | None` annotation
on the `render_file` lexer variable; and two per-name
`# pyright: ignore[reportUnknownVariableType]` comments on the
`get_lexer_by_name`/`get_lexer_for_filename` imports (Pygments' own stubs
leave their return types partially unknown — same local-annotation
convention T13/T14 already established, no project-level pyright config
added).

## Status

status: done, updated 2026-07-07T16:59:36Z
