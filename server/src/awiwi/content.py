"""Pure filesystem/date domain logic for the notes tree.

No FastAPI imports here — everything operates on `pathlib.Path` and returns
plain data, so it can be unit-tested without a running app and reused
verbatim by routers (see `docs/architecture.md` §Server for the route
surface that will eventually call into this module).

Ported and *assessed* from `server.old/app.py` (Flask) per the design brief
(`~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`, T14 entry) — not a
1:1 migration. Notable divergences from the legacy behavior are called out
on the relevant function's docstring.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Callable


def parse_date(date_str: str, home: Path, today: date | None = None) -> date | None:
    """Parse a journal date string, including the `today`/`yesterday`/`prev`
    (and `previous`) aliases.

    `home` is the notes root (same directory `Settings.home` points at); it
    is only consulted for the `prev`/`previous` alias, which needs to look
    at the journal tree on disk to find the nearest earlier existing entry
    relative to `today`.

    `today` defaults to `date.today()`; tests should pass it explicitly for
    determinism.

    Returns `None` on anything unparseable — including the legacy `prev`
    crash case (`server.old/app.py:parse_date` calls
    `datetime.date.fromisoformat(prev)` where `prev` can be `None`, raising
    `TypeError` and crashing the request with a 500). Here that terminates
    cleanly as `None` so the router can turn it into a 404.
    """
    today = today if today is not None else date.today()
    normalized = date_str.lower()
    if normalized == "today":
        return today
    if normalized == "yesterday":
        return today - timedelta(days=1)
    if normalized in ("previous", "prev"):
        prev, _next = get_prev_and_next_journal(today, home)
        if prev is None:
            return None
        return date.fromisoformat(prev)
    try:
        return date.fromisoformat(date_str)
    except ValueError:
        return None


def find_min_max_paths(path: Path, max_depth: int) -> tuple[Path | None, Path | None]:
    """Walk `path` picking the alphabetically min/max child at each level,
    down to `max_depth` levels, returning the resulting leaf paths.

    Used to find the earliest/latest journal file in a `journal/YYYY/MM/
    YYYY-MM-DD.md` tree (`max_depth=3`). Ported from
    `server.old/app.py:find_min_max_paths`, but hardened: any filesystem
    error (missing directory) or an empty directory (nothing to pick) yields
    `None` for that side rather than propagating — the legacy version let
    `os.listdir` raise on a missing directory and relied on a broad
    `except Exception` further up the call chain (`get_prev_and_next_journal`)
    to paper over it. Here `find_min_max_paths` is safe to call standalone.
    """

    def pick(p: Path, choose: Callable[[list[str]], str], level: int = 0) -> Path | None:
        if level == max_depth:
            return p
        if p.is_file():
            return p
        is_leaf_level = level + 1 == max_depth
        try:
            entries = sorted(
                child.name
                for child in p.iterdir()
                if not child.name.startswith(".")
                and (child.is_file() if is_leaf_level else child.is_dir())
            )
        except OSError:
            return None
        try:
            chosen = choose(entries)
        except ValueError:
            return None
        return pick(p / chosen, choose, level + 1)

    return pick(path, min), pick(path, max)


def get_adjacent_journal_file(
    current_date: date, diff: int, journal_root: Path
) -> str | None:
    """Search from `current_date` towards `current_date + diff` days
    (inclusive of the end, exclusive of `current_date` itself) for the
    first existing `journal_root/YYYY/MM/YYYY-MM-DD.md` file, returning its
    ISO date string, or `None` if none exists in that range.

    `diff == 0` always returns `None` (nothing to search).
    """
    sign = 1 if diff > 0 else -1
    for i in range(1, abs(diff) + 1):
        d = current_date + timedelta(days=sign * i)
        p = journal_root / f"{d:%Y}" / f"{d:%m}" / f"{d.isoformat()}.md"
        if p.exists():
            return d.isoformat()
    return None


def get_prev_and_next_journal(
    current_date: date, home: Path
) -> tuple[str | None, str | None]:
    """Find the nearest existing journal entries before/after
    `current_date`, across month (and year) boundaries.

    `home` is the notes root; the journal tree is `home/journal/...`.
    Returns `(prev, next)` as ISO date strings, either of which may be
    `None` if `current_date` is already the earliest/latest entry, or if
    there are no journal entries at all.
    """
    journal_root = home / "journal"
    try:
        min_path, max_path = find_min_max_paths(journal_root, 3)
        if min_path is None or max_path is None:
            return None, None
        min_ = date.fromisoformat(min_path.stem)
        max_ = date.fromisoformat(max_path.stem)
        lo_diff = (min_ - current_date).days
        hi_diff = (max_ - current_date).days
        prev = get_adjacent_journal_file(current_date, lo_diff, journal_root)
        next_ = get_adjacent_journal_file(current_date, hi_diff, journal_root)
    except Exception:
        return None, None
    return prev, next_


@dataclass(frozen=True)
class Breadcrumb:
    """One `/dir/...` link in a breadcrumb trail."""

    name: str
    target: str


def make_breadcrumbs(
    path: Path, home: Path, include_cur_dir: bool = False
) -> list[Breadcrumb]:
    """Build breadcrumb trail from `home` down to `path`'s parent directory
    (or to `path` itself when `include_cur_dir=True`).

    Ported verbatim from `server.old/app.py:make_breadcrumbs`, including its
    quirk of using the path segment's *stem* (extension stripped) as the
    display `name` while the `target` keeps the full segment (so a file
    segment's target embeds its extension, e.g. `.../pasta.md`) — this
    matches shipped behavior and templates aren't in scope for this module.
    """
    p = path.relative_to(home)
    if not include_cur_dir:
        p = p.parent
    breadcrumbs: list[Breadcrumb] = []
    while p != Path("."):
        breadcrumbs.append(Breadcrumb(name=p.stem, target=f"/dir/{p}"))
        p = p.parent
    return list(reversed(breadcrumbs))


def safe_resolve(relative: str | Path, root: Path) -> Path | None:
    """Resolve `relative` against `root`, refusing anything that would
    escape `root` (absolute overrides, `..` traversal, symlink escapes).

    Returns the resolved absolute `Path` on success, or `None` if the
    result would fall outside `root`. `root` itself is a valid result
    (e.g. `relative="."`).

    Not present in `server.old/app.py` — the legacy app has no path-
    traversal guard (it builds paths straight from route params with
    lightweight defensive redirects for `.`/`..` segments only:
    `remove_current_dir`/`redirect_to_parent`). This is new, assessed
    behavior per the brief.
    """
    root = root.resolve()
    rel = Path(relative)
    if rel.is_absolute():
        return None
    candidate = (root / rel).resolve()
    if candidate != root and root not in candidate.parents:
        return None
    return candidate


def list_directory(path: Path) -> list[Path]:
    """List `path`'s direct children, dotfiles excluded, sorted by name.

    Deliberately minimal: just filesystem enumeration. Doc-type-specific
    presentation (month names, week banding, `todos.md` -> "todo" aliasing
    as in `server.old/app.py:dir_index`) is presentation/routing logic that
    belongs with the templates wiring (T16), not this pure leaf module.
    """
    return sorted(
        (p for p in path.iterdir() if not p.name.startswith(".")),
        key=lambda p: p.name,
    )
