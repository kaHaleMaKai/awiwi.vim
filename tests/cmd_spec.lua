-- Acceptance specs for lua/awiwi/cmd.lua — `:Awiwi` dispatch (M.run), completion
-- (M.get_completion), the tags/show_tasks rg grep, session save/restore, and
-- drawio export. Every façade call goes through `cmd.deps.*` (T10 injection
-- points) and every picker through `require('awiwi.picker')`, both stubbed here.
-- Numbering mirrors the behavior contract in handovers/lua-port/cmd.md.

local cmd = require("awiwi.cmd")
local picker = require("awiwi.picker")
local asset = require("awiwi.asset")
local util = require("awiwi.util")
local server = require("awiwi.server")
local date = require("awiwi.date")
local pathlib = require("awiwi.path")

vim.g.awiwi_home = vim.fn.tempname()
vim.fn.mkdir(vim.g.awiwi_home, "p")

--- Sandbox: `set(tbl, key, val)` overrides fields and auto-restores (LIFO)
--- after `fn` runs, even on error.
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

-- Convenience: a function that records its call args into `log`.
local function recorder(log, name)
  return function(...)
    log[#log + 1] = { name = name, args = { ... } }
    return log[name .. "_ret"]
  end
end

describe("cmd.run dispatch guards", function()
  it("C1: run() with zero args throws AwiwiCmdError", function()
    local ok_, err = pcall(cmd.run)
    eq(false, ok_)
    ok(tostring(err):find("AwiwiCmdError", 1, true), "expected AwiwiCmdError, got: " .. tostring(err))
  end)

  it("C2/B7: unknown subcommand ('bogus', 'tasks') is a silent no-op", function()
    -- must not error, must not dispatch anything
    cmd.run("bogus")
    cmd.run("tasks")
  end)
end)

describe("cmd.run journal (C3-C6)", function()
  it("C3: bare journal opens a file picker over the journal subpath", function()
    sandbox(function(set)
      local got
      set(picker, "files", function(opts)
        got = opts
      end)
      cmd.run("journal")
      eq(pathlib.join(vim.g.awiwi_home, "journal"), got.dir)
    end)
  end)

  it("C4: journal <date> edits via deps.edit_journal (new_window=false default)", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      local log = {}
      set(cmd.deps, "edit_journal", recorder(log, "edit_journal"))
      cmd.run("journal", "today")
      eq("edit_journal", log[1].name)
      eq("today", log[1].args[1])
      eq(false, log[1].args[2].new_window)
    end)
  end)

  it("C4: +new flag sets new_window=true, position=auto", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      local log = {}
      set(cmd.deps, "edit_journal", recorder(log, "edit_journal"))
      cmd.run("journal", "today", "+new")
      eq(true, log[1].args[2].new_window)
      eq("auto", log[1].args[2].position)
    end)
  end)

  it("C5: link journal (bare) shows a list picker over journal files + literals", function()
    sandbox(function(set)
      set(cmd.deps, "get_all_journal_files", function(opts)
        ok(opts.include_literals, "include_literals requested")
        return { "2024-01-01", "today" }
      end)
      local sel_opts
      set(picker, "select", function(opts)
        sel_opts = opts
      end)
      local link_log = {}
      set(cmd.deps, "insert_journal_link", recorder(link_log, "insert_journal_link"))

      cmd.run("link", "journal")
      eq({ "2024-01-01", "today" }, sel_opts.items)
      sel_opts.on_choice("2024-01-01")
      eq("2024-01-01", link_log[1].args[1])
    end)
  end)

  it("C6: link journal <date> inserts a journal link", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      local log = {}
      set(cmd.deps, "insert_journal_link", recorder(log, "insert_journal_link"))
      cmd.run("link", "journal", "today")
      eq("insert_journal_link", log[1].name)
      eq("today", log[1].args[1])
    end)
  end)
end)

describe("cmd.run task/continuation dispatch (C7-C10)", function()
  it("C7: export delegates to export_drawio_diagram", function()
    sandbox(function(set)
      local called = false
      set(cmd, "export_drawio_diagram", function()
        called = true
      end)
      cmd.run("export")
      eq(true, called)
    end)
  end)

  it("C8/C9/C10: continue/activate/deactivate call their façade deps", function()
    sandbox(function(set)
      local log = {}
      set(cmd.deps, "insert_and_open_continuation", recorder(log, "continue"))
      set(cmd.deps, "activate_current_task", recorder(log, "activate"))
      set(cmd.deps, "deactivate_active_task", recorder(log, "deactivate"))
      cmd.run("continue")
      cmd.run("activate")
      cmd.run("deactivate")
      eq("continue", log[1].name)
      eq("activate", log[2].name)
      eq("deactivate", log[3].name)
    end)
  end)
end)

describe("cmd.run asset (C11-C17)", function()
  it("C11: top-level paste and 'asset paste' both create a paste asset", function()
    sandbox(function(set)
      local log = {}
      set(asset, "create_asset_here_if_not_exists", function(type_, opts, on_done)
        log[#log + 1] = type_
      end)
      cmd.run("paste")
      cmd.run("asset", "paste")
      eq({ asset.types.paste, asset.types.paste }, log)
    end)
  end)

  it("C12: bare asset opens the date:name list picker → open_asset_sink", function()
    sandbox(function(set)
      set(asset, "get_all_asset_files", function()
        return { { date = "2024-01-01", name = "foo.png" } }
      end)
      local sel
      set(picker, "select", function(opts)
        sel = opts
      end)
      local sink = {}
      set(asset, "open_asset_sink", function(expr)
        sink[#sink + 1] = expr
      end)
      cmd.run("asset")
      eq({ "2024-01-01:foo.png" }, sel.items)
      sel.on_choice("2024-01-01:foo.png")
      eq("2024-01-01:foo.png", sink[1])
    end)
  end)

  it("C13: asset copy with an asset link under cursor copies the resolved path", function()
    sandbox(function(set)
      set(util, "get_link_under_cursor", function()
        return { type = "asset", target = "../assets/x.png" }
      end)
      local log = {}
      set(cmd.deps, "copy_file", recorder(log, "copy_file"))
      cmd.run("asset", "copy")
      eq("copy_file", log[1].name)
      ok(log[1].args[1]:find("x.png", 1, true), "resolved path passed to copy_file")
    end)
  end)

  it("C13: asset copy without an asset link does not copy", function()
    sandbox(function(set)
      set(util, "get_link_under_cursor", function()
        return { type = "journal", target = "whatever" }
      end)
      local log = {}
      set(cmd.deps, "copy_file", recorder(log, "copy_file"))
      set(vim.api, "nvim_err_writeln", function() end)
      cmd.run("asset", "copy")
      eq(0, #log)
    end)
  end)

  it("C14/C15: asset create url / paste route to create_asset_here_if_not_exists", function()
    sandbox(function(set)
      local log = {}
      set(asset, "create_asset_here_if_not_exists", function(type_)
        log[#log + 1] = type_
      end)
      cmd.run("asset", "create", "url")
      cmd.run("asset", "create", "paste")
      eq({ asset.types.url, asset.types.paste }, log)
    end)
  end)

  it("C16: asset create <name> creates empty .md, writes host buffer, opens asset", function()
    sandbox(function(set)
      set(asset, "create_asset_here_if_not_exists", function(type_, opts, on_done)
        eq(asset.types.empty, type_)
        eq(".md", opts.suffix)
        on_done("mynote.md")
      end)
      local cmds = {}
      set(vim, "cmd", function(c)
        cmds[#cmds + 1] = c
      end)
      local opened = {}
      set(asset, "open_asset", function(name, opts)
        opened = { name = name, opts = opts }
      end)
      cmd.run("asset", "create", "some", "name")
      ok(vim.tbl_contains(cmds, "write"), "host buffer written")
      eq("mynote.md", opened.name)
      eq(true, opened.opts.new_window)
    end)
  end)

  it("C17: asset <date:name> opens by name; link asset inserts; bare name uses own date", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      set(date, "get_own_date", function()
        return "2030-06-06"
      end)
      local open_log = {}
      local link_log = {}
      set(asset, "open_asset_by_name", function(d, f, o)
        open_log[#open_log + 1] = { d, f }
      end)
      set(asset, "insert_asset_link", function(d, f, o)
        link_log[#link_log + 1] = { d, f }
      end)

      cmd.run("asset", "2024-01-01:foo.png")
      eq({ "2024-01-01", "foo.png" }, open_log[1])

      cmd.run("link", "asset", "2024-01-01:bar.png")
      eq({ "2024-01-01", "bar.png" }, link_log[1])

      cmd.run("asset", "bareName")
      eq({ "2030-06-06", "bareName" }, open_log[2])
    end)
  end)
end)

describe("cmd.run recipe (C18-C19)", function()
  it("C18: bare recipe opens a file picker (no &shell mutation, B1)", function()
    sandbox(function(set)
      local shell_before = vim.o.shell
      local got
      set(picker, "files", function(opts)
        got = opts
      end)
      cmd.run("recipe")
      eq(pathlib.join(vim.g.awiwi_home, "recipes"), got.dir)
      eq(shell_before, vim.o.shell)
    end)
  end)

  it("C18: link recipe (bare) file picker wires an insert_recipe_link sink", function()
    sandbox(function(set)
      set(cmd.deps, "get_recipe_subpath", function()
        return "/tmp/recipes"
      end)
      local got
      set(picker, "files", function(opts)
        got = opts
      end)
      local link_log = {}
      set(cmd.deps, "insert_recipe_link", recorder(link_log, "insert_recipe_link"))
      cmd.run("link", "recipe")
      got.on_choice("/tmp/recipes/cooking/pasta.md")
      eq("cooking/pasta.md", link_log[1].args[1])
    end)
  end)

  it("C19: recipe <name> appends .md, forces create_dirs, opens file", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      set(cmd.deps, "get_recipe_subpath", function()
        return "/tmp/recipes"
      end)
      local log = {}
      set(cmd.deps, "open_file", recorder(log, "open_file"))
      cmd.run("recipe", "pasta")
      eq("/tmp/recipes/pasta.md", log[1].args[1])
      eq(true, log[1].args[2].create_dirs)
    end)
  end)

  it("C19: link recipe <name> inserts a recipe link", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      local log = {}
      set(cmd.deps, "insert_recipe_link", recorder(log, "insert_recipe_link"))
      cmd.run("link", "recipe", "pasta")
      eq("pasta.md", log[1].args[1])
    end)
  end)
end)

describe("cmd.run misc dispatch (C20-C37)", function()
  it("C21: search joins remaining args to fuzzy_search", function()
    sandbox(function(set)
      local log = {}
      set(cmd.deps, "fuzzy_search", recorder(log, "fuzzy_search"))
      cmd.run("search", "foo", "bar")
      eq({ "foo", "bar" }, log[1].args)
    end)
  end)

  it("C22: serve calls server.serve", function()
    sandbox(function(set)
      local called = false
      set(server, "serve", function()
        called = true
      end)
      cmd.run("serve")
      eq(true, called)
    end)
  end)

  it("C23: bare server errors, no dispatch", function()
    sandbox(function(set)
      local errs = {}
      set(vim.api, "nvim_err_writeln", function(m)
        errs[#errs + 1] = m
      end)
      cmd.run("server")
      ok(#errs > 0, "expected an error message")
    end)
  end)

  it("C24: server start defaults host=localhost and default port", function()
    sandbox(function(set)
      set(server, "get_default_port", function()
        return "5823"
      end)
      local log = {}
      set(server, "start_server", function(h, p)
        log[#log + 1] = { h, p }
      end)
      cmd.run("server", "start")
      eq({ "localhost", "5823" }, log[1])
      cmd.run("server", "start", "example.org", "9000")
      eq({ "example.org", "9000" }, log[2])
    end)
  end)

  it("C25/C26: server stop / logs delegate", function()
    sandbox(function(set)
      local log = {}
      set(server, "stop_server", function()
        log[#log + 1] = "stop"
      end)
      set(server, "server_logs", function(k)
        log[#log + 1] = "logs:" .. tostring(k)
      end)
      cmd.run("server", "stop")
      cmd.run("server", "logs", "stderr")
      eq({ "stop", "logs:stderr" }, log)
    end)
  end)

  it("C27: redact calls deps.redact", function()
    sandbox(function(set)
      local called = false
      set(cmd.deps, "redact", function()
        called = true
      end)
      cmd.run("redact")
      eq(true, called)
    end)
  end)

  it("C28: due passes column=due and the rest args", function()
    sandbox(function(set)
      local log = {}
      set(cmd.deps, "edit_meta_info", recorder(log, "edit_meta_info"))
      cmd.run("due", "in", "3", "days")
      eq(false, log[1].args[1].delete)
      eq("due", log[1].args[1].column)
      eq({ "in", "3", "days" }, log[1].args[1].args)
    end)
  end)

  it("C29/C30: meta delete / edit <col>", function()
    sandbox(function(set)
      local log = {}
      set(cmd.deps, "edit_meta_info", recorder(log, "edit_meta_info"))
      cmd.run("meta", "delete")
      eq(true, log[1].args[1].delete)
      cmd.run("meta", "edit", "due")
      eq("due", log[2].args[1].column)
    end)
  end)

  it("C31: meta <unknown> echoes (not echoerr) and does not edit", function()
    sandbox(function(set)
      local log = {}
      set(cmd.deps, "edit_meta_info", recorder(log, "edit_meta_info"))
      set(vim.api, "nvim_echo", function() end)
      cmd.run("meta", "bogus")
      eq(0, #log)
    end)
  end)

  it("C33: bare todo opens 'inprogress'; named todo passes the name", function()
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      local log = {}
      set(cmd.deps, "edit_todo", recorder(log, "edit_todo"))
      cmd.run("todo")
      eq("inprogress", log[1].args[1])
      cmd.run("todo", "backlog")
      eq("backlog", log[2].args[1])
    end)
  end)

  it("C34/C35: save writes a session, restore sources it", function()
    sandbox(function(set)
      local cmds = {}
      set(vim, "cmd", function(c)
        cmds[#cmds + 1] = c
      end)
      cmd.run("save")
      cmd.run("restore")
      ok(cmds[1]:match("^mksession!"), "mksession issued: " .. tostring(cmds[1]))
      ok(cmds[2]:match("^source"), "source issued: " .. tostring(cmds[2]))
    end)
  end)

  it("C36/C37: toc bare uses own date; toc parts capped to YYYY-MM", function()
    sandbox(function(set)
      set(date, "get_own_date", function()
        return "2030-06-06"
      end)
      local log = {}
      set(cmd.deps, "show_toc_in_qlist", recorder(log, "show_toc_in_qlist"))
      cmd.run("toc")
      eq("2030-06-06", log[1].args[1].date)
      cmd.run("toc", "2024", "03")
      eq("2024-03", log[2].args[1].date)
      cmd.run("toc", "2024-03-05")
      eq("2024-03", log[3].args[1].date)
    end)
  end)
end)

describe("parse_file_and_options flags (C41-C45, B3)", function()
  local function options_for(...)
    local extra = { ... }
    local captured
    sandbox(function(set)
      set(util, "window_split_below", function()
        return false
      end)
      set(cmd.deps, "edit_journal", function(_d, o)
        captured = o
      end)
      cmd.run("journal", unpack(extra))
    end)
    return captured
  end

  it("C41: +hnew/+vnew/+tab/-new/+create map correctly", function()
    eq("bottom", options_for("d", "+hnew").position)
    eq("right", options_for("d", "+vnew").position)
    eq(true, options_for("d", "+tab").new_tab)
    eq(false, options_for("d", "-new").new_window)
    eq(true, options_for("d", "+create").create_dirs)
  end)

  it("C42/B3: +width= sets options.width, +height= sets options.height", function()
    eq(40, options_for("d", "+width=40").width)
    eq(30, options_for("d", "+height=30").height)
  end)

  it("C43: #anchor sets options.anchor", function()
    eq("intro", options_for("d", "#intro").anchor)
  end)

  it("C45: default height 20 when window_split_below is true", function()
    local captured
    sandbox(function(set)
      set(util, "window_split_below", function()
        return true
      end)
      set(cmd.deps, "edit_journal", function(_d, o)
        captured = o
      end)
      cmd.run("journal", "d")
    end)
    eq(20, captured.height)
  end)
end)

describe("cmd.show_tasks (C-tags-1..5)", function()
  it("C-tags-1: no args defaults to 'todo' and builds an rg grep", function()
    sandbox(function(set)
      local got
      set(picker, "grep", function(opts)
        got = opts
      end)
      cmd.show_tasks()
      eq("rg", got.argv[1])
      ok(vim.tbl_contains(got.argv, "!awiwi*"), "excludes awiwi* files")
      eq(nil, got.filter_argv)
    end)
  end)

  it("C-tags-3: filter without a pattern throws AwiwiCmdError", function()
    local ok_, err = pcall(cmd.show_tasks, "filter")
    eq(false, ok_)
    ok(tostring(err):find("filter", 1, true), "error mentions filter")
  end)

  it("C-tags-4: due request adds the anti-pattern filter_argv", function()
    sandbox(function(set)
      local got
      set(picker, "grep", function(opts)
        got = opts
      end)
      cmd.show_tasks("due")
      ok(got.filter_argv ~= nil, "filter_argv present for due search")
      eq("rg", got.filter_argv[1])
      eq("-v", got.filter_argv[2])
    end)
  end)

  it("C20: :Awiwi tags <sub> forwards to show_tasks", function()
    sandbox(function(set)
      local got
      set(picker, "grep", function(opts)
        got = opts
      end)
      cmd.run("tags", "urgent")
      ok(got ~= nil, "grep invoked via tags dispatch")
    end)
  end)
end)

describe("cmd.run entries (C32, B2)", function()
  it("builds an rg heading grep and its picker has a navigable sink", function()
    sandbox(function(set)
      local got
      set(picker, "grep", function(opts)
        got = opts
      end)
      cmd.run("entries")
      eq("rg", got.argv[1])
      ok(vim.tbl_contains(got.argv, "!awiwi*"), "excludes awiwi* files")
      -- transform strips the `##+ ` marker but keeps file:line:col for jumping
      eq("/f:1:1:Heading", got.transform("/f:1:1:## Heading"))
    end)
  end)
end)

describe("cmd.get_completion", function()
  local function comp(arglead, cmdline)
    return cmd.get_completion(arglead, cmdline, #cmdline)
  end

  it("C47: completes subcommands at position 1", function()
    local res = comp("jo", "Awiwi jo")
    ok(vim.tbl_contains(res, "journal"), "journal offered")
  end)

  it("C48: tags completion excludes already-used categories and filter", function()
    local res = comp("", "Awiwi tags urgent ")
    ok(not vim.tbl_contains(res, "urgent"), "urgent not offered twice")
    ok(not vim.tbl_contains(res, "filter"), "filter excluded once other tags used")
    ok(vim.tbl_contains(res, "onhold"), "other categories still offered")
  end)

  it("C48: tags position 2 offers all tag subcommands", function()
    local res = comp("", "Awiwi tags ")
    ok(vim.tbl_contains(res, "all"), "all offered")
    ok(vim.tbl_contains(res, "filter"), "filter offered at pos 2")
  end)

  it("C49: journal completion prepends literals and de-dups todos", function()
    sandbox(function(set)
      set(cmd.deps, "get_all_journal_files", function()
        return { "todos", "2024-01-01" }
      end)
      local res = comp("", "Awiwi journal ")
      eq("todos", res[1])
      eq("today", res[2])
      eq("next", res[3])
      eq("previous", res[4])
      ok(vim.tbl_contains(res, "2024-01-01"), "journal file offered")
      -- 'todos' appears exactly once (moved to the literal block)
      local todos_count = 0
      for _, v in ipairs(res) do
        if v == "todos" then
          todos_count = todos_count + 1
        end
      end
      eq(1, todos_count)
    end)
  end)

  it("C52: link-recipe # completes slugified heading anchors", function()
    sandbox(function(set)
      set(cmd.deps, "get_recipe_subpath", function()
        return "/tmp/recipes"
      end)
      set(cmd.deps, "system", function(_argv)
        return {
          wait = function()
            return { stdout = "# My Heading!\n## Another/One\n" }
          end,
        }
      end)
      local res = comp("", "Awiwi link recipe foo #")
      eq({ "#my-heading", "#anotherone" }, res)
    end)
  end)

  it("C50: asset create offers [paste,url,copy]", function()
    local res = comp("", "Awiwi asset create ")
    eq({ "paste", "url", "copy" }, res)
  end)

  it("C53: todo offers todo subcommands", function()
    local res = comp("", "Awiwi todo ")
    ok(vim.tbl_contains(res, "inprogress"), "inprogress offered")
    ok(vim.tbl_contains(res, "backlog"), "backlog offered")
  end)

  it("C54: meta completion", function()
    eq(true, vim.tbl_contains(comp("", "Awiwi meta "), "edit"))
    eq(true, vim.tbl_contains(comp("", "Awiwi meta edit "), "due"))
  end)

  it("C55: due completion offers relative expressions", function()
    local res = comp("", "Awiwi due ")
    ok(vim.tbl_contains(res, "today"), "today offered")
    ok(vim.tbl_contains(res, "next"), "next offered")
  end)

  it("C56: server completion flips start/stop by running state", function()
    sandbox(function(set)
      set(server, "server_is_running", function()
        return false
      end)
      local res = comp("", "Awiwi server ")
      ok(vim.tbl_contains(res, "start"), "start offered when stopped")
      ok(not vim.tbl_contains(res, "stop"), "stop not offered when stopped")
      ok(vim.tbl_contains(res, "logs"), "logs offered")
    end)
  end)

  it("C57: bare link offers [journal,recipe,asset]", function()
    eq({ "journal", "recipe", "asset" }, comp("", "Awiwi link "))
  end)

  it("C58: no completion for terminal subcommands", function()
    eq({}, comp("", "Awiwi redact "))
    eq({}, comp("", "Awiwi activate "))
  end)
end)

describe("cmd.export_drawio_diagram (C-export-*, B5/B6)", function()
  it("C-export-1: no drawio ref in line and no arg errors and returns false", function()
    sandbox(function(set)
      set(vim.fn, "getline", function()
        return "no diagram here"
      end)
      set(vim.api, "nvim_err_writeln", function() end)
      eq(false, cmd.export_drawio_diagram())
    end)
  end)

  it("C-export-3: empty output path aborts", function()
    sandbox(function(set)
      set(util, "input", function(_opts, on_confirm)
        on_confirm("")
      end)
      local errs = {}
      set(vim.api, "nvim_err_writeln", function(m)
        errs[#errs + 1] = m
      end)
      local spawned = false
      set(cmd.deps, "system", function()
        spawned = true
        return { wait = function() end }
      end)
      cmd.export_drawio_diagram("diagram.drawio")
      eq(false, spawned)
      ok(#errs > 0, "abort error emitted")
    end)
  end)

  it("C-export-5/6/B5: stderr 'Error' lines collected, ERROR notify on failure", function()
    sandbox(function(set)
      set(util, "input", function(_opts, on_confirm)
        on_confirm("/tmp/out.pdf")
      end)
      local notes = {}
      set(vim, "notify", function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
      end)
      set(cmd.deps, "system", function(_cmd, opts, on_exit)
        opts.stderr(nil, "object_proxy.cc noise\n")
        opts.stderr(nil, "Error: boom\n")
        on_exit({ code = 1 })
        return { wait = function() end }
      end)
      cmd.export_drawio_diagram("diagram.drawio")
      vim.wait(100, function()
        return #notes > 0
      end)
      eq(vim.log.levels.ERROR, notes[1].level)
      ok(notes[1].msg:find("boom", 1, true), "collected error surfaced (B5)")
    end)
  end)

  it("C-export-6: success notifies INFO and copies output path to clipboard", function()
    sandbox(function(set)
      set(util, "input", function(_opts, on_confirm)
        on_confirm("/tmp/out.pdf")
      end)
      local notes = {}
      set(vim, "notify", function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
      end)
      local reg
      set(vim.fn, "setreg", function(r, v)
        if r == "+" then
          reg = v
        end
      end)
      set(cmd.deps, "system", function(_cmd, opts, on_exit)
        on_exit({ code = 0 })
        return { wait = function() end }
      end)
      cmd.export_drawio_diagram("diagram.drawio")
      vim.wait(100, function()
        return #notes > 0
      end)
      eq(vim.log.levels.INFO, notes[1].level)
      eq("/tmp/out.pdf", reg)
    end)
  end)

  it("B6: spawn failure reports the argv, not a phantom var", function()
    sandbox(function(set)
      set(util, "input", function(_opts, on_confirm)
        on_confirm("/tmp/out.pdf")
      end)
      local errs = {}
      set(vim.api, "nvim_err_writeln", function(m)
        errs[#errs + 1] = m
      end)
      set(cmd.deps, "system", function()
        error("ENOENT: drawio not found")
      end)
      cmd.export_drawio_diagram("diagram.drawio")
      ok(#errs > 0 and errs[1]:find("drawio", 1, true), "argv referenced in error")
    end)
  end)
end)
