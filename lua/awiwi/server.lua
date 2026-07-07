-- Lifecycle manager for the single background viewer-server job: start/stop/
-- status/logs, `config.json` generation, and `:Awiwi serve` (open the
-- current buffer's rendered URL in a browser).
--
-- See handovers/lua-port/server.md for the full behavior contract, bug list,
-- and the ADR on replacing the (long-dead) Flask launch command.
--
-- Every external effect (process spawn, marker lookup, browser opener) is
-- reachable through `M.config`, so the whole lifecycle is unit-testable
-- headless without a real server binary — see tests/server_spec.lua.

local str = require("awiwi.str")
local pathlib = require("awiwi.path")

local M = {}

local DEFAULT_PORT = "5823"
local MARKER_TYPES = { "todo", "onhold", "urgent", "delegate", "question", "due" }

--- This file's own directory chain (`lua/awiwi/server.lua`) walked up three
--- levels gives the plugin/repo root — the nvim-Lua equivalent of the
--- vimscript original's `expand('<sfile>:p:h:h')` (from `autoload/awiwi/`,
--- two levels; one extra level here for the added `awiwi/` directory).
local function default_code_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  source = vim.fs.abspath(source)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

--- Bug #5 ADR (superseded by T17, see handovers/server-rewrite/T16-app-assembly.md
--- and T17-entrypoint-pin.md): the vimscript original launched
--- `server/.venv/bin/flask run`, but `server/app.py` no longer exists (moved
--- to `server.old/`). The FastAPI rewrite has since landed under
--- `server/src/awiwi/app.py` (module-level `app = create_app()`), so this
--- default now targets the real entrypoint `awiwi.app:app` via
--- `uv run uvicorn`, with `AWIWI_HOME` threaded through the env so the
--- launched process discovers the same notes home as this nvim instance
--- (still overridable via `M.config.cmd_builder`).
function M.default_cmd_builder(host, port)
  return {
    cmd = { "uv", "run", "uvicorn", "awiwi.app:app", "--host", host, "--port", tostring(port) },
    cwd = pathlib.join(default_code_root(), "server"),
    env = { AWIWI_HOME = vim.g.awiwi_home },
  }
end

--- Bug #7 fix: env vars (if any) live on the spawned job's own env table
--- (`vim.system`'s `env` opt), never on `vim.env`/the process-wide
--- environment — nothing here ever mutates global state.
local function default_system(cmd, opts, on_exit)
  return vim.system(cmd, opts, on_exit)
end

--- Port-notes stub: `awiwi#get_markers` lives in the not-yet-ported
--- `awiwi.vim` core (façade, T10) — call through to the legacy vimscript
--- function so `config.json` stays correct today, but keep it swappable so
--- this module is fully TDD-able against a fake before/without that
--- function existing (see handovers/lua-port/server.md Port notes).
local function default_get_markers(marker)
  return vim.fn["awiwi#get_markers"](marker, { join = false })
end

--- Bug's Linux-only `xdg-open` opener, preserved (per Port notes: out of
--- scope to add cross-platform fallbacks unless architecture.md says
--- otherwise), but now guarded by an executable check instead of a silent
--- fire-and-forget failure.
local function default_opener(url)
  if vim.fn.executable("xdg-open") == 1 then
    M.config.system({ "xdg-open", url })
  else
    vim.api.nvim_err_writeln("[ERROR] xdg-open not found; cannot open " .. url)
  end
end

--- All external effects, injectable for tests (see tests/server_spec.lua)
--- and future callers that need different behavior (e.g. once the real
--- FastAPI entrypoint lands).
M.config = {
  system = default_system,
  cmd_builder = M.default_cmd_builder,
  get_markers = default_get_markers,
  opener = default_opener,
}

local function initial_state()
  return {
    running = false,
    host = "",
    port = "",
    proc = nil,
    logs = { stdout = {}, stderr = {}, exit = {} },
  }
end

M._state = initial_state()

--- Test-only: reset module state and config back to defaults. Never called
--- from production code paths.
function M._reset()
  M._state = initial_state()
  M.config = {
    system = default_system,
    cmd_builder = M.default_cmd_builder,
    get_markers = default_get_markers,
    opener = default_opener,
  }
end

function M.get_default_port()
  return DEFAULT_PORT
end

--- `'*'`/`'all'` -> `0.0.0.0`; `''`/`'127.0.0.1'`/`'::1'` -> `localhost`;
--- anything else passed through verbatim.
local function normalize_host(host)
  if host == "*" or host == "all" then
    return "0.0.0.0"
  elseif host == "" or host == "127.0.0.1" or host == "::1" then
    return "localhost"
  end
  return host
end

--- Bug #3 fix: both `start_server` and `serve()` resolve the port through
--- this single function (`g:awiwi_server_port` if set, else the module
--- default) instead of `serve()` hardcoding the default independently.
local function resolve_port(port)
  if port ~= nil and port ~= "" then
    return tostring(port)
  end
  local configured = vim.g.awiwi_server_port
  if configured ~= nil and configured ~= vim.NIL and configured ~= "" then
    return tostring(configured)
  end
  return M.get_default_port()
end

function M.server_is_running()
  return M._state.running
end

--- Serializes global config + marker lists into `<g:awiwi_home>/config.json`,
--- mirroring the vimscript original's `s:write_json_config`.
function M._write_json_config()
  local conf = {
    search_engine = vim.g.awiwi_search_engine,
    home = vim.g.awiwi_home,
    screensaver = vim.g.awiwi_screensaver,
    link_color = vim.g.awiwi_link_color,
  }
  for _, marker in ipairs(MARKER_TYPES) do
    conf[marker .. "_markers"] = M.config.get_markers(marker)
  end

  local config_file = pathlib.join(vim.g.awiwi_home, "config.json")
  local f = assert(io.open(config_file, "w"))
  f:write(vim.json.encode(conf))
  f:write("\n")
  f:close()
end

--- Start the background server. Returns `true` on a (so-far) successful
--- spawn, or `false, message` if it's already running or the spawn itself
--- failed. Bug #1 fix: "running" now reflects actual spawn success — a
--- `vim.system` spawn error (caught below) or an immediate nonzero exit
--- (via `on_exit`, which may fire synchronously for a dead-on-arrival
--- process) both leave `server_is_running()` false, instead of the
--- vimscript original's unconditional `s:server_started = v:true`.
function M.start_server(host, port)
  if M.server_is_running() then
    local msg = ("server already running on %s:%s"):format(M._state.host, M._state.port)
    vim.api.nvim_err_writeln(msg)
    return false, msg
  end

  host = normalize_host(host)
  port = resolve_port(port)

  M._write_json_config()
  M._state.logs = { stdout = {}, stderr = {}, exit = {} }

  local built = M.config.cmd_builder(host, port)

  local function on_stdout(_, data)
    if data and data ~= "" then
      vim.list_extend(M._state.logs.stdout, vim.split(data, "\n", { trimempty = true }))
    end
  end
  local function on_stderr(_, data)
    if data and data ~= "" then
      vim.list_extend(M._state.logs.stderr, vim.split(data, "\n", { trimempty = true }))
    end
  end
  local function on_exit(obj)
    table.insert(M._state.logs.exit, obj and obj.code or -1)
    M._state.running = false
    M._state.proc = nil
  end

  -- Tentatively "running" before the spawn call so a synchronous on_exit
  -- (immediate death) can flip it back off without this function
  -- clobbering that decision afterwards.
  M._state.running = true

  local ok, proc_or_err = pcall(
    M.config.system,
    built.cmd,
    { cwd = built.cwd, env = built.env, stdout = on_stdout, stderr = on_stderr },
    on_exit
  )

  if not ok or proc_or_err == nil then
    M._state.running = false
    local err = tostring(proc_or_err)
    vim.api.nvim_err_writeln(("[ERROR] failed to start server: %s"):format(err))
    return false, err
  end

  M._state.host = host
  M._state.port = port
  if M._state.running then
    M._state.proc = proc_or_err
  end
  return M._state.running
end

--- No-op if not running. Else kills the process (best-effort — tolerates a
--- process that's already gone) and resets all state.
function M.stop_server()
  if not M.server_is_running() then
    return
  end
  print(("stopping server on %s:%s"):format(M._state.host, M._state.port))
  if M._state.proc then
    pcall(function()
      M._state.proc:kill("sigterm")
    end)
  end
  M._state = initial_state()
end

--- `key` in `{'', 'stdout', 'stderr', 'exit'}`; `''` (default) means
--- stdout+stderr concatenated. Returns the joined text, or `nil, message` on
--- an empty buffer or an unrecognized key. Bug #6 fix: an unknown key
--- returns a clean error instead of the vimscript original's raw dict-index
--- crash.
function M.server_logs(key)
  key = key or ""
  local logs

  if key == "" then
    logs = {}
    vim.list_extend(logs, M._state.logs.stdout)
    vim.list_extend(logs, M._state.logs.stderr)
  elseif M._state.logs[key] ~= nil then
    logs = M._state.logs[key]
  else
    local msg = ("unknown log key: %s"):format(tostring(key))
    vim.api.nvim_err_writeln("[ERROR] " .. msg)
    return nil, msg
  end

  if #logs == 0 then
    vim.api.nvim_err_writeln("no logs received")
    return nil, "no logs received"
  end

  local text = table.concat(logs, "\n")
  print(text)
  return text
end

--- Strip an exact suffix (guarded strip, not a magic fixed-length slice —
--- Bug #4 fix: the vimscript original's `fnamemodify(...)[:−4]` blindly
--- dropped the last 3 bytes assuming a 2-character extension).
local function strip_suffix(s, suffix)
  if str.endswith(s, suffix) then
    return s:sub(1, #s - #suffix)
  end
  return s
end

--- URL target for `current_file` (defaults to the current buffer's path)
--- relative to `g:awiwi_home`: `journal/todos.md` -> `/todo`; anything else
--- under `journal/` -> `journal/<basename, .md stripped>` (matching the
--- vimscript original's use of only the file's basename, not its full
--- subpath, for this branch); everything else -> the raw relative path.
function M.resolve_target(current_file)
  current_file = current_file or vim.api.nvim_buf_get_name(0)
  local rel = pathlib.relativize(current_file, vim.g.awiwi_home)

  if str.endswith(rel, "journal/todos.md") then
    return "/todo"
  elseif str.startswith(rel, "journal") then
    local base = vim.fs.basename(rel)
    return "journal/" .. strip_suffix(base, ".md")
  else
    return rel
  end
end

--- Bounded, non-blocking readiness poll (Bug #2 fix, replacing the
--- vimscript original's blocking `sleep 0.5`): waits until either the first
--- stdout line arrives (mirrors a human watching for the server's "now
--- listening" log line) or the process is no longer running (spawn/early
--- failure), up to `timeout_ms`. Returns `vim.wait`'s own boolean.
function M.wait_ready(timeout_ms, poll_ms)
  timeout_ms = timeout_ms or 3000
  poll_ms = poll_ms or 20
  return vim.wait(timeout_ms, function()
    return not M.server_is_running() or #M._state.logs.stdout > 0
  end, poll_ms)
end

--- Ensure a server is running (cold-starting one on `localhost:<resolved
--- port>` if not — Bug #3 fix: resolves the port the same way
--- `start_server` does, instead of always hardcoding the default), wait for
--- it to become ready (Bug #2 fix: non-blocking poll, never a fixed sleep),
--- then open the current buffer's rendered URL in the browser.
function M.serve()
  if not M.server_is_running() then
    local ok = M.start_server("localhost", resolve_port())
    if ok then
      M.wait_ready()
    end
  end

  local target = M.resolve_target()
  local url = ("http://%s:%s/%s"):format(M._state.host, M._state.port, target)
  M.config.opener(url)
end

return M
