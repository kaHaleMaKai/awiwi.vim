# lua-port / server

**Responsibility:** Manage the lifecycle (start/stop/status/logs) of a single background
viewer-server job, write its `config.json`, and open the current buffer's rendered URL in a
browser (`:Awiwi serve`).

**Source:** `autoload/awiwi/server.vim` (131 lines). See `docs/architecture.md:53,81,165-169`.

## Public surface (current vimscript)

- `awiwi#server#get_default_port() -> string` — returns `'5823'` (module constant).
- `awiwi#server#server_logs(...) -> nil`  (`echo`s or `echoerr`s)
  - `a:1` optional key: `''` (default, stdout+stderr concatenated), `'stdout'`, `'stderr'`, `'exit'`.
  - Unknown key → vimscript dict-index error (not caught).
  - Empty log → `echoerr 'no logs received'`.
- `awiwi#server#stop_server() -> nil`
  - No-op if not running. Else: echoes `stopping server on <host>:<port>`, `jobstop()`s the job
    (swallows Vim error `E900` "not a job" printing `echoerr`), resets all module state
    (`started=false`, `host=''`, `port=''`, `job_id=-1`).
- `awiwi#server#server_is_running() -> bool` — returns cached `s:server_started` flag (NOT a live
  process check).
- `awiwi#server#start_server(host, [port]) -> nil`
  - `port` defaults to `get(g:, 'awiwi_server_port', '5823')`.
  - Errors (`echoerr`, does not raise/throw) and returns early if already running.
  - Host normalization: `'*'` or `'all'` → `0.0.0.0`; `''`/`'127.0.0.1'`/`'::1'` → `localhost`;
    anything else passed through verbatim.
  - Sets env vars `$FLASK_APP`, `$FLASK_ROOT`, `$FLASK_ENV=development`, `$FLASK_HOST`,
    `$FLASK_PORT` as a side effect (process-global — leaks into the whole nvim session).
  - Writes `config.json` into `g:awiwi_home` (see below) BEFORE spawning.
  - Resets `s:server_logs` (`stdout`/`stderr`/`exit`) to empty lists.
  - Spawns `<code_root>/server/.venv/bin/flask run --host=<host> --port=<port>` via `jobstart`,
    where `code_root = expand('<sfile>:p:h:h')` from `autoload/awiwi.vim` — i.e. the plugin's own
    repo root (two dirs up from `autoload/awiwi.vim`), NOT `g:awiwi_home`.
  - `on_stdout`/`on_stderr` append raw job-callback line lists into `s:server_logs.{stdout,stderr}`;
    `on_exit` appends the raw exit-callback payload (a list, itself) into `s:server_logs.exit`.
  - Sets `s:server_started=true`, `s:server_host=host`, `s:server_port=port` unconditionally —
    even if `jobstart` returns a failure code (0 or -1) — see Bugs.
- `awiwi#server#serve() -> nil`
  - If not running: starts it on `localhost:5823` (`s:default_port`, ignoring
    `g:awiwi_server_port`!) and then blocks the whole editor for 500ms
    (`system('sleep 0.5')`) hoping the server is up by then.
  - Derives the URL path from the current buffer's file, relative to `g:awiwi_home`:
    - `journal/todos.md` → `/todo`
    - anything else under `journal/` → `journal/<basename without last 3 chars>` (strips the
      `.md` extension by slicing off the last 3 characters, not a proper extension strip)
    - anything else → the raw relative path
  - Builds `http://<s:server_host>:<s:server_port>/<target>` and opens it via
    `jobstart(['xdg-open', url])` (fire-and-forget, no error handling, Linux-only binary).

**Internal (module-local, not part of public surface):** `s:write_json_config()` — serializes
`g:awiwi_search_engine`, `g:awiwi_home`, `g:awiwi_screensaver`, `g:awiwi_link_color`, plus
`<marker>_markers` for `todo/onhold/urgent/delegate/question/due` (via
`awiwi#get_markers(marker, {join: false})`, ripgrep-escaped) into
`<g:awiwi_home>/config.json` as one JSON line via `writefile`.

**Reads/writes:**
- Globals read: `g:awiwi_home`, `g:awiwi_search_engine`, `g:awiwi_screensaver`,
  `g:awiwi_link_color`, `g:awiwi_server_port` (optional), `g:awiwi_autostart_server` (read by
  `ftplugin/awiwi.vim`, not by `server.vim` itself).
- Module-local state (`s:` vars): `server_started`, `server_host`, `server_port`,
  `server_job_id`, `server_logs` (`{stdout, stderr, exit}` lists), `default_port='5823'`.
- Files: writes `<g:awiwi_home>/config.json` on every `start_server` call.
- Env vars: `$FLASK_APP`, `$FLASK_ROOT`, `$FLASK_ENV`, `$FLASK_HOST`, `$FLASK_PORT` (process-wide
  side effect for the lifetime of the nvim process, never unset on stop).
- Process: one `jobstart`-spawned flask job (`s:server_job_id`), one fire-and-forget `xdg-open`
  job per `serve()` call (id discarded).

**External:**
- Binary launched: `<code_root>/server/.venv/bin/flask run --host=<host> --port=<port>`
  — **this is the OLD Flask app's venv/entrypoint** (see "What server actually launches" below).
- `xdg-open` (Linux desktop-open, no fallback for macOS/`open` or Windows).
- Awiwi modules called: `awiwi#path#join`, `awiwi#get_code_root`, `awiwi#get_markers`,
  `awiwi#str#endswith`, `awiwi#str#startswith`.
- No fzf/other plugin deps.

## What server.vim actually launches (flag)

`awiwi#get_code_root()` = `expand('<sfile>:p:h:h')` evaluated in `autoload/awiwi.vim`, i.e. the
awiwi.vim **plugin repo root** (two directories above `autoload/awiwi.vim`), **not**
`g:awiwi_home`. `start_server` builds:

- `flask = <repo_root>/server/.venv/bin/flask`
- `app   = <repo_root>/server/app.py`

In the **current repo state**, `server/` is the new FastAPI project (`pyproject.toml`, uv-managed,
no `app.py`, no `.venv/bin/flask`) — the old Flask app now lives at `server.old/app.py` with a
Flask venv. So **as shipped today, `:Awiwi serve` / `:Awiwi server start` targets a path that no
longer exists** (`server/app.py`, `server/.venv/bin/flask`): the `jobstart` will fail to spawn the
job, but `start_server` still unconditionally sets `s:server_started = v:true` (see Bugs #3), so
the plugin believes a server is running when it never started. `docs/architecture.md:168-169`
already flags this exact coupling as needing rework. **Recommendation for the port:** do not
resurrect the Flask launch path; make the Lua module launch the FastAPI server (`uv run uvicorn`
or equivalent from `server/`) instead, and treat the old `flask run` command line as a historical
artifact to document, not to reproduce byte-for-byte.

## Call sites

- `ftplugin/awiwi.vim:318-320` — on buffer load, if `g:awiwi_autostart_server` is set (default
  `''`, so disabled by default) and no server is running yet, calls
  `awiwi#server#start_server(awiwi_server)` with that global as the host arg.
- `autoload/awiwi/cmd.vim:449` — completion: offers `stop`/`start` (mutually exclusive, based on
  `server_is_running()`) plus `logs` as subcommands of `:Awiwi server <TAB>`.
- `autoload/awiwi/cmd.vim:451-455` (completion) — offers `localhost`/`*` as host completions after
  `server start`, and `stdout`/`stderr`/`exit` after `server logs`.
- `autoload/awiwi/cmd.vim:570` — `:Awiwi serve` → `awiwi#server#serve()`.
- `autoload/awiwi/cmd.vim:575-583` — `:Awiwi server start [host] [port]` →
  `awiwi#server#start_server(host, port)` (port defaults via
  `awiwi#server#get_default_port()`); `:Awiwi server stop` → `awiwi#server#stop_server()`;
  `:Awiwi server logs [stdout|stderr|exit]` → `awiwi#server#server_logs(log_type)`.
- No call site ever calls `awiwi#server#server_logs()` with no logs pre-populated in tests; no
  autocmd stops the server on `VimLeave` — the job is simply killed by the OS when nvim exits
  (or leaked if nvim is killed with the job detached, which is `jobstart`'s default in Vim/Neovim
  unless `detach` is not set — Neovim by default terminates jobs when the pty exits, but that is
  OS/terminal-dependent, not something `server.vim` manages explicitly).

## Behavior contract

1. `get_default_port()` returns the fixed literal `"5823"`.
2. `server_is_running()` reflects only in-memory state set by `start_server`/`stop_server`; it is
   never re-verified against the actual OS process, so it can be stale (true after the spawned
   process has already died, e.g. because the binary didn't exist).
3. `start_server(host, port?)`:
   - No-op (reports an error, does not throw) if a server is already marked running.
   - Normalizes `host`: `*`/`all` → `0.0.0.0`; empty/`127.0.0.1`/`::1` → `localhost`; otherwise
     unchanged.
   - `port` defaults to `g:awiwi_server_port` if set, else `"5823"`.
   - Always (re)writes `config.json` under `g:awiwi_home` before spawning, from current global
     config + marker lists.
   - Clears all previously buffered logs.
   - Spawns the server process asynchronously and immediately marks itself "running" — it does
     NOT wait for or verify a successful launch.
4. `stop_server()`:
   - No-op if not running.
   - Else stops the job (best-effort; tolerates "job already gone") and resets all state
     (`running=false`, `host=''`, `port=''`).
5. `server_logs(kind?)`:
   - `kind` in `{'', 'stdout', 'stderr', 'exit'}`; `''` means stdout+stderr concatenated.
   - Prints the buffered lines joined by newlines, or an error if the buffer is empty.
   - Buffers accumulate for the lifetime of one `start_server` call (cleared on next start), are
     NOT cleared on `stop_server`.
6. `serve()`:
   - Ensures a server is running on `localhost:5823` if none is (ignores `g:awiwi_server_port`
     here — always uses the hardcoded default, a divergence from `start_server`'s own default
     logic).
   - Blocks the editor for ~500ms as a crude "wait for server to be ready" hack.
   - Computes a target path from the current buffer's path relative to `g:awiwi_home`:
     `journal/todos.md` → `/todo`; other files under `journal/` → `journal/<name-without-.md>`;
     everything else → the raw relative path.
   - Opens `http://<host>:<port>/<target>` via `xdg-open`, fire-and-forget (no verification the
     browser or server responded).
7. Browser-open behavior is Linux-only (`xdg-open`); no cross-platform fallback exists.
8. Nothing in this module registers a `VimLeavePre`/`VimLeave` autocmd — server processes are not
   explicitly stopped when nvim exits; whether the child process survives depends on how Neovim's
   job/process-group handling treats `jobstart`ed children on exit (OS/terminal dependent), not on
   any code in `server.vim`.

## Bugs found

1. **Stale "running" flag after failed spawn** (server.vim:108-111) — `start_server` sets
   `s:server_started = v:true` unconditionally after calling `jobstart`, without checking the
   returned job id (`jobstart` returns `0` for invalid arguments or a negative number on failure).
   If the flask binary doesn't exist (true today, see "What server actually launches"), the plugin
   still believes the server is up. **Recommendation: fix in port** — check the spawn result (or
   `vim.system`'s completion) before marking the server started; expose a way to detect the
   process actually failed (e.g., surface on_exit with nonzero code and flip state back to
   stopped + log an error).

2. **Blocking `sleep 0.5` readiness hack** (server.vim:118) — `call system('sleep 0.5')` blocks the
   entire editor UI for half a second, every time `serve()` has to cold-start the server, and is
   not actually a readiness check (just a fixed delay, may be too short or wastes time).
   **Recommendation: fix in port** (mandated by task) — replace with a non-blocking poll
   (`vim.wait` + condition, e.g. probing the port or watching first stdout line) with a bounded
   timeout and explicit failure/timeout message; must never block the editor on a fixed sleep.

3. **`serve()` ignores `g:awiwi_server_port`** (server.vim:117) — cold-starts always bind to
   `s:default_port` ("5823") regardless of the user's configured `g:awiwi_server_port`, while
   `start_server()` called directly (e.g. via `:Awiwi server start`) does respect that global. This
   is an inconsistency, not obviously intentional. **Recommendation: fix in port** — `serve()`
   should resolve the port the same way `start_server` does (`g:awiwi_server_port` else default),
   or the port config surface should be unified into one option.

4. **`.md` suffix stripped by fixed-length slice, not proper extension removal**
   (server.vim:125): `fnamemodify(current_file, ':t')[:-4]` removes exactly the last 3 characters,
   assuming a 2-character extension is preceded by a `.` — this happens to work for `.md` (3 chars
   total) but is fragile/unreadable and breaks silently for any non-`.md` file that reaches this
   branch. **Recommendation: fix in port** — use a proper "strip suffix `.md`" helper
   (`awiwi#str#endswith`-guarded strip, already used elsewhere in this very file for the
   `todos.md` check) instead of a magic slice.

5. **Launch target (`server/app.py`, `server/.venv/bin/flask`) points at the OLD Flask app whose
   files have moved to `server.old/`** — see dedicated section above.
   **Recommendation: fix in port** — do not preserve the Flask launch command; the Lua module
   should launch the FastAPI server from `server/` (e.g., `uv run uvicorn app:app --host --port`,
   pending confirmation of the actual FastAPI entrypoint/module name once that work lands) or, if
   the FastAPI server isn't launchable yet, stub the process-spawn behind an injectable command
   builder so it's a one-line change once the new entrypoint exists. Flag this explicitly to the
   orchestrator — this module's "port faithfully" instruction conflicts with the fact that the
   faithful command is already broken; architecture.md:168-169 already calls this out as
   needing rework.

6. **`server_logs('badkey')` raises a raw Vim dict-index error** (server.vim:43) instead of a
   handled `AwiwiError`/echoerr for unrecognized keys. **Recommendation: preserve or fix at
   engineer's discretion** — low-value edge case (only reachable via `:Awiwi server logs <TAB>`
   which only completes valid keys), but the Lua port should raise a clear, typed error instead of
   an opaque "field not found" for parity-plus-quality; not a behavior-contract concern either way.

7. **`$FLASK_*` env vars are set as process-global nvim env vars and never unset** on
   `stop_server()` — leaks into any other job spawned from the same nvim session afterward.
   **Recommendation: fix in port** — irrelevant once the Flask launch path is replaced (bug #5),
   but if any env vars are needed for the new server, scope them to the spawned job's env table
   (`vim.system({...}, {env = {...}})`) rather than mutating global `vim.env`.

## Port notes

- Use `vim.system(cmd, {cwd=..., env=..., stdout=on_stdout, stderr=on_stderr}, on_exit)` in place
  of `jobstart`; keep the returned `vim.SystemObj` (has `:wait()`, `:kill()`) instead of a bare
  job id — this also directly gives a real "is the process still alive" check to back
  `server_is_running()` instead of a hand-maintained boolean (still keep an explicit boolean for
  "user intent to run", but let a `handle:is_closing()`/exit-callback flip it off on unexpected
  death — this actually fixes bug #1 for free).
  Note: `vim.system` is Neovim core (not job-control specific), available on the target Neovim
  ≥0.12; confirm `vim.system` exists in the test harness's `nvim --clean --headless` before relying
  on it (it has shipped since Neovim 0.10, so this is safe).
- Replace the `sleep 0.5` readiness hack with a bounded, non-blocking `vim.wait(timeout_ms, cond,
  interval_ms)` polling either: (a) first line received on stdout via the `on_stdout` callback
  (flip a local flag), or (b) a TCP connect probe to `host:port` (heavier, needs a socket lib —
  prefer (a) for the port, it requires no new dependency and mirrors what a human watching `flask
  run`'s log line "Running on http://..." would do).
- `xdg-open` should probably become a small "open with OS opener" abstraction
  (`xdg-open`/`open`/`start`) if cross-platform matters — out of scope unless architecture.md says
  otherwise; the vimscript is Linux-only, so preserving Linux-only behavior (with a
  `vim.fn.executable('xdg-open')` guard and a clear error otherwise) is acceptable for parity.
- `s:write_json_config()`'s dependency on `awiwi#get_markers` means this module cannot be ported
  in isolation before a Lua equivalent of markers/config exists; if `awiwi.vim` core globals
  (`get_markers`) haven't been ported yet, stub/inject that function so `server.lua` can still be
  TDD'd against a fake.
- Treesitter is not relevant here (no buffer/syntax parsing in this module).
- Consider modeling `server.lua`'s state as a single table (`M._state = {running, host, port,
  job, logs = {stdout={}, stderr={}, exit={}}}`) instead of five separate upvalues, for easier
  testing/reset between specs.

## Suggested acceptance tests

1. `get_default_port()` returns `"5823"`.
2. `start_server("localhost")` with a stubbed `vim.system` that "succeeds": after it returns,
   `server_is_running()` is `true`, and the stub was invoked with a command line containing
   `--host=localhost` and a port matching the default.
3. `start_server("*")` normalizes host to `0.0.0.0` in the spawned command/env.
4. `start_server("")` normalizes host to `localhost`.
5. `start_server(...)` when already running: does not spawn a second process, surfaces an error
   result/message, leaves existing state untouched.
6. `start_server(...)` when the spawn fails (stub returns immediate nonzero exit / spawn error):
   `server_is_running()` must be `false` afterward (regression test pinning the fix for Bug #1).
7. `stop_server()` when not running: no-op, no error.
8. `stop_server()` when running: kills the process (assert stub kill/terminate called), resets
   state so `server_is_running()` is `false`.
9. `server_logs()` with empty buffers surfaces an error/false result rather than printing nothing.
10. `server_logs('stdout')` returns only buffered stdout lines after simulated `on_stdout` events;
    `server_logs()` (no arg) returns stdout+stderr concatenated.
11. `serve()` on a fresh (not-running) state starts a server without any blocking sleep call
    (assert no `vim.wait`/blocking call exceeds e.g. 50ms in the test, or assert the readiness
    poll function was invoked instead of a hardcoded delay) — regression test for Bug #2.
12. `serve()` port resolution: with `g:awiwi_server_port` set to a custom value and server not yet
    running, the spawned server uses that custom port (regression test for Bug #3, assuming fix
    is accepted) — OR, if "preserve" is chosen by ADR, assert it still uses the hardcoded default
    and document why.
13. URL target derivation: `journal/todos.md` → target `/todo`; `journal/2026/07/2026-07-05.md`
    → target `journal/2026-07-05` (extension stripped via proper suffix removal, not slice
    arithmetic — regression test for Bug #4); a file outside `journal/` (e.g. `recipes/foo.md`)
    → target is the raw relative path `recipes/foo.md`.
14. `write_json_config` equivalent: given fake globals for search engine/home/screensaver/link
    color and fake marker lists, the written config file is valid JSON containing all the expected
    keys (`search_engine`, `home`, `screensaver`, `link_color`, `<marker>_markers` for the six
    marker types).

## Ported

**Lua module:** `lua/awiwi/server.lua` — `local M = {} … return M` shape, `require("awiwi.str")`
(`endswith`/`startswith`) and `require("awiwi.path")` (`join`, `relativize`) for deps already
ported (DRY per SKILL.md — not re-derived). Spec: `tests/server_spec.lua` (18 `it` cases across 7
`describe` blocks, covering all 14 of the brief's suggested acceptance tests plus explicit Bug
#1/#2/#3/#4/#6 regression tests). Full suite green: `nvim --clean --headless -l tests/run.lua`
245 passed, 0 failed (8 files).

**Public API:**
- `M.get_default_port() -> "5823"`
- `M.start_server(host, port?) -> ok:boolean, err?:string` — `port` resolves through
  `g:awiwi_server_port` else the module default (same resolution `serve()` uses, Bug #3 fixed).
  Host normalized (`*`/`all` -> `0.0.0.0`; `''`/`127.0.0.1`/`::1` -> `localhost`; else verbatim).
  Writes `config.json`, clears log buffers, then spawns via `M.config.system`. Returns `false, msg`
  (and `nvim_err_writeln`s) if already running or if the spawn itself fails/dies immediately
  (Bug #1 fixed — see below).
- `M.stop_server()` — no-op if not running; else kills the tracked process (best-effort,
  `pcall`-wrapped) and resets all state.
- `M.server_is_running() -> boolean` — a real flag that the spawn path (success/failure) and the
  process's own `on_exit` callback keep honest, not a fire-and-forget boolean.
- `M.server_logs(key?) -> text:string|nil, err?:string` — `key` in `{'', 'stdout', 'stderr',
  'exit'}`; `''` (default) is stdout+stderr concatenated. Returns `nil, message` (and
  `nvim_err_writeln`s) on an empty buffer or an unrecognized key (Bug #6 fixed: no raw dict-index
  crash) instead of the vimscript original's bare `echo`.
- `M.serve()` — ensures a server is running (cold-starting on `localhost:<resolved port>` if not,
  same port resolution as `start_server`, Bug #3 fixed), waits for readiness via `M.wait_ready()`
  (Bug #2 fixed: bounded non-blocking poll, never a fixed sleep), then opens
  `http://<host>:<port>/<target>` via `M.config.opener` (default: `xdg-open`, guarded by
  `vim.fn.executable` instead of a silent fire-and-forget failure).
- `M.resolve_target(current_file?) -> string` — exposed directly (not just via `serve()`) for unit
  testing the URL-target derivation; defaults to the current buffer's path. `journal/todos.md` ->
  `/todo`; anything else under `journal/` -> `journal/<basename with .md stripped via a proper
  suffix-removal helper, Bug #4 fixed>` (preserves the vimscript original's use of only the
  file's *basename*, not its full subpath, in this branch); everything else -> the raw path
  relative to `g:awiwi_home` (via `path.relativize`).
- `M.wait_ready(timeout_ms?, poll_ms?) -> boolean` — `vim.wait`-backed poll (default 3000ms
  timeout, 20ms interval) that returns once either the first stdout line arrives or the process is
  no longer running; used internally by `serve()`, exposed for direct testing/reuse by T9.
- `M._write_json_config()` — internal, exposed for direct testing (see below).
- `M.config` — the injection point: `{system, cmd_builder, get_markers, opener}`. All four default
  to real implementations (`vim.system`, `M.default_cmd_builder`, a call-through to the legacy
  `awiwi#get_markers` VimL function, and a guarded `xdg-open`), and every one is swappable per-test
  via `tests/server_spec.lua`'s fakes — no real process, VimL function, or browser is ever touched
  by the spec suite.
- `M._reset()` — test-only, resets `M._state` and `M.config` back to defaults between specs
  (module state is a singleton table, same pattern the brief's Port notes suggested).

**Bugs fixed (per binding orchestrator ruling):**
- **Bug #1** (stale "running" flag on failed spawn) — `M._state.running` is set tentatively
  `true` immediately before the `pcall`'d spawn call, so a synchronous `on_exit` (a stub/process
  that dies immediately) can flip it back to `false` without being clobbered afterwards; an
  actual `vim.system` spawn error (e.g. `ENOENT`) is caught by the `pcall` and also leaves it
  `false`. Both paths surface a clean error message via `nvim_err_writeln` and a `false, err`
  return. Two dedicated regression tests (`Bug #1 regression: ...`) pin both cases.
- **Bug #2** (blocking `sleep 0.5`) — replaced entirely by `M.wait_ready`, a bounded
  `vim.wait(timeout_ms, cond, poll_ms)` poll on "first stdout line received OR process died",
  mirroring the vimscript author's own intent (watch for the server's "ready" log line) without
  ever blocking the editor. Regression test asserts `serve()` completes in well under 50ms when
  the fake process writes its first stdout line synchronously.
- **Bug #3** (`serve()` ignoring `g:awiwi_server_port`) — both `start_server` and `serve()` now
  resolve the port through the same private `resolve_port()` helper; single source of truth,
  `g:awiwi_server_port` honored everywhere. Regression test confirms a custom configured port
  reaches the command builder from a cold `serve()` call.
- **Bug #4** (magic `[:-4]` slice for `.md` stripping) — replaced with a generic, guarded
  `strip_suffix(s, suffix)` helper (checks `str.endswith` first, then slices by the suffix's own
  length) — correct for any suffix length, not just a hardcoded 3-byte assumption.
- **Bug #5** (Flask launch command target no longer exists) — **ADR, behavior change**: the
  default `M.config.cmd_builder` does **not** reproduce the dead `server/.venv/bin/flask run`
  command line. It launches the new FastAPI server instead: `uv run uvicorn app:app --host <host>
  --port <port>` with `cwd` set to `<repo_root>/server`. The `app:app` entrypoint module/object
  name is a **placeholder** — `server/` currently contains only `pyproject.toml`, no app code yet
  (verified: `find server -maxdepth 3` returns just the one file) — so this must be revisited
  (one-line change to `M.default_cmd_builder`, or override via `M.config.cmd_builder`) once the
  real FastAPI entrypoint lands. `repo_root` is computed from this file's own path
  (`debug.getinfo` + `vim.fs.abspath`/`dirname` x3), not hardcoded, so it tracks wherever the
  plugin is installed. T9's `:Awiwi server start [host] [port]` dispatch needs no special-casing
  for this — it just calls `M.start_server(host, port)` as before.
- **Bug #6** (`server_logs('badkey')` raw dict-index crash) — engineer's discretion, per the
  brief: fixed. Unknown keys return `nil, "unknown log key: <key>"` and `nvim_err_writeln`, never
  a raw table-index error.
- **Bug #7** (`$FLASK_*` env vars mutating `vim.env` globally, never unset) — moot given Bug #5 (no
  more Flask env vars), but structurally fixed by construction anyway: `M.config.system` is always
  called with an `env` table scoped to that one `vim.system` call (`{cwd=..., env=...}` from the
  command builder's own return value) — nothing in this module ever reads or writes `vim.env`.

**Deviations from the brief's suggested acceptance test #2:** the brief's literal wording
(`--host=localhost`, Flask-style `=`-joined flags) doesn't apply post-Bug-#5 ADR — `uvicorn`'s CLI
takes space-separated `--host <value>` flags, not `--host=<value>`. The spec instead asserts the
command *builder* is invoked with the resolved `(host, port)` values (via a fake `cmd_builder`
that records its call args), which is format-agnostic and survives whatever the real entrypoint's
flag syntax turns out to be once it lands.

**Test count:** 18 `it` (`get_default_port`: 1, `start_server`/`server_is_running`: 8,
`stop_server`: 2, `server_logs`: 3, `serve`: 3, `_write_json_config`: 1).

**Gotchas for T9 (`cmd` façade, next after `sql`):**
- `:Awiwi server start [host] [port]` -> `M.start_server(host, port)`; `:Awiwi server stop` ->
  `M.stop_server()`; `:Awiwi server logs [stdout|stderr|exit]` -> `M.server_logs(key)` (now
  returns a value — `cmd.lua` should `print`/surface it, the module itself already
  echoes/`nvim_err_writeln`s so a bare call still behaves like the vimscript original
  interactively); `:Awiwi serve` -> `M.serve()`. Completion logic (`stop`/`start` mutually
  exclusive based on `M.server_is_running()`, `localhost`/`*` host completions, `stdout`/`stderr`/
  `exit` log-key completions) is unchanged from the brief's Call sites section — no new
  completion surface introduced by the port.
- `M.config.get_markers` still calls through to the legacy VimL `awiwi#get_markers` function
  (not yet ported — lives in `awiwi.vim` core, T10 façade). If/when that gets a Lua port, swap
  `default_get_markers`'s implementation for a direct `require` call; the public `M.config`
  injection point doesn't need to change.
- The FastAPI entrypoint placeholder (Bug #5 ADR above) is the one loose end before `:Awiwi serve`/
  `:Awiwi server start` do anything useful against a real server — until `server/` has an app,
  `M.default_cmd_builder`'s spawn will fail with a real `vim.system` `ENOENT`-style error, which
  `M.start_server` already surfaces cleanly (`server_is_running()` stays `false`, error message
  returned) rather than lying about server state, per Bug #1's fix.

status: done
