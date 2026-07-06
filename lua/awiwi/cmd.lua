-- `:Awiwi <sub> [args…]` command parsing, dispatch (`M.run`) and completion
-- (`M.get_completion`) for the whole plugin surface, plus three loosely-related
-- helpers bolted onto the same original autoload file: session save/restore,
-- the `tags`/`show_tasks` rg marker grep, and async drawio→PDF export.
--
-- Port of `autoload/awiwi/cmd.vim` (780 lines). See handovers/lua-port/cmd.md
-- for the full 38-item behavior contract, bugs fixed (B1-B7), and the picker
-- seam / M.deps injection design.
--
-- Boundary: this module exposes ONLY `M.run`, `M.get_completion`,
-- `M.show_tasks`, `M.store_session`, `M.restore_session`,
-- `M.export_drawio_diagram`. It does NOT define the `:Awiwi` user command, its
-- completion wiring, or the buffer mappings — that is T10's (init.lua/ftplugin)
-- job. Every fzf usage is behind `require('awiwi.picker')`; every not-yet-ported
-- façade function is behind `M.deps.*` (default = a `vim.fn['awiwi#…']` shim,
-- rebound by T10) — never inline `vim.fn[...]` calls in the body.

local str = require("awiwi.str")
local path = require("awiwi.path")
local util = require("awiwi.util")
local asset = require("awiwi.asset")
local date = require("awiwi.date")
local server = require("awiwi.server")
local markers = require("awiwi.markers")
local picker = require("awiwi.picker")

local M = {}

-- ---------------------------------------------------------------------------
-- Constants (were the `s:*_cmd` script-locals; now plain module locals).
-- ---------------------------------------------------------------------------

local ACTIVATE = "activate"
local BOOKMARK = "!bookmark"
local DEACTIVATE = "deactivate"
local JOURNAL = "journal"
local CONTINUE = "continue"
local ENTRIES = "entries"
local ASSET = "asset"
local LINK = "link"
local RECIPE = "recipe"
local SEARCH = "search"
local SERVE = "serve"
local SERVER = "server"
local REDACT = "redact"
local TAGS = "tags"
local TODO = "todo"
local SAVE = "save"
local RESTORE = "restore"
local META = "meta"
local DUE = "due"
local TOC = "toc"
local EXPORT = "export"

local CREATE = "create"
local COPY = "copy"

local SERVER_START = "start"
local SERVER_STOP = "stop"
local SERVER_LOGS = "logs"

local META_EDIT = "edit"
local META_DELETE = "delete"

local SUBCOMMANDS = {
  ACTIVATE, CONTINUE, DUE, DEACTIVATE, EXPORT, JOURNAL, ENTRIES, ASSET, LINK,
  asset.types.paste, RECIPE, REDACT, META, RESTORE, SAVE, SEARCH, SERVE, SERVER,
  TAGS, TOC, TODO,
}

local CREATE_FILE_CMD = "+create"
local NEW_CMD = "+new"
local HNEW_CMD = "+hnew"
local VNEW_CMD = "+vnew"
local SAME_CMD = "-new"
local TAB_CMD = "+tab"
local JOURNAL_OPTIONS_CMD = { NEW_CMD, HNEW_CMD, VNEW_CMD, SAME_CMD, TAB_CMD, CREATE_FILE_CMD, BOOKMARK }

local HEIGHT_CMD = "+height="
local WIDTH_CMD = "+width="
local JOURNAL_ALL_DIM_WINDOW_CMDS = { HEIGHT_CMD, WIDTH_CMD }

local TAGS_ALL = "all"
local TAGS_DUE = "due"
local TAGS_FILTER = "filter"
local TAGS_SUBCOMMANDS = {
  TAGS_ALL, TAGS_DUE, TAGS_FILTER, "urgent", "onhold", "question", "todo",
  "incidents", "changes", "issues", "bugs",
}

-- NOTE (C53): `waiting` is a defined-but-unused constant in the vimscript
-- original — `s:todo_subcommands` only lists 5 of the 6 `s:todo_*_cmd`
-- values. Preserved verbatim (dead-constant quirk, ADR-flagged, not "fixed").
local TODO_SUBCOMMANDS = { "inprogress", "backlog", "done", "onhold", "questions" }

local WEEK_DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

-- ---------------------------------------------------------------------------
-- M.deps — T10 injection points (façade functions not yet ported). Subpath
-- helpers get pure defaults (trivial `path.join` arithmetic, functionally
-- identical to the façade's own); everything else is a `vim.fn['awiwi#…']`
-- shim until T10 rebinds it.
-- ---------------------------------------------------------------------------

M.deps = {}

function M.deps.get_journal_subpath()
  return path.join(vim.g.awiwi_home, "journal")
end

function M.deps.get_asset_subpath()
  return path.join(vim.g.awiwi_home, "assets")
end

function M.deps.get_recipe_subpath()
  return path.join(vim.g.awiwi_home, "recipes")
end

function M.deps.get_journal_file_by_date(date_expr)
  local parsed = date.parse_date(date_expr)
  local parts = vim.split(parsed, "-", { plain = true })
  return path.join(vim.g.awiwi_home, "journal", parts[1], parts[2], parsed .. ".md")
end

-- `vim.system`-shaped dep (rg calls in completion/entries/export, drawio spawn).
function M.deps.system(cmd, opts, on_exit)
  return vim.system(cmd, opts, on_exit)
end

local function vimshim(name)
  return function(...)
    return vim.fn["awiwi#" .. name](...)
  end
end

M.deps.get_all_journal_files = vimshim("get_all_journal_files")
M.deps.insert_journal_link = vimshim("insert_journal_link")
M.deps.edit_journal = vimshim("edit_journal")
M.deps.insert_and_open_continuation = vimshim("insert_and_open_continuation")
M.deps.activate_current_task = vimshim("activate_current_task")
M.deps.deactivate_active_task = vimshim("deactivate_active_task")
M.deps.copy_file = vimshim("copy_file")
M.deps.insert_recipe_link = vimshim("insert_recipe_link")
M.deps.open_file = vimshim("open_file")
M.deps.fuzzy_search = vimshim("fuzzy_search")
M.deps.redact = vimshim("redact")
M.deps.edit_meta_info = vimshim("edit_meta_info")
M.deps.edit_todo = vimshim("edit_todo")
M.deps.show_toc_in_qlist = vimshim("show_toc_in_qlist")

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function cmd_error(msg, ...)
  if select("#", ...) > 0 then
    msg = msg:format(...)
  end
  error("AwiwiCmdError: " .. msg, 0)
end

-- `s:contains(list, el, ...)` — true if the list contains any of the elements.
local function contains(list, ...)
  local els = { ... }
  for _, x in ipairs(list) do
    for _, e in ipairs(els) do
      if x == e then
        return true
      end
    end
  end
  return false
end

-- slice `list[from..to]` (1-indexed, inclusive), returning a new table.
local function slice(list, from, to)
  to = to or #list
  local out = {}
  for i = from, to do
    out[#out + 1] = list[i]
  end
  return out
end

local function bool2n(b)
  return b and 1 or 0
end

local function session_file()
  return path.join(vim.g.awiwi_home, "session.vim")
end

-- ---------------------------------------------------------------------------
-- Shared arg parser (journal/asset/recipe/todo) — `s:parse_file_and_options`.
-- ---------------------------------------------------------------------------

local function has_new_win_cmd(args)
  for _, v in ipairs(args) do
    if vim.tbl_contains(JOURNAL_OPTIONS_CMD, v) then
      return true
    end
  end
  return false
end

local function has_win_height_cmd(args)
  for _, v in ipairs(args) do
    if str.startswith(v, HEIGHT_CMD) or str.startswith(v, WIDTH_CMD) then
      return true
    end
  end
  return false
end

--- C40-C46. Non-fatal `nvim_err_writeln` on bad arg count / missing file
--- (matches the vimscript `echoerr`-doesn't-return "warn but keep going"
--- quirk). B3 fixed: `+width=` writes `options.width`, `+height=` writes
--- `options.height` (were both aliased to `.height`). `!bookmark` is preserved
--- as a recognized-but-inert flag (dead per #39; recognizing it avoids it being
--- mis-parsed as the file token).
local function parse_file_and_options(args, defaults)
  if #args == 0 or #args > 3 then
    vim.api.nvim_err_writeln(("Awiwi journal: 1 to 3 arguments expected. got %d"):format(#args - 1))
  end

  local options
  if defaults ~= nil then
    options = vim.deepcopy(defaults)
  else
    options = { position = "auto", new_window = true, new_tab = false, create_dirs = false, bookmark = false }
  end

  local file = ""
  for _, arg in ipairs(args) do
    if arg:sub(1, 1) == "#" then
      options.anchor = arg:sub(2)
    elseif arg == CREATE_FILE_CMD then
      options.create_dirs = true
    elseif vim.tbl_contains(JOURNAL_OPTIONS_CMD, arg) then
      if arg == HNEW_CMD then
        options.position = "bottom"
        options.new_window = true
      elseif arg == VNEW_CMD then
        options.position = "right"
        options.new_window = true
      elseif arg == NEW_CMD then
        options.position = "auto"
        options.new_window = true
      elseif arg == SAME_CMD then
        options.new_window = false
      elseif arg == TAB_CMD then
        options.new_window = false
        options.new_tab = true
      elseif arg == BOOKMARK then
        options.bookmark = true
      end
    elseif str.startswith(arg, HEIGHT_CMD) then
      options.height = tonumber(arg:match("=(.*)$")) or 0
    elseif str.startswith(arg, WIDTH_CMD) then
      options.width = tonumber(arg:match("=(.*)$")) or 0
    else
      file = arg
    end
  end

  if (options.height or 0) == 0 and util.window_split_below() then
    options.height = 20
  end
  if file == "" then
    vim.api.nvim_err_writeln("Awiwi journal: missing file to open")
  end
  return file, options
end

-- ---------------------------------------------------------------------------
-- Completion helpers
-- ---------------------------------------------------------------------------

local function need_to_insert_files(current_arg_pos, args, start)
  start = start or 2
  if current_arg_pos == start then
    return true
  end
  return (current_arg_pos - bool2n(has_new_win_cmd(args)) - bool2n(has_win_height_cmd(args))) == start
end

--- In-place mutate `li` with window/flag completion candidates.
--- Fix-in-port (latent bug): the vimscript `insert(a:li, dim_cmds_list)`
--- inserted the whole dim-cmd list as a single nested element; flattened here
--- to individual `+height=`/`+width=` candidates so they render as real
--- completions.
local function insert_win_cmds(li, current_arg_pos, args)
  if current_arg_pos == 2 then
    return
  elseif not has_new_win_cmd(args) then
    for _, v in ipairs(JOURNAL_OPTIONS_CMD) do
      li[#li + 1] = v
    end
    return
  elseif not has_win_height_cmd(args) then
    for i = #JOURNAL_ALL_DIM_WINDOW_CMDS, 1, -1 do
      table.insert(li, 1, JOURNAL_ALL_DIM_WINDOW_CMDS[i])
    end
  end
end

--- `s:get_file_for_command` — resolve the target file for `#anchor` heading
--- completion. `args` is the full 0-indexed-in-vimscript split (index+1 here).
local function get_file_for_command(args)
  if #args < 2 then
    return nil
  end
  local cmd, rem
  if args[2] == LINK then
    if #args == 2 then
      return nil
    end
    cmd = args[3]
    rem = slice(args, 4)
  else
    cmd = args[2]
    rem = slice(args, 3)
  end
  local file = ""
  for _, arg in ipairs(rem) do
    if not arg:match("^[-+#]") then
      file = arg
      break
    end
  end
  if not cmd or cmd == "" then
    return nil
  end
  if cmd == RECIPE then
    return ("%s/%s"):format(M.deps.get_recipe_subpath(), file)
  elseif cmd == ASSET then
    local parts = vim.split(file, ":", { plain = true })
    return asset.get_asset_path(parts[1], parts[2])
  elseif cmd == JOURNAL then
    return M.deps.get_journal_file_by_date(file)
  end
  return nil
end

--- `s:get_headings_from_file` — rg `^#+ ` over a file, slugify each heading
--- into an anchor (lower, strip `#+ ` prefix, whitelist `[-a-zA-Z0-9 ]`,
--- spaces→`-`, drop `/`). Kept as an rg+pattern pass over a disk file (not
--- treesitter) per Port notes (the file may not be an open buffer).
local function get_headings_from_file(file)
  if not file then
    return {}
  end
  local res = M.deps.system({ "rg", "^#+ ", file }, { text = true }):wait()
  local out = {}
  for _, line in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
    local s = line:lower()
    s = s:gsub("^#+%s+", "")
    s = s:gsub("[^%-a-zA-Z0-9 ]", "")
    s = s:gsub("%s+", "-")
    s = s:gsub("/", "")
    out[#out + 1] = s
  end
  return out
end

-- ---------------------------------------------------------------------------
-- get_completion (C47-C58)
-- ---------------------------------------------------------------------------

function M.get_completion(ArgLead, CmdLine, CursorPos)
  local current_arg_pos = util.get_argument_number(CmdLine:sub(1, CursorPos + 1))
  if current_arg_pos < 2 then
    return util.match_subcommands(SUBCOMMANDS, ArgLead)
  end

  local args = vim.fn.split(CmdLine)
  -- Access helper for the vimscript-0-indexed `args`/`get(args, k, d)` idiom.
  local function g(k, d)
    local v = args[k + 1]
    if v == nil then
      return d
    end
    return v
  end
  local a1 = args[2] -- vimscript args[1] (the subcommand)

  if a1 == TAGS and current_arg_pos >= 2 then
    local matches = util.match_subcommands(TAGS_SUBCOMMANDS, ArgLead)
    if current_arg_pos == 2 then
      return matches
    elseif g(2, "") == TAGS_FILTER then
      return {}
    end
    local prev = slice(args, 3, current_arg_pos) -- args[2:current_arg_pos-1] 0-indexed
    -- uniq (adjacent) then + filter
    local prev_cmds = {}
    for i, v in ipairs(prev) do
      if i == 1 or prev[i - 1] ~= v then
        prev_cmds[#prev_cmds + 1] = v
      end
    end
    prev_cmds[#prev_cmds + 1] = TAGS_FILTER
    local filtered = {}
    for _, v in ipairs(matches) do
      if not vim.tbl_contains(prev_cmds, v) then
        filtered[#filtered + 1] = v
      end
    end
    return filtered
  elseif a1 == JOURNAL or (a1 == LINK and g(2, "") == JOURNAL) then
    local start = a1 == JOURNAL and 2 or 3
    local submatches = {}
    if need_to_insert_files(current_arg_pos, slice(args, start + 1), start) then
      local jf = M.deps.get_all_journal_files()
      for i = #jf, 1, -1 do
        if jf[i] == "todos" then
          table.remove(jf, i)
        end
      end
      local pre = { "todos", "today", "next", "previous" }
      for i = #pre, 1, -1 do
        table.insert(jf, 1, pre[i])
      end
      for _, v in ipairs(jf) do
        submatches[#submatches + 1] = v
      end
    elseif a1 == LINK and g(current_arg_pos, "") == "#" then
      local file = get_file_for_command(args)
      local headings = {}
      for _, v in ipairs(get_headings_from_file(file)) do
        headings[#headings + 1] = "#" .. v
      end
      if #headings > 0 and headings[1]:match("^#%s+2[%-0-9]+%s*$") then
        table.remove(headings, 1)
      end
      return headings
    end
    if a1 == JOURNAL then
      insert_win_cmds(submatches, current_arg_pos, slice(args, start + 1))
    end
    return util.match_subcommands(submatches, ArgLead)
  elseif a1 == ASSET or (a1 == LINK and g(2, "") == ASSET) then
    local submatches = {}
    if current_arg_pos > 2 and a1 == ASSET and g(2, "") == CREATE then
      return { asset.types.paste, asset.types.url, COPY }
    end
    local start = a1 == ASSET and 2 or 3
    if #args == 2 then
      submatches[#submatches + 1] = CREATE
      submatches[#submatches + 1] = asset.types.paste
    end
    if need_to_insert_files(current_arg_pos, slice(args, start + 1), start) then
      submatches[#submatches + 1] = CREATE
      submatches[#submatches + 1] = asset.types.paste
      for _, f in ipairs(asset.get_all_asset_files()) do
        submatches[#submatches + 1] = ("%s:%s"):format(f.date, f.name)
      end
    elseif a1 == LINK and g(current_arg_pos, "") == "#" then
      local file = get_file_for_command(args)
      local headings = {}
      for _, v in ipairs(get_headings_from_file(file)) do
        headings[#headings + 1] = "#" .. v
      end
      return headings
    end
    if a1 == ASSET then
      insert_win_cmds(submatches, current_arg_pos, slice(args, start + 1))
    end
    return util.match_subcommands(submatches, ArgLead)
  elseif a1 == RECIPE or (a1 == LINK and g(2, "") == RECIPE) then
    local start = a1 == RECIPE and 2 or 3
    local submatches = {}
    if need_to_insert_files(current_arg_pos, slice(args, start + 1), start) then
      for _, v in ipairs(M.get_all_recipe_files()) do
        submatches[#submatches + 1] = v
      end
    elseif a1 == LINK and g(current_arg_pos, "") == "#" then
      local file = get_file_for_command(args)
      local headings = {}
      for _, v in ipairs(get_headings_from_file(file)) do
        headings[#headings + 1] = "#" .. v
      end
      return headings
    end
    if a1 == RECIPE then
      insert_win_cmds(submatches, current_arg_pos, slice(args, start + 1))
    end
    return util.match_subcommands(submatches, ArgLead)
  elseif a1 == TODO then
    local submatches = {}
    for _, v in ipairs(TODO_SUBCOMMANDS) do
      submatches[#submatches + 1] = v
    end
    insert_win_cmds(submatches, current_arg_pos + 1, slice(args, 3))
    return util.match_subcommands(submatches, ArgLead)
  elseif a1 == META then
    if current_arg_pos == 2 then
      return util.match_subcommands({ META_EDIT, META_DELETE }, ArgLead)
    elseif current_arg_pos == 3 and g(2, "") == META_EDIT then
      return util.match_subcommands({ "created", DUE }, ArgLead)
    end
  elseif a1 == DUE or (g(2, "") == META_EDIT and g(3, "") == DUE) then
    local start = a1 == DUE and 2 or 4
    if current_arg_pos == start then
      local submatches = { "today", "tomorrow", "next", "in", "+" }
      for _, v in ipairs(WEEK_DAYS) do
        submatches[#submatches + 1] = v
      end
      return util.match_subcommands(submatches, ArgLead)
    elseif g(start, "") == "next" and current_arg_pos == start + 1 then
      local submatches = {}
      for _, v in ipairs(WEEK_DAYS) do
        submatches[#submatches + 1] = v
      end
      for _, v in ipairs({ "day", "week", "month", "year" }) do
        submatches[#submatches + 1] = v
      end
      return util.match_subcommands(submatches, ArgLead)
    elseif (g(start, "") == "in" or g(start, "") == "+") and current_arg_pos == start + 2 then
      local units = { "day", "week", "month", "year" }
      if g(start + 1, "") ~= "1" then
        for i, v in ipairs(units) do
          units[i] = v .. "s"
        end
      end
      return util.match_subcommands(units, ArgLead)
    end
  elseif a1 == SERVER and current_arg_pos == 2 then
    local first = server.server_is_running() and SERVER_STOP or SERVER_START
    return util.match_subcommands({ first, SERVER_LOGS }, ArgLead)
  elseif a1 == SERVER and current_arg_pos == 3 and g(2, "") == SERVER_START then
    return util.match_subcommands({ "localhost", "*" }, ArgLead)
  elseif a1 == SERVER and current_arg_pos == 3 and g(2, "") == SERVER_LOGS then
    return util.match_subcommands({ "stdout", "stderr", "exit" }, ArgLead)
  elseif a1 == LINK then
    return util.match_subcommands({ JOURNAL, RECIPE, ASSET }, ArgLead)
  end

  return {}
end

--- `s:get_all_recipe_files` (B4 fix): every readable file under the recipe
--- subpath, relative to it. Uses `path.relativize` (which already strips the
--- prefix + one separator correctly regardless of a trailing slash) instead of
--- the vimscript `strlen` arithmetic that could be off-by-one across configs.
function M.get_all_recipe_files()
  local subpath = M.deps.get_recipe_subpath()
  local matches = vim.fn.glob(path.join(subpath, "**", "*"), false, true)
  local files = {}
  for _, v in ipairs(matches) do
    if vim.fn.filereadable(v) == 1 then
      files[#files + 1] = path.relativize(v, subpath)
    end
  end
  table.sort(files)
  return files
end

-- ---------------------------------------------------------------------------
-- run (C1-C37)
-- ---------------------------------------------------------------------------

function M.run(...)
  local args = { ... }
  if #args == 0 then
    cmd_error("Awiwi expects 1+ arguments")
  end
  local a1 = args[1]
  local n = #args
  -- `get(a:000, k, d)` idiom: a:000 is 0-indexed, so element k is args[k+1].
  local function g(k, d)
    local v = args[k + 1]
    if v == nil then
      return d
    end
    return v
  end

  if a1 == JOURNAL or (a1 == LINK and g(1, "") == JOURNAL) then
    if args[n] == JOURNAL then
      if n == 1 then
        -- C3: file browser over the journal subpath.
        return picker.files({ dir = M.deps.get_journal_subpath(), prompt = "journal" })
      else
        -- C5: list picker over journal files + literals, sink = insert_journal_link.
        local items = M.deps.get_all_journal_files({ include_literals = true })
        return picker.select({
          items = items,
          prompt = "link journal",
          on_choice = function(choice)
            M.deps.insert_journal_link(choice)
          end,
        })
      end
    end
    local date_expr, options = parse_file_and_options(slice(args, 2), { new_window = false })
    if a1 == LINK then
      return M.deps.insert_journal_link(date_expr, options)
    end
    M.deps.edit_journal(date_expr, options)
  elseif a1 == EXPORT then
    M.export_drawio_diagram()
  elseif a1 == CONTINUE then
    M.deps.insert_and_open_continuation()
  elseif a1 == ACTIVATE then
    M.deps.activate_current_task()
  elseif a1 == DEACTIVATE then
    M.deps.deactivate_active_task()
  elseif a1 == asset.types.paste or (a1 == ASSET and g(1, "") == asset.types.paste) then
    -- C11: top-level `paste` or `asset paste`.
    return asset.create_asset_here_if_not_exists(asset.types.paste, {}, function() end)
  elseif a1 == ASSET or (a1 == LINK and g(1, "") == ASSET) then
    if n == 1 then
      -- C12 (P3' revived): richer date:name list picker → open_asset_sink.
      local items = {}
      for _, f in ipairs(asset.get_all_asset_files()) do
        items[#items + 1] = ("%s:%s"):format(f.date, f.name)
      end
      return picker.select({
        items = items,
        prompt = "asset",
        on_choice = function(choice)
          asset.open_asset_sink(choice)
        end,
      })
    elseif n >= 2 and args[2] == COPY then
      -- C13
      local link = util.get_link_under_cursor()
      if link.type ~= "asset" then
        vim.api.nvim_err_writeln("[ERROR] no asset file under cursor")
        return
      end
      local dest = path.canonicalize(path.join(vim.fn.expand("%:p:h"), link.target))
      return M.deps.copy_file(dest)
    elseif n >= 2 and args[2] == CREATE then
      local sub = g(2, "")
      if sub == asset.types.url then
        return asset.create_asset_here_if_not_exists(asset.types.url, {}, function() end)
      elseif sub == asset.types.paste then
        return asset.create_asset_here_if_not_exists(asset.types.paste, {}, function() end)
      else
        -- C16: create empty .md, write the HOST buffer, then open the asset.
        -- (The extra CLI name tokens are inert in the vimscript original — the
        -- name is always prompted interactively — so they are not forwarded.)
        return asset.create_asset_here_if_not_exists(asset.types.empty, { suffix = ".md" }, function(filename)
          if filename == nil or filename == "" then
            return
          end
          vim.cmd("write")
          asset.open_asset(filename, { new_window = true })
        end)
      end
    end

    -- C17: `asset <date:name-or-name>` / `link asset <...>`
    local start = a1 == ASSET and 1 or 2
    local date_file_expr, options = parse_file_and_options(slice(args, start + 1))
    local d, file
    if str.contains(date_file_expr, ":") then
      local parts = vim.split(date_file_expr, ":", { plain = true })
      d, file = parts[1], parts[2]
    else
      d = date.get_own_date()
      file = date_file_expr
    end
    if a1 == LINK then
      return asset.insert_asset_link(d, file, options)
    end
    return asset.open_asset_by_name(d, file, options)
  elseif a1 == RECIPE or (a1 == LINK and g(1, "") == RECIPE) then
    if args[n] == RECIPE then
      local subpath = M.deps.get_recipe_subpath()
      if n == 1 then
        -- C18 bare recipe file browser (B1: no &shell mutation at all).
        return picker.files({ dir = subpath, prompt = "recipe" })
      else
        -- link recipe (bare): file browser, sink = insert_recipe_link.
        return picker.files({
          dir = subpath,
          prompt = "link recipe",
          on_choice = function(f)
            M.deps.insert_recipe_link(path.relativize(f, subpath))
          end,
        })
      end
    end
    local recipe, options = parse_file_and_options(slice(args, 2))
    if not str.endswith(recipe, ".md") then
      recipe = recipe .. ".md"
    end
    options.create_dirs = true
    if a1 == RECIPE then
      local recipe_file = path.join(M.deps.get_recipe_subpath(), recipe)
      M.deps.open_file(recipe_file, options)
    else
      M.deps.insert_recipe_link(recipe, options)
    end
  elseif a1 == TAGS then
    M.show_tasks(unpack(slice(args, 2)))
  elseif a1 == SEARCH then
    M.deps.fuzzy_search(unpack(slice(args, 2)))
  elseif a1 == SERVE then
    server.serve()
  elseif a1 == SERVER then
    if n == 1 then
      vim.api.nvim_err_writeln("Awiwi server command needs further arguments")
      return
    elseif args[2] == SERVER_START then
      local host = g(2, "localhost")
      local port = g(3, server.get_default_port())
      server.start_server(host, port)
    elseif args[2] == SERVER_STOP then
      server.stop_server()
    elseif args[2] == SERVER_LOGS then
      server.server_logs(g(2, ""))
    end
  elseif a1 == REDACT then
    M.deps.redact()
  elseif a1 == DUE then
    M.deps.edit_meta_info({ delete = false, column = "due", args = slice(args, 2) })
  elseif a1 == META then
    local meta_opts = {}
    if args[2] == META_DELETE then
      meta_opts.delete = true
    elseif args[2] == META_EDIT then
      if n >= 3 then
        meta_opts.column = args[3]
      end
    else
      -- C31: `echo` (NOT echoerr) — distinction preserved per contract.
      vim.api.nvim_echo({ { ('error: got unknown command: "Awiwi meta %s"'):format(tostring(args[2])) } }, false, {})
      return
    end
    M.deps.edit_meta_info(meta_opts)
  elseif a1 == ENTRIES then
    -- C32 (B2 fix): heading grep with a navigable sink (picker.grep's default
    -- jump). The transform strips the `##+ ` marker but keeps `file:line:col:`.
    local pattern = "^#{2,}[[:space:]]+.*$"
    local argv = {
      "rg", "-u", "--column", "--line-number", "--no-heading", "--color=never",
      "-g", "!awiwi*", pattern,
    }
    picker.grep({
      argv = argv,
      prompt = "entries",
      transform = function(line)
        return (line:gsub("^(.-)##+%s+", "%1", 1))
      end,
    })
  elseif a1 == TODO then
    -- C33: default open options depend on whether the current buffer sits in a
    -- `todos/` directory. NOTE: parse gets the FULL args (incl the `todo`
    -- keyword) — faithful to the vimscript.
    local cur_dir = vim.fn.expand("%:p:h:t")
    local default_opts
    if cur_dir == "todos" then
      default_opts = { new_window = true, position = "top", new_tab = false }
    else
      default_opts = { new_window = false, new_tab = true }
    end
    local file, options = parse_file_and_options(args, default_opts)
    if file == TODO then
      file = "inprogress"
    end
    M.deps.edit_todo(file, options)
  elseif a1 == SAVE then
    return M.store_session()
  elseif a1 == RESTORE then
    return M.restore_session()
  elseif a1 == TOC then
    local d
    if n == 1 then
      d = date.get_own_date()
    else
      local frags = {}
      for _, v in ipairs(slice(args, 2)) do
        for _, p in ipairs(vim.split(v, "-", { plain = true })) do
          frags[#frags + 1] = p
        end
      end
      local capped = {}
      for i = 1, math.min(2, #frags) do
        capped[i] = frags[i]
      end
      d = table.concat(capped, "-")
    end
    M.deps.show_toc_in_qlist({ date = d })
  end
  -- C2: any other subcommand falls through silently (no else, no error).
end

-- ---------------------------------------------------------------------------
-- show_tasks / tags (C-tags-1..5)
-- ---------------------------------------------------------------------------

function M.show_tasks(...)
  local args = { ... }
  if #args == 0 then
    args = { "todo" }
  end

  local markers_list = {}
  if contains(args, "urgent", TAGS_ALL, "todo") then
    markers_list = { markers.get_markers("urgent") }
  end

  local has_due = false
  if contains(args, "todo", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("todo")
  end
  if contains(args, TAGS_DUE, TAGS_ALL) then
    local due = markers.get_markers("due")
    markers_list[#markers_list + 1] = ([[\(?(%s):?( \S+)*\)?]]):format(due)
    has_due = true
  end
  if contains(args, "onhold", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("onhold")
  end
  if contains(args, "question", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("question")
  end
  if contains(args, "incidents", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("incident")
  end
  if contains(args, "changes", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("change")
  end
  if contains(args, "issues", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("issue")
  end
  if contains(args, "bugs", TAGS_ALL) then
    markers_list[#markers_list + 1] = markers.get_markers("bug")
  end
  if args[1] == TAGS_FILTER then
    if #args == 1 then
      cmd_error('missing argument for "Awiwi tasks filter"')
    end
    for i = 2, #args do
      markers_list[#markers_list + 1] = args[i]
    end
  end

  local pattern = table.concat(markers_list, "|")
  -- No shellescape / shell string: argv goes straight to vim.system (no shell).
  local argv = {
    "rg", "-u", "--column", "--line-number", "--no-heading", "--color=always",
    "-g", "!awiwi*", pattern,
  }
  local filter_argv
  if has_due then
    local anti = ([[0m:[*-] +\[x\] |~~.{20}(%s)]]):format(pattern)
    filter_argv = { "rg", "-v", "--color=always", anti }
  end
  picker.grep({ argv = argv, filter_argv = filter_argv, prompt = "tags" })
end

-- ---------------------------------------------------------------------------
-- Session save / restore (C34/C35)
-- ---------------------------------------------------------------------------

function M.store_session()
  vim.cmd("mksession! " .. vim.fn.fnameescape(session_file()))
end

function M.restore_session()
  -- No existence check — throws Vim's own error if the file is missing (C35).
  vim.cmd("source " .. vim.fn.fnameescape(session_file()))
end

-- ---------------------------------------------------------------------------
-- drawio → PDF export (C-export-1..7). jobstart → vim.system (M.deps.system).
-- B5 fixed (errors collected into the right table). B6 fixed (spawn-failure
-- message references the argv, not the phantom `markup_language`). The
-- vimscript per-job `s:job_data` dict is unnecessary here — the closure holds
-- the output path + errors directly.
-- ---------------------------------------------------------------------------

function M.export_drawio_diagram(input_arg)
  local input_file
  if input_arg ~= nil and input_arg ~= "" then
    input_file = input_arg
  else
    local line = vim.fn.getline(".")
    local m = line:match("%(([^)]*%.drawio)%)")
    if m then
      input_file = m
    else
      vim.api.nvim_err_writeln("No drawio filename specified as input, nor found in the current line")
      return false
    end
  end

  if input_file:find("/assets/", 1, true) then
    -- Strip everything up to and including the last `/` before `assets/`.
    input_file = input_file:gsub("^.*/(assets/.*)$", "%1")
  end

  local name = vim.fn.fnamemodify(input_file, ":t:r")
  local default = ("/tmp/%s.pdf"):format(name)

  util.input({ prompt = "output: ", default = default }, function(output_file)
    if output_file == nil or output_file == "" then
      vim.api.nvim_err_writeln("No output file given.")
      return
    end

    local cmd = { "drawio", "--export", "--output", output_file, "--crop", "--all-pages", input_file }
    local errors = {}

    local ok = pcall(M.deps.system, cmd, {
      text = true,
      stderr = function(_, data)
        if not data then
          return
        end
        for _, l in ipairs(vim.split(data, "\n", { plain = true })) do
          if l ~= "" and not l:find("object_proxy.cc", 1, true) and l:find("Error", 1, true) then
            errors[#errors + 1] = l -- B5: right table
          end
        end
      end,
    }, function(_res)
      vim.schedule(function()
        if #errors == 0 then
          vim.notify("converted successfully to pdf ✔\n\n(filename copied to clipboard)", vim.log.levels.INFO, { timeout = 1000 })
          vim.fn.setreg("+", output_file)
        else
          vim.notify(
            ("could not convert to pdf ✖\n\n%s"):format(table.concat(errors, "\n")),
            vim.log.levels.ERROR,
            {}
          )
        end
      end)
    end)

    if not ok then
      -- B6: spawn failure — reference the argv, drop the phantom var.
      vim.api.nvim_err_writeln(
        ("[ERROR] could not convert file to pdf. reason: bad arguments %s"):format(vim.inspect(cmd))
      )
    end
  end)
end

return M
