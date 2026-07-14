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

S23.2 additionally exercises the `/api/*` JSON routes end-to-end via the
`client` fixture (a booted `TestClient`, see `conftest.py`), same pattern as
`test_acceptance.py`.
"""

# The Starlette TestClient delegates to httpx, whose Response accessors
# basedpyright resolves as Unknown; silence those (only) file-wide rather
# than per-line across every request assertion (matches test_acceptance.py).
# pyright: reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false
from __future__ import annotations

import shutil
from collections.abc import Iterator
from datetime import date
from pathlib import Path
from typing import cast

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from awiwi.checkbox import hash_line
from awiwi.docs import build_dir_payload, build_doc_payload, build_journal_payload
from awiwi.watch import DocWatcher

# `client` is typed as `object` in conftest to avoid importing TestClient
# there; re-narrow here for the type checker (matches test_acceptance.py).
Client = TestClient


def _watcher(client: Client) -> DocWatcher:
    """`client.app` is typed as the general ASGI-app union (basedpyright
    resolves it to callables like `FunctionType`/`_WrapASGI2` with no
    `.state`), not the concrete `FastAPI` instance `conftest.client` actually
    boots -- narrow it once here rather than at every `TestApiWebsocket`
    call site."""
    return cast(FastAPI, client.app).state.watcher  # pyright: ignore[reportAny]


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
        # Redacted section: default (non-remote) builder call embeds the
        # original body escaped inside an obscured `.redacted` wrapper
        # instead of stripping it; gating itself is pinned by
        # TestRedactionEmbedGating below.
        assert '<div class="redacted">' in doc.html
        assert "super secret data" in doc.html
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


class TestRedactionEmbedGating:
    """S23.4: `build_doc_payload`/`build_journal_payload` pass
    `embed_redacted=True` into `render_markdown` only when their
    `allow_remote` kwarg is `False` (the default, matching
    `Settings.allow_remote`'s own localhost-only-by-default) -- gated at
    build time, independent of the per-request `is_localhost` (which stays
    reserved for the unrelated secret-*file* blanking). `allow_remote=True`
    keeps the old stripping behavior -- redacted values must never reach a
    deployment that admits non-localhost clients. The fixture's
    2026-07-01 journal page carries a `!!redacted` section containing
    "super secret data"."""

    def test_default_embeds_redacted_section(self, acceptance_home: Path) -> None:
        doc = build_journal_payload("2026-07-01", acceptance_home, is_localhost=True)
        assert doc is not None
        assert doc.html is not None
        assert '<div class="redacted">' in doc.html
        assert "super secret data" in doc.html

    def test_default_doc_builder_embeds_too(self, acceptance_home: Path) -> None:
        path = acceptance_home / "journal" / "2026" / "07" / "2026-07-01.md"
        doc = build_doc_payload(path, acceptance_home, is_localhost=True)
        assert doc.html is not None
        assert '<div class="redacted">' in doc.html
        assert "super secret data" in doc.html

    def test_allow_remote_strips_redacted_values_from_journal_payload(
        self, acceptance_home: Path
    ) -> None:
        doc = build_journal_payload(
            "2026-07-01", acceptance_home, is_localhost=True, allow_remote=True
        )
        assert doc is not None
        assert doc.html is not None
        assert "super secret data" not in doc.html
        assert '<div class="redacted">' not in doc.html
        # The stripped placeholder wording is still there.
        assert "redacted" in doc.html

    def test_allow_remote_strips_redacted_values_from_doc_payload(
        self, acceptance_home: Path
    ) -> None:
        path = acceptance_home / "journal" / "2026" / "07" / "2026-07-01.md"
        doc = build_doc_payload(
            path, acceptance_home, is_localhost=True, allow_remote=True
        )
        assert doc.html is not None
        assert "super secret data" not in doc.html
        assert '<div class="redacted">' not in doc.html
        assert "redacted" in doc.html

    def test_allow_remote_env_var_strips_without_explicit_kwarg(
        self, acceptance_home: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Requirement S23.4/3 end-to-end: the live /api routes call the
        # builders *without* an `allow_remote` kwarg, so the default must
        # mirror the deployment's actual AWIWI_ALLOW_REMOTE setting -- a
        # remote-admitting server keeps the old stripping behavior.
        monkeypatch.setenv("AWIWI_ALLOW_REMOTE", "1")
        doc = build_journal_payload("2026-07-01", acceptance_home, is_localhost=True)
        assert doc is not None
        assert doc.html is not None
        assert "super secret data" not in doc.html
        assert '<div class="redacted">' not in doc.html

    def test_unset_env_var_embeds_without_explicit_kwarg(
        self, acceptance_home: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("AWIWI_ALLOW_REMOTE", raising=False)
        doc = build_journal_payload("2026-07-01", acceptance_home, is_localhost=True)
        assert doc is not None
        assert doc.html is not None
        assert '<div class="redacted">' in doc.html
        assert "super secret data" in doc.html


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
        # Best-effort hint: the vim-modeline sniff resolves the `pgsql`
        # alias via `mdrender.LEXER_MAP` (see `mdrender.guess_language`).
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


# ---------------------------------------------------------------------------
# S23.2: `/api/*` JSON route tests. `client` (from conftest.py) is a
# `TestClient` booted over `acceptance_home`, hitting the app as a real
# localhost request (base_url="http://localhost"). Secret-file and
# non-localhost behavior needs its own small tree + a client that flips the
# `Host` header per-request (see `remote_client` below), since the shared
# `acceptance_home` fixture has no secret-named file and the shared `client`
# fixture always looks like localhost.
# ---------------------------------------------------------------------------


@pytest.fixture
def remote_client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[Client]:
    """A `TestClient` with `AWIWI_ALLOW_REMOTE=1` (so the app-wide 403 guard
    doesn't block us) over a small tree with a secret-named recipe. Tests
    flip the effective `is_localhost()` outcome per-request by overriding
    the `Host` header (`is_localhost` keys off it), rather than booting two
    separate apps."""
    home = tmp_path
    (home / "journal").mkdir(parents=True)
    _ = (home / "journal" / "todos.md").write_text("# TODO\n\n* [ ] first\n")
    (home / "recipes").mkdir(parents=True)
    _ = (home / "recipes" / "credentials.md").write_text("# creds\n\napi key: xyz\n")
    _ = (home / "recipes" / "plain.md").write_text("# Plain\n\nnothing secret.\n")

    monkeypatch.setenv("AWIWI_HOME", str(home))
    monkeypatch.setenv("AWIWI_ALLOW_REMOTE", "1")
    from fastapi.testclient import TestClient

    from awiwi.app import create_app

    app = create_app()
    with TestClient(app, base_url="http://example.com") as test_client:
        yield test_client


class TestApiJournal:
    def test_journal_payload_shape(self, client: Client) -> None:
        resp = client.get("/api/journal/2026-07-01")
        assert resp.status_code == 200
        data = resp.json()
        assert data["kind"] == "markdown"
        assert data["doc_type"] == "journal"
        assert 'class="awiwi-checkbox"' in data["html"]
        assert data["nav"] == {"prev": "2026-06-30", "next": "2026-07-02"}
        assert data["watch_path"] == "journal/2026/07/2026-07-01.md"
        assert data["is_secret"] is False

    def test_today_alias_resolves(self, client: Client) -> None:
        resp = client.get("/api/journal/today")
        assert resp.status_code == 200
        today = date.today()
        assert (
            resp.json()["watch_path"]
            == f"journal/{today:%Y}/{today:%m}/{today.isoformat()}.md"
        )

    def test_invalid_date_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/journal/not-a-date")
        assert resp.status_code == 404
        assert "detail" in resp.json()

    def test_wellformed_but_missing_date_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/journal/2099-01-01")
        assert resp.status_code == 404
        assert "detail" in resp.json()


class TestApiTodo:
    def test_todo_payload(self, client: Client) -> None:
        resp = client.get("/api/todo")
        assert resp.status_code == 200
        data = resp.json()
        assert data["doc_type"] == "journal"
        assert data["kind"] == "markdown"
        assert 'class="awiwi-checkbox"' in data["html"]
        assert data["watch_path"] == "journal/todos.md"


class TestApiDoc:
    def test_doc_markdown_by_relpath(self, client: Client) -> None:
        resp = client.get("/api/doc/recipes/cooking/pasta.md")
        assert resp.status_code == 200
        data = resp.json()
        assert data["kind"] == "markdown"
        assert data["doc_type"] == "recipe"
        assert data["watch_path"] == "recipes/cooking/pasta.md"

    def test_doc_image_has_raw_url(self, client: Client) -> None:
        resp = client.get("/api/doc/assets/2026/07/01/photo.png")
        assert resp.status_code == 200
        data = resp.json()
        assert data["kind"] == "image"
        assert data["doc_type"] == "asset"
        assert data["journal_date"] == "2026-07-01"
        assert data["raw_url"] == "/api/raw/assets/2026/07/01/photo.png"

    def test_doc_missing_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/doc/recipes/nope.md")
        assert resp.status_code == 404
        assert "detail" in resp.json()

    def test_doc_traversal_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/doc/%2e%2e/%2e%2e/etc/passwd")
        assert resp.status_code == 404

    def test_doc_secret_blanked_when_not_localhost(self, remote_client: Client) -> None:
        resp = remote_client.get("/api/doc/recipes/credentials.md")
        assert resp.status_code == 200
        data = resp.json()
        assert data["is_secret"] is True
        assert data["html"] is None
        assert data["text"] is None
        assert data["raw_url"] is None

    def test_doc_secret_visible_on_localhost(self, remote_client: Client) -> None:
        resp = remote_client.get(
            "/api/doc/recipes/credentials.md", headers={"host": "localhost"}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["is_secret"] is True
        assert data["html"] is not None
        assert "api key: xyz" in data["html"]


class TestApiDir:
    def test_dir_root(self, client: Client) -> None:
        resp = client.get("/api/dir")
        assert resp.status_code == 200
        data = resp.json()
        assert data["breadcrumbs"] == []
        names = {e["name"] for e in data["entries"]}
        assert {"journal", "assets", "recipes"} <= names

    def test_dir_subpath(self, client: Client) -> None:
        resp = client.get("/api/dir/journal")
        assert resp.status_code == 200
        by_name = {e["name"]: e for e in resp.json()["entries"]}
        assert "todo" in by_name
        assert by_name["todo"]["relpath"] == "journal/todos.md"

    def test_dir_missing_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/dir/no-such-dir")
        assert resp.status_code == 404
        assert "detail" in resp.json()

    def test_dir_traversal_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/dir/%2e%2e/%2e%2e/etc")
        assert resp.status_code == 404


class TestApiMeta:
    def test_meta_shape(self, client: Client) -> None:
        resp = client.get("/api/meta")
        assert resp.status_code == 200
        data = resp.json()
        assert data["today"] == date.today().isoformat()
        assert isinstance(data["home"], str) and data["home"]
        assert isinstance(data["version"], str) and data["version"]


class TestApiRaw:
    def test_raw_serves_bytes_with_etag(self, client: Client) -> None:
        resp = client.get("/api/raw/scratch.txt")
        assert resp.status_code == 200
        assert resp.content == b"scratch file body\n"
        etag = resp.headers.get("etag")
        assert etag is not None
        assert etag.startswith('"') and etag.endswith('"')

    def test_raw_conditional_get_returns_304(self, client: Client) -> None:
        first = client.get("/api/raw/scratch.txt")
        etag = first.headers["etag"]
        second = client.get("/api/raw/scratch.txt", headers={"if-none-match": etag})
        assert second.status_code == 304
        assert second.content == b""

    def test_raw_download_sets_content_disposition(self, client: Client) -> None:
        resp = client.get("/api/raw/assets/2026/07/01/report.pdf?download=1")
        assert resp.status_code == 200
        disposition = resp.headers.get("content-disposition", "")
        assert "attachment" in disposition
        assert "report.pdf" in disposition

    def test_raw_missing_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/raw/nope.txt")
        assert resp.status_code == 404
        assert "detail" in resp.json()

    def test_raw_traversal_is_404_json(self, client: Client) -> None:
        resp = client.get("/api/raw/%2e%2e/%2e%2e/etc/passwd")
        assert resp.status_code == 404

    def test_raw_secret_is_403_off_localhost(self, remote_client: Client) -> None:
        resp = remote_client.get("/api/raw/recipes/credentials.md")
        assert resp.status_code == 403

    def test_raw_secret_allowed_on_localhost(self, remote_client: Client) -> None:
        resp = remote_client.get(
            "/api/raw/recipes/credentials.md", headers={"host": "localhost"}
        )
        assert resp.status_code == 200
        assert b"api key" in resp.content


class TestApiCheckbox:
    def test_toggle_success_returns_200_with_hash_and_mtime(self, client: Client) -> None:
        line = "* [ ] first todo"
        body = {
            "path": "journal/todos.md",
            "line_no": 2,
            "line_hash": hash_line(line),
            "checked": True,
        }
        resp = client.patch("/api/checkbox", json=body)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["line_hash"] == hash_line(line)
        assert data["mtime_ns"] > 0

    def test_hash_mismatch_is_409(self, client: Client) -> None:
        body = {
            "path": "journal/todos.md",
            "line_no": 2,
            "line_hash": "deadbeef",
            "checked": True,
        }
        resp = client.patch("/api/checkbox", json=body)
        assert resp.status_code == 409

    def test_missing_file_is_404(self, client: Client) -> None:
        body = {
            "path": "journal/does-not-exist.md",
            "line_no": 0,
            "line_hash": "whatever",
            "checked": True,
        }
        resp = client.patch("/api/checkbox", json=body)
        assert resp.status_code == 404

    def test_line_past_end_of_file_is_404(self, client: Client) -> None:
        body = {
            "path": "journal/todos.md",
            "line_no": 999,
            "line_hash": "whatever",
            "checked": True,
        }
        resp = client.patch("/api/checkbox", json=body)
        assert resp.status_code == 404

    def test_path_traversal_is_404(self, client: Client) -> None:
        body = {
            "path": "../../etc/passwd",
            "line_no": 0,
            "line_hash": "whatever",
            "checked": True,
        }
        resp = client.patch("/api/checkbox", json=body)
        assert resp.status_code == 404


# ---------------------------------------------------------------------------
# T24: `GET /api/ws` live-sync websocket + the checkbox-PATCH broadcast hook.
#
# `websocket_connect`'s URL is always joined against a hardcoded
# "ws://testserver" host (ignores the client's `base_url`), so every call
# below passes `headers={"host": "localhost"}` explicitly -- otherwise the
# endpoint's own localhost-only re-check (the app-wide HTTP middleware does
# not run for the websocket ASGI scope) would close the connection with
# code 1008 before it's ever accepted.
#
# `client.portal` (an `anyio.abc.BlockingPortal`, set by `TestClient.
# __enter__`) is the *same* event loop the websocket's ASGI task runs on --
# used to invoke `watcher.broadcast(...)` directly (per the design brief)
# from this synchronous test thread without cross-loop hazards.
# ---------------------------------------------------------------------------


class TestApiWebsocket:
    def test_ping_pong(self, client: Client) -> None:
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}

    def test_subscribe_then_direct_broadcast_receives_doc_message(
        self, client: Client
    ) -> None:
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "subscribe", "path": "journal/todos.md"})
            # Round-trip a ping first so we know the server has already
            # processed the subscribe message (single task, in order) before
            # we trigger the broadcast below.
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}

            watcher = _watcher(client)
            assert client.portal is not None
            client.portal.call(watcher.broadcast, "journal/todos.md")

            msg = ws.receive_json()  # pyright: ignore[reportAny]
            assert msg["type"] == "doc"
            assert msg["path"] == "journal/todos.md"
            assert msg["payload"]["watch_path"] == "journal/todos.md"
            assert msg["payload"]["kind"] == "markdown"

    def test_unsubscribe_stops_further_broadcasts(self, client: Client) -> None:
        watcher = _watcher(client)
        assert client.portal is not None
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "subscribe", "path": "journal/todos.md"})
            ws.send_json({"type": "unsubscribe", "path": "journal/todos.md"})
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}
            assert watcher.subscriber_count("journal/todos.md") == 0
            client.portal.call(watcher.broadcast, "journal/todos.md")  # must not raise

    def test_malformed_message_gets_error_not_disconnect(self, client: Client) -> None:
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "bogus"})
            msg = ws.receive_json()  # pyright: ignore[reportAny]
            assert msg["type"] == "error"
            # Socket must still be alive afterwards.
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}

    def test_message_missing_path_gets_error_not_disconnect(self, client: Client) -> None:
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "subscribe"})
            msg = ws.receive_json()  # pyright: ignore[reportAny]
            assert msg["type"] == "error"
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}

    def test_disconnect_drops_all_subscriptions(self, client: Client) -> None:
        watcher = _watcher(client)
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "subscribe", "path": "journal/todos.md"})
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}
            assert watcher.subscriber_count("journal/todos.md") == 1
        # `with` block's __exit__ blocks until the server-side task (incl.
        # its `finally: watcher.drop(...)`) has fully completed.
        assert watcher.subscriber_count("journal/todos.md") == 0

    def test_websocket_refused_when_not_localhost_and_not_allowed(
        self, client: Client
    ) -> None:
        # `client` (acceptance_home, AWIWI_ALLOW_REMOTE unset -> False) with
        # no Host-header override: `websocket_connect` always joins against
        # a hardcoded "ws://testserver" host, i.e. this is a non-localhost
        # handshake by default -- mirrors the app-wide HTTP middleware's own
        # 403 posture, just re-derived at the websocket layer since that
        # middleware itself doesn't run for the websocket ASGI scope.
        from starlette.websockets import WebSocketDisconnect

        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/api/ws"):
                pass

    def test_websocket_admitted_when_allow_remote_set(
        self, remote_client: Client
    ) -> None:
        # `remote_client` sets AWIWI_ALLOW_REMOTE=1; its websocket_connect
        # also defaults to a non-localhost "testserver" Host, so admission
        # here is proof the endpoint honors `allow_remote`, not localhost.
        with remote_client.websocket_connect("/api/ws") as ws:
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}

    def test_checkbox_patch_broadcasts_to_subscribed_socket(self, client: Client) -> None:
        with client.websocket_connect("/api/ws", headers={"host": "localhost"}) as ws:
            ws.send_json({"type": "subscribe", "path": "journal/todos.md"})
            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}  # subscribe processed first

            line = "* [ ] first todo"
            body = {
                "path": "journal/todos.md",
                "line_no": 2,
                "line_hash": hash_line(line),
                "checked": True,
            }
            resp = client.patch("/api/checkbox", json=body)
            assert resp.status_code == 200

            msg = ws.receive_json()  # pyright: ignore[reportAny]
            assert msg["type"] == "doc"
            assert msg["path"] == "journal/todos.md"
            assert msg["payload"]["watch_path"] == "journal/todos.md"


@pytest.mark.skipif(shutil.which("rg") is None, reason="ripgrep not installed")
class TestApiSearch:
    def test_fixed_mode_finds_todo_hits(self, client: Client) -> None:
        resp = client.get("/api/search", params={"q": "first todo"})
        assert resp.status_code == 200
        hits = resp.json()
        assert any(h["type"] == "todo" for h in hits)

    def test_scope_restricts_to_recipes(self, client: Client) -> None:
        resp = client.get("/api/search", params={"q": "Boil", "scope": "recipes"})
        assert resp.status_code == 200
        hits = resp.json()
        assert len(hits) > 0
        assert all(h["type"] == "recipe" for h in hits)

    def test_regex_mode_matches_pattern(self, client: Client) -> None:
        resp = client.get("/api/search", params={"q": "f.rst", "mode": "regex"})
        assert resp.status_code == 200
        hits = resp.json()
        assert any("first" in h["text"] for h in hits)

    def test_fixed_mode_treats_dot_literally(self, client: Client) -> None:
        # In fixed mode "f.rst" must NOT match "first" (the "." isn't a
        # wildcard), proving `-F` actually took effect end-to-end.
        resp = client.get("/api/search", params={"q": "f.rst", "mode": "fixed"})
        assert resp.status_code == 200
        assert resp.json() == []

    def test_empty_query_is_422(self, client: Client) -> None:
        resp = client.get("/api/search", params={"q": ""})
        assert resp.status_code == 422

    def test_invalid_regex_is_400_not_500(self, client: Client) -> None:
        resp = client.get("/api/search", params={"q": "(unclosed", "mode": "regex"})
        assert resp.status_code == 400
        assert "detail" in resp.json()

    def test_invalid_scope_is_422(self, client: Client) -> None:
        resp = client.get("/api/search", params={"q": "x", "scope": "bogus"})
        assert resp.status_code == 422


class TestApiUnknownRoute404sAsJson:
    def test_unknown_api_path_is_json_404_not_html(self, client: Client) -> None:
        resp = client.get("/api/this-route-does-not-exist")
        assert resp.status_code == 404
        assert resp.headers["content-type"].startswith("application/json")
        assert "detail" in resp.json()
