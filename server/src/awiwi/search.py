"""Content search: ripgrep arg-list builder + result parsing/ordering.

Pure module: it only builds an argv list and parses text — it never spawns
a subprocess itself. Actually shelling out to `rg` and feeding this parser
its stdout is the router's job (T16 per the design brief), which also gets
the skipif-no-rg acceptance test. This keeps the parsing/mapping/ordering
logic — the part with real behavior worth pinning down — unit-testable
without a filesystem or a `rg` binary.

Ported and *assessed* from `server.old/app.py`'s `server_search_content` /
`format_search_hits`; divergences are documented per-function below.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

# Matches server.old/app.py:server_search_content's `cmd` list exactly,
# except the trailing `pattern` element is appended by the caller.
_RG_BASE_ARGS = [
    "rg",
    "-i",
    "-U",
    "--multiline-dotall",
    "--color=never",
    "--column",
    "--line-number",
    "--no-heading",
    "-g",
    "!awiwi*",
]

# Top-level doc-type directories the JSON `/api/search` route can restrict
# a search to (S23.2). Order isn't semantically meaningful here -- it just
# controls the order the `-g` glob pairs are appended.
SCOPE_DIRS = ("journal", "assets", "recipes")


def build_rg_args(
    pattern: str, *, fixed: bool = False, scopes: Sequence[str] | None = None
) -> list[str]:
    """Build the full ripgrep argv (including the `rg` executable name) for
    searching the notes tree for `pattern`.

    `fixed`/`scopes` are S23.2 additions for the JSON `/api/search` route.
    `fixed=False` is the *default* deliberately -- it reproduces the exact
    argv the legacy `POST /search/content` action route has always gotten
    (positional-only call, `build_rg_args(pattern)`), so that existing
    caller keeps working byte-for-byte. `fixed=True` appends `-F` (treat
    `pattern` as a literal string, not a regex). `scopes` -- an iterable of
    top-level directory names (`"journal"`/`"assets"`/`"recipes"`) --
    appends one `-g "{scope}/**"` include-glob pair per scope, restricting
    the search to those directories; `None`/empty means unrestricted (all
    three). The trailing `pattern` element always stays last.
    """
    args = list(_RG_BASE_ARGS)
    if fixed:
        args.append("-F")
    if scopes:
        for scope in scopes:
            args.extend(["-g", f"{scope}/**"])
    args.append(pattern)
    return args


@dataclass(frozen=True)
class SearchHit:
    """One parsed `rg` match, mapped to a doc-type-aware URL."""

    target: str
    name: str
    line: int
    col: int
    type: str
    text: str


# type -> sort rank, ported from server.old/app.py:server_search_content's
# local `sortable()` helper.
_TYPE_ORDER = {"todo": 0, "journal": 1, "asset": 2, "recipe": 3}


def _map_hit(file: str, line_no: int, col: int, text: str) -> SearchHit | None:
    if file == "journal/todos.md":
        # Assessed fix: server.old/app.py compares against the literal
        # (nonexistent) "journal/todo.md" — a typo that never matches the
        # real filename "journal/todos.md" — so todo hits always fell
        # through to the generic "journal" branch below and linked to
        # /journal/todos instead of /todo. Fixed here.
        return SearchHit(
            target="/todo", name="todo", line=line_no, col=col, type="todo", text=text
        )

    parts = file.split("/")
    top = parts[0]
    if top == "journal":
        journal_name = parts[-1].replace(".md", "")
        return SearchHit(
            target=f"/journal/{journal_name}",
            name=journal_name,
            line=line_no,
            col=col,
            type="journal",
            text=text,
        )
    if top == "assets":
        date = "-".join(parts[1:4])
        asset_name = parts[-1]
        return SearchHit(
            target=f"/assets/{date}/{asset_name}",
            name=f"{date}/{asset_name}",
            line=line_no,
            col=col,
            type="asset",
            text=text,
        )
    if top == "recipes":
        name = file.replace("/", " – ", 1)
        return SearchHit(
            target=file, name=name, line=line_no, col=col, type="recipe", text=text
        )

    # Assessed fix: server.old/app.py:format_search_hits has no final
    # `else` here — an unrecognized top-level directory leaves `target`/
    # `name` unbound and crashes with UnboundLocalError. Skip instead.
    return None


def parse_search_output(output: str) -> list[SearchHit]:
    """Parse `rg --column --line-number --no-heading` stdout (one match per
    line, `file:line:col:text`) into `SearchHit`s, mapped to app URLs by doc
    type. Blank lines are ignored. Unrecognized top-level directories are
    skipped (see `_map_hit`)."""
    hits: list[SearchHit] = []
    for line in output.splitlines():
        if not line:
            continue
        file, line_no, col, text = line.split(":", 3)
        hit = _map_hit(file, int(line_no), int(col), text.strip())
        if hit is not None:
            hits.append(hit)
    return hits


def _sort_key(hit: SearchHit) -> str:
    """Ported from server.old/app.py's local `sortable()`: rank by type,
    then lexically by name within a type."""
    return f"{_TYPE_ORDER[hit.type]}{hit.name}"


def sort_hits(hits: list[SearchHit]) -> list[SearchHit]:
    """Order hits: todo, then journal, then asset, then recipe; within a
    type, lexically by name."""
    return sorted(hits, key=_sort_key)
