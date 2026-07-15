"""End-to-end acceptance contract for the assembled FastAPI app.

After the T26 cutover the app is a JSON API (`/api/*`) plus a single-page
Svelte app served from the committed build (`frontend/dist`): a mounted
`/_app/*` static tree of hashed assets, and an app-wide catch-all that serves
`dist/index.html` for every other (non-`/api`) GET so the client-side router
can resolve the view. The legacy Jinja page/asset/action routes are gone; a
small set of legacy 302 redirects survives (so old bookmarks still land on an
SPA-navigable URL).

Each test drives a real HTTP request through the booted app (via the `client`
fixture in conftest.py) and asserts a user-observable outcome:

- page content is asserted against `/api/*` JSON payloads (not rendered HTML);
- the surviving legacy redirects still 302 to their canonical target;
- the checkbox flow uses the relpath `PATCH /api/checkbox` protocol;
- the SPA fallback serves `index.html` for app routes, `/api/*` unknowns 404
  as JSON, and hashed `/_app/*` assets are served.
"""

# The Starlette TestClient delegates to httpx, whose Response accessors
# basedpyright resolves as Unknown; silence those (only) file-wide rather than
# per-line across every request assertion.
# pyright: reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false
from __future__ import annotations

import shutil
from datetime import date, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from awiwi.checkbox import hash_line

# `client` is typed as `object` in conftest to avoid importing TestClient
# there; re-narrow here for the type checker.
Client = TestClient


# 1. Journal page data: body HTML + TOC + prev/next nav, as a DocPayload.
def test_api_journal_payload_toc_and_prevnext(client: Client) -> None:
    resp = client.get("/api/journal/2026-07-01")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["doc_type"] == "journal"
    assert payload["kind"] == "markdown"
    assert "visible tail text" in payload["html"]
    # TOC block from the `## Tasks` / `## Public Again` headings.
    assert payload["toc"] and 'class="toc"' in payload["toc"]
    # prev/next across the month boundary and within July.
    assert payload["nav"]["prev"] == "2026-06-30"
    assert payload["nav"]["next"] == "2026-07-02"


# 2. today/yesterday aliases resolve to the corresponding journal day.
def test_api_journal_today_yesterday_aliases(client: Client) -> None:
    today = date.today().isoformat()
    yesterday = (date.today() - timedelta(days=1)).isoformat()

    resp_today = client.get("/api/journal/today")
    assert resp_today.status_code == 200
    assert f"Day content for {today}" in resp_today.json()["html"]

    resp_yesterday = client.get("/api/journal/yesterday")
    assert resp_yesterday.status_code == 200
    assert f"Day content for {yesterday}" in resp_yesterday.json()["html"]


def test_api_journal_missing_date_404(client: Client) -> None:
    resp = client.get("/api/journal/2099-01-01")
    assert resp.status_code == 404
    assert "application/json" in resp.headers["content-type"]


# 3. Surviving legacy date-URL redirects, kept root-relative (not absolute).
@pytest.mark.parametrize(
    "url",
    [
        "/2026-07-01.md",
        "/07/2026-07-01.md",
        "/2026/07/2026-07-01.md",
        "/journal/2026-07-01.md",
        "/journal/2026/07/2026-07-01.md",
    ],
)
def test_legacy_date_redirects(client: Client, url: str) -> None:
    resp = client.get(url, follow_redirects=False)
    assert resp.status_code in (301, 302, 307, 308)
    location = resp.headers["location"]
    assert location == "/journal/2026-07-01"
    assert not location.startswith("http")  # kept relative


def test_asset_ymd_redirects_to_dashed(client: Client) -> None:
    resp = client.get("/assets/2026/07/01/photo.png", follow_redirects=False)
    assert resp.status_code in (301, 302, 307, 308)
    assert resp.headers["location"] == "/assets/2026-07-01/photo.png"


def test_asset_ymd_dashed_redirects_to_dashed(client: Client) -> None:
    # S33.1: the redundant-dashed-segment alias page URL
    # (`/assets/YYYY/MM/DD/YYYY-MM-DD/file`) also lands on the canonical
    # dashed page URL.
    resp = client.get(
        "/assets/2026/07/01/2026-07-01/photo.png", follow_redirects=False
    )
    assert resp.status_code in (301, 302, 307, 308)
    assert resp.headers["location"] == "/assets/2026-07-01/photo.png"


# S33.1: /api/doc and /api/raw both serve every alias shape stakeholder
# feedback named, alongside the on-disk shape already in use.
@pytest.mark.parametrize(
    "alias_path",
    [
        "assets/2026/07/01/photo.png",  # on-disk shape (already worked)
        "assets/2026-07-01/photo.png",  # dashed public shape
        "assets/2026/07/01/2026-07-01/photo.png",  # redundant dashed segment
    ],
)
def test_api_doc_serves_all_asset_alias_shapes(client: Client, alias_path: str) -> None:
    resp = client.get(f"/api/doc/{alias_path}")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["watch_path"] == "assets/2026/07/01/photo.png"
    assert payload["raw_url"] == "/api/raw/assets/2026/07/01/photo.png"


@pytest.mark.parametrize(
    "alias_path",
    [
        "assets/2026/07/01/photo.png",
        "assets/2026-07-01/photo.png",
        "assets/2026/07/01/2026-07-01/photo.png",
    ],
)
def test_api_raw_serves_all_asset_alias_shapes(client: Client, alias_path: str) -> None:
    resp = client.get(f"/api/raw/{alias_path}")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("image/png")


# 4. /api/todo returns the todos doc with checkbox markup.
def test_api_todo_has_checkboxes(client: Client) -> None:
    resp = client.get("/api/todo")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["doc_type"] == "journal"
    assert 'type="checkbox"' in payload["html"]
    assert "first todo" in payload["html"]


# 5. PATCH /api/checkbox (relpath protocol) flips the glyph on disk, hash-guarded.
def test_api_checkbox_flips_on_disk(client: Client, acceptance_home: Path) -> None:
    todos = acceptance_home / "journal" / "todos.md"
    # line index 2 == "* [ ] first todo" (0:"# TODO", 1:"", 2:...).
    good_hash = hash_line("* [ ] first todo")
    resp = client.patch(
        "/api/checkbox",
        json={
            "path": "journal/todos.md",
            "line_no": 2,
            "line_hash": good_hash,
            "checked": True,
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    # hash echoes back unchanged (box glyph is stripped before hashing).
    assert body["line_hash"] == good_hash
    assert isinstance(body["mtime_ns"], int)
    assert "* [x] first todo" in todos.read_text()


def test_api_checkbox_hash_mismatch_409(client: Client) -> None:
    resp = client.patch(
        "/api/checkbox",
        json={
            "path": "journal/todos.md",
            "line_no": 2,
            "line_hash": "deadbeef",
            "checked": True,
        },
    )
    assert resp.status_code == 409


def test_api_checkbox_missing_line_404(client: Client) -> None:
    resp = client.patch(
        "/api/checkbox",
        json={
            "path": "journal/todos.md",
            "line_no": 999,
            "line_hash": "x",
            "checked": True,
        },
    )
    assert resp.status_code == 404


def test_api_checkbox_missing_file_404(client: Client) -> None:
    resp = client.patch(
        "/api/checkbox",
        json={
            "path": "journal/2099/01/2099-01-01.md",
            "line_no": 0,
            "line_hash": "x",
            "checked": True,
        },
    )
    assert resp.status_code == 404


# 6. Directory listing as a DirPayload at root and a subdirectory.
def test_api_dir_root(client: Client) -> None:
    resp = client.get("/api/dir")
    assert resp.status_code == 200
    names = {e["name"] for e in resp.json()["entries"]}
    assert "journal" in names
    assert "recipes" in names


def test_api_dir_subdir_with_breadcrumbs(client: Client) -> None:
    resp = client.get("/api/dir/journal/2026")
    assert resp.status_code == 200
    payload = resp.json()
    # month dirs are presented by calendar name; the relpath is canonical.
    relpaths = {e["relpath"] for e in payload["entries"]}
    assert "journal/2026/07" in relpaths
    # breadcrumb trail back up to the journal root.
    targets = {c["target"] for c in payload["breadcrumbs"]}
    assert "/dir/journal" in targets


# 7. Asset bytes via /api/raw: mime type + download disposition.
def test_api_raw_image_served_inline(client: Client) -> None:
    resp = client.get("/api/raw/assets/2026/07/01/photo.png")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("image/png")


def test_api_raw_application_download_disposition(client: Client) -> None:
    resp = client.get("/api/raw/assets/2026/07/01/report.pdf", params={"download": 1})
    assert resp.status_code == 200
    assert "attachment" in resp.headers.get("content-disposition", "")


# ETag / conditional-GET round-trip on /api/raw.
def test_api_raw_etag_conditional_304(client: Client) -> None:
    resp = client.get("/api/raw/assets/2026/07/01/photo.png")
    assert resp.status_code == 200
    etag = resp.headers["etag"]
    assert etag
    again = client.get(
        "/api/raw/assets/2026/07/01/photo.png",
        headers={"If-None-Match": etag},
    )
    assert again.status_code == 304


# 8. Recipe markdown render + source-file language hint via /api/doc.
def test_api_doc_recipe_markdown(client: Client) -> None:
    resp = client.get("/api/doc/recipes/cooking/pasta.md")
    assert resp.status_code == 200
    payload = resp.json()
    assert "Boil water" in payload["html"]
    # Clean, Shiki-ready markup -- no server-side CodeHilite/Pygments baked in.
    assert 'class="language-python"' in payload["html"]


def test_api_doc_recipe_source_text_with_language(client: Client) -> None:
    resp = client.get("/api/doc/recipes/db/schema.sql")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["kind"] == "text"
    # modeline `vim: ft=pgsql` -> sql language hint (LEXER_MAP alias).
    assert payload["language"] == "sql"
    assert "SELECT * FROM foo;" in payload["text"]


# 9. !!redacted sections are embedded obscured (localhost, click-revealable),
#    not stripped; the reveal shows the RENDERED section (S32.2) and the
#    section after the redaction still renders.
def test_api_journal_redacted_section_obscured(client: Client) -> None:
    resp = client.get("/api/journal/2026-07-01")
    assert resp.status_code == 200
    html = resp.json()["html"]
    assert 'class="redacted"' in html
    assert "<p>super secret data</p>" in html  # rendered, not escaped raw text
    assert "visible tail text" in html  # section after the redaction resumes


# 10. /api/search: ripgrep-backed, ordered todo->journal->asset->recipe.
@pytest.mark.skipif(shutil.which("rg") is None, reason="ripgrep not installed")
def test_api_search_finds_hits(client: Client) -> None:
    resp = client.get("/api/search", params={"q": "July"})
    assert resp.status_code == 200
    targets = {hit["target"] for hit in resp.json()}
    assert "/journal/2026-07-01" in targets or "/journal/2026-07-02" in targets


def test_api_search_requires_query(client: Client) -> None:
    resp = client.get("/api/search", params={"q": ""})
    assert resp.status_code == 422


# 11. SPA shell + static assets + JSON 404 for unknown /api paths.
def test_spa_fallback_serves_index_html(client: Client) -> None:
    resp = client.get("/journal/2024-01-01")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert 'id="app"' in resp.text
    # served no-cache so a rebuilt dist is always picked up.
    assert "no-cache" in resp.headers.get("cache-control", "")


def test_spa_fallback_serves_root(client: Client) -> None:
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert 'id="app"' in resp.text


def test_app_static_asset_served(client: Client) -> None:
    resp = client.get("/_app/favicon.svg")
    assert resp.status_code == 200


def test_unknown_api_route_404s_as_json(client: Client) -> None:
    resp = client.get("/api/nope")
    assert resp.status_code == 404
    assert "application/json" in resp.headers["content-type"]
    assert "detail" in resp.json()


# 12. localhost-only guard (and the allow-remote override).
def test_non_localhost_is_forbidden(
    acceptance_home: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("AWIWI_HOME", str(acceptance_home))
    from awiwi.app import create_app

    app = create_app()
    with TestClient(app, base_url="http://example.com") as remote:
        resp = remote.get("/", follow_redirects=False)
    assert resp.status_code == 403


def test_allow_remote_env_admits_non_localhost(
    acceptance_home: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # User decision: localhost-only *unless explicitly configured*.
    monkeypatch.setenv("AWIWI_HOME", str(acceptance_home))
    monkeypatch.setenv("AWIWI_ALLOW_REMOTE", "1")
    from awiwi.app import create_app

    app = create_app()
    with TestClient(app, base_url="http://example.com") as remote:
        resp = remote.get("/", follow_redirects=False)
    assert resp.status_code == 200
