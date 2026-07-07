"""Application assembly: `create_app()` + module-level `app`.

Boot with `uv run uvicorn awiwi.app:app` (with `AWIWI_HOME` set). The lifespan
reads the environment `Settings` and the plugin-written `config.json` once and
stashes them on `app.state`; there is no reload machinery (the plugin only
rewrites `config.json` when it starts a server).

Wiring notes:
- **localhost-only guard** (user decision, replaces legacy login/session):
  non-localhost requests get a 403 before routing.
- **route order**: routers are included assets -> actions -> pages so that
  `pages`' `/{path:path}` catch-all stays the final registered route.
- **StaticFiles** is mounted at `/static` (the templates reference
  `/static/...` verbatim).
- **FileNotFoundError -> 404**: routes raise the builtin (or
  `awiwi.checkbox`/`content` map to it) for missing files; a single handler
  renders `404.html`.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse, Response
from fastapi.staticfiles import StaticFiles

from awiwi.config import PluginConfig, Settings
from awiwi.routers import actions, assets, pages
from awiwi.templating import STATIC_DIR, is_localhost, render


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    settings = Settings()  # pyright: ignore[reportCallIssue]  # AWIWI_HOME from env
    app.state.home = settings.home
    app.state.allow_remote = settings.allow_remote
    app.state.plugin_config = PluginConfig.load(settings.home)
    yield


def create_app() -> FastAPI:
    app = FastAPI(lifespan=lifespan)

    if STATIC_DIR.is_dir():
        app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

    @app.middleware("http")
    async def localhost_only(  # pyright: ignore[reportUnusedFunction]
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        allowed = request.app.state.allow_remote  # pyright: ignore[reportAny]
        if not (allowed or is_localhost(request)):
            return PlainTextResponse("forbidden: localhost only", status_code=403)
        return await call_next(request)

    async def file_not_found(request: Request, exc: Exception) -> Response:
        _ = exc
        return render(request, "404.html", {}, status_code=404)

    app.add_exception_handler(FileNotFoundError, file_not_found)

    app.include_router(assets.router)
    app.include_router(actions.router)
    app.include_router(pages.router)
    return app


app = create_app()
