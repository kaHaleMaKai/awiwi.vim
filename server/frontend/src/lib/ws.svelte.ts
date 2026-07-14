// Live-sync WebSocket client — connects to `GET /api/ws` (the frozen T24
// protocol, handovers/server-rewrite/T24-live-sync.md) and fans "doc"/
// "deleted" pushes out to whichever page component currently cares about a
// given `watch_path`. The server keeps no session state (T24 doc: "Reconnect
// expectations"), so every reconnect re-sends "subscribe" for every path
// still registered and — for genuine *reconnects* only, not the first-ever
// connect — re-fetches each over HTTP to close the missed-change window.
//
// Pages don't talk to `WsClient` directly; they call `useLiveDoc()` once in
// their component script (see JournalPage/TodoPage/DocPage), which wraps
// `ws.subscribe()` in a `$effect` keyed off a `$derived` watch_path so
// subscribe/unsubscribe tracks route changes automatically.

import type { DocPayload } from "./api";

export type ConnStatus = "live" | "reconnecting" | "down";

// --- pure logic (unit-tested directly, see ws.spec.ts) ---

export interface BackoffOptions {
  baseMs?: number;
  maxMs?: number;
  factor?: number;
  /** Fraction of the computed delay to randomize by, +/-. 0 = no jitter. */
  jitterRatio?: number;
  random?: () => number; // injectable for deterministic tests
}

/** Exponential backoff with jitter. `attempt` is 0-based (0 = first retry
 * after the initial disconnect). Deterministic given a fixed `random`. */
export function backoffDelay(attempt: number, opts: BackoffOptions = {}): number {
  const {
    baseMs = 500,
    maxMs = 15_000,
    factor = 2,
    jitterRatio = 0.3,
    random = Math.random,
  } = opts;
  const raw = Math.min(baseMs * factor ** Math.max(attempt, 0), maxMs);
  const jitter = raw * jitterRatio * (random() * 2 - 1);
  return Math.max(0, Math.round(raw + jitter));
}

/** After this many consecutive failed (re)connect attempts, the UI reports
 * "down" instead of "reconnecting" — still retrying underneath (backoff is
 * capped, never gives up), just an honest "this is not coming back
 * momentarily" signal per ConnectionDot's three states. */
export const DOWN_AFTER_ATTEMPTS = 4;

export function statusForFailures(consecutiveFailures: number): ConnStatus {
  if (consecutiveFailures <= 0) return "live";
  return consecutiveFailures > DOWN_AFTER_ATTEMPTS ? "down" : "reconnecting";
}

/** Decides whether a "doc" push should actually re-render, given the
 * mtime_ns we last rendered/acknowledged for this subscription. `null` means
 * "nothing seen yet" (always render). Equal mtime_ns means either the
 * fs-watcher noticed our own just-applied checkbox toggle (already rendered
 * via onCheckboxSuccess) or a duplicate/no-op broadcast — skip either way. */
export function shouldRenderIncoming(
  lastSeenMtimeNs: number | null,
  incomingMtimeNs: number,
): boolean {
  return lastSeenMtimeNs === null || incomingMtimeNs !== lastSeenMtimeNs;
}

// --- scroll preservation ---

/** Runs `fn` (expected to synchronously trigger a Svelte state update that
 * re-renders a `{@html}` block) while keeping the page's scroll position
 * pinned across the DOM replacement. Not pixel-perfect (a genuinely
 * different-height doc will still shift content below the fold) — just
 * cancels the incidental jump from `{@html}` briefly collapsing/rebuilding
 * the container. No-op outside a browser (tests). */
function withScrollPreserved(fn: () => void): void {
  if (typeof window === "undefined") {
    fn();
    return;
  }
  const y = window.scrollY;
  fn();
  requestAnimationFrame(() => {
    if (window.scrollY !== y) window.scrollTo(0, y);
  });
}

// --- the client ---

interface DocHandlers {
  onDoc: (payload: DocPayload) => void;
  onDeleted: () => void;
  /** Called after a reconnect (never the first connect) to close the
   * missed-change window over HTTP, per the T24 handover. */
  refetch: () => void;
}

interface DocSubscriber extends DocHandlers {
  lastMtimeNs: number | null;
}

export interface LiveSub {
  /** Record a mtime_ns as "already seen" — call from onCheckboxSuccess so
   * the echo of our own write doesn't trigger a needless re-render. */
  ackMtime(mtimeNs: number): void;
  unsubscribe(): void;
}

interface ServerMessage {
  type?: unknown;
  path?: unknown;
  payload?: unknown;
  detail?: unknown;
}

function wsUrl(): string {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${location.host}/api/ws`;
}

class WsClient {
  status = $state<ConnStatus>("down");

  #socket: WebSocket | null = null;
  #subs = new Map<string, DocSubscriber>();
  #consecutiveFailures = 0;
  #hasConnectedOnce = false;
  #reconnectTimer: ReturnType<typeof setTimeout> | undefined;

  /** Idempotent — connects on first subscribe, no-ops if already
   * open/connecting, and never jumps a pending reconnect's backoff wait. */
  connect(): void {
    if (this.#socket || this.#reconnectTimer !== undefined) return;
    if (typeof WebSocket === "undefined") return;
    this.#open();
  }

  subscribe(watchPath: string, handlers: DocHandlers): LiveSub {
    this.connect();
    const sub: DocSubscriber = { ...handlers, lastMtimeNs: null };
    this.#subs.set(watchPath, sub);
    this.#send({ type: "subscribe", path: watchPath });
    return {
      ackMtime: (mtimeNs: number) => {
        sub.lastMtimeNs = mtimeNs;
      },
      unsubscribe: () => {
        if (this.#subs.get(watchPath) === sub) this.#subs.delete(watchPath);
        this.#send({ type: "unsubscribe", path: watchPath });
      },
    };
  }

  #open(): void {
    this.#reconnectTimer = undefined;
    let socket: WebSocket;
    try {
      socket = new WebSocket(wsUrl());
    } catch {
      this.#scheduleReconnect();
      return;
    }
    this.#socket = socket;

    socket.onopen = () => {
      const isReconnect = this.#hasConnectedOnce;
      this.#hasConnectedOnce = true;
      this.#consecutiveFailures = 0;
      this.status = "live";
      for (const [path, sub] of this.#subs) {
        this.#send({ type: "subscribe", path });
        if (isReconnect) sub.refetch();
      }
    };
    socket.onmessage = (ev: MessageEvent) => this.#onMessage(ev);
    socket.onclose = () => {
      if (this.#socket !== socket) return; // stale handler from a superseded socket
      this.#socket = null;
      this.#scheduleReconnect();
    };
    socket.onerror = () => {
      try {
        socket.close();
      } catch {
        // already closed/closing
      }
    };
  }

  #scheduleReconnect(): void {
    this.#consecutiveFailures += 1;
    this.status = statusForFailures(this.#consecutiveFailures);
    clearTimeout(this.#reconnectTimer);
    const delay = backoffDelay(this.#consecutiveFailures - 1);
    this.#reconnectTimer = setTimeout(() => this.#open(), delay);
  }

  #send(msg: Record<string, unknown>): void {
    if (this.#socket?.readyState === WebSocket.OPEN) {
      this.#socket.send(JSON.stringify(msg));
    }
    // Not open yet: onopen above re-subscribes everything once connected, so
    // a send attempted mid-connect is safely dropped rather than queued.
  }

  #onMessage(ev: MessageEvent): void {
    let msg: ServerMessage;
    try {
      msg = JSON.parse(ev.data as string) as ServerMessage;
    } catch {
      return;
    }
    if (!msg || typeof msg !== "object") return;

    if (msg.type === "doc" && typeof msg.path === "string" && msg.payload) {
      const sub = this.#subs.get(msg.path);
      if (!sub) return;
      const payload = msg.payload as DocPayload;
      if (!shouldRenderIncoming(sub.lastMtimeNs, payload.mtime_ns)) {
        sub.lastMtimeNs = payload.mtime_ns;
        return;
      }
      sub.lastMtimeNs = payload.mtime_ns;
      withScrollPreserved(() => sub.onDoc(payload));
    } else if (msg.type === "deleted" && typeof msg.path === "string") {
      this.#subs.get(msg.path)?.onDeleted();
    } else if (msg.type === "error") {
      // Non-fatal per the T24 protocol — the socket stays open.
      console.warn("awiwi ws: server reported an error:", msg.detail);
    }
    // "pong": nothing to do — no heartbeat is currently sent.
  }
}

export const ws = new WsClient();

/**
 * Component-level composable: subscribes to live updates for whatever
 * watch_path `getWatchPath()` currently returns, re-subscribing whenever it
 * changes and unsubscribing on teardown. Call once per page component,
 * during its own initialization (like any other `$effect`-based composable).
 *
 * `getWatchPath` MUST read a `$derived` value (not a raw `$state` doc
 * object) so this effect only re-runs when the watch_path itself changes —
 * not on every content update to the doc (which would otherwise
 * unsubscribe/resubscribe on every WS push, including our own).
 */
export function useLiveDoc(
  getWatchPath: () => string | undefined,
  handlers: DocHandlers,
): { ackMtime: (mtimeNs: number) => void } {
  let liveSub: LiveSub | null = null;

  $effect(() => {
    const watchPath = getWatchPath();
    if (!watchPath) {
      liveSub = null;
      return;
    }
    const sub = ws.subscribe(watchPath, handlers);
    liveSub = sub;
    return () => {
      sub.unsubscribe();
      if (liveSub === sub) liveSub = null;
    };
  });

  return {
    ackMtime(mtimeNs: number): void {
      liveSub?.ackMtime(mtimeNs);
    },
  };
}
