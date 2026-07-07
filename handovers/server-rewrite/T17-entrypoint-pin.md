# T17 S17.1 — pin real server entrypoint in lua/awiwi/server.lua

## Responsibility

Small integration change (not a module port): update the already-ported
`lua/awiwi/server.lua` so its `default_cmd_builder` targets the now-real
FastAPI entrypoint (`awiwi.app:app`, landed in T16) instead of the old
`app:app` placeholder, and threads `AWIWI_HOME` (pointing at
`vim.g.awiwi_home`) into the spawned uvicorn process's env, per the
Home-discovery decision in the design brief and T16's "T17 needs" section.

## Boundary

Edited only:

- `lua/awiwi/server.lua`
- `tests/server_spec.lua`

No `server/`, no `docs/`, no other `lua/` files touched. No commit made.

## What changed

`lua/awiwi/server.lua`, `M.default_cmd_builder(host, port)` (was ~line 42):

- `cmd` entrypoint arg: `"app:app"` → `"awiwi.app:app"`.
- Added `env = { AWIWI_HOME = vim.g.awiwi_home }` to the returned table.
- Doc comment above the function rewritten: the old "Bug #5 ADR" placeholder
  note now says it's superseded by T17/T16 landing, and describes the real
  entrypoint + env threading.

No other function changed. The `env` plumbing from `built.env` into
`vim.system`'s opts at the `start_server` call site (~line 210,
`{ cwd = built.cwd, env = built.env, stdout = on_stdout, stderr = on_stderr }`)
already existed pre-T17 (added when `default_cmd_builder`'s return shape was
designed) — it was simply unpopulated by `default_cmd_builder` until now, so
no call-site change was needed, only the builder itself.

## Tests

`tests/server_spec.lua`:

- New `describe("server.default_cmd_builder", ...)` block (2 cases):
  - asserts `"awiwi.app:app"` appears in the built `cmd` argv.
  - asserts `built.env.AWIWI_HOME == vim.g.awiwi_home` (set to a fixture
    value first).
- New `describe("server.start_server env threading", ...)` block (1 case):
  end-to-end check that swapping in the *real* `server.default_cmd_builder`
  (not the existing `fake_cmd_builder` test double) and calling
  `start_server` results in the fake `vim.system` stub receiving
  `opts.env.AWIWI_HOME == vim.g.awiwi_home` — proves the builder's `env` is
  actually threaded through, not just returned.
- All 3 new tests confirmed RED first (entrypoint string absent, `env` nil)
  before the `server.lua` edit, then GREEN after.
- Existing specs (host/port normalization, already-running guard, spawn
  failure bugs #1, log bugs #6, `serve()` bugs #2/#3, `resolve_target` bug
  #4, `_write_json_config`) untouched and still pass — they use
  `fake_cmd_builder`, which already returned `env = {}` before this change,
  so none of them exercised `default_cmd_builder` directly.

## Suite counts

- Targeted (`tests/server_spec.lua`): before 18 passed / 0 failed → after
  **21 passed / 0 failed**.
- Full suite (`nvim --clean --headless -l tests/run.lua`): baseline 458
  green (per task brief) → **461 passed, 0 failed (14 files)** after.

## What downstream needs (S17.2 doc close-out)

- ADR / `docs/decisions.md`: record that the T16-landing-time placeholder
  ADR ("Bug #5", `app:app` targeting a not-yet-existing FastAPI app) is now
  **superseded** — `lua/awiwi/server.lua`'s `default_cmd_builder` pins the
  real entrypoint `awiwi.app:app` and passes `AWIWI_HOME=<g:awiwi_home>` via
  `vim.system`'s `env` option (never via `vim.env`/process-wide state — see
  existing "Bug #7 fix" comment in the same file, which this change is
  consistent with).
- `docs/architecture.md` §Server (already flagged by T16 for refresh) should
  also note the nvim-side launch command now reads
  `uv run uvicorn awiwi.app:app --host <host> --port <port>` with
  `AWIWI_HOME` env, cwd `<repo>/server`.
- No behavior change to `:Awiwi server start/stop/status/logs` or `:Awiwi
  serve` dispatch — only the command line + env the spawned process
  receives.

## Status

status: done, 2026-07-07T18:44:17Z (not committed by this task —
orchestrator/user to commit)
