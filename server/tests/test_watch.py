"""Unit + thin integration tests for `awiwi.watch.DocWatcher` (T24 live sync).

Covers the subscription registry (`subscribe`/`unsubscribe`/`drop`), the
broadcast logic (including the atomic-write decision -- broadcast always
consults live fs state rather than trusting the triggering event kind, see
`DocWatcher._build_message`'s docstring), dead-socket cleanup, and the
`_is_ignored` dotfile/config.json filter as a pure function. One thin
integration test drives the real `watchfiles.awatch` loop (`run()`) against
a real tmp_path tree to prove the wiring end-to-end; everything else is
unit-tested with fake socket doubles (no real fs watching, no timing
flakiness).

No `pytest-asyncio` in this project's dev deps -- async methods are driven
directly via `asyncio.run()` inside otherwise-ordinary sync test functions.
"""

from __future__ import annotations

import asyncio
import contextlib
from pathlib import Path

import pytest

import awiwi.watch as watch_mod
from awiwi.watch import DocWatcher, _is_ignored  # pyright: ignore[reportPrivateUsage]


class FakeSocket:
    """Minimal `SendsJSON` double: records what it's sent, or raises to
    simulate a dead/closed connection."""

    def __init__(self, *, fail: bool = False) -> None:
        self.sent: list[dict[str, object]] = []
        self.fail: bool = fail

    async def send_json(self, data: object) -> None:
        if self.fail:
            raise RuntimeError("socket closed")
        self.sent.append(data)  # pyright: ignore[reportArgumentType]


@pytest.fixture
def home(tmp_path: Path) -> Path:
    (tmp_path / "journal").mkdir()
    _ = (tmp_path / "journal" / "todos.md").write_text("# Todos\n\n* [ ] a\n")
    return tmp_path


# ---------------------------------------------------------------------------
# Subscription registry
# ---------------------------------------------------------------------------


class TestSubscriptionRegistry:
    def test_subscribe_adds_and_counts(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("journal/todos.md", ws)
        assert watcher.subscriber_count("journal/todos.md") == 1

    def test_subscribe_same_path_twice_is_idempotent(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("journal/todos.md", ws)
        watcher.subscribe("journal/todos.md", ws)
        assert watcher.subscriber_count("journal/todos.md") == 1

    def test_unsubscribe_removes_and_cleans_up_empty_entry(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("journal/todos.md", ws)
        watcher.unsubscribe("journal/todos.md", ws)
        assert watcher.subscriber_count("journal/todos.md") == 0
        # The dict entry itself is pruned, not just left as an empty set --
        # otherwise a long-lived server accumulates one dead dict key per
        # unique doc ever subscribed to.
        assert "journal/todos.md" not in watcher._subs  # pyright: ignore[reportPrivateUsage]

    def test_unsubscribe_missing_path_is_noop(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.unsubscribe("nope.md", ws)  # must not raise

    def test_unsubscribe_socket_not_in_set_is_noop(self, home: Path) -> None:
        watcher = DocWatcher(home)
        a, b = FakeSocket(), FakeSocket()
        watcher.subscribe("journal/todos.md", a)
        watcher.unsubscribe("journal/todos.md", b)  # never subscribed
        assert watcher.subscriber_count("journal/todos.md") == 1

    def test_drop_removes_from_every_subscription(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("a.md", ws)
        watcher.subscribe("b.md", ws)
        watcher.drop(ws)
        assert watcher.subscriber_count("a.md") == 0
        assert watcher.subscriber_count("b.md") == 0

    def test_drop_only_affects_the_given_socket(self, home: Path) -> None:
        watcher = DocWatcher(home)
        a, b = FakeSocket(), FakeSocket()
        watcher.subscribe("journal/todos.md", a)
        watcher.subscribe("journal/todos.md", b)
        watcher.drop(a)
        assert watcher.subscriber_count("journal/todos.md") == 1


# ---------------------------------------------------------------------------
# Broadcast (incl. the atomic-write decision)
# ---------------------------------------------------------------------------


class TestBroadcast:
    def test_broadcast_with_no_subscribers_is_noop(self, home: Path) -> None:
        watcher = DocWatcher(home)
        asyncio.run(watcher.broadcast("journal/todos.md"))  # must not raise

    def test_broadcast_sends_doc_message_for_existing_file(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("journal/todos.md", ws)
        asyncio.run(watcher.broadcast("journal/todos.md"))
        assert len(ws.sent) == 1
        msg = ws.sent[0]
        assert msg["type"] == "doc"
        assert msg["path"] == "journal/todos.md"
        payload = msg["payload"]
        assert isinstance(payload, dict)
        assert payload["watch_path"] == "journal/todos.md"
        assert payload["kind"] == "markdown"
        assert 'class="awiwi-checkbox"' in payload["html"]

    def test_broadcast_sends_deleted_message_for_missing_file(self, home: Path) -> None:
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("journal/nope.md", ws)
        asyncio.run(watcher.broadcast("journal/nope.md"))
        assert ws.sent == [{"type": "deleted", "path": "journal/nope.md"}]

    def test_broadcast_reflects_atomic_replace_as_doc_not_deleted(
        self, home: Path
    ) -> None:
        # Simulates nvim's rename-based save: by the time broadcast() runs,
        # the file exists again (was deleted then immediately recreated) --
        # broadcast() takes no event-kind argument at all, it only ever
        # consults live fs state, so this always resolves to "doc".
        watcher = DocWatcher(home)
        ws = FakeSocket()
        target = home / "journal" / "todos.md"
        target.unlink()
        _ = target.write_text("# Todos\n\n* [ ] fresh\n")
        watcher.subscribe("journal/todos.md", ws)
        asyncio.run(watcher.broadcast("journal/todos.md"))
        assert ws.sent[0]["type"] == "doc"

    def test_broadcast_drops_dead_socket_without_raising(self, home: Path) -> None:
        watcher = DocWatcher(home)
        dead = FakeSocket(fail=True)
        alive = FakeSocket()
        watcher.subscribe("journal/todos.md", dead)
        watcher.subscribe("journal/todos.md", alive)
        asyncio.run(watcher.broadcast("journal/todos.md"))  # must not raise
        assert watcher.subscriber_count("journal/todos.md") == 1
        assert len(alive.sent) == 1

    def test_broadcast_handles_raced_filenotfound_from_builder(
        self, home: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # is_file() said the file existed, but build_doc_payload's own
        # Path.read_*() raced and lost -- must degrade to "deleted", not
        # propagate the exception.
        def _boom(*_args: object, **_kwargs: object) -> None:
            raise FileNotFoundError()

        monkeypatch.setattr(watch_mod, "build_doc_payload", _boom)
        watcher = DocWatcher(home)
        ws = FakeSocket()
        watcher.subscribe("journal/todos.md", ws)
        asyncio.run(watcher.broadcast("journal/todos.md"))
        assert ws.sent == [{"type": "deleted", "path": "journal/todos.md"}]

    def test_broadcast_only_notifies_subscribers_of_that_path(self, home: Path) -> None:
        _ = (home / "journal" / "other.md").write_text("# Other\n\nHi.\n")
        watcher = DocWatcher(home)
        subscribed = FakeSocket()
        elsewhere = FakeSocket()
        watcher.subscribe("journal/todos.md", subscribed)
        watcher.subscribe("journal/other.md", elsewhere)
        asyncio.run(watcher.broadcast("journal/todos.md"))
        assert len(subscribed.sent) == 1
        assert elsewhere.sent == []


# ---------------------------------------------------------------------------
# _is_ignored (pure filter function)
# ---------------------------------------------------------------------------


class TestIsIgnored:
    def test_dotdir_component_is_ignored(self) -> None:
        assert _is_ignored((".git", "HEAD"))

    def test_dotfile_is_ignored(self) -> None:
        assert _is_ignored((".todos.md.swp",))

    def test_config_json_is_ignored(self) -> None:
        assert _is_ignored(("config.json",))

    def test_config_json_nested_is_ignored(self) -> None:
        assert _is_ignored(("sub", "config.json"))

    def test_ordinary_doc_path_is_not_ignored(self) -> None:
        assert not _is_ignored(("journal", "2026", "07", "2026-07-01.md"))

    def test_empty_relparts_is_ignored(self) -> None:
        assert _is_ignored(())


# ---------------------------------------------------------------------------
# Thin integration test: the real watchfiles.awatch loop, end to end.
#
# Everything else above is unit-tested with fake sockets and no real fs
# watching (fast, zero timing flakiness). This one test proves the actual
# wiring -- a real file write reaches a real awatch() loop reaches a real
# broadcast() call -- works at all. Kept to exactly one case, generous on
# timeout, polling rather than a fixed sleep.
# ---------------------------------------------------------------------------


class TestRunIntegration:
    def test_run_broadcasts_on_real_fs_write(self, home: Path) -> None:
        async def scenario() -> list[dict[str, object]]:
            watcher = DocWatcher(home)
            ws = FakeSocket()
            watcher.subscribe("journal/new.md", ws)
            task = asyncio.create_task(watcher.run())
            try:
                # Give watchfiles' background watcher thread a moment to
                # actually start observing `home` before we write -- writes
                # that land before the watcher is live are simply missed.
                await asyncio.sleep(0.5)
                _ = (home / "journal" / "new.md").write_text("# New\n\nHello.\n")
                for _ in range(100):
                    if ws.sent:
                        break
                    await asyncio.sleep(0.1)
            finally:
                _ = task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
            return ws.sent

        sent = asyncio.run(scenario())
        assert sent, "expected at least one broadcast from a real fs write"
        assert sent[0]["type"] == "doc"
        assert sent[0]["path"] == "journal/new.md"
