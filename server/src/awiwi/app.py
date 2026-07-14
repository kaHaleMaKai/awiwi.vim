"""Application assembly: `create_app()` + module-level `app`.

Boot with `uv run uvicorn awiwi.app:app` (with `AWIWI_HOME` set). The lifespan
reads the environment `Settings` and the plugin-written `config.json` once and
stashes them on `app.state`; there is no reload machinery (the plugin only
rewrites `config.json` when it starts a server).

Wiring notes:
- **localhost-only guard** (user decision, replaces legacy login/session):
  non-localhost requests get a 403 before routing.
- **route order** (T26 cutover): routers are included `api -> redirects` so
  the `api` router (with its own `/api/{rest:path}` JSON-404 catch-all) wins
  for anything under `/api/*` before the `redirects` router's app-wide
  `/{path:path}` SPA catch-all can see it.
- **StaticFiles** is mounted at `/_app` over the committed Svelte build
  (`frontend/dist`): the hashed asset URLs the SPA references (`/_app/...`)
  are content-addressed and long-cacheable. `index.html` itself is served
  no-cache by the SPA catch-all (`routers/redirects.py`).
- **FileNotFoundError -> 404 (JSON)**: a stray builtin `FileNotFoundError`
  reaching the app (the `/api/*` routes catch their own) maps to a JSON 404
  rather than a 500.
"""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncGenerator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from fastapi.staticfiles import StaticFiles

from awiwi.config import PluginConfig, Settings
from awiwi.httputil import is_localhost
from awiwi.routers import api, redirects
from awiwi.watch import DocWatcher


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    settings = Settings()  # pyright: ignore[reportCallIssue]  # AWIWI_HOME from env
    app.state.home = settings.home
    app.state.allow_remote = settings.allow_remote
    app.state.plugin_config = PluginConfig.load(settings.home)

    # Live sync (T24): a single DocWatcher instance is THE in-memory
    # subscription registry (see watch.py's module docstring on the
    # single-process constraint). Its fs-watch loop runs as a background
    # task for the app's lifetime; cancelled + awaited cleanly on shutdown.
    watcher = DocWatcher(settings.home)
    app.state.watcher = watcher
    watcher_task = asyncio.create_task(watcher.run())

    try:
        yield
    finally:
        _ = watcher_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await watcher_task


def create_app() -> FastAPI:
    app = FastAPI(lifespan=lifespan)

    # The committed Svelte build: hashed assets under /_app/*, long-cacheable.
    if redirects.DIST_DIR.is_dir():
        app.mount(
            "/_app",
            StaticFiles(directory=str(redirects.DIST_DIR)),
            name="spa_assets",
        )

    @app.middleware("http")
    async def localhost_only(  # pyright: ignore[reportUnusedFunction]
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        allowed = request.app.state.allow_remote  # pyright: ignore[reportAny]
        if not (allowed or is_localhost(request)):
            return PlainTextResponse("forbidden: localhost only", status_code=403)
        return await call_next(request)

    async def file_not_found(request: Request, exc: Exception) -> Response:
        _ = (request, exc)
        return JSONResponse({"detail": "not found"}, status_code=404)

    app.add_exception_handler(FileNotFoundError, file_not_found)

    # api.router's own "/api/{rest:path}" catch-all (its last route) must be
    # reached before redirects.router's app-wide "/{path:path}" SPA catch-all
    # for any /api/* path -- so this include must stay before redirects'.
    app.include_router(api.router)
    app.include_router(redirects.router)
    return app


app = create_app()
