"""Filesystem watcher + WebSocket broadcast registry for live doc sync.

`DocWatcher` is the single, in-process, in-memory registry of `watch_path ->
{socket, ...}` subscriptions, plus the filesystem-watching loop
(`watchfiles.awatch`) that turns raw fs events into `doc`/`deleted`
broadcasts pushed over `GET /api/ws` (`routers/api.py`).

See `handovers/server-rewrite/T24-live-sync.md` for the frozen wire
protocol (every message, field-by-field) and design rationale.

**Single-process design**: this in-memory dict IS the subscription
registry -- never run this app with `--workers > 1` (uvicorn) or any other
multi-process arrangement. A second worker process would hold its own
independent, empty registry; a browser subscribed via a websocket accepted
by worker A would never see a broadcast triggered by a file write handled
by worker B.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Protocol

from watchfiles import awatch  # pyright: ignore[reportUnknownVariableType]

from awiwi.docs import build_doc_payload

logger = logging.getLogger(__name__)

# Path segments (anywhere in the relpath) that never surface as doc
# changes: dotdirs/dotfiles (".git", ".mypy_cache", editor swap dirs, a
# leading "." on any component, ...) and the plugin-written config.json
# (rewritten on every `:Awiwi serve` -- not a document).
_IGNORED_NAMES = frozenset({"config.json"})


class SendsJSON(Protocol):
    """Structural minimum `DocWatcher` needs from a "socket" -- satisfied by
    both `starlette.websockets.WebSocket` (`send_json` is part of its real
    API) and the fake test doubles in `tests/test_watch.py`. Kept as a
    `Protocol` (rather than importing `WebSocket` here) so this module has
    no FastAPI/Starlette import and the unit tests can use plain objects."""

    async def send_json(self, data: object) -> None: ...


def _is_ignored(relparts: tuple[str, ...]) -> bool:
    """True if any path segment (already relative to `home`) is a
    dotfile/dotdir or `config.json`."""
    if not relparts:
        return True
    return any(part.startswith(".") or part in _IGNORED_NAMES for part in relparts)


class DocWatcher:
    """In-memory subscription registry + broadcast + fs-watch loop over a
    single notes `home` directory."""

    def __init__(self, home: Path) -> None:
        self.home: Path = home
        self._subs: dict[str, set[SendsJSON]] = {}

    # -- subscription registry -----------------------------------------

    def subscribe(self, path: str, ws: SendsJSON) -> None:
        """Add `ws` to `path`'s subscriber set."""
        self._subs.setdefault(path, set()).add(ws)

    def unsubscribe(self, path: str, ws: SendsJSON) -> None:
        """Remove `ws` from `path`'s subscriber set (no-op if not
        subscribed). Drops the now-empty set entry entirely."""
        subs = self._subs.get(path)
        if subs is None:
            return
        subs.discard(ws)
        if not subs:
            del self._subs[path]

    def drop(self, ws: SendsJSON) -> None:
        """Remove `ws` from every subscription it holds -- call this on
        websocket disconnect (client didn't necessarily unsubscribe from
        everything before going away)."""
        for path in list(self._subs):
            self.unsubscribe(path, ws)

    def subscriber_count(self, path: str) -> int:
        """Test/debug helper: how many sockets are subscribed to `path`."""
        return len(self._subs.get(path, ()))

    # -- broadcast -------------------------------------------------------

    def _build_message(self, path: str) -> dict[str, object]:
        """Pure(-ish) decision, factored out for direct unit testing: `doc`
        (with a freshly built payload, always with `is_localhost=True` --
        see the handover's "WS content trust" note) if the file exists on
        disk right now, `deleted` otherwise.

        This single existence check, performed at broadcast time rather
        than trusting the triggering fs event's own kind, is what absorbs
        the atomic-write case: nvim's rename-based save often surfaces as
        a delete+add pair (or assorted temp-file churn) rather than a
        single clean "modified" event. By the time this runs the file is
        already back on disk for an atomic replace, so a `deleted` fs
        event for a path that in fact still exists still yields a `doc`
        message, never a spurious `deleted`.
        """
        full = self.home / path
        if not full.is_file():
            return {"type": "deleted", "path": path}
        try:
            payload = build_doc_payload(full, self.home, is_localhost=True)
        except FileNotFoundError:
            # Raced: existed a moment ago (the is_file() check above), gone
            # by the time build_doc_payload re-reads it.
            return {"type": "deleted", "path": path}
        return {"type": "doc", "path": path, "payload": payload.model_dump(mode="json")}

    async def broadcast(self, path: str) -> None:
        """Rebuild the doc at `path` and push it to every subscriber of
        that path. No-op if nobody is subscribed (skips the payload build
        entirely). Dead sockets discovered while sending are dropped from
        the registry, never raised -- one broken tab must not crash the
        broadcast for the others."""
        targets = self._subs.get(path)
        if not targets:
            return
        message = self._build_message(path)
        dead: list[SendsJSON] = []
        for ws in list(targets):
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.unsubscribe(path, ws)

    # -- fs watch loop -----------------------------------------------------

    async def run(self) -> None:
        """Watch `home` for filesystem changes and broadcast to whatever
        `watch_path`s are currently subscribed.

        Every surviving event -- added, modified, or deleted alike --
        triggers a `broadcast()` call for its home-relative path;
        `broadcast`/`_build_message`'s own existence check (not the raw
        `watchfiles.Change` kind) is what decides `doc` vs. `deleted`,
        which is what makes atomic-write saves resolve correctly (see
        `_build_message`'s docstring). Cancel the task running this (see
        `app.py`'s lifespan) to stop it -- `watchfiles.awatch` reacts
        cleanly to `asyncio.CancelledError`.
        """
        async for changes in awatch(self.home):
            rels: set[str] = set()
            for _change, raw_path in changes:
                p = Path(raw_path)
                try:
                    relparts = p.relative_to(self.home).parts
                except ValueError:
                    continue
                if _is_ignored(relparts):
                    continue
                rels.add(p.relative_to(self.home).as_posix())
            for rel in rels:
                await self.broadcast(rel)
