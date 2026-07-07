-- Acceptance specs for lua/awiwi/server.lua, per the behavior contract in
-- handovers/lua-port/server.md. Never touches a real process: `M.config.system`
-- is swapped for a fake "vim.system"-shaped stub so lifecycle logic
-- (start/stop/status/logs/serve) is fully testable headless.

local server = require("awiwi.server")

--- A fake `vim.system`-shaped stub: `fake_system(opts) -> stub_fn, calls`.
--- `calls` accumulates `{cmd, opts}` per invocation. `opts.exit_code`
--- (default `nil`, meaning "stays alive until :kill()") controls whether the
--- fake process exits immediately (synchronously, before returning) with
--- that code. `opts.spawn_error` makes the stub `error()` instead of
--- returning a process object, simulating a `vim.system` spawn failure
--- (e.g. ENOENT).
local function fake_system(opts)
  opts = opts or {}
  local calls = {}
  local last_proc = nil

  local function stub(cmd, sys_opts, on_exit)
    sys_opts = sys_opts or {}
    calls[#calls + 1] = { cmd = cmd, opts = sys_opts }

    if opts.spawn_error then
      error(opts.spawn_error)
    end

    if opts.stdout_line and sys_opts.stdout then
      sys_opts.stdout(nil, opts.stdout_line)
    end

    local killed = false
    local proc = {
      kill = function(_, sig)
        killed = true
        if on_exit then
          on_exit({ code = 143, signal = sig })
        end
      end,
      is_killed = function()
        return killed
      end,
    }
    last_proc = proc

    if opts.exit_code ~= nil then
      -- Simulate an immediate (synchronous) exit, e.g. spawn "succeeded"
      -- but the child process died right away.
      on_exit({ code = opts.exit_code })
    end

    return proc
  end

  return stub, calls, function()
    return last_proc
  end
end

--- Fake command builder recording the (host, port) it was called with,
--- returning a harmless argv (never actually exec'd, since `system` is also
--- stubbed in every test).
local function fake_cmd_builder(calls)
  return function(host, port)
    calls[#calls + 1] = { host = host, port = port }
    return { cmd = { "sleep-stub", host, tostring(port) }, cwd = "/tmp", env = {} }
  end
end

local function fresh_home()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Resets module state + config to a clean, fully-stubbed slate before each
--- test (no real process ever spawned, no real `awiwi#get_markers` call).
local function reset(opts)
  server._reset()
  vim.g.awiwi_home = fresh_home()
  vim.g.awiwi_server_port = nil
  server.config.get_markers = function(_marker)
    return { "fake-marker" }
  end
  if opts and opts.system then
    server.config.system = opts.system
  end
  if opts and opts.cmd_builder then
    server.config.cmd_builder = opts.cmd_builder
  end
end

describe("server.get_default_port", function()
  it("returns the literal '5823'", function()
    eq("5823", server.get_default_port())
  end)
end)

describe("server.start_server / server_is_running", function()
  it("marks the server running after a successful spawn, with host/port forwarded to the command builder", function()
    reset({ system = fake_system() })
    local builder_calls = {}
    server.config.cmd_builder = fake_cmd_builder(builder_calls)

    local okv = server.start_server("localhost")

    ok(okv, "start_server should report success")
    eq(true, server.server_is_running())
    eq(1, #builder_calls)
    eq("localhost", builder_calls[1].host)
    eq("5823", builder_calls[1].port)
  end)

  it("normalizes '*' to 0.0.0.0", function()
    reset({ system = fake_system() })
    local builder_calls = {}
    server.config.cmd_builder = fake_cmd_builder(builder_calls)

    server.start_server("*")

    eq("0.0.0.0", builder_calls[1].host)
  end)

  it("normalizes 'all' to 0.0.0.0", function()
    reset({ system = fake_system() })
    local builder_calls = {}
    server.config.cmd_builder = fake_cmd_builder(builder_calls)

    server.start_server("all")

    eq("0.0.0.0", builder_calls[1].host)
  end)

  it("normalizes '' / '127.0.0.1' / '::1' to localhost", function()
    for _, h in ipairs({ "", "127.0.0.1", "::1" }) do
      reset({ system = fake_system() })
      local builder_calls = {}
      server.config.cmd_builder = fake_cmd_builder(builder_calls)

      server.start_server(h)

      eq("localhost", builder_calls[1].host)
    end
  end)

  it("passes any other host through verbatim", function()
    reset({ system = fake_system() })
    local builder_calls = {}
    server.config.cmd_builder = fake_cmd_builder(builder_calls)

    server.start_server("example.org")

    eq("example.org", builder_calls[1].host)
  end)

  it("refuses to spawn a second process when already running, and leaves existing state untouched", function()
    reset({ system = fake_system() })
    local builder_calls = {}
    server.config.cmd_builder = fake_cmd_builder(builder_calls)

    server.start_server("localhost", "9000")
    local okv, err = server.start_server("example.org", "9999")

    eq(false, okv)
    ok(err ~= nil, "expected an error message")
    eq(1, #builder_calls) -- second call never reached the command builder
    eq(true, server.server_is_running())
  end)

  it("Bug #1 regression: does not report running when the spawn errors out synchronously", function()
    reset({ system = fake_system({ spawn_error = "ENOENT: uv not found" }) })
    server.config.cmd_builder = fake_cmd_builder({})

    local okv, err = server.start_server("localhost")

    eq(false, okv)
    ok(err ~= nil, "expected an error message")
    eq(false, server.server_is_running())
  end)

  it("Bug #1 regression: does not report running when the process exits immediately with a nonzero code", function()
    reset({ system = fake_system({ exit_code = 1 }) })
    server.config.cmd_builder = fake_cmd_builder({})

    server.start_server("localhost")

    eq(false, server.server_is_running())
  end)
end)

describe("server.stop_server", function()
  it("is a no-op when not running", function()
    reset({ system = fake_system() })
    server.stop_server() -- must not error
    eq(false, server.server_is_running())
  end)

  it("kills the running process and resets state", function()
    reset({ system = fake_system() })
    server.config.cmd_builder = fake_cmd_builder({})
    server.start_server("localhost")
    ok(server.server_is_running(), "precondition: server should be running")

    server.stop_server()

    eq(false, server.server_is_running())
  end)
end)

describe("server.server_logs", function()
  it("surfaces an error (not a crash) when buffers are empty", function()
    reset({ system = fake_system() })
    local text, err = server.server_logs()
    eq(nil, text)
    ok(err ~= nil, "expected an error message for empty logs")
  end)

  it("Bug #6 regression: an unknown key returns a clean error, not a raw crash", function()
    reset({ system = fake_system() })
    local text, err = server.server_logs("bogus-key")
    eq(nil, text)
    ok(err ~= nil, "expected a clean error message for an unknown log key")
  end)

  it("returns only stdout lines for 'stdout', and stdout+stderr for the default key", function()
    reset({ system = fake_system() })
    server.config.cmd_builder = fake_cmd_builder({})
    local stdout_cb, stderr_cb
    server.config.system = function(cmd, sys_opts, on_exit)
      stdout_cb, stderr_cb = sys_opts.stdout, sys_opts.stderr
      return { kill = function() end }
    end

    server.start_server("localhost")
    stdout_cb(nil, "server: line one\n")
    stderr_cb(nil, "warn: line two\n")

    eq("server: line one", server.server_logs("stdout"))
    eq("server: line one\nwarn: line two", server.server_logs())
  end)
end)

describe("server.serve", function()
  it("Bug #2 regression: never blocks on a fixed sleep — readiness is a bounded poll", function()
    reset({ system = fake_system({ stdout_line = "Uvicorn running\n" }) })
    server.config.cmd_builder = fake_cmd_builder({})
    vim.cmd("edit " .. vim.fn.tempname())

    local start = vim.uv.hrtime()
    server.serve()
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    ok(elapsed_ms < 50, ("serve() took %dms, expected a fast non-blocking readiness poll"):format(elapsed_ms))
    eq(true, server.server_is_running())
  end)

  it("Bug #3 regression: resolves g:awiwi_server_port the same way start_server does", function()
    reset({ system = fake_system({ stdout_line = "ready\n" }) })
    vim.g.awiwi_server_port = "9911"
    local builder_calls = {}
    server.config.cmd_builder = fake_cmd_builder(builder_calls)
    vim.cmd("edit " .. vim.fn.tempname())

    server.serve()

    eq("9911", builder_calls[1].port)
  end)

  it("Bug #4 regression: derives the URL target via proper suffix removal", function()
    reset({ system = fake_system() })

    eq("/todo", server.resolve_target(vim.g.awiwi_home .. "/journal/todos.md"))
    eq(
      "journal/2026-07-05",
      server.resolve_target(vim.g.awiwi_home .. "/journal/2026/07/2026-07-05.md")
    )
    eq("recipes/foo.md", server.resolve_target(vim.g.awiwi_home .. "/recipes/foo.md"))
  end)
end)

describe("server.default_cmd_builder", function()
  it("targets the real FastAPI entrypoint awiwi.app:app", function()
    reset({ system = fake_system() })

    local built = server.default_cmd_builder("localhost", "5823")

    local found = false
    for _, arg in ipairs(built.cmd) do
      if arg == "awiwi.app:app" then
        found = true
      end
    end
    ok(found, "expected default_cmd_builder's cmd to reference awiwi.app:app")
  end)

  it("threads AWIWI_HOME=g:awiwi_home through the env table", function()
    reset({ system = fake_system() })
    vim.g.awiwi_home = "/tmp/some-awiwi-home"

    local built = server.default_cmd_builder("localhost", "5823")

    ok(built.env ~= nil, "expected default_cmd_builder to set env")
    eq("/tmp/some-awiwi-home", built.env.AWIWI_HOME)
  end)
end)

describe("server.start_server env threading", function()
  it("forwards the command builder's env (AWIWI_HOME) to the spawned process", function()
    local system_calls = {}
    reset({
      system = function(cmd, opts, on_exit)
        local stub = fake_system()
        system_calls[#system_calls + 1] = opts
        return stub(cmd, opts, on_exit)
      end,
    })
    -- Use the real default_cmd_builder (not the fake) to prove the
    -- AWIWI_HOME env actually reaches vim.system's opts.
    server.config.cmd_builder = server.default_cmd_builder

    server.start_server("localhost")

    eq(1, #system_calls)
    eq(vim.g.awiwi_home, system_calls[1].env.AWIWI_HOME)
  end)
end)

describe("server._write_json_config", function()
  it("serializes globals + marker lists into <home>/config.json", function()
    reset({ system = fake_system() })
    vim.g.awiwi_search_engine = "plain"
    vim.g.awiwi_screensaver = "5"
    vim.g.awiwi_link_color = "blue"
    server.config.get_markers = function(marker)
      return { marker .. "-1", marker .. "-2" }
    end

    server._write_json_config()

    local path = vim.g.awiwi_home .. "/config.json"
    local f = assert(io.open(path, "r"))
    local content = f:read("*a")
    f:close()
    local decoded = vim.json.decode(content)

    eq("plain", decoded.search_engine)
    eq(vim.g.awiwi_home, decoded.home)
    eq("5", decoded.screensaver)
    eq("blue", decoded.link_color)
    eq({ "todo-1", "todo-2" }, decoded.todo_markers)
    eq({ "due-1", "due-2" }, decoded.due_markers)

    -- don't leak config globals into later spec files (syn's
    -- setup_highlights honors g:awiwi_link_color)
    vim.g.awiwi_search_engine = nil
    vim.g.awiwi_screensaver = nil
    vim.g.awiwi_link_color = nil
  end)
end)
