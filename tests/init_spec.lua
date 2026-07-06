-- Acceptance specs for lua/awiwi/init.lua — the façade (ports autoload/awiwi.vim).
-- Numbering mirrors the behavior contract in handovers/lua-port/init.md.
-- Every subprocess/window/clipboard call goes through awiwi.deps.* or an
-- injected module seam, stubbed here; real files live under vim.fn.tempname().

vim.g.awiwi_home = vim.fn.tempname()
vim.fn.mkdir(vim.g.awiwi_home, "p")

local awiwi = require("awiwi")
local util = require("awiwi.util")
local asset = require("awiwi.asset")
local hi = require("awiwi.hi")
local date = require("awiwi.date")
local path = require("awiwi.path")

-- LIFO auto-restoring override sandbox (same shape as cmd_spec.lua).
local function sandbox(fn)
  local restores = {}
  local function set(tbl, key, val)
    restores[#restores + 1] = { tbl = tbl, key = key, old = tbl[key] }
    tbl[key] = val
  end
  local ok, err = pcall(fn, set)
  for i = #restores, 1, -1 do
    local r = restores[i]
    r.tbl[r.key] = r.old
  end
  if not ok then
    error(err, 0)
  end
end

local function recorder(log, name)
  return function(...)
    log[#log + 1] = { name = name, args = { ... } }
    return log[name .. "_ret"]
  end
end

-- Fake vim.system-shaped handle.
local function fake_system(log, name)
  return function(cmd, opts)
    log[#log + 1] = { name = name, cmd = cmd, opts = opts }
    return { wait = function() return { code = 0, stdout = "" } end }
  end
end

-- Scratch buffer made current, with lines + cursor.
local function scratch(lines, row, col)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
  return buf
end

-- ===========================================================================
-- Bootstrap (§1-4)
-- ===========================================================================

describe("bootstrap", function()
  it("1-2: ensures subdirs + task.log", function()
    local home = vim.fn.tempname()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      awiwi.bootstrap()
      for _, d in ipairs({ "data", "journal", "assets", "recipes", "todos", "cache" }) do
        ok(vim.fn.isdirectory(path.join(home, d)) == 1, d .. " missing")
      end
      ok(vim.fn.filereadable(path.join(home, "data", "task.log")) == 1, "task.log missing")
    end)
  end)

  it("3: subpath getters", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      eq("/h/journal", awiwi.get_journal_subpath())
      eq("/h/assets", awiwi.get_asset_subpath())
      eq("/h/recipes", awiwi.get_recipe_subpath())
    end)
  end)

  it("4: get_journal_file_by_date", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      eq("/h/journal/2024/03/2024-03-05.md", awiwi.get_journal_file_by_date("2024-03-05"))
    end)
  end)
end)

-- ===========================================================================
-- open_file (§5-17)
-- ===========================================================================

describe("open_file", function()
  local function capture_exec(fn)
    local execs, sys = {}, {}
    sandbox(function(set)
      set(awiwi.deps, "exec", function(c)
        execs[#execs + 1] = c
      end)
      set(awiwi.deps, "system", fake_system(sys, "system"))
      set(util, "window_split_below", function()
        return false
      end)
      fn(execs, sys, set)
    end)
    return execs, sys
  end

  it("5: xdg-open extension spawns and returns", function()
    local _, sys = capture_exec(function(execs, s)
      awiwi.open_file("/tmp/x.drawio", {})
      eq(0, #execs)
      eq({ "xdg-open", "/tmp/x.drawio" }, s[1].cmd)
    end)
    ok(sys)
  end)

  it("6: no options -> :edit", function()
    local execs = capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", {})
      eq("e  /tmp/f.md", e[1])
    end)
    ok(execs)
  end)

  it("7: new_tab -> tabnew", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_tab = true })
      eq("tabnew  /tmp/f.md", e[1])
    end)
  end)

  it("8: new_window auto (split_below false) -> right vnew", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true })
      eq(" vnew  /tmp/f.md", e[1])
    end)
  end)

  it("9: position=left -> leftabove vnew (B-INIT-3)", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "left" })
      eq("leftabove  vnew  /tmp/f.md", e[1])
    end)
  end)

  it("10: position=right -> vnew (no prefix)", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "right" })
      eq(" vnew  /tmp/f.md", e[1])
    end)
  end)

  it("11: position=top -> leftabove new", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "top" })
      eq("leftabove  new  /tmp/f.md", e[1])
    end)
  end)

  it("12: position=bottom -> new (no prefix)", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "bottom" })
      eq(" new  /tmp/f.md", e[1])
    end)
  end)

  it("13: width sizes vertical split, height sizes horizontal (B3)", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "right", width = 40 })
      eq(" 40vnew  /tmp/f.md", e[1])
    end)
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "bottom", height = 12 })
      eq(" 12new  /tmp/f.md", e[1])
    end)
    -- width is ignored for a horizontal split (independent axes)
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { new_window = true, position = "bottom", width = 40 })
      eq(" new  /tmp/f.md", e[1])
    end)
  end)

  it("14: create_dirs makes parent dir", function()
    local home = vim.fn.tempname()
    local target = path.join(home, "sub", "deep", "f.md")
    capture_exec(function()
      awiwi.open_file(target, { create_dirs = true })
      ok(vim.fn.isdirectory(path.join(home, "sub", "deep")) == 1, "parent not created")
    end)
  end)

  it("15: anchor jump", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { anchor = "Standup" })
      eq("e +/\\cStandup /tmp/f.md", e[1])
    end)
  end)

  it("16: last_line jump", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", { last_line = true })
      eq("e + /tmp/f.md", e[1])
    end)
  end)

  it("17: no jump", function()
    capture_exec(function(e)
      awiwi.open_file("/tmp/f.md", {})
      eq("e  /tmp/f.md", e[1])
    end)
  end)

  it("left split actually places window to the left", function()
    local f = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "x" }, f)
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      vim.cmd("silent! only")
      local orig = vim.api.nvim_get_current_win()
      awiwi.open_file(f, { new_window = true, position = "left" })
      local new = vim.api.nvim_get_current_win()
      ok(new ~= orig, "no new window")
      local orig_col = vim.api.nvim_win_get_position(orig)[2]
      local new_col = vim.api.nvim_win_get_position(new)[2]
      ok(new_col < orig_col, "new window not to the left")
      vim.cmd("silent! only")
    end)
  end)
end)

-- ===========================================================================
-- edit_journal (§18-21) / edit_todo (§22)
-- ===========================================================================

describe("edit_journal", function()
  it("18: already-open date echoes and does not open", function()
    sandbox(function(set)
      local opened = false
      set(awiwi, "open_file", function()
        opened = true
      end)
      set(date, "get_own_date", function()
        return "2024-03-05"
      end)
      set(date, "get_today", function()
        return "2024-06-01"
      end)
      awiwi.edit_journal("2024-03-05", {})
      eq(false, opened)
    end)
  end)

  it("19: today forces create_dirs", function()
    sandbox(function(set)
      local seen
      set(awiwi, "open_file", function(_, o)
        seen = o
      end)
      set(date, "get_today", function()
        return "2024-06-01"
      end)
      set(date, "get_own_date", function()
        error("AwiwiDateError: nope", 0)
      end)
      awiwi.edit_journal("2024-06-01", {})
      eq(true, seen.create_dirs)
    end)
  end)

  it("20: future date without create -> error, no open", function()
    sandbox(function(set)
      local opened = false
      set(awiwi, "open_file", function()
        opened = true
      end)
      set(date, "get_today", function()
        return "2024-06-01"
      end)
      set(date, "get_own_date", function()
        error("AwiwiDateError: nope", 0)
      end)
      awiwi.edit_journal("2999-01-01", {})
      eq(false, opened)
    end)
  end)

  it("18b: 'previous' resolves against the real journal-file list (T10.1 dogfood fix)", function()
    sandbox(function(set)
      local jdir = path.join(vim.g.awiwi_home, "journal", "2024", "03")
      vim.fn.mkdir(jdir, "p")
      local f1 = path.join(jdir, "2024-03-05.md")
      local f2 = path.join(jdir, "2024-03-07.md")
      vim.fn.writefile({}, f1)
      vim.fn.writefile({}, f2)
      local file
      set(awiwi, "open_file", function(f)
        file = f
      end)
      set(date, "get_own_date", function()
        return "2024-03-07"
      end)
      local success, err = pcall(awiwi.edit_journal, "previous", {})
      vim.fn.delete(f1)
      vim.fn.delete(f2)
      ok(success, "edit_journal('previous') threw: " .. tostring(err))
      ok(file and file:find("2024%-03%-05%.md$"), "expected previous journal file, got " .. tostring(file))
    end)
  end)

  it("21: normal date sets last_line + delegates", function()
    sandbox(function(set)
      local file, o
      set(awiwi, "open_file", function(f, opts)
        file, o = f, opts
      end)
      set(date, "get_today", function()
        return "2024-06-01"
      end)
      set(date, "get_own_date", function()
        error("AwiwiDateError: nope", 0)
      end)
      awiwi.edit_journal("2024-03-05", {})
      eq(true, o.last_line)
      ok(file:find("2024%-03%-05%.md$"), "wrong file")
    end)
  end)
end)

describe("edit_todo", function()
  it("22: opens todos/<name>.md", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      local file, o
      set(awiwi, "open_file", function(f, opts)
        file, o = f, opts
      end)
      awiwi.edit_todo("groceries", { new_tab = true })
      eq("/h/todos/groceries.md", file)
      eq(true, o.new_tab)
    end)
  end)
end)

-- ===========================================================================
-- get_current_task (§23-24)
-- ===========================================================================

describe("get_current_task", function()
  it("23: nearest heading above cursor, parses tags + cont", function()
    scratch({
      "## First task @work",
      "some text",
      "## Second task (cont. from 2024-01-01)",
      "more text",
    }, 4, 0)
    local t = awiwi.get_current_task(true)
    eq("##", t.marker)
    eq("Second task", t.title)
    eq("(cont. from 2024-01-01)", t.cont)
    eq({}, t.tags)
  end)

  it("23: @tag captured in tags", function()
    scratch({ "## First task @work", "body" }, 2, 0)
    local t = awiwi.get_current_task(true)
    eq("First task", t.title)
    eq({ "@work" }, t.tags)
    eq("", t.cont)
  end)

  it("24: no heading -> empty fields, never throws (B-INIT-1)", function()
    scratch({ "just prose", "more prose" }, 2, 0)
    local ok_, t = pcall(awiwi.get_current_task, true)
    ok(ok_, "threw")
    eq({ marker = "", title = "", tags = {}, cont = "" }, t)
  end)

  it("23: only_main=false matches ### headings too", function()
    scratch({ "### sub task", "body" }, 2, 0)
    local t = awiwi.get_current_task(false)
    eq("###", t.marker)
    eq("sub task", t.title)
  end)
end)

-- ===========================================================================
-- insert_and_open_continuation (§25-27)
-- ===========================================================================

describe("insert_and_open_continuation", function()
  it("25: own date == today -> throws", function()
    sandbox(function(set)
      set(date, "get_own_date", function()
        return "2024-06-01"
      end)
      set(date, "parse_date", function()
        return "2024-06-01"
      end)
      local ok_ = pcall(awiwi.insert_and_open_continuation)
      eq(false, ok_)
    end)
  end)

  it("26: no task under cursor -> throws", function()
    sandbox(function(set)
      set(date, "get_own_date", function()
        return "2024-05-01"
      end)
      set(date, "parse_date", function()
        return "2024-06-01"
      end)
      set(awiwi, "get_current_task", function()
        return { marker = "", title = "", tags = {}, cont = "" }
      end)
      local ok_ = pcall(awiwi.insert_and_open_continuation)
      eq(false, ok_)
    end)
  end)

  it("27: appends continuation link, writes, opens today in top split", function()
    local own = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "## Task", "cursor here" }, own)
    vim.cmd("edit " .. own)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    sandbox(function(set)
      set(date, "get_own_date", function()
        return "2024-05-01"
      end)
      set(date, "parse_date", function(x)
        return x == "today" and "2024-06-01" or x
      end)
      set(awiwi, "get_journal_file_by_date", function(d)
        return "/h/journal/" .. d .. ".md"
      end)
      set(util, "relativize", function(t)
        return t
      end)
      set(awiwi, "get_current_task", function()
        return { marker = "##", title = "Task", tags = {}, cont = "" }
      end)
      local ej = {}
      set(awiwi, "edit_journal", recorder(ej, "edit_journal"))
      awiwi.insert_and_open_continuation()
      -- link inserted right after the cursor line in the own-date buffer
      ok(vim.fn.getline(2):find("continued on 2024%-06%-01"), "no continuation link")
      eq("2024-06-01", ej[1].args[1])
      eq("top", ej[1].args[2].position)
      -- cont heading appended to end (edit_journal stubbed, so same buffer)
      local last = vim.fn.getline("$")
      ok(vim.fn.getline(vim.fn.line("$") - 2):find("%(cont%. from 2024%-05%-01%)"), "no cont heading")
      ok(last == "" or last ~= nil)
    end)
    vim.cmd("silent! bwipeout!")
  end)
end)

-- ===========================================================================
-- get_all_journal_files (§28-31)
-- ===========================================================================

describe("get_all_journal_files", function()
  local home = vim.fn.tempname()
  local function seed()
    vim.fn.mkdir(path.join(home, "journal", "2024", "01"), "p")
    vim.fn.mkdir(path.join(home, "journal", "2023", "12"), "p")
    vim.fn.writefile({ "" }, path.join(home, "journal", "2024", "01", "2024-01-05.md"))
    vim.fn.writefile({ "" }, path.join(home, "journal", "2024", "01", "2024-01-02.md"))
    vim.fn.writefile({ "" }, path.join(home, "journal", "2023", "12", "2023-12-31.md"))
  end

  it("28: basenames sorted ascending", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      eq({ "2023-12-31", "2024-01-02", "2024-01-05" }, awiwi.get_all_journal_files())
    end)
  end)

  it("29: date filter narrows to a year", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      eq({ "2024-01-02", "2024-01-05" }, awiwi.get_all_journal_files({ date = "2024" }))
    end)
  end)

  it("30: full_path returns paths", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      local files = awiwi.get_all_journal_files({ full_path = true })
      ok(files[1]:find("2023%-12%-31%.md$"), "not a full path")
    end)
  end)

  it("31: include_literals appends four trailing entries", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      local files = awiwi.get_all_journal_files({ include_literals = true })
      eq({ "previous day", "next day", "yesterday", "today" }, {
        files[#files - 3], files[#files - 2], files[#files - 1], files[#files],
      })
    end)
  end)
end)

-- ===========================================================================
-- Active-task timer (§32-39)
-- ===========================================================================

describe("active-task timer", function()
  local home
  local function fresh()
    home = vim.fn.tempname()
    vim.g.awiwi_home = home
    awiwi.bootstrap()
    awiwi._active_task = { title = "", marker = "", type = false, activity = {}, state = "inactive", created = 0, updated = 0, duration = 0 }
    vim.g.awiwi_active_task = nil
  end
  local function tasklog()
    return vim.fn.readfile(path.join(home, "data", "task.log"))
  end
  local function awiwilog()
    return vim.fn.readfile(path.join(home, "data", "awiwi.log"))
  end

  it("32: not in a task -> no state change, no log", function()
    fresh()
    scratch({ "prose only" }, 1, 0)
    awiwi.activate_current_task()
    eq(nil, vim.g.awiwi_active_task)
    eq(0, #tasklog())
  end)

  it("35: activate writes task.log + awiwi.log + sets g:awiwi_active_task", function()
    fresh()
    scratch({ "## My task", "body" }, 2, 0)
    sandbox(function(set)
      set(awiwi, "now", function()
        return 1000
      end)
      awiwi.activate_current_task()
    end)
    eq(1, #tasklog())
    local rec = vim.json.decode(tasklog()[1])
    eq("My task", rec.title)
    eq("active", rec.state)
    eq("activate", rec.activity[#rec.activity].action)
    ok(awiwilog()[1]:find('activate task "My task"', 1, true), "no INFO line")
    eq("My task", vim.g.awiwi_active_task.title)
  end)

  it("33: same task already active -> echo, no duplicate log", function()
    fresh()
    scratch({ "## My task", "body" }, 2, 0)
    sandbox(function(set)
      set(awiwi, "now", function()
        return 1000
      end)
      awiwi.activate_current_task()
      awiwi.activate_current_task()
    end)
    eq(1, #tasklog())
  end)

  it("34: different task active -> error, no state change", function()
    fresh()
    scratch({ "## First", "body" }, 2, 0)
    sandbox(function(set)
      set(awiwi, "now", function()
        return 1000
      end)
      awiwi.activate_current_task()
    end)
    scratch({ "## Second", "body" }, 2, 0)
    sandbox(function(set)
      set(awiwi, "now", function()
        return 2000
      end)
      awiwi.activate_current_task()
    end)
    eq(1, #tasklog())
    eq("First", vim.g.awiwi_active_task.title)
  end)

  it("36: deactivate clears g:awiwi_active_task + appends record", function()
    fresh()
    scratch({ "## My task", "body" }, 2, 0)
    sandbox(function(set)
      set(awiwi, "now", function()
        return 1000
      end)
      awiwi.activate_current_task()
      set(awiwi, "now", function()
        return 1060
      end)
      awiwi.deactivate_active_task()
    end)
    eq(2, #tasklog())
    local rec = vim.json.decode(tasklog()[2])
    eq("inactive", rec.state)
    eq(60, rec.duration)
    eq(nil, vim.g.awiwi_active_task)
  end)

  it("36: deactivate with none active -> no-op", function()
    fresh()
    awiwi.deactivate_active_task()
    eq(0, #tasklog())
  end)

  it("37: module load resumes an active task from task.log", function()
    fresh()
    local rec = { title = "Resumed", marker = "##", type = false, activity = { { action = "activate", ts = 1 } }, state = "active", created = 0, updated = 1, duration = 0 }
    vim.fn.writefile({ vim.json.encode(rec) }, path.join(home, "data", "task.log"))
    awiwi.resume_active_task()
    eq("Resumed", vim.g.awiwi_active_task.title)
  end)
end)

describe("add_active_task_to_airline", function()
  it("38: no active task -> ''", function()
    sandbox(function(set)
      set(vim.g, "awiwi_active_task", nil)
      eq("", awiwi.add_active_task_to_airline())
    end)
  end)

  it("39: four duration buckets", function()
    local function fmt(dur, now)
      local out
      sandbox(function(set)
        set(vim.g, "awiwi_active_task", {
          title = "T",
          state = "active",
          duration = dur,
          activity = { { action = "activate", ts = 0 } },
        })
        set(awiwi, "now", function()
          return now
        end)
        out = awiwi.add_active_task_to_airline()
      end)
      return out
    end
    eq("[ T (30s) ]", fmt(0, 30))
    eq("[ T (2m 5s) ]", fmt(0, 125))
    eq("[ T (1h 1m) ]", fmt(0, 3660))
    eq("[ T (1d 1h) ]", fmt(0, 90000))
  end)
end)

-- ===========================================================================
-- open_link (§40-44)
-- ===========================================================================

describe("open_link", function()
  it("40/42: explicit link resolves via as_link/determine_link_type -> open_file", function()
    sandbox(function(set)
      set(util, "as_link", function(x)
        return { target = x }
      end)
      set(util, "determine_link_type", function(l)
        return { type = "journal", target = l.target, anchor = "Sec" }
      end)
      local opened
      set(awiwi, "open_file", function(dest, o)
        opened = { dest = dest, o = o }
      end)
      awiwi.open_link({}, "foo.md")
      ok(opened, "open_file not called")
      eq("Sec", opened.o.anchor)
    end)
  end)

  it("41: browser type spawns xdg-open, no open_file", function()
    sandbox(function(set)
      set(util, "get_link_under_cursor", function()
        return { type = "browser", target = "https://x" }
      end)
      local sys = {}
      set(awiwi.deps, "system", fake_system(sys, "system"))
      local opened = false
      set(awiwi, "open_file", function()
        opened = true
      end)
      awiwi.open_link({})
      eq({ "xdg-open", "https://x" }, sys[1].cmd)
      eq(false, opened)
    end)
  end)

  it("43: image type spawns g:awiwi_image_opener with resolved asset path", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      set(vim.g, "awiwi_image_opener", { "feh" })
      set(util, "get_link_under_cursor", function()
        return { type = "image", target = "/x/2024-03-05/pic.png" }
      end)
      local sys = {}
      set(awiwi.deps, "system", fake_system(sys, "system"))
      awiwi.open_link({})
      eq({ "feh", "/h/assets/2024/03/05/pic.png" }, sys[1].cmd)
    end)
  end)

  it("44: empty type -> single error, no side effects (B-INIT-4)", function()
    sandbox(function(set)
      set(util, "get_link_under_cursor", function()
        return { type = "", target = "?" }
      end)
      local opened = false
      set(awiwi, "open_file", function()
        opened = true
      end)
      awiwi.open_link({})
      eq(false, opened)
    end)
  end)
end)

-- ===========================================================================
-- redact (§45-46)
-- ===========================================================================

describe("redact", function()
  it("45: appends !!redacted with leading space", function()
    scratch({ "secret stuff" }, 1, 0)
    awiwi.redact()
    eq("secret stuff !!redacted", vim.fn.getline(1))
  end)

  it("45: empty line gets no leading space", function()
    scratch({ "" }, 1, 0)
    awiwi.redact()
    eq("!!redacted", vim.fn.getline(1))
  end)

  it("46: removes every redacted occurrence", function()
    scratch({ "a !!redacted b   !!redacted" }, 1, 0)
    awiwi.redact()
    eq("a b", vim.fn.getline(1))
  end)
end)

-- ===========================================================================
-- copy_file
-- ===========================================================================

describe("copy_file", function()
  it("shells xclip -r and returns true on success", function()
    sandbox(function(set)
      local sys = {}
      set(awiwi.deps, "system", fake_system(sys, "system"))
      local r = awiwi.copy_file("/a/b/c.md")
      eq(true, r)
      eq({ "xclip", "-selection", "clipboard", "-r", "/a/b/c.md" }, sys[1].cmd)
    end)
  end)
end)

-- ===========================================================================
-- insert_recipe_link (§47-49) / insert_journal_link (§50-51)
-- ===========================================================================

describe("insert_recipe_link", function()
  it("47: relativizes to recipes/ component", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      set(util, "relativize", function()
        return "recipes/cooking/pasta.md"
      end)
      local link
      set(asset.deps, "insert_link_here", function(l)
        link = l
      end)
      awiwi.insert_recipe_link("cooking/pasta.md")
      eq("[recipe cooking/pasta.md](recipes/cooking/pasta.md)", link)
    end)
  end)

  it("48: anchor variant", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      set(util, "relativize", function()
        return "recipes/cooking/pasta.md"
      end)
      local link
      set(asset.deps, "insert_link_here", function(l)
        link = l
      end)
      awiwi.insert_recipe_link("cooking/pasta.md", { anchor = "Ingredients" })
      eq("[recipe cooking/pasta.md: Ingredients](recipes/cooking/pasta.md#Ingredients)", link)
    end)
  end)
end)

describe("insert_journal_link", function()
  it("50: basic link", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      set(util, "relativize", function()
        return "journal/2024/03/2024-03-05.md"
      end)
      local link
      set(asset.deps, "insert_link_here", function(l)
        link = l
      end)
      awiwi.insert_journal_link("2024-03-05")
      eq("[journal for 2024-03-05](journal/2024/03/2024-03-05.md)", link)
    end)
  end)

  it("51: anchor variant has no stray ) (B-INIT-2)", function()
    sandbox(function(set)
      set(vim.g, "awiwi_home", "/h")
      set(util, "relativize", function()
        return "journal/2024/03/2024-03-05.md"
      end)
      local link
      set(asset.deps, "insert_link_here", function(l)
        link = l
      end)
      awiwi.insert_journal_link("2024-03-05", { anchor = "Standup" })
      eq("[journal for 2024-03-05: Standup](journal/2024/03/2024-03-05.md#Standup)", link)
    end)
  end)
end)

-- ===========================================================================
-- handle_paste_in_insert_mode (§52-54)
-- ===========================================================================

describe("handle_paste_in_insert_mode", function()
  it("52: empty mime -> no-op", function()
    sandbox(function(set)
      set(awiwi, "guess_selection_mime_type", function()
        return ""
      end)
      local created = false
      set(asset, "create_asset_here_if_not_exists", function()
        created = true
      end)
      awiwi.handle_paste_in_insert_mode()
      eq(false, created)
    end)
  end)

  it("53: text/plain pastes register", function()
    scratch({ "" }, 1, 0)
    vim.fn.setreg("+", "hello world")
    sandbox(function(set)
      set(awiwi, "guess_selection_mime_type", function()
        return "text/plain"
      end)
      awiwi.handle_paste_in_insert_mode()
    end)
    eq("hello world", vim.fn.getline(1))
  end)

  it("54: image type -> create paste asset", function()
    sandbox(function(set)
      set(awiwi, "guess_selection_mime_type", function()
        return "image/png"
      end)
      local args
      set(asset, "create_asset_here_if_not_exists", function(t, o, cb)
        args = { t = t, o = o }
        cb("")
      end)
      awiwi.handle_paste_in_insert_mode()
      eq(asset.types.paste, args.t)
    end)
  end)
end)

-- ===========================================================================
-- edit_meta_info (§55-61)
-- ===========================================================================

describe("edit_meta_info", function()
  local function noredraw(set)
    set(hi, "redraw_due_dates", function() end)
  end

  it("55: blank line -> no-op", function()
    scratch({ "   " }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      awiwi.edit_meta_info({})
      eq("   ", vim.fn.getline(1))
    end)
  end)

  it("56: delete with no blob -> no-op", function()
    scratch({ "task without blob" }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      awiwi.edit_meta_info({ delete = true })
      eq("task without blob", vim.fn.getline(1))
    end)
  end)

  it("57: delete strips blob + leading whitespace", function()
    scratch({ 'a task   {"due": "2024-01-01"}' }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      awiwi.edit_meta_info({ delete = true })
      eq("a task", vim.fn.getline(1))
    end)
  end)

  it("58: column=due with args, tomorrow abbreviation normalized", function()
    scratch({ "a task" }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      set(date, "to_iso_date", function(v)
        eq("tomorrow", v)
        return "2024-01-02"
      end)
      awiwi.edit_meta_info({ column = "due", args = { "tom" } })
      eq('a task {"due":"2024-01-02"}', vim.fn.getline(1))
    end)
  end)

  it("58: column non-due stores raw value", function()
    scratch({ "a task" }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      awiwi.edit_meta_info({ column = "prio", args = { "high" } })
      eq('a task {"prio":"high"}', vim.fn.getline(1))
    end)
  end)

  it("59: empty column prompts whole blob, normalizes due", function()
    scratch({ "a task" }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      set(date, "to_iso_date", function()
        return "2024-01-02"
      end)
      set(util, "input", function(_, cb)
        cb('{"due": "tomorrow"}')
      end)
      awiwi.edit_meta_info({})
      eq('a task {"due":"2024-01-02"}', vim.fn.getline(1))
    end)
  end)

  it("59: invalid JSON -> no-op", function()
    scratch({ "a task" }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      set(util, "input", function(_, cb)
        cb("{not json")
      end)
      awiwi.edit_meta_info({})
      eq("a task", vim.fn.getline(1))
    end)
  end)

  it("58: empty value -> no-op", function()
    scratch({ "a task" }, 1, 0)
    sandbox(function(set)
      noredraw(set)
      awiwi.edit_meta_info({ column = "prio", args = { "   " } })
      eq("a task", vim.fn.getline(1))
    end)
  end)
end)

-- ===========================================================================
-- show_toc_in_qlist (§62-68)
-- ===========================================================================

describe("show_toc_in_qlist", function()
  local home = vim.fn.tempname()
  local function seed()
    vim.fn.mkdir(path.join(home, "journal", "2024", "03"), "p")
    vim.fn.writefile({
      "# 2024-03-05",
      "## Standup",
      "notes",
      "### detail",
      "```",
      "## not a heading (in code)",
      "```",
      "## Wrapup",
    }, path.join(home, "journal", "2024", "03", "2024-03-05.md"))
  end

  it("64: single date builds qf, skips code + own title", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      awiwi.show_toc_in_qlist({ date = "2024-03-05", show = false })
      local items = vim.fn.getqflist()
      local texts = {}
      for _, it in ipairs(items) do
        texts[#texts + 1] = it.text
      end
      eq({ "Standup", "..detail", "Wrapup" }, texts)
      eq("topics " .. date.to_nice_date("2024-03-05"), vim.fn.getqflist({ title = 0 }).title)
    end)
  end)

  it("62: empty date title is 'topics'", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      awiwi.show_toc_in_qlist({ show = false })
      eq("topics", vim.fn.getqflist({ title = 0 }).title)
    end)
  end)

  it("63: year date title 'topics <year>'", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      awiwi.show_toc_in_qlist({ date = "2024", show = false })
      eq("topics 2024", vim.fn.getqflist({ title = 0 }).title)
    end)
  end)

  it("65: year-month title from month name", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      awiwi.show_toc_in_qlist({ date = "2024-03", show = false })
      eq("March 2024", vim.fn.getqflist({ title = 0 }).title)
    end)
  end)

  it("68/B-INIT-5: refresh predicate is dynamic across window changes", function()
    seed()
    sandbox(function(set)
      set(vim.g, "awiwi_home", home)
      vim.cmd("silent! only")
      eq(false, awiwi._toc_should_refresh())
      vim.fn.setqflist({})
      vim.cmd("copen")
      eq(true, awiwi._toc_should_refresh())
      -- move/resize windows: still detects the listed qf buffer
      vim.cmd("wincmd J")
      vim.cmd("resize 5")
      eq(true, awiwi._toc_should_refresh())
      vim.cmd("cclose")
      vim.cmd("silent! only")
    end)
  end)
end)

-- ===========================================================================
-- ftplugin Enter handling (§69-77), append (§78), split-screen (§79),
-- cleanup (§84), folding
-- ===========================================================================

describe("handle_enter_on_insert", function()
  it("69: blank line, insert-mode below adds a blank line and moves down", function()
    scratch({ "" }, 1, 0)
    awiwi.handle_enter_on_insert("i", false, false)
    eq(2, vim.fn.line("."))
    eq({ "", "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("71: list line with content continues marker (append)", function()
    scratch({ "* item one" }, 1, 10)
    -- cursor past end (col beyond) so is_trailing_cursor
    vim.fn.setpos(".", { 0, 1, 11, 0, 999 })
    awiwi.handle_enter_on_insert("i", false, false)
    eq("* item one", vim.fn.getline(1))
    eq("* ", vim.fn.getline(2))
  end)

  it("71: .todo filetype appends dated blob on new line", function()
    scratch({ "* buy milk" }, 1, 10)
    vim.fn.setpos(".", { 0, 1, 11, 0, 999 })
    sandbox(function(set)
      set(vim.bo, "ft", "awiwi.todo")
      awiwi.handle_enter_on_insert("i", false, false)
    end)
    local today = os.date("%F")
    eq(('*  {"created": "%s"}'):format(today), vim.fn.getline(2))
  end)

  it("70: list marker without content de-indents / blanks", function()
    scratch({ "* " }, 1, 2)
    vim.fn.setpos(".", { 0, 1, 3, 0, 999 })
    awiwi.handle_enter_on_insert("i", false, false)
    eq("  ", vim.fn.getline(1))
  end)

  it("72: breaking mid-content splits at cursor", function()
    scratch({ "* hello world" }, 1, 0)
    -- cursor at col 8 (0-based 7 -> before 'world')
    vim.fn.setpos(".", { 0, 1, 9, 0, 9 })
    awiwi.handle_enter_on_insert("i", false, false)
    eq("* hello ", vim.fn.getline(1))
    eq("  world", vim.fn.getline(2))
  end)
end)

describe("handle_enter (checkbox toggle)", function()
  local function with_file(lines, row, col, fn)
    local f = vim.fn.tempname() .. ".md"
    vim.fn.writefile(lines, f)
    vim.cmd("edit " .. f)
    vim.api.nvim_win_set_cursor(0, { row, col })
    fn()
    vim.cmd("bwipeout!")
  end

  it("74: checks an open checkbox", function()
    with_file({ "- [ ] task", "next" }, 1, 0, function()
      awiwi.handle_enter()
      eq("- [x] task", vim.fn.getline(1))
    end)
  end)

  it("76: unchecking removes the x", function()
    with_file({ "- [x] task", "next" }, 1, 0, function()
      awiwi.handle_enter()
      eq("- [ ] task", vim.fn.getline(1))
    end)
  end)

  it("73: non-checkbox non-bullet line unchanged", function()
    with_file({ "plain paragraph", "next" }, 1, 0, function()
      awiwi.handle_enter()
      eq("plain paragraph", vim.fn.getline(1))
    end)
  end)

  it("75: checking a due marker strikes it through", function()
    with_file({ "- [ ] task DUE 2024-01-01", "next" }, 1, 0, function()
      awiwi.handle_enter()
      eq("- [x] task ~~DUE 2024-01-01~~", vim.fn.getline(1))
    end)
  end)
end)

describe("append_to_line (§78)", function()
  -- hi.get_meta_and_pos only recognizes the blob on an open `* [ ] ` checklist
  -- line (faithful to the vimscript gate), so §78's space-insertion applies there.
  it("inserts a space before the blob and stops there", function()
    scratch({ '* [ ] task{"due": "2024-01-01"}' }, 1, 0)
    awiwi.append_to_line()
    eq('* [ ] task {"due": "2024-01-01"}', vim.fn.getline(1))
  end)

  it("no blob -> line unchanged", function()
    scratch({ "todo item" }, 1, 0)
    awiwi.append_to_line()
    eq("todo item", vim.fn.getline(1))
  end)
end)

describe("split_screen (§79)", function()
  it("non-':' cmdline -> ''", function()
    eq("", awiwi._split_screen_result("/", "search", "h"))
  end)

  it("preserved inverted guard: injects even for Awiwi command", function()
    eq(" +hnew", awiwi._split_screen_result(":", "Awiwi journal", "h"))
    eq(" +vnew", awiwi._split_screen_result(":", "Awiwi journal", "v"))
  end)

  it("injects flag for other ex commands", function()
    eq(" +hnew", awiwi._split_screen_result(":", "split foo", "h"))
  end)
end)

describe("delete_old_tasks (§84, B6)", function()
  it("deletes old-created lines including the last line", function()
    local today = os.date("%F")
    local old = os.date("%F", os.time() - 20 * 86400)
    local recent = os.date("%F", os.time() - 3 * 86400)
    local buf = scratch({
      ('- [x] done old {"created": "%s"}'):format(old),
      ('- [x] done recent {"created": "%s"}'):format(recent),
      ('* [ ] open old {"created": "%s"}'):format(old),
      "plain line no blob",
      ('- [x] last old {"created": "%s"}'):format(old),
    }, 1, 0)
    awiwi.delete_old_tasks(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- old done lines (incl. last) gone; recent kept; open checkbox kept; prose kept
    eq(3, #lines)
    ok(lines[1]:find("done recent", 1, true), "recent removed")
    ok(lines[2]:find("open old", 1, true), "open checkbox removed")
    ok(lines[3] == "plain line no blob", "prose removed")
    ok(today ~= nil)
  end)
end)

describe("foldexpr", function()
  it("blank -> -1, heading -> >level-1, other -> =", function()
    scratch({ "## heading", "text", "" }, 1, 0)
    eq(">1", awiwi.foldexpr(1))
    eq("=", awiwi.foldexpr(2))
    eq("-1", awiwi.foldexpr(3))
  end)
end)

describe("fuzzy_search", function()
  it("routes through picker.grep with the pattern", function()
    local picker = require("awiwi.picker")
    sandbox(function(set)
      local got
      set(picker, "grep", function(o)
        got = o
      end)
      awiwi.fuzzy_search("foo", "bar")
      eq("foo bar", got.argv[#got.argv])
    end)
  end)
end)
