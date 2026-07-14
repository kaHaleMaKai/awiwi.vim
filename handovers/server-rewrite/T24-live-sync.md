# T24 S24.1 — Live sync (filesystem watcher + WebSocket)

## Responsibility

Browsers viewing a doc re-render when the underlying file changes on disk
(nvim writes it), and a checkbox toggle from one tab is pushed to every
other tab looking at the same doc — no polling. Two new pieces:

- `server/src/awiwi/watch.py` (new) — `DocWatcher`: the in-memory
  subscription registry (`watch_path -> {socket, ...}`), the `broadcast()`
  push, and the `watchfiles.awatch`-backed background loop that turns real
  fs events into broadcasts.
- `GET /api/ws` (`server/src/awiwi/routers/api.py`) — the WebSocket endpoint
  browsers connect to; subscribe/unsubscribe per doc, receive `doc`/
  `deleted` pushes.

This is **the** document a frontend engineer (S25.4, the SPA's WS client)
needs to read — written for zero other context.

## Boundary (touched)

- `server/src/awiwi/watch.py` (new) — `DocWatcher`, `SendsJSON` protocol,
  `_is_ignored`.
- `server/src/awiwi/routers/api.py` — added the `/ws` endpoint and three
  small typed helpers (`_get_watcher`, `_get_allow_remote`,
  `_ws_is_localhost`); `api_update_checkbox` now also
  `await`s `watcher.broadcast(path)` after a successful toggle. Every
  existing route is otherwise untouched.
- `server/src/awiwi/app.py` — lifespan now also creates a `DocWatcher` on
  `app.state.watcher`, starts `watcher.run()` as a background task, cancels
  + awaits it on shutdown.
- `server/pyproject.toml` — added `watchfiles`, `websockets` deps.
- `server/tests/test_watch.py` (new, 21 tests) — `DocWatcher` unit tests
  (fake sockets, no real fs watching) + one thin real-fs integration test.
- `server/tests/test_api.py` — new `TestApiWebsocket` class (9 tests):
  ping/pong, subscribe+broadcast, unsubscribe, malformed message, missing
  field, disconnect cleanup, localhost gating (refused/admitted), checkbox
  PATCH broadcast.

**Not touched**: `docs.py`, `schemas.py`, `httputil.py`, `checkbox.py`,
`content.py`, `search.py`, any other router, `conftest.py`, `docs/`.

## The frozen wire protocol

Endpoint: `GET /api/ws` (upgrade), same localhost-only posture as every
other `/api/*` route — **re-derived locally**, because FastAPI's
`@app.middleware("http")` (the app-wide localhost guard in `app.py`) does
**not** run for the `websocket` ASGI scope, only `http`. If the connection
isn't from localhost and `AWIWI_ALLOW_REMOTE` isn't set, the socket is
closed immediately after accept-time checks, before `.accept()`, with close
code `1008` (policy violation) — no HTTP-level 403 is possible for a
websocket upgrade at this layer.

### Client → server messages

All messages are JSON objects with a `"type"` field.

| `type` | Other fields | Effect |
|---|---|---|
| `"subscribe"` | `"path"`: string | Subscribes this socket to that `watch_path` (the same home-relative posix path every `DocPayload.watch_path` carries, e.g. `"journal/2026/07/2026-07-01.md"`). Idempotent — subscribing twice to the same path is a no-op. |
| `"unsubscribe"` | `"path"`: string | Removes this socket's subscription to that path. No-op if not subscribed. |
| `"ping"` | — | Server replies `{"type": "pong"}`. Use this for a liveness check, and (as the test suite does) to know a prior message has already been processed — the server handles one message at a time per socket, in order. |

A client may be subscribed to any number of paths at once (e.g. the doc
currently open, plus doc(s) shown in a sidebar/nav preview).

### Server → client messages

| `type` | Other fields | When |
|---|---|---|
| `"doc"` | `"path"`: string, `"payload"`: full `DocPayload` JSON (same shape as `GET /api/doc/{path}`'s body) | The subscribed doc changed and still exists on disk. Rebuilt fresh via `build_doc_payload` at broadcast time — always the current file content, not a diff. |
| `"deleted"` | `"path"`: string | The subscribed doc no longer exists on disk (or a race meant it couldn't be read). |
| `"pong"` | — | Reply to a client `"ping"`. |
| `"error"` | `"detail"`: string | The client's last message was malformed or unrecognized (see below). The socket is **not** closed — treat this as informational and keep talking. |

### Malformed/unknown messages — never kill the socket

Deliberate choice: anything the server can't parse or doesn't recognize
gets an `{"type": "error", "detail": "..."}` reply, and the connection
stays open. Covers: non-JSON text frames, a JSON value that isn't an
object, an unrecognized `"type"`, and `"subscribe"`/`"unsubscribe"`
missing a string `"path"`. Rationale: a single client-side bug (a stray
message, a version-skewed frontend) should not force a full reconnect —
reconnecting is not free when a client may be subscribed to several paths.

### Reconnect expectations — server keeps no session state

The subscription registry lives entirely in `DocWatcher._subs`, keyed by
the live `WebSocket`/`SendsJSON` object itself — there is no client id, no
session token, nothing persisted. **On disconnect, every subscription that
socket held is dropped** (`DocWatcher.drop`, called from the endpoint's
`finally`). Consequences for the S25.4 frontend WS client:

- After any reconnect (page reload, network blip, server restart), the
  client must re-send `"subscribe"` for every path it cares about — the
  server will not remember.
- Because a broadcast only fires from a *live* fs event or a checkbox PATCH
  that happens while subscribed, a client that was disconnected during a
  change will simply miss that push. **On (re)connect/(re)subscribe, the
  client should independently re-fetch the doc via `GET /api/doc/{path}`
  (or `/api/journal/{date}` etc.) to get current state** — the WS is a
  live-update channel on top of the REST snapshot, not a replacement for
  it, and carries no backlog/replay.

## Single-process constraint

`DocWatcher._subs` is an **in-process, in-memory** dict — it is the entire
subscription registry, full stop. Never run this app with `uvicorn
--workers > 1` (or any other multi-process arrangement, gunicorn workers,
etc.). A second worker process would hold its own independent, empty
registry: a browser whose websocket was accepted by worker A would never
see a broadcast triggered by a file write or checkbox PATCH handled by
worker B. This is already noted in `watch.py`'s module docstring; repeating
it here since it's a hard operational constraint, not an implementation
detail.

## Atomic-write handling

nvim's (and most editors') "safe write" is rename-based: it typically
surfaces to `watchfiles` as a delete+create pair (or assorted temp-file
churn), not a single clean "modified" event. `DocWatcher` sidesteps needing
to reason about the raw event kind at all: **every** surviving fs event
(added/modified/deleted alike) triggers `broadcast(path)`, and
`broadcast`/`_build_message` decide `"doc"` vs `"deleted"` purely by
checking whether the file exists on disk *right now* (`Path.is_file()`) —
never by trusting which `watchfiles.Change` fired. By the time a `deleted`
event for an atomically-replaced file reaches `broadcast()`, the file is
already back, so it resolves to `"doc"`. A genuine deletion still resolves
to `"deleted"`. A further race — `is_file()` says yes but the payload
builder's own read loses the race a moment later — is caught too
(`build_doc_payload` raising `FileNotFoundError` also degrades to
`"deleted"`, never propagates).

Filtered out of `run()`'s event stream entirely (`_is_ignored`): any path
with a dotfile/dotdir component (`.git/`, editor swap files, `.foo`, …) and
`config.json` (the plugin-rewritten server config, not a document).

## Checkbox PATCH → broadcast (deterministic, not fs-watch-dependent)

`PATCH /api/checkbox` (`api_update_checkbox`) calls
`await watcher.broadcast(path)` directly, right after `toggle_checkbox`
succeeds — **not** by relying on the fs watcher to notice its own write.
This means other subscribed tabs update the instant the PATCH response
comes back, with no dependency on `watchfiles`' latency, and it's what
makes `test_checkbox_patch_broadcasts_to_subscribed_socket` deterministic
in tests (no sleep/poll needed for that path — only the one thin real-fs
integration test in `test_watch.py` needs to poll).

## Deviations from the design contract

- **Broadcast payloads always use `is_localhost=True`.** `DocWatcher` has
  no per-subscriber notion of "is this socket a localhost client" (it holds
  bare `SendsJSON`s, deliberately decoupled from Starlette's `WebSocket` so
  the unit tests need no FastAPI import at all). In practice this only
  matters for the one field `build_doc_payload` gates on `is_localhost`
  outside of `allow_remote`/secrecy (see `docs.py`) — flagged here as a
  known simplification, not something the frozen contract explicitly
  required either way. If a future non-localhost-admitted deployment
  (`AWIWI_ALLOW_REMOTE=1`) needs per-connection secret redaction over the
  WS channel too, this is the spot to revisit.
- **Malformed/unknown messages get `{"type": "error"}`, not a closed
  socket** — the contract left this as an explicit either/or; documented
  above under "Malformed/unknown messages."
- **Test-writing gotcha for anyone extending `TestApiWebsocket`**:
  Starlette's `TestClient.websocket_connect()` hardcodes
  `url = urljoin("ws://testserver", url)` — it does **not** honor the
  `TestClient`'s own `base_url`. To exercise the localhost-admitted path in
  a test, pass `headers={"host": "localhost"}` explicitly to
  `websocket_connect()`. To directly trigger a broadcast from synchronous
  test code without a cross-event-loop hazard, use
  `client.portal.call(watcher.broadcast, path)` (`client.portal` is the
  `anyio.BlockingPortal` running the same event loop as the accepted
  websocket's ASGI task) — do **not** `asyncio.run(...)` from the test
  thread, that spins up an unrelated loop.

## What the S25.4 frontend WS client must implement

1. Connect to `GET /api/ws` (same origin/host the REST calls already use).
2. On connect (and on every reconnect), re-`"subscribe"` to every
   `watch_path` currently rendered/open, and re-fetch each via the REST
   endpoint to get a fresh snapshot (no server-side replay/backlog).
3. On navigating away from a doc / closing a tab's view of it, send
   `"unsubscribe"` (optional cleanliness — disconnect alone also drops
   everything, but explicit unsubscribe avoids paying for updates to docs
   no longer shown while the tab is still open for other docs).
4. Handle `"doc"` by re-rendering that `watch_path` from the given
   `payload` (identical shape to the REST `DocPayload` body — no separate
   parsing path needed).
5. Handle `"deleted"` by showing a "this file no longer exists" state (or
   navigating away) for that `watch_path`.
6. Treat `"error"` as non-fatal — log it, keep the connection.
7. Implement its own reconnect-with-backoff; the server does nothing
   special to help resume a session (see "Reconnect expectations" above).

## Test coverage — what's covered where

- `test_watch.py`: registry (`subscribe`/`unsubscribe`/`drop`,
  idempotency, empty-entry cleanup) — 7 tests. `broadcast`/
  `_build_message` including the atomic-write decision, dead-socket
  cleanup, raced `FileNotFoundError`, per-path isolation — 7 tests.
  `_is_ignored` as a pure function — 6 tests. One real-fs integration test
  (`TestRunIntegration`) drives the actual `watchfiles.awatch` loop against
  a real `tmp_path` tree, polling for the broadcast to prove the wiring
  end-to-end — everything else deliberately avoids real fs-watch timing.
- `test_api.py` (`TestApiWebsocket`, 9 tests): ping/pong; subscribe then a
  directly-triggered broadcast is received as a `"doc"` message;
  unsubscribe stops further broadcasts; malformed/missing-field messages
  get `"error"` without disconnecting; disconnect drops all of a socket's
  subscriptions; localhost gating (refused by default host, admitted with
  `AWIWI_ALLOW_REMOTE=1`); a real `PATCH /api/checkbox` triggers a broadcast
  to a subscribed socket.

## Gates (all green)

From `server/`:
- `uv run pytest` → **231 passed** (201 baseline + 21 `test_watch.py` + 9
  new `test_api.py` WS tests).
- `uv run ruff check .` → clean.
- `uv run basedpyright` → **0 errors, 0 warnings, 0 notes** (project-wide).
- `uv run ruff format --check` on every touched file (`watch.py`,
  `routers/api.py`, `app.py`, `pyproject.toml`, `test_watch.py`,
  `test_api.py`) → clean (pre-existing drift in `checkbox.py`, `content.py`,
  `actions.py`, `pages.py`, `conftest.py`, `test_acceptance.py`,
  `test_config.py`, `test_content.py` predates this task and was left
  alone, per prior handovers' convention).
