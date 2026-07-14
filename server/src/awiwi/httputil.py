"""Small HTTP request helpers shared by every router.

Relocated out of the (T27-deleted) `templating.py` (T23.1): neither
`is_localhost` nor `get_home` is a presentation concern -- `is_localhost`
backs the app-wide 403 middleware (`app.py`) *and* the secret-file content
gate (`docs.py`'s payload builders, formerly `routers/pages.py:
render_content_file`); `get_home` is the single `request.app.state.home`
access point every router uses. `templating.py` used to re-export both,
unchanged, as a temporary backward-compat shim for existing imports; that
shim was removed in T27 once nothing imported from it anymore -- no
behavior changed by either move.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import Request

_LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


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
