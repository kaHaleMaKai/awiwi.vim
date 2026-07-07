"""End-to-end acceptance contract for the assembled FastAPI app (T16).

These are the high-value tests: each one drives a real HTTP request through
the booted app (via the `client` fixture in conftest.py) and asserts a
user-observable outcome from the design brief's 10-item acceptance contract.
They are written before the app/routers exist, so the whole module is RED
until the implementation lands.

Legacy behavior reference: `server.old/app.py`. Domain logic under test lives
in the T13-T15 leaf modules (`awiwi.config`/`content`/`checkbox`/`search`/
`mdrender`); the routers are thin glue, so these tests exercise the glue +
route ordering + redirect/cookie fidelity, not the leaf logic again.
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


# 1. Journal render: body + TOC + prev/next navigation.
def test_journal_render_toc_and_prevnext(client: Client) -> None:
    resp = client.get("/journal/2026-07-01")
    assert resp.status_code == 200
    body = resp.text
    assert "visible tail text" in body
    # TOC block from the `## Tasks` / `## Public Again` headings.
    assert 'class="toc"' in body
    # prev/next links across the month boundary and within July.
    assert "/journal/2026-06-30" in body
    assert "/journal/2026-07-02" in body


# 2. today/yesterday aliases resolve to the corresponding journal day.
def test_journal_today_yesterday_aliases(client: Client) -> None:
    today = date.today().isoformat()
    yesterday = (date.today() - timedelta(days=1)).isoformat()

    resp_today = client.get("/journal/today")
    assert resp_today.status_code == 200
    assert f"Day content for {today}" in resp_today.text

    resp_yesterday = client.get("/journal/yesterday")
    assert resp_yesterday.status_code == 200
    assert f"Day content for {yesterday}" in resp_yesterday.text


# 3. Legacy date-URL redirects, kept root-relative (not absolute).
@pytest.mark.parametrize(
    "url",
    [
        "/2026-07-01.md",
        "/07/2026-07-01.md",
        "/2026/07/2026-07-01.md",
    ],
)
def test_legacy_date_redirects(client: Client, url: str) -> None:
    resp = client.get(url, follow_redirects=False)
    assert resp.status_code in (301, 302, 307, 308)
    location = resp.headers["location"]
    assert location == "/journal/2026-07-01"
    assert not location.startswith("http")  # kept relative


def test_journal_md_suffix_redirect(client: Client) -> None:
    resp = client.get("/journal/2026-07-01.md", follow_redirects=False)
    assert resp.status_code in (301, 302, 307, 308)
    assert resp.headers["location"] == "/journal/2026-07-01"


# 4. /todo renders journal/todos.md with checkbox inputs and no TOC.
def test_todo_renders_checkboxes_without_toc(client: Client) -> None:
    resp = client.get("/todo")
    assert resp.status_code == 200
    body = resp.text
    assert 'type="checkbox"' in body
    assert "first todo" in body
    # add_toc=False -> no TOC block on the todo page.
    assert 'class="toc"' not in body


# 5. PATCH /checkbox flips the glyph on disk, with hash guard.
def test_patch_checkbox_flips_on_disk(client: Client, acceptance_home: Path) -> None:
    todos = acceptance_home / "journal" / "todos.md"
    # line index 2 == "* [ ] first todo" (0:"# TODO", 1:"", 2:...).
    good_hash = hash_line("* [ ] first todo")
    resp = client.patch(
        "/checkbox",
        json={"line_nr": 2, "path": "/todo", "check": True, "hash": good_hash},
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True
    assert "* [x] first todo" in todos.read_text()


def test_patch_checkbox_hash_mismatch_409(client: Client) -> None:
    resp = client.patch(
        "/checkbox",
        json={"line_nr": 2, "path": "/todo", "check": True, "hash": "deadbeef"},
    )
    assert resp.status_code == 409


def test_patch_checkbox_missing_line_404(client: Client) -> None:
    resp = client.patch(
        "/checkbox",
        json={"line_nr": 999, "path": "/todo", "check": True, "hash": "x"},
    )
    assert resp.status_code == 404


def test_patch_checkbox_missing_file_404(client: Client) -> None:
    resp = client.patch(
        "/checkbox",
        json={
            "line_nr": 0,
            "path": "/journal/2099-01-01",
            "check": True,
            "hash": "x",
        },
    )
    assert resp.status_code == 404


# 6. Directory index + breadcrumbs at / and /dir/<path>.
def test_dir_index_root(client: Client) -> None:
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.text
    assert "/dir/journal" in body
    assert "/dir/recipes" in body


def test_dir_index_subdir_with_breadcrumbs(client: Client) -> None:
    resp = client.get("/dir/journal/2026")
    assert resp.status_code == 200
    body = resp.text
    # month directory listed via calendar month name, linking one level down.
    assert "/dir/journal/2026/07" in body
    assert "July" in body
    # breadcrumb trail back up to the journal root.
    assert 'href="/dir/journal"' in body


# 7. Asset serving: mime type, download disposition, and y/m/d -> dashed redirect.
def test_asset_image_served_inline(client: Client) -> None:
    resp = client.get("/assets/2026-07-01/photo.png")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("image/png")


def test_asset_application_is_downloadable(client: Client) -> None:
    resp = client.get("/assets/2026-07-01/report.pdf")
    assert resp.status_code == 200
    assert "attachment" in resp.headers.get("content-disposition", "")


def test_asset_ymd_redirects_to_dashed(client: Client) -> None:
    resp = client.get("/assets/2026/07/01/photo.png", follow_redirects=False)
    assert resp.status_code in (301, 302, 307, 308)
    assert resp.headers["location"] == "/assets/2026-07-01/photo.png"


# 8. Recipe markdown render + pygments source render.
def test_recipe_markdown_render(client: Client) -> None:
    resp = client.get("/recipes/cooking/pasta.md")
    assert resp.status_code == 200
    body = resp.text
    assert "Boil water" in body
    # fenced python block highlighted by codehilite/pygments.
    assert 'class="highlight"' in body


def test_recipe_source_pygments_render(client: Client) -> None:
    resp = client.get("/recipes/db/schema.sql")
    assert resp.status_code == 200
    # modeline `vim: ft=pgsql` -> sql lexer -> pygments highlight container.
    assert 'class="highlight"' in resp.text


# 9. !!redacted sections are hidden from the rendered output.
def test_redacted_section_hidden(client: Client) -> None:
    resp = client.get("/journal/2026-07-01")
    assert resp.status_code == 200
    body = resp.text
    assert "super secret data" not in body
    assert "redacted" in body  # the "_…redacted…_" heading placeholder
    assert "visible tail text" in body  # section after the redaction resumes


# 10. POST /search/content: ripgrep-backed, ordered todo->journal->asset->recipe.
@pytest.mark.skipif(shutil.which("rg") is None, reason="ripgrep not installed")
def test_search_content_orders_hits(client: Client) -> None:
    resp = client.post("/search/content", data={"search-content": "July"})
    assert resp.status_code == 200
    body = resp.text
    # A journal hit for the search term is surfaced with its /journal/ link.
    assert "/journal/2026-07-01" in body or "/journal/2026-07-02" in body


def test_search_content_requires_pattern(client: Client) -> None:
    resp = client.post("/search/content", data={"search-content": ""})
    assert resp.status_code == 400


# 11. /change-mode cookie semantics + path-traversal requests are blocked.
def test_change_mode_resets_cookie_and_redirects_to_referrer(client: Client) -> None:
    client.cookies.set("awiwi.theme-mode", "dark")
    resp = client.get(
        "/change-mode",
        headers={"referer": "/journal/2026-07-01"},
        follow_redirects=False,
    )
    assert resp.status_code in (301, 302, 307, 308)
    assert resp.headers["location"] == "/journal/2026-07-01"
    set_cookie = resp.headers.get("set-cookie", "")
    # Server re-sets (does not toggle) the cookie, with a long max-age.
    assert "awiwi.theme-mode=dark" in set_cookie
    assert "Max-Age" in set_cookie


def test_change_mode_defaults_to_root_without_referrer(client: Client) -> None:
    resp = client.get("/change-mode", follow_redirects=False)
    assert resp.status_code in (301, 302, 307, 308)
    assert resp.headers["location"] == "/"


def test_catch_all_serves_arbitrary_file(client: Client) -> None:
    resp = client.get("/scratch.txt")
    assert resp.status_code == 200
    assert "scratch file body" in resp.text


def test_path_traversal_is_blocked(client: Client) -> None:
    # Encoded `../../etc/passwd`: safe_resolve must refuse to escape home.
    resp = client.get("/%2e%2e%2f%2e%2e%2fetc%2fpasswd", follow_redirects=False)
    assert resp.status_code == 404


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
