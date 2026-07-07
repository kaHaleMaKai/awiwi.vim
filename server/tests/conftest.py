"""Shared pytest fixtures for the awiwi server test suite.

`notes_home` builds a minimal-but-representative notes tree matching the
doc-type hierarchy from docs/architecture.md (journal/assets/recipes) plus a
`config.json`, so downstream test modules (content/search/routers) can reuse
one fixture instead of hand-rolling tmp trees.
"""

import json
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
