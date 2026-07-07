# T14 S14.1 — content.py + checkbox.py + search.py (pure domain leaf modules)

## Responsibility

Implement the three pure, FastAPI-free domain leaf modules the routers
(T16) will call into: journal/date navigation + path safety + directory
listing (`content.py`), checkbox line-hashing + in-place toggle
(`checkbox.py`), and ripgrep arg-building + result parsing/ordering
(`search.py`). Strict red/green TDD, unit-first, no subprocess spawned in
tests.

## Boundary

Touched only:

- `server/src/awiwi/content.py`
- `server/src/awiwi/checkbox.py`
- `server/src/awiwi/search.py`
- `server/tests/test_content.py`
- `server/tests/test_checkbox.py`
- `server/tests/test_search.py`

Nothing else touched (no `conftest.py` edits — the existing `notes_home`
fixture from T13 was sufficient as-is; no gaps found).

## What downstream needs from me

### `awiwi.content`

```python
from awiwi.content import (
    Breadcrumb, parse_date, find_min_max_paths, get_adjacent_journal_file,
    get_prev_and_next_journal, make_breadcrumbs, safe_resolve, list_directory,
)
```

- `parse_date(date_str: str, home: Path, today: date | None = None) -> date | None`
  — parses `today`/`yesterday`/`prev`/`previous` (case-insensitive) plus
  ISO `YYYY-MM-DD`. `today` defaults to `date.today()`; pass explicitly in
  tests/routers for determinism. Returns `None` for anything unparseable
  **and** for the `prev`/`previous` alias when no earlier journal exists at
  all — a clean, 404-able outcome (see divergence below).
- `find_min_max_paths(path: Path, max_depth: int) -> tuple[Path | None, Path | None]`
  — alphabetical min/max leaf path at `max_depth` levels down; `(None,
  None)` for a missing or empty directory (never raises for those cases).
- `get_adjacent_journal_file(current_date: date, diff: int, journal_root: Path) -> str | None`
  — nearest existing `journal_root/YYYY/MM/YYYY-MM-DD.md` between
  `current_date` (exclusive) and `current_date + diff` days (inclusive);
  `None` if `diff == 0` or nothing found.
- `get_prev_and_next_journal(current_date: date, home: Path) -> tuple[str | None, str | None]`
  — `(prev, next)` ISO date strings across month/year boundaries, `home` is
  the notes root (journal tree is `home/journal/...`). Either or both may
  be `None`. Never raises (broad `except Exception` retained from legacy as
  defense-in-depth around the two `date.fromisoformat` calls).
- `Breadcrumb` — frozen dataclass, fields `name: str`, `target: str`.
- `make_breadcrumbs(path: Path, home: Path, include_cur_dir: bool = False) -> list[Breadcrumb]`
  — ordered root-to-leaf trail; `[]` for a root-level path.
- `safe_resolve(relative: str | Path, root: Path) -> Path | None`
  — path-traversal guard, **new** (no legacy equivalent). Rejects absolute
  input and any `..`/symlink escape outside `root`; returns the resolved
  absolute `Path` otherwise (including `root` itself for `"."`).
- `list_directory(path: Path) -> list[Path]` — direct children, dotfiles
  excluded, sorted by name. Deliberately minimal (no month-name / week-class
  / `todos.md`→"todo" presentation logic — that's routing/template glue,
  left for T16).

### `awiwi.checkbox`

```python
from awiwi.checkbox import (
    hash_line, toggle_checkbox,
    CheckboxError, LineNotFoundError, HashMismatchError,
    AlreadyInStateError, NotACheckboxLineError,
)
```

- `hash_line(line: str) -> str` — MD5 hex digest, **byte-for-byte
  compatible** with `server.old/app.py:hash_line` (golden-tested against
  hashes computed by running the legacy algorithm standalone, not by
  reusing this implementation).
- `toggle_checkbox(path: Path, line_nr: int, check: bool, expected_hash: str) -> None`
  — flips the checkbox glyph on 0-indexed line `line_nr` in place (single
  byte written; rest of file untouched). Exceptions, all subclasses of
  `CheckboxError` (except the builtin), for the router to map:
  - `FileNotFoundError` (builtin) — `path` doesn't exist → **404**
  - `LineNotFoundError` — `line_nr` at/past EOF → **404**
  - `HashMismatchError` — hash mismatch (stale render) → **409**
  - `AlreadyInStateError` — box already in requested state → **409**
  - `NotACheckboxLineError` — line isn't `* [ ]`/`* [x]` → **409**

### `awiwi.search`

```python
from awiwi.search import SearchHit, build_rg_args, parse_search_output, sort_hits
```

- `build_rg_args(pattern: str) -> list[str]` — full argv (incl. `"rg"`),
  matches legacy flags exactly:
  `["rg", "-i", "-U", "--multiline-dotall", "--color=never", "--column",
  "--line-number", "--no-heading", "-g", "!awiwi*", pattern]`.
- `SearchHit` — frozen dataclass: `target: str`, `name: str`, `line: int`,
  `col: int`, `type: str`, `text: str`.
- `parse_search_output(output: str) -> list[SearchHit]` — parses
  `file:line:col:text` lines (rg's `--column --line-number --no-heading`
  format) into `SearchHit`s, mapped to app URLs by doc type (`todo` /
  `journal` / `asset` / `recipe`). Blank lines ignored; unrecognized
  top-level directories are skipped (see divergence below).
- `sort_hits(hits: list[SearchHit]) -> list[SearchHit]` — orders
  todo → journal → asset → recipe, then lexically by `name` within a type.

**Scope note:** `search.py` never spawns a subprocess — it only builds the
argv and parses text. Actually invoking `rg` and feeding it
`build_rg_args`'s output / `parse_search_output`'s input is T16's job (the
plan's S16.1 already lists a skipif-no-rg acceptance test for this).

## Divergences from `server.old/app.py` (assessed, not migrated as-is)

1. **`parse_date("prev"/"previous")` clean-404 instead of crash.** Legacy
   calls `datetime.date.fromisoformat(prev)` where `prev` can be `None`
   (`TypeError`, uncaught → 500) when no journal files exist yet. Here it
   returns `None` cleanly.
2. **`toggle_checkbox` line-not-found instead of crash.** Legacy reads past
   EOF (`f.readline()` → `""`) then does `line[-1]` unconditionally
   (`IndexError`, uncaught → 500). Here: `LineNotFoundError`.
3. **`toggle_checkbox` non-checkbox-line instead of crash.** Legacy assumes
   the `(\s*\* \[)([ x])` regex always matches and does `m.group(2)`
   unconditionally (`AttributeError` if it doesn't). Here:
   `NotACheckboxLineError`.
4. **Search todo-file typo fixed.** Legacy compares against the literal,
   nonexistent filename `"journal/todo.md"` (missing the `s`) — this
   condition never fires against the real file `journal/todos.md`, so todo
   hits always fell through to the generic `journal` branch and linked to
   `/journal/todos` instead of `/todo`. Fixed to compare against
   `"journal/todos.md"`.
5. **Search unrecognized top-level dir: skip instead of crash.** Legacy's
   `format_search_hits` has no final `else`; an unrecognized top-level
   directory (e.g. a stray `rg` hit under `static/`) leaves `target`/`name`
   unbound → `UnboundLocalError`. Here such hits are silently skipped.
6. **`safe_resolve` is new** — legacy has no path-traversal guard at all
   (only cosmetic `.`/`..` segment redirects on two specific routes). Added
   per the brief's explicit T14 scope ("safe_resolve — path-traversal guard
   confining resolution under home").
7. **`find_min_max_paths` hardened to never raise** for a missing/empty
   directory (returns `(None, None)`) instead of relying on a broad
   `except Exception` further up the call chain, as legacy did. Behavior at
   the `get_prev_and_next_journal` level is unchanged; the broad
   `except Exception` there is kept anyway as a second line of defense
   around the two `date.fromisoformat(...)` calls on the returned stems.

Everywhere else, legacy behavior was matched deliberately, even where it
looks slightly odd — e.g. `make_breadcrumbs` uses a path segment's *stem*
for `name` but the full segment (with extension) for `target`, and
`search.py`'s recipe `name` replaces only the *first* `/` in the full
`recipes/...` path (so `recipes/cooking/pasta.md` → `"recipes – cooking/pasta.md"`,
not `"cooking – pasta.md"`) — both ported verbatim since the brief wasn't
explicit about them and they're cosmetic, not crash/dead-code bugs.

## Inputs I consumed

- Design brief: `~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`
  (§Context, §User decisions, §Assessment of server.old, §Proposed
  structure, T14 entry) — authoritative.
- `handovers/server-rewrite/T13-scaffold-config.md` — `Settings`/
  `PluginConfig` API, `notes_home` fixture shape (used as-is, no edits).
- `server.old/app.py` (read-only) — `hash_line`, `update_checkbox_in_file`,
  `parse_date`, `find_min_max_paths`, `get_adjacent_journal_file`,
  `get_prev_and_next_journal`, `make_breadcrumbs`, `dir_index`,
  `server_search_content`, `format_search_hits` — the exact legacy
  algorithms re-implemented/assessed above.
- `server/tests/conftest.py`, `server/src/awiwi/config.py` (read-only,
  from T13) — reused the `notes_home` fixture unmodified.

## Tests

`server/tests/test_content.py` — 30 tests: `TestParseDate` (7),
`TestFindMinMaxPaths` (3), `TestGetAdjacentJournalFile` (4),
`TestGetPrevAndNextJournal` (4, including the June→July month-boundary
crossing and the no-journals-at-all case), `TestMakeBreadcrumbs` (3),
`TestSafeResolve` (6, incl. `..` traversal, embedded `..`, absolute-path
rejection), `TestListDirectory` (2).

`server/tests/test_checkbox.py` — 14 tests: `TestHashLine` (5 golden
hashes, independently computed from the legacy algorithm),
`TestToggleCheckbox` (9, covering both toggle directions, indentation
preservation, wrong-hash/already-in-state/EOF/non-checkbox-line/missing-file
error outcomes, and that a failed toggle leaves the file byte-for-byte
untouched).

`server/tests/test_search.py` — 17 tests: `TestBuildRgArgs` (1),
`TestParseSearchOutput` (9, incl. the todo-typo-fix case, colon-in-text
preservation, blank-line skipping, unrecognized-dir skipping, multi-hit
parsing), `TestSortHits` (1, cross-type + within-type ordering).

Confirmed red-then-green for each module: each test file was written and
run first (`ModuleNotFoundError: No module named 'awiwi.<module>'`), then
the corresponding implementation module was added and tests re-run to
green, one module at a time (content → checkbox → search).

Full gate:

```sh
cd server && uv run pytest && uv run ruff check . && uv run basedpyright
```

Results:
- `uv run pytest` → **61 passed** (30 + 14 + 17, plus the 7 pre-existing
  `test_config.py` tests from T13, total 61)
- `uv run ruff check .` → **All checks passed!**
- `uv run basedpyright` → **0 errors, 0 warnings, 0 notes**

basedpyright's `reportUnusedCallResult` fired on a few discarded return
values (`f.readline()`/`f.seek()`/`f.write()` in `checkbox.py`,
`Path.write_text()` in two test fixtures) — fixed with `_ = ...`-prefixing,
same convention T13 established, no project-level pyright config added.

## Status

status: done, updated 2026-07-07T16:48:01Z
