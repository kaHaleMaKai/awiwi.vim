-- Acceptance specs for ftdetect/awiwi.lua + ftplugin/awiwi.lua (T10 switchover).
-- Covers filetype assignment (§80-83), the :Awiwi command + <F12> rewire, the
-- foldexpr wiring (B7), and the dropped session-wide updatetime mutation (B8).

local path = require("awiwi.path")

local home = vim.fn.tempname()
vim.g.awiwi_home = home
for _, d in ipairs({ "journal/2024/03", "assets/2024/03/05", "recipes/cooking", "todos" }) do
  vim.fn.mkdir(path.join(home, d), "p")
end

vim.cmd("filetype plugin on")
vim.cmd("runtime ftdetect/awiwi.lua")

local function edit_new(rel)
  local f = path.join(home, rel)
  vim.cmd("silent! bwipeout!")
  vim.cmd("edit " .. f)
  return vim.bo.filetype
end

-- ===========================================================================
-- ftdetect filetype assignment (§80-83)
-- ===========================================================================

describe("ftdetect", function()
  it("80: journal/**/*.md -> awiwi", function()
    eq("awiwi", edit_new("journal/2024/03/2024-03-05.md"))
  end)

  it("81: assets/**/* -> awiwi.asset", function()
    eq("awiwi.asset", edit_new("assets/2024/03/05/pic.md"))
  end)

  it("81: recipes/**/* -> awiwi.recipe", function()
    eq("awiwi.recipe", edit_new("recipes/cooking/pasta.md"))
  end)

  it("81: recipes/* -> awiwi.recipe", function()
    eq("awiwi.recipe", edit_new("recipes/top.md"))
  end)

  it("81: todos/*.md -> awiwi.todo", function()
    eq("awiwi.todo", edit_new("todos/inprogress.md"))
  end)

  it("80: guard preserved — pre-set unrelated ft not overridden", function()
    local f = path.join(home, "journal/2024/03/2024-03-06.md")
    vim.cmd("silent! bwipeout!")
    vim.cmd("edit " .. f)
    vim.bo.filetype = "python"
    -- re-trigger detection: our autocmd must not override a non-markdown ft
    vim.api.nvim_exec_autocmds("BufWinEnter", { pattern = f })
    eq("python", vim.bo.filetype)
  end)

  it("83: any .md buffer gets aP/iP text objects", function()
    local f = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "x" }, f)
    vim.cmd("silent! bwipeout!")
    vim.cmd("edit " .. f)
    ok(vim.fn.maparg("aP", "x") ~= "", "aP visual missing")
    ok(vim.fn.maparg("iP", "o") ~= "", "iP operator missing")
  end)

  it("82: external_dirs/*.md -> awiwi", function()
    local ext = vim.fn.tempname()
    vim.fn.mkdir(ext, "p")
    vim.g.awiwi_external_dirs = { work = ext }
    vim.cmd("runtime ftdetect/awiwi.lua") -- re-register with the new external dir
    local f = path.join(ext, "notes.md")
    vim.cmd("silent! bwipeout!")
    vim.cmd("edit " .. f)
    eq("awiwi", vim.bo.filetype)
    vim.g.awiwi_external_dirs = nil
  end)
end)

-- ===========================================================================
-- ftplugin wiring (command, mappings, folding, updatetime)
-- ===========================================================================

describe("ftplugin", function()
  local function open_awiwi_buffer()
    local f = path.join(home, "journal/2024/03/2024-03-09.md")
    vim.cmd("silent! bwipeout!")
    vim.cmd("edit " .. f)
    vim.bo.filetype = "awiwi"
    return f
  end

  it("registers the :Awiwi user command", function()
    open_awiwi_buffer()
    eq(true, vim.fn.exists(":Awiwi") == 2)
  end)

  it("<F12> maps to :Awiwi tags<CR> (cmd.md B7 rewire, not `tasks`)", function()
    open_awiwi_buffer()
    local rhs = vim.fn.maparg("<F12>", "n")
    ok(rhs:find("Awiwi tags", 1, true), "F12 not mapped to Awiwi tags: " .. rhs)
    ok(not rhs:find("tasks", 1, true), "F12 still references tasks")
  end)

  it("sets a Lua foldexpr (B7 — no stringified Funcref)", function()
    open_awiwi_buffer()
    eq("expr", vim.wo.foldmethod)
    ok(vim.wo.foldexpr:find("awiwi", 1, true), "foldexpr not wired to awiwi")
    ok(not vim.wo.foldexpr:find("<SNR>", 1, true), "foldexpr uses a Funcref splice")
  end)

  it("sets window conceallevel so link conceal actually renders (T10.2 dogfood fix)", function()
    open_awiwi_buffer()
    eq(2, vim.wo.conceallevel)
  end)

  it("starts base markdown treesitter highlighting (T10.1 dogfood fix)", function()
    open_awiwi_buffer()
    local buf = vim.api.nvim_get_current_buf()
    ok(vim.treesitter.highlighter.active[buf], "no treesitter highlighter active on awiwi buffer")
  end)

  it("B8: does not mutate updatetime session-wide", function()
    vim.o.updatetime = 271
    open_awiwi_buffer()
    eq(271, vim.o.updatetime)
    vim.o.updatetime = 4000
  end)

  it("gj is bound only for asset buffers", function()
    local f = path.join(home, "assets/2024/03/05/thing.md")
    vim.cmd("silent! bwipeout!")
    vim.cmd("edit " .. f)
    vim.bo.filetype = "awiwi.asset"
    ok(vim.fn.maparg("gj", "n") ~= "", "gj missing on asset buffer")
  end)
end)
