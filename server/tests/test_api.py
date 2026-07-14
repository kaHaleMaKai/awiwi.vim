"""Acceptance tests for the JSON API payload builders (`awiwi.docs`).

Exercises `build_doc_payload`, `build_journal_payload`, `build_dir_payload`
against the acceptance contract from the T23.1 design brief: journal payload
with nav+toc+checkbox html, asset image payload with journal_date+raw_url,
drawio, text file (with a best-effort language hint), binary, secret
blanking (and its localhost bypass), dir payload, watch_path posix-relative,
mtime_ns present.

Reuses the shared `notes_home`/`acceptance_home` fixtures from `conftest.py`
(untouched -- out of this subtask's boundary) where their shape fits;
builds small bespoke trees via the builtin `tmp_path` fixture for cases
those trees don't cover (drawio, genuinely non-UTF-8 binary, a secret-named
file).
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

from awiwi.docs import build_dir_payload, build_doc_payload, build_journal_payload


class TestJournalPayload:
    def test_nav_toc_and_checkbox_html(self, acceptance_home: Path) -> None:
        doc = build_journal_payload("2026-07-01", acceptance_home, is_localhost=True)
        assert doc is not None

        assert doc.kind == "markdown"
        assert doc.doc_type == "journal"
        assert doc.is_secret is False

        # Checkbox lines rendered as real <input> elements with the same
        # hash contract PATCH /checkbox already understands.
        assert doc.html is not None
        assert 'class="awiwi-checkbox"' in doc.html
        assert 'data-hash="' in doc.html
        # @bug tag span.
        assert 'class="awiwi-bug"' in doc.html
        # Redacted section hidden, not leaked into the body.
        assert "super secret data" not in doc.html
        # H1 title line extracted, not duplicated into the body.
        assert "<h1" not in doc.html

        assert doc.toc is not None
        assert "Tasks" in doc.toc

        # Nearest neighbors in the fixture's journal tree, independent of
        # wall-clock "today"/"yesterday" entries also present.
        assert doc.nav is not None
        assert doc.nav.prev == "2026-06-30"
        assert doc.nav.next == "2026-07-02"

        assert doc.watch_path == "journal/2026/07/2026-07-01.md"
        assert "\\" not in doc.watch_path
        assert doc.mtime_ns > 0
        assert doc.journal_date is None
        assert len(doc.breadcrumbs) > 0

    def test_today_alias_resolves(self, acceptance_home: Path) -> None:
        today = date.today()
        doc = build_journal_payload(
            "today", acceptance_home, is_localhost=True, today=today
        )
        assert doc is not None
        assert doc.watch_path == f"journal/{today:%Y}/{today:%m}/{today.isoformat()}.md"

    def test_unparseable_date_returns_none(self, acceptance_home: Path) -> None:
        assert (
            build_journal_payload("not-a-date", acceptance_home, is_localhost=True)
            is None
        )

    def test_missing_journal_file_raises(self, acceptance_home: Path) -> None:
        # Well-formed date, no file on disk for it -- propagates like the
        # legacy `journal` route (caught by the app's 404 handler upstream).
        with pytest.raises(FileNotFoundError):
            _ = build_journal_payload("2099-01-01", acceptance_home, is_localhost=True)


class TestDocPayloadAssetImage:
    def test_image_journal_date_and_raw_url(self, acceptance_home: Path) -> None:
        path = acceptance_home / "assets" / "2026" / "07" / "01" / "photo.png"
        doc = build_doc_payload(path, acceptance_home, is_localhost=True)

        assert doc.kind == "image"
        assert doc.doc_type == "asset"
        assert doc.journal_date == "2026-07-01"
        assert doc.raw_url == "/api/raw/assets/2026/07/01/photo.png"
        assert doc.html is None
        assert doc.text is None
        assert doc.watch_path == "assets/2026/07/01/photo.png"
        assert doc.mtime_ns > 0
        assert doc.nav is None  # nav is journal-pages-only


class TestDocPayloadKindDispatch:
    def test_drawio_returns_raw_xml_as_text(self, tmp_path: Path) -> None:
        home = tmp_path
        recipe_dir = home / "recipes"
        recipe_dir.mkdir()
        xml = "<mxfile><diagram>hello</diagram></mxfile>"
        _ = (recipe_dir / "diagram.drawio").write_text(xml)

        doc = build_doc_payload(recipe_dir / "diagram.drawio", home, is_localhost=True)

        assert doc.kind == "drawio"
        assert doc.doc_type == "recipe"
        assert doc.text == xml
        assert doc.html is None
        assert doc.raw_url is None

    def test_text_file_gets_language_hint(self, acceptance_home: Path) -> None:
        path = acceptance_home / "recipes" / "db" / "schema.sql"
        doc = build_doc_payload(path, acceptance_home, is_localhost=True)

        assert doc.kind == "text"
        assert doc.doc_type == "recipe"
        assert doc.text is not None
        assert "SELECT" in doc.text
        assert doc.html is None
        # Best-effort hint: some lexer alias, exact value not pinned (see
        # docs.py:_guess_language -- ambiguous SQL-lexer registrations mean
        # pygments' pick isn't a stable contract worth asserting on).
        assert doc.language is not None

    def test_binary_non_utf8_file(self, tmp_path: Path) -> None:
        home = tmp_path
        assets_dir = home / "assets" / "2026" / "07" / "01"
        assets_dir.mkdir(parents=True)
        blob = assets_dir / "payload.bin"
        _ = blob.write_bytes(b"\xff\xfe\x01\x02\x03")

        doc = build_doc_payload(blob, home, is_localhost=True)

        assert doc.kind == "binary"
        assert doc.doc_type == "asset"
        assert doc.text is None
        assert doc.html is None
        assert doc.raw_url == "/api/raw/assets/2026/07/01/payload.bin"


class TestSecretGate:
    def test_secret_file_blanked_off_localhost(self, tmp_path: Path) -> None:
        home = tmp_path
        recipe_dir = home / "recipes"
        recipe_dir.mkdir()
        _ = (recipe_dir / "credentials.md").write_text("# creds\n\napi key: xyz\n")

        doc = build_doc_payload(recipe_dir / "credentials.md", home, is_localhost=False)

        assert doc.is_secret is True
        assert doc.html is None
        assert doc.toc is None
        assert doc.text is None
        assert doc.language is None
        assert doc.raw_url is None
        # Metadata is not itself sensitive and stays populated.
        assert doc.kind == "markdown"
        assert doc.doc_type == "recipe"
        assert doc.watch_path == "recipes/credentials.md"
        assert doc.mtime_ns > 0

    def test_secret_file_visible_on_localhost(self, tmp_path: Path) -> None:
        home = tmp_path
        recipe_dir = home / "recipes"
        recipe_dir.mkdir()
        _ = (recipe_dir / "credentials.md").write_text("# creds\n\napi key: xyz\n")

        doc = build_doc_payload(recipe_dir / "credentials.md", home, is_localhost=True)

        assert doc.is_secret is True
        assert doc.html is not None
        assert "api key: xyz" in doc.html


class TestDirPayload:
    def test_root_listing(self, notes_home: Path) -> None:
        payload = build_dir_payload("", notes_home)

        assert payload.breadcrumbs == []
        names = {e.name for e in payload.entries}
        assert names == {"assets", "journal", "recipes"}
        for entry in payload.entries:
            assert entry.is_dir is True
            assert "/" not in entry.relpath  # top-level, single segment

    def test_journal_top_level(self, notes_home: Path) -> None:
        payload = build_dir_payload("journal", notes_home)
        by_name = {e.name: e for e in payload.entries}

        assert "2026" in by_name
        assert by_name["2026"].is_dir is True
        assert by_name["2026"].doc_type == "journal"
        assert by_name["2026"].relpath == "journal/2026"

        assert "todo" in by_name
        assert by_name["todo"].is_dir is False
        assert by_name["todo"].relpath == "journal/todos.md"

    def test_journal_year_shows_month_names(self, notes_home: Path) -> None:
        payload = build_dir_payload("journal/2026", notes_home)
        names = {e.name for e in payload.entries}
        assert names == {"June", "July"}

    def test_journal_month_shows_iso_dates(self, notes_home: Path) -> None:
        payload = build_dir_payload("journal/2026/07", notes_home)
        entries = {e.name: e for e in payload.entries}

        assert "2026-07-01" in entries
        assert entries["2026-07-01"].relpath == "journal/2026/07/2026-07-01.md"
        assert entries["2026-07-01"].doc_type == "journal"
        assert "2026-07-02" in entries

        assert len(payload.breadcrumbs) == 3
        assert payload.breadcrumbs[-1].name == "07"

    def test_assets_day_listing(self, notes_home: Path) -> None:
        payload = build_dir_payload("assets/2026/07/01", notes_home)
        names = {e.name for e in payload.entries}
        assert "x.txt" in names
        entry = next(e for e in payload.entries if e.name == "x.txt")
        assert entry.doc_type == "asset"
        assert entry.relpath == "assets/2026/07/01/x.txt"

    def test_recipes_listing(self, notes_home: Path) -> None:
        payload = build_dir_payload("recipes/cooking", notes_home)
        names = {e.name for e in payload.entries}
        assert "pasta.md" in names
        entry = next(e for e in payload.entries if e.name == "pasta.md")
        assert entry.doc_type == "recipe"
        assert entry.relpath == "recipes/cooking/pasta.md"
