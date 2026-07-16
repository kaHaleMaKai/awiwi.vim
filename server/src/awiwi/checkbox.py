"""Checkbox line hashing + in-place toggle for markdown todo lines.

`hash_line` is a *contract*: it must match `server.old/app.py:hash_line`
byte-for-byte, since the hash is round-tripped through rendered HTML
(`data-hash` attribute on the `<input type="checkbox">`) and back into a
PATCH request body — any drift breaks every existing rendered page as soon
as this server takes over.

No FastAPI imports here; `toggle_checkbox` raises distinct exception types
so the router (T16) can map them to specific HTTP status codes instead of a
single catch-all 500 like the legacy Flask route did for some inputs.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

# GFM task-list forms: `*`/`-`/`+` bullets or ordered items (`1.`/`1)`),
# one or more spaces, `[ ]`/`[x]`/`[X]`, optionally with no trailing text.
# Kept in lockstep with mdrender._CHECKBOX_LINE_RE — a form the renderer
# emits an <input> for must hash/toggle here, and vice versa.
_CHECKBOX_ITEM_RE = re.compile(r"\s*(?:[*+-]|\d+[.)]) +\[[xX ]\]( |$)")
_CHECKBOX_BOX_RE = re.compile(r"\[[ xX]\]")
_CHECKBOX_PREFIX_RE = re.compile(r"(\s*(?:[*+-]|\d+[.)]) +\[)([ xX])")


class CheckboxError(Exception):
    """Base class for all toggle_checkbox failure outcomes."""


class LineNotFoundError(CheckboxError):
    """`line_nr` is at or beyond the end of the file. Maps to 404."""


class HashMismatchError(CheckboxError):
    """The caller's hash doesn't match the current line content (the file
    changed since the hash was computed, e.g. the page was rendered against
    a stale copy). Maps to 409."""


class AlreadyInStateError(CheckboxError):
    """The checkbox is already in the requested checked/unchecked state.
    Maps to 409."""


class NotACheckboxLineError(CheckboxError):
    """The target line doesn't look like a GFM task-list item
    (`*`/`-`/`+`/ordered bullet followed by `[ ]`/`[x]`/`[X]`) at all.

    Legacy crash case: `server.old/app.py:update_checkbox_in_file` assumes
    the regex always matches and does `m.group(2)` unconditionally, raising
    `AttributeError` (uncaught -> 500) if it doesn't. Assessed behavior:
    raise this instead, so the router can map it to a clean 409.
    """


def hash_line(line: str) -> str:
    """MD5 hex digest identifying a checkbox (or plain) line, independent of
    its current checked state and trailing newline.

    Ported verbatim from `server.old/app.py:hash_line`, widened to GFM
    task-list forms (S32.1 dash bullets, then `+`/ordered/`[X]`/bare boxes):
    1. If the line looks like a GFM task-list item, strip the
       `[ ]`/`[x]`/`[X]` box (first occurrence only) before hashing — so
       toggling a box doesn't change its own hash. Hashes for the
       previously supported `* `/`- ` single-space forms are unchanged.
    2. Strip one trailing `\\n`, if present.
    3. MD5 the result.
    """
    if _CHECKBOX_ITEM_RE.match(line):
        line = _CHECKBOX_BOX_RE.sub("", line, count=1)
    if line.endswith("\n"):
        line = line[:-1]
    return hashlib.md5(line.encode()).hexdigest()


def toggle_checkbox(path: Path, line_nr: int, check: bool, expected_hash: str) -> None:
    """Flip the checkbox on 0-indexed line `line_nr` of `path` to `check`
    (`True` -> `[x]`, `False` -> `[ ]`), in place.

    `line_nr` is the same 0-based index used to build the `data-line-nr`
    attribute when rendering (see `content.py`/legacy `filter_body`'s
    `enumerate(lines, start=offset)`).

    Raises:
    - `FileNotFoundError` (builtin) if `path` doesn't exist.
    - `LineNotFoundError` if `line_nr` is at or past the end of the file.
    - `HashMismatchError` if `expected_hash` doesn't match the current line.
    - `NotACheckboxLineError` if the line isn't a GFM task-list item.
    - `AlreadyInStateError` if the box is already in the requested state.

    On success, exactly one character (the box glyph) is overwritten in
    place; the rest of the file is untouched.
    """
    check_char = "x" if check else " "
    with open(path, "r+") as f:
        for _ in range(line_nr):
            _ = f.readline()
        pos = f.tell()
        line = f.readline()
        if not line:
            raise LineNotFoundError(f"line {line_nr} not found in {path}")
        if line.endswith("\n"):
            line = line[:-1]

        actual_hash = hash_line(line)
        if expected_hash != actual_hash:
            raise HashMismatchError(
                f"hashes don't match. exp: '{actual_hash}'. got: '{expected_hash}'"
            )

        m = _CHECKBOX_PREFIX_RE.match(line)
        if m is None:
            raise NotACheckboxLineError(
                f"line {line_nr} is not a checkbox line: {line!r}"
            )

        is_checked = m.group(2) != " "
        if is_checked == check:
            state = "checked" if is_checked else "unchecked"
            raise AlreadyInStateError(f"checkbox is already {state}")

        offset = m.end() - 1
        _ = f.seek(pos + offset)
        _ = f.write(check_char)
