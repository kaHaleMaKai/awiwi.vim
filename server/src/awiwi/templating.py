"""Jinja2 wiring: template environment, filters, theme cookie, localhost check.

Thin presentation glue over the pure leaf modules. The templates themselves
are copied verbatim from `server.old/html/` (adapted only for Jinja wiring),
so this module reproduces the two pieces of Flask machinery those templates
depended on:

- **autoescape OFF.** Flask's default `select_autoescape` does *not* escape
  the `.j2` extension (only `.html`/`.htm`/`.xml`/`.xhtml`), so the legacy
  templates render `{{ content }}`/`{{ toc }}`/`beautify_if_date` output as
  raw HTML. `Jinja2Templates` defaults autoescape to `True`, which would
  escape the rendered markdown into visible tag soup — so we turn it off to
  match shipped behavior.
- **the `beautify_if_date` filter**, ported from `server.old/app.py`.

`theme_from_cookie` and `is_localhost` port the legacy same-named helpers.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

from fastapi import Request
from fastapi.responses import Response
from fastapi.templating import Jinja2Templates

# server/src/awiwi/templating.py -> parents[1] == server/
_SERVER_ROOT = Path(__file__).resolve().parents[2]
TEMPLATES_DIR = _SERVER_ROOT / "templates"
STATIC_DIR = _SERVER_ROOT / "static"

THEME_MODE_KEY = "awiwi.theme-mode"
_COOKIE_MAX_AGE = 9999999999  # legacy value (server.old/app.py:change_mode)
_LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


def beautify_if_date(value: object, format: str | None = None) -> object:
    """Format a date (or ISO date string) as e.g. `Mon, 1<sup>st</sup>`.

    Ported verbatim from `server.old/app.py:beautify_if_date`, including the
    ordinal-suffix logic and the optional trailing `format` (a strftime
    suffix, used by the journal template for `%B`/`%B %Y`). Anything that
    isn't a date or an ISO-parseable string is returned unchanged — so plain
    directory names and month names in listings pass through untouched.

    The parameter is deliberately named `format` (shadowing the builtin) to
    match the keyword the copied `journal.html.j2` passes
    (`beautify_if_date(format="%B")`).
    """
    if isinstance(value, str):
        try:
            value = date.fromisoformat(value)
        except ValueError:
            return value
    if not isinstance(value, date):
        return value
    days = value.strftime("%d")
    if days.endswith("1"):
        suffix = "st"
    elif days.endswith("2"):
        suffix = "nd"
    elif days.endswith("3"):
        suffix = "rd"
    else:
        suffix = "th"
    month_year = "" if not format else f" {format}"
    return value.strftime(f"%a, %-d<sup>{suffix}</sup>{month_year}")


templates: Jinja2Templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
# Flask's default select_autoescape does NOT escape the `.j2` extension, so the
# copied templates render `{{ content }}`/`{{ toc }}` as raw HTML. Match that
# (Jinja2Templates defaults autoescape on, which would escape the markdown).
templates.env.autoescape = False
templates.env.filters["beautify_if_date"] = beautify_if_date


def theme_from_cookie(request: Request) -> str:
    """Return the effective theme ("light"/"dark") from the request cookie.

    Ported from `server.old/app.py:get_theme_from_cookie`: absent or "light"
    -> "light", anything else -> "dark".
    """
    mode = request.cookies.get(THEME_MODE_KEY)
    if not mode or mode == "light":
        return "light"
    return "dark"


def is_localhost(request: Request) -> bool:
    """Whether the request originates from localhost.

    Ported from `server.old/app.py:is_localhost` (which keyed off the `Host`
    header), extended to also accept a loopback client peer. Used both for
    the app-wide 403 guard and for the secret-file content gate.
    """
    host = request.headers.get("host", "").rsplit(":", 1)[0]
    if host in _LOCAL_HOSTS:
        return True
    client = request.client
    return bool(client and client.host in _LOCAL_HOSTS)


def get_home(request: Request) -> Path:
    """The notes root, stashed on `app.state` by the lifespan (see `app.py`).

    Centralizes the single unavoidable `Any` crossing (`request.app.state` is
    untyped) so route handlers stay strictly typed.
    """
    return request.app.state.home  # pyright: ignore[reportAny]


def render(
    request: Request,
    name: str,
    context: dict[str, object] | None = None,
    status_code: int = 200,
) -> Response:
    """Render `name` with `context`, injecting `theme_mode` from the cookie."""
    ctx: dict[str, object] = dict(context or {})
    _ = ctx.setdefault("theme_mode", theme_from_cookie(request))
    return templates.TemplateResponse(
        request=request, name=name, context=ctx, status_code=status_code
    )
