"""Unit tests for awiwi.content — pure filesystem/date domain logic.

No FastAPI involved; exercises parse_date, journal prev/next navigation,
breadcrumbs, safe_resolve and directory listing directly against the
`notes_home` fixture tree (see conftest.py).
"""

from datetime import date
from pathlib import Path

from awiwi.content import (
    Breadcrumb,
    find_min_max_paths,
    get_adjacent_journal_file,
    get_prev_and_next_journal,
    list_directory,
    make_breadcrumbs,
    parse_date,
    safe_resolve,
)


class TestParseDate:
    def test_today_alias(self, notes_home: Path):
        assert parse_date("today", notes_home, today=date(2026, 7, 3)) == date(
            2026, 7, 3
        )

    def test_today_alias_case_insensitive(self, notes_home: Path):
        assert parse_date("TODAY", notes_home, today=date(2026, 7, 3)) == date(
            2026, 7, 3
        )

    def test_yesterday_alias(self, notes_home: Path):
        assert parse_date("yesterday", notes_home, today=date(2026, 7, 3)) == date(
            2026, 7, 2
        )

    def test_explicit_iso_date(self, notes_home: Path):
        assert parse_date("2026-07-01", notes_home) == date(2026, 7, 1)

    def test_invalid_date_returns_none(self, notes_home: Path):
        assert parse_date("not-a-date", notes_home) is None

    def test_prev_alias_finds_nearest_earlier_journal(self, notes_home: Path):
        # today (2026-07-03) has no journal file of its own; nearest earlier
        # existing file is 2026-07-02.
        got = parse_date("prev", notes_home, today=date(2026, 7, 3))
        assert got == date(2026, 7, 2)

    def test_previous_alias_is_synonym_for_prev(self, notes_home: Path):
        got = parse_date("previous", notes_home, today=date(2026, 7, 3))
        assert got == date(2026, 7, 2)

    def test_prev_alias_clean_none_when_no_journals_exist(self, tmp_path: Path):
        # Legacy crash case (server.old/app.py parse_date "prev" branch calls
        # datetime.date.fromisoformat(None) and raises TypeError when no
        # journal files exist at all). Assessed behavior: return None so the
        # router can turn this into a clean 404 instead of a 500.
        got = parse_date("prev", tmp_path, today=date(2026, 7, 3))
        assert got is None


class TestFindMinMaxPaths:
    def test_finds_earliest_and_latest_journal_file(self, notes_home: Path):
        journal_root = notes_home / "journal"
        min_path, max_path = find_min_max_paths(journal_root, 3)
        assert min_path is not None
        assert max_path is not None
        assert min_path.name == "2026-06-29.md"
        assert max_path.name == "2026-07-02.md"

    def test_empty_directory_returns_none_none(self, tmp_path: Path):
        empty = tmp_path / "journal"
        empty.mkdir()
        assert find_min_max_paths(empty, 3) == (None, None)

    def test_missing_directory_returns_none_none(self, tmp_path: Path):
        missing = tmp_path / "does-not-exist"
        assert find_min_max_paths(missing, 3) == (None, None)


class TestGetAdjacentJournalFile:
    def test_finds_next_existing_file_forward(self, notes_home: Path):
        journal_root = notes_home / "journal"
        got = get_adjacent_journal_file(date(2026, 6, 30), 5, journal_root)
        assert got == "2026-07-01"

    def test_finds_next_existing_file_backward(self, notes_home: Path):
        journal_root = notes_home / "journal"
        got = get_adjacent_journal_file(date(2026, 7, 1), -5, journal_root)
        assert got == "2026-06-30"

    def test_zero_diff_returns_none(self, notes_home: Path):
        journal_root = notes_home / "journal"
        assert get_adjacent_journal_file(date(2026, 6, 30), 0, journal_root) is None

    def test_no_file_in_range_returns_none(self, notes_home: Path):
        journal_root = notes_home / "journal"
        got = get_adjacent_journal_file(date(2020, 1, 1), 2, journal_root)
        assert got is None


class TestGetPrevAndNextJournal:
    def test_middle_date_crosses_month_boundary(self, notes_home: Path):
        # 2026-06-30 -> prev 2026-06-29 (same month), next 2026-07-01 (next month)
        prev, next_ = get_prev_and_next_journal(date(2026, 6, 30), notes_home)
        assert prev == "2026-06-29"
        assert next_ == "2026-07-01"

    def test_earliest_date_has_no_prev(self, notes_home: Path):
        prev, next_ = get_prev_and_next_journal(date(2026, 6, 29), notes_home)
        assert prev is None
        assert next_ == "2026-06-30"

    def test_latest_date_has_no_next(self, notes_home: Path):
        prev, next_ = get_prev_and_next_journal(date(2026, 7, 2), notes_home)
        assert prev == "2026-07-01"
        assert next_ is None

    def test_no_journals_returns_none_none(self, tmp_path: Path):
        prev, next_ = get_prev_and_next_journal(date(2026, 7, 3), tmp_path)
        assert prev is None
        assert next_ is None


class TestMakeBreadcrumbs:
    def test_nested_journal_file(self, notes_home: Path):
        file = notes_home / "journal" / "2026" / "06" / "2026-06-29.md"
        crumbs = make_breadcrumbs(file, notes_home)
        assert crumbs == [
            Breadcrumb(name="journal", target="/dir/journal"),
            Breadcrumb(name="2026", target="/dir/journal/2026"),
            Breadcrumb(name="06", target="/dir/journal/2026/06"),
        ]

    def test_root_level_file_has_no_breadcrumbs(self, notes_home: Path):
        file = notes_home / "config.json"
        assert make_breadcrumbs(file, notes_home) == []

    def test_include_cur_dir(self, notes_home: Path):
        file = notes_home / "recipes" / "cooking" / "pasta.md"
        crumbs = make_breadcrumbs(file, notes_home, include_cur_dir=True)
        assert crumbs[-1] == Breadcrumb(
            name="pasta", target="/dir/recipes/cooking/pasta.md"
        )


class TestSafeResolve:
    def test_resolves_nested_valid_path(self, notes_home: Path):
        got = safe_resolve("journal/2026/06/2026-06-29.md", notes_home)
        assert got == (notes_home / "journal" / "2026" / "06" / "2026-06-29.md").resolve()

    def test_rejects_dotdot_traversal(self, notes_home: Path):
        assert safe_resolve("../../etc/passwd", notes_home) is None

    def test_rejects_dotdot_traversal_embedded(self, notes_home: Path):
        assert safe_resolve("journal/../../etc/passwd", notes_home) is None

    def test_rejects_absolute_path(self, notes_home: Path):
        assert safe_resolve("/etc/passwd", notes_home) is None

    def test_root_itself_resolves(self, notes_home: Path):
        assert safe_resolve(".", notes_home) == notes_home.resolve()

    def test_accepts_path_object(self, notes_home: Path):
        got = safe_resolve(Path("recipes/cooking/pasta.md"), notes_home)
        assert got == (notes_home / "recipes" / "cooking" / "pasta.md").resolve()


class TestListDirectory:
    def test_lists_sorted_entries(self, notes_home: Path):
        entries = list_directory(notes_home / "journal")
        names = [p.name for p in entries]
        assert names == sorted(names)
        assert "2026" in names
        assert "todos.md" in names

    def test_excludes_dotfiles(self, tmp_path: Path):
        _ = (tmp_path / ".hidden").write_text("secret")
        _ = (tmp_path / "visible.txt").write_text("visible")
        entries = list_directory(tmp_path)
        assert [p.name for p in entries] == ["visible.txt"]
