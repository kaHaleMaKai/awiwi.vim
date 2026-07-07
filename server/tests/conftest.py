"""Shared pytest fixtures for the awiwi server test suite.

`notes_home` builds a minimal-but-representative notes tree matching the
doc-type hierarchy from docs/architecture.md (journal/assets/recipes) plus a
`config.json`, so downstream test modules (content/search/routers) can reuse
one fixture instead of hand-rolling tmp trees.
"""

import json
from collections.abc import Iterator
from datetime import date, timedelta
from pathlib import Path

import pytest


@pytest.fixture
def notes_home(tmp_path: Path) -> Path:
    """A tmp_path notes tree spanning a month boundary, plus config.json.

    Layout:
        journal/2026/06/2026-06-29.md
        journal/2026/06/2026-06-30.md
        journal/2026/07/2026-07-01.md
        journal/2026/07/2026-07-02.md
        journal/todos.md
        assets/2026/07/01/x.txt
        recipes/cooking/pasta.md
        config.json

    Returns the tmp_path root (the "home" directory itself).
    """
    home = tmp_path

    journal_june = home / "journal" / "2026" / "06"
    journal_june.mkdir(parents=True)
    _ = (journal_june / "2026-06-29.md").write_text("# 2026-06-29\n\nJune day.\n")
    _ = (journal_june / "2026-06-30.md").write_text(
        "# 2026-06-30\n\nLast day of June.\n"
    )

    journal_july = home / "journal" / "2026" / "07"
    journal_july.mkdir(parents=True)
    _ = (journal_july / "2026-07-01.md").write_text(
        "# 2026-07-01\n\nFirst day of July.\n"
    )
    _ = (journal_july / "2026-07-02.md").write_text(
        "# 2026-07-02\n\nSecond day of July.\n"
    )

    _ = (home / "journal" / "todos.md").write_text("# Todos\n\n- [ ] example todo\n")

    asset_dir = home / "assets" / "2026" / "07" / "01"
    asset_dir.mkdir(parents=True)
    _ = (asset_dir / "x.txt").write_text("asset content\n")

    recipe_dir = home / "recipes" / "cooking"
    recipe_dir.mkdir(parents=True)
    _ = (recipe_dir / "pasta.md").write_text("# Pasta\n\nBoil water.\n")

    config = {
        "search_engine": "rg",
        "home": str(home),
        "screensaver": False,
        "link_color": "#0000ff",
        "todo_markers": ["TODO"],
        "onhold_markers": ["ONHOLD"],
        "urgent_markers": ["URGENT"],
        "delegate_markers": ["DELEGATE"],
        "question_markers": ["QUESTION"],
        "due_markers": ["DUE"],
    }
    _ = (home / "config.json").write_text(json.dumps(config))

    return home


# ---------------------------------------------------------------------------
# Acceptance-test fixtures (T16): a richer notes tree + a booted TestClient.
#
# `notes_home` above is deliberately minimal and shared with the leaf-module
# unit tests — its shape must not change. The acceptance suite needs a
# superset (checkbox bullets that actually match the `* [ ]` render regex,
# a redaction section, TOC headings, binary/downloadable assets, a pygments
# source file, plus journal entries for *today*/*yesterday* so the alias
# routes resolve regardless of the wall-clock date), so it gets its own tree.
# ---------------------------------------------------------------------------


@pytest.fixture
def acceptance_home(tmp_path: Path) -> Path:
    """A comprehensive notes tree exercising every route the app serves."""
    home = tmp_path

    def write(rel: str, text: str) -> None:
        p = home / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        _ = p.write_text(text)

    # Journal entries spanning a month boundary.
    write("journal/2026/06/2026-06-29.md", "# 2026-06-29\n\nJune content.\n")
    write("journal/2026/06/2026-06-30.md", "# 2026-06-30\n\nEnd of June.\n")
    write("journal/2026/07/2026-07-02.md", "# 2026-07-02\n\nSecond of July.\n")

    # The headline journal page: TOC headings, checkboxes, a tag, an ordinal,
    # and a redaction section that must be hidden.
    write(
        "journal/2026/07/2026-07-01.md",
        """\
# 2026-07-01

## Tasks

* [ ] open task
* [x] done task

Reported a @bug on the 1st of July.

## Secret !!redacted

super secret data

## Public Again

visible tail text
""",
    )

    # Journal entries for today/yesterday so the aliases resolve on any date.
    today = date.today()
    yesterday = today - timedelta(days=1)
    for d in (today, yesterday):
        write(
            f"journal/{d:%Y}/{d:%m}/{d.isoformat()}.md",
            f"# {d.isoformat()}\n\nDay content for {d.isoformat()}.\n",
        )

    # Todos: uses the `* [ ]` bullet the checkbox render regex requires.
    write(
        "journal/todos.md",
        "# TODO\n\n* [ ] first todo\n* [x] second todo\n",
    )

    # Assets: an image (served inline), a PDF (application/* -> download),
    # and a plain text asset.
    (home / "assets" / "2026" / "07" / "01").mkdir(parents=True, exist_ok=True)
    _ = (home / "assets/2026/07/01/photo.png").write_bytes(b"\x89PNG\r\n\x1a\nfakedata")
    _ = (home / "assets/2026/07/01/report.pdf").write_bytes(b"%PDF-1.4 fake pdf")
    write("assets/2026/07/01/note.txt", "plain asset text\n")

    # Recipes: a markdown recipe (with a fenced code block for pygments) and
    # a source file that relies on a vim modeline for its lexer.
    write(
        "recipes/cooking/pasta.md",
        "# Pasta\n\n## Ingredients\n\nBoil water.\n\n```python\nprint('hi')\n```\n",
    )
    write("recipes/db/schema.sql", "-- vim: ft=pgsql\nSELECT * FROM foo;\n")

    # A top-level non-markdown file, served by the catch-all route.
    write("scratch.txt", "scratch file body\n")

    config = {
        "search_engine": "rg",
        "home": str(home),
        "screensaver": False,
        "link_color": "#0000ff",
        "todo_markers": ["TODO"],
        "onhold_markers": ["ONHOLD"],
        "urgent_markers": ["URGENT"],
        "delegate_markers": ["DELEGATE"],
        "question_markers": ["QUESTION"],
        "due_markers": ["DUE"],
    }
    _ = (home / "config.json").write_text(json.dumps(config))

    return home


@pytest.fixture
def client(acceptance_home: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[object]:
    """A booted `TestClient` over the acceptance tree.

    `base_url` is `http://localhost` so the app's localhost-only guard admits
    the request (it keys off the `Host` header, matching the legacy
    `is_localhost` check).
    """
    monkeypatch.setenv("AWIWI_HOME", str(acceptance_home))
    from fastapi.testclient import TestClient

    from awiwi.app import create_app

    app = create_app()
    with TestClient(app, base_url="http://localhost") as test_client:
        yield test_client
