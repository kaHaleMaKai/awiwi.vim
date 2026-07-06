-- Acceptance specs for lua/awiwi/picker.lua — the single UI seam that isolates
-- every fzf/telescope/vim.ui.select picker used by cmd.lua. Per the brief's
-- `## Pickers` contract and the orchestrator's picker-backend ADR:
--   * default backend = vim.ui.select (stubbable headless)
--   * telescope auto-upgrade when `require('telescope')` succeeds — smoke-tested
--     here via a FAKE telescope injected through `picker.deps.require`; the real
--     telescope is never required for the suite to pass.
--   * live-grep pickers materialize via rg (vim.system) then select.

local picker = require("awiwi.picker")

-- Snapshot/restore picker.deps around each test so stubs don't leak.
local function with_deps(overrides, fn)
  local saved = {}
  for k, v in pairs(picker.deps) do
    saved[k] = v
  end
  for k, v in pairs(overrides) do
    picker.deps[k] = v
  end
  local ok, err = pcall(fn)
  for k in pairs(picker.deps) do
    picker.deps[k] = nil
  end
  for k, v in pairs(saved) do
    picker.deps[k] = v
  end
  if not ok then
    error(err, 0)
  end
end

-- A fake vim.system-shaped proc: :wait() returns a canned result table.
local function fake_proc(result)
  return { wait = function() return result end }
end

-- A fake telescope module set + recorder. Simulates telescope invoking
-- attach_mappings and a default selection of the first finder result.
local function fake_telescope()
  local rec = { new_count = 0, find_count = 0 }
  local action_state = {
    get_selected_entry = function()
      return rec.selected
    end,
  }
  local actions = {
    close = function()
      rec.closed = true
    end,
    select_default = {
      replace = function(_self, replacement)
        rec.replacement = replacement
      end,
    },
  }
  local finders = {
    new_table = function(o)
      rec.finder = o
      return o
    end,
  }
  local conf = {
    values = {
      generic_sorter = function()
        return { kind = "sorter" }
      end,
    },
  }
  local pickers = {
    new = function(_opts, cfg)
      rec.new_count = rec.new_count + 1
      rec.cfg = cfg
      return {
        find = function()
          rec.find_count = rec.find_count + 1
          cfg.attach_mappings(1, function() end)
          rec.selected = cfg.finder.entry_maker(cfg.finder.results[1])
          if rec.replacement then
            rec.replacement()
          end
        end,
      }
    end,
  }
  local modules = {
    ["telescope.pickers"] = pickers,
    ["telescope.finders"] = finders,
    ["telescope.config"] = conf,
    ["telescope.actions"] = actions,
    ["telescope.actions.state"] = action_state,
  }
  local req = function(name)
    local m = modules[name]
    if m == nil then
      error("module not found: " .. name)
    end
    return m
  end
  return req, rec
end

describe("picker.select (vim.ui.select fallback)", function()
  it("uses ui_select and calls on_choice with the chosen item", function()
    with_deps({
      require = function()
        error("no telescope")
      end,
      ui_select = function(items, _opts, on_choice)
        on_choice(items[2], 2)
      end,
    }, function()
      local chosen
      picker.select({
        items = { "a", "b", "c" },
        prompt = "pick",
        on_choice = function(item)
          chosen = item
        end,
      })
      eq("b", chosen)
    end)
  end)

  it("does not call on_choice when the user cancels (nil)", function()
    with_deps({
      require = function()
        error("no telescope")
      end,
      ui_select = function(_items, _opts, on_choice)
        on_choice(nil)
      end,
    }, function()
      local called = false
      picker.select({
        items = { "a" },
        on_choice = function()
          called = true
        end,
      })
      eq(false, called)
    end)
  end)

  it("passes prompt + format_item through to ui_select", function()
    local got
    with_deps({
      require = function()
        error("no telescope")
      end,
      ui_select = function(_items, opts, _on_choice)
        got = opts
      end,
    }, function()
      picker.select({
        items = { 1 },
        prompt = "Choose one",
        format_item = tostring,
      })
    end)
    eq("Choose one", got.prompt)
    ok(type(got.format_item) == "function", "format_item forwarded")
  end)
end)

describe("picker.select (telescope backend)", function()
  it("constructs a telescope picker and drives on_choice on selection", function()
    local req, rec = fake_telescope()
    with_deps({ require = req }, function()
      local chosen
      picker.select({
        items = { "first", "second" },
        prompt = "ts",
        on_choice = function(item)
          chosen = item
        end,
      })
      eq(1, rec.new_count)
      eq(1, rec.find_count)
      eq("ts", rec.cfg.prompt_title)
      eq("first", chosen)
    end)
  end)
end)

describe("picker backend selection", function()
  it("falls back to ui_select when telescope require fails", function()
    local used_ui = false
    with_deps({
      require = function(name)
        error("cannot require " .. name)
      end,
      ui_select = function()
        used_ui = true
      end,
    }, function()
      picker.select({ items = { "x" } })
    end)
    eq(true, used_ui)
  end)
end)

describe("picker.files", function()
  it("globs files under dir and hands full path to a custom sink", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/sub", "p")
    local f = dir .. "/sub/note.md"
    local fh = io.open(f, "w")
    fh:write("x")
    fh:close()

    local chosen
    with_deps({
      require = function()
        error("no telescope")
      end,
      ui_select = function(items, _opts, on_choice)
        on_choice(items[1], 1)
      end,
    }, function()
      picker.files({
        dir = dir,
        on_choice = function(path)
          chosen = path
        end,
      })
    end)
    eq(f, chosen)
  end)
end)

describe("picker.grep", function()
  it("runs argv, parses file:line:col, default jump navigates (B2 regression)", function()
    local jumped_file
    local orig_cmd = vim.cmd
    with_deps({
      require = function()
        error("no telescope")
      end,
      system = function(_argv, _opts)
        return fake_proc({ stdout = "/tmp/foo.md:12:3:some heading\n", code = 0 })
      end,
      ui_select = function(items, _opts, on_choice)
        on_choice(items[1], 1)
      end,
    }, function()
      -- default on_choice edits + positions cursor; intercept vim.cmd/edit
      vim.cmd = function(c)
        if type(c) == "string" and c:match("^edit ") then
          jumped_file = c
        end
      end
      local ok_, err = pcall(function()
        picker.grep({ argv = { "rg", "pattern" }, prompt = "g" })
      end)
      vim.cmd = orig_cmd
      if not ok_ then
        error(err, 0)
      end
    end)
    ok(jumped_file ~= nil and jumped_file:find("foo.md", 1, true), "default jump edited the file")
  end)

  it("applies filter_argv as a second (stdin-piped) rg pass", function()
    local calls = {}
    with_deps({
      require = function()
        error("no telescope")
      end,
      system = function(argv, opts)
        calls[#calls + 1] = { argv = argv, opts = opts }
        if #calls == 1 then
          return fake_proc({ stdout = "keep\ndrop\n", code = 0 })
        end
        return fake_proc({ stdout = "keep\n", code = 0 })
      end,
      ui_select = function(items, _opts, _on_choice)
        calls.items = items
      end,
    }, function()
      picker.grep({
        argv = { "rg", "p" },
        filter_argv = { "rg", "-v", "drop" },
        prompt = "g",
      })
    end)
    eq(2, #calls)
    eq("keep\ndrop\n", calls[2].opts.stdin)
    eq({ "keep" }, calls.items)
  end)

  it("strips ANSI color codes and applies transform to each line", function()
    local items
    with_deps({
      require = function()
        error("no telescope")
      end,
      system = function()
        return fake_proc({ stdout = "/f:1:1:\27[31m## Title\27[0m\n", code = 0 })
      end,
      ui_select = function(its, _opts, _on_choice)
        items = its
      end,
    }, function()
      picker.grep({
        argv = { "rg" },
        transform = function(line)
          return (line:gsub("^(.-)##+%s+", "%1", 1))
        end,
      })
    end)
    eq({ "/f:1:1:Title" }, items)
  end)
end)
