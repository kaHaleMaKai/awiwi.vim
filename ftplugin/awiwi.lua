-- awiwi ftplugin (ports ftplugin/awiwi.vim). Loaded by Neovim for every
-- dot-separated component of &filetype, so this single file covers `awiwi`,
-- `awiwi.todo`, `awiwi.asset`, `awiwi.recipe`. Wires the `:Awiwi` command, all
-- buffer mappings/options/autocmds, folding, and syn activation to the ported
-- Lua modules. See handovers/lua-port/init.md §69-79 + the ftplugin inventory.

if vim.b.did_ftplugin then
  return
end

if not vim.g.awiwi_home or vim.g.awiwi_home == "" then
  vim.api.nvim_err_writeln("g:awiwi_home is not defined")
  return
end

vim.cmd("runtime! ftplugin/markdown.vim")
vim.b.did_ftplugin = 1

local awiwi = require("awiwi") -- also wires cmd.deps + bootstraps on first load
local hi = require("awiwi.hi")
local syn = require("awiwi.syn")

local buf = vim.api.nvim_get_current_buf()
local ft = vim.bo.ft

vim.opt_local.concealcursor = "nciv"
-- T10.2 dogfood fix: legacy relied on the user's global config for
-- 'conceallevel', so link conceal (▶name, hidden URL) never rendered in a
-- clean setup. Deliberate improvement over shipped behavior (user sign-off,
-- dogfood round 2). Window-local, like concealcursor above.
vim.opt_local.conceallevel = 2

-- Command (global, idempotent redefinition — no per-buffer variance today).
vim.api.nvim_create_user_command("Awiwi", function(o)
  require("awiwi.cmd").run(unpack(o.fargs))
end, {
  nargs = "+",
  complete = function(arglead, cmdline, cursorpos)
    return require("awiwi.cmd").get_completion(arglead, cmdline, cursorpos)
  end,
})

-- Buffer mappings ------------------------------------------------------------

local function bmap(mode, lhs, rhs, opts)
  opts = opts or {}
  opts.buffer = true
  opts.silent = true
  vim.keymap.set(mode, lhs, rhs, opts)
end

local function redraw()
  hi.redraw_due_dates()
end

bmap("n", "gf", function()
  awiwi.open_link({ new_window = true })
end)
bmap("n", "<leader>gft", function()
  awiwi.open_link({ new_window = false, new_tab = true })
end)
bmap("n", "<leader>gfn", function()
  awiwi.open_link({ new_window = true })
end)
bmap("n", "gC", ":Awiwi continue<CR>")
bmap("n", "gT", ":Awiwi todo<CR>")
bmap("n", "ge", ":Awiwi journal today<CR>")
-- cmd.md B7 rewire: `tasks` is not a subcommand; the real one is `tags`.
bmap("n", "<F12>", ":Awiwi tags<CR>")
bmap("n", "gn", ":Awiwi journal next<CR>")
bmap("n", "gp", ":Awiwi journal previous<CR>")

bmap("n", "O", function()
  awiwi.handle_enter_on_insert("n", true, false)
  redraw()
end)
bmap("n", "o", function()
  awiwi.handle_enter_on_insert("n", false, false)
  redraw()
end)
bmap("i", "<Enter>", function()
  awiwi.handle_enter_on_insert("i", false, false)
  redraw()
end)
bmap("i", "<C-j>", function()
  awiwi.handle_enter_on_insert("i", false, true)
  redraw()
end)
bmap("n", "<Enter>", function()
  awiwi.handle_enter()
  redraw()
end)
bmap("i", "<C-y>", "* [ ] ")

bmap("i", "<C-f>", function()
  return os.date("%H:%M")
end, { expr = true })
bmap("n", "<C-q>", ":Awiwi redact<CR>")
bmap("i", "<C-q>", "<C-o>:Awiwi redact<CR>")
bmap("i", "<C-v>", function()
  awiwi.handle_paste_in_insert_mode()
end)

bmap("i", "<C-s>", "<C-o>:Awiwi link ")
bmap("i", "<C-b>", "<C-o>:Awiwi asset create<CR>")

if ft:find("awiwi.asset", 1, true) then
  bmap("n", "gj", function()
    vim.cmd.edit(require("awiwi.asset").get_journal_for_current_asset())
  end)
end

if ft == "awiwi.todo" then
  bmap("n", "A", function()
    awiwi.append_to_line()
    redraw()
  end)
end

-- Command-line split-screen helper (§79). Global (matches the vimscript
-- cnoremap, which was not <buffer>-scoped).
vim.keymap.set("c", "<C-x>", "<C-r>=v:lua.require'awiwi'.split_screen('h')<CR><CR>", { silent = true })
vim.keymap.set("c", "<C-v>", "<C-r>=v:lua.require'awiwi'.split_screen('v')<CR><CR>", { silent = true })

-- Abbreviations (global iabbrev, as in the source — idempotent redeclaration).
vim.cmd([[iabbrev :shrug: `¯\_(ツ)_/¯`]])
vim.cmd("iabbrev :arrow: →")
vim.cmd("iabbrev :check: ✔")
vim.cmd("iabbrev :cross: ✖")

-- Autocmds -------------------------------------------------------------------

local autosave = vim.api.nvim_create_augroup("awiwiAutosave", { clear = true })
vim.api.nvim_create_autocmd({ "InsertLeave", "CursorHold" }, {
  group = autosave,
  pattern = "*.md",
  command = "silent w",
})

local del_old = vim.api.nvim_create_augroup("awiwiDeleteOldTasks", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePre" }, {
  group = del_old,
  pattern = "*/todos/*.md",
  callback = function()
    awiwi.delete_old_tasks(0)
  end,
})

local due_dates = vim.api.nvim_create_augroup("awiwiTodoDueDates", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufLeave", "InsertEnter", "InsertLeave" }, {
  group = due_dates,
  pattern = "*/todos/*.md",
  callback = function()
    hi.redraw_due_dates()
  end,
})

local hlines = vim.api.nvim_create_augroup("awiwiHorizontalLines", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  group = hlines,
  pattern = "*.md",
  callback = function()
    hi.draw_horizontal_lines()
  end,
})
vim.api.nvim_create_autocmd("BufModifiedSet", {
  group = hlines,
  pattern = "*.md",
  callback = function()
    if not vim.bo.modified then
      hi.draw_horizontal_lines()
    end
  end,
})

-- syn activation (net-new for T10; the deleted syntax/awiwi.vim self-activated
-- via :syntax). Attach the current buffer; detach on unload.
-- T10.1 dogfood fix: syn.lua paints only the awiwi *extras* — the base
-- markdown look (headings, fences, emphasis) that the legacy :syntax file
-- layered on top of must come from the bundled markdown treesitter
-- highlighter, which nothing started. pcall: a nvim built without the
-- bundled markdown parser just loses base styling, not the whole ftplugin.
pcall(vim.treesitter.start, buf, "markdown")
syn.setup_highlights()
syn.attach(buf)

-- Inline images (T19/T20, ADR D17): optional snacks.nvim backend; silently
-- no-ops without snacks or when g:awiwi_inline_images is false/0.
-- Deliberately NOT in the awiwiSynRepaint augroup below — snacks manages its
-- own repaint cycle, and attach is buffer-guarded on the snacks side.
require("awiwi.img").attach(buf)

-- Repaint trigger (missed in T10): syn.attach() only ran once above, at
-- initial load, so markers/links/structure typed afterward never got
-- painted. Mirrors the awiwiHorizontalLines pattern below exactly.
local synRepaint = vim.api.nvim_create_augroup("awiwiSynRepaint", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  group = synRepaint,
  pattern = "*.md",
  callback = function()
    syn.attach(0)
  end,
})
vim.api.nvim_create_autocmd("BufModifiedSet", {
  group = synRepaint,
  pattern = "*.md",
  callback = function()
    if not vim.bo.modified then
      syn.attach(0)
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufUnload" }, {
  buffer = buf,
  callback = function()
    pcall(syn.detach, buf)
  end,
})

-- Folding (B7 fix: plain Lua foldexpr, no stringified Funcref). B8 dropped:
-- no session-wide `set updatetime` mutation.
vim.wo.foldmethod = "expr"
vim.wo.foldexpr = 'v:lua.require("awiwi").foldexpr(v:lnum)'
vim.wo.wrap = false

-- Optional server autostart (dogfood; guarded).
local autostart = vim.g.awiwi_autostart_server
if autostart and autostart ~= "" then
  local server = require("awiwi.server")
  if not server.server_is_running() then
    server.start_server(autostart)
  end
end

-- Optional entitlement.nvim title decoration (dogfood-only, guarded exactly as
-- the vimscript original was).
local use_ent = vim.g.awiwi_use_entitlement
if use_ent == nil then
  use_ent = true
end
if use_ent and vim.o.runtimepath:find("entitlement.nvim", 1, true) then
  -- Dogfood-only, gated on entitlement.nvim being installed (never in the test
  -- suite). Title getters come from the ported hi module; a dogfooder with
  -- entitlement.nvim installed should pass their own g:awiwi_use_entitlement_opts
  -- if entitlement#add_title needs vimscript funcrefs (see init.md gotchas).
  local ent_opts = vim.g.awiwi_use_entitlement_opts or {}
  local ent = vim.api.nvim_create_augroup("awiwiEntitlement", { clear = true })
  local function add_title(kind, default)
    vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter", "BufWinEnter", "CursorHold" }, {
      group = ent,
      pattern = "*/" .. kind .. "/*",
      callback = function()
        vim.fn["entitlement#add_title"](ent_opts[kind] or default)
      end,
    })
  end
  add_title("journal", { fn = hi.get_journal_title, hl_group = "markdownH1" })
  add_title("assets", { fn = hi.get_asset_title, hl_group = "markdownH1" })
  add_title("recipes", { fn = hi.get_recipe_title, hl_group = "markdownH1" })
end

vim.cmd("doautocmd User AwiwiInitPost")
