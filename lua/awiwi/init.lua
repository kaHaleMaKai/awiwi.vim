-- awiwi façade (ports autoload/awiwi.vim). Bootstraps the g:awiwi_home
-- directory tree + log files, owns the glue that never fit a leaf module:
-- file-opening policy (open_file), journal/todo editing, the file-based
-- active-task timer, link insertion, redact/toc/meta-info utilities, and the
-- ftplugin list/checkbox Enter handling. Everything structural (link parsing,
-- dates, paths, markers, highlighting, asset creation, pickers, server) lives
-- in already-ported leaf modules and is `require`d, never re-derived.
--
-- See handovers/lua-port/init.md for the numbered behavior contract and the
-- bug ledger (B3, B6, B7, B8, B10, B-INIT-1..6) fixed/preserved here.

local path = require("awiwi.path")
local date = require("awiwi.date")
local str = require("awiwi.str")
local util = require("awiwi.util")
local hi = require("awiwi.hi")
local asset = require("awiwi.asset")
local markers = require("awiwi.markers")
local picker = require("awiwi.picker")

local M = {}

-- ---------------------------------------------------------------------------
-- Injection seams (mirrors asset.lua/server.lua's M.deps/M.config pattern so
-- specs never touch the real filesystem/clipboard/xdg outside a tempname dir).
-- ---------------------------------------------------------------------------

M.deps = {}

--- `vim.system`-shaped dep for every subprocess (xdg-open fire-and-forget,
--- xclip copy). Returns the handle; fire-and-forget callers ignore it,
--- copy_file `:wait()`s.
function M.deps.system(cmd, opts)
  return vim.system(cmd, opts)
end

--- Runs an Ex command string (open_file's `:edit`/split/tab dance). Injectable
--- so open_file's command construction is assertable without real windows.
function M.deps.exec(command)
  vim.cmd(command)
end

--- Epoch clock, injectable for the active-task timer specs.
function M.now()
  return os.time()
end

-- ---------------------------------------------------------------------------
-- Small local helpers
-- ---------------------------------------------------------------------------

local function err(msg)
  vim.api.nvim_err_writeln(msg)
end

local function echo(msg)
  vim.api.nvim_echo({ { msg } }, false, {})
end

local function data_dir()
  return path.join(vim.g.awiwi_home, "data")
end

local function log_file()
  return path.join(data_dir(), "awiwi.log")
end

local function task_log_file()
  return path.join(data_dir(), "task.log")
end

local function todos_subpath()
  return path.join(vim.g.awiwi_home, "todos")
end

--- Reuse asset.lua's byte-faithful cursor-insertion primitive (DRY: the
--- single biggest overlap between this façade and T5). Never re-derived.
local function insert_link_here(link)
  return asset.deps.insert_link_here(link)
end

--- `s:add_link` — relativized markdown link.
local function add_link(title, target, base)
  local rel = base and util.relativize(target, base) or util.relativize(target)
  return string.format("[%s](%s)", title, rel)
end

-- ---------------------------------------------------------------------------
-- Subpaths (§3-4). B10: computed via path.join, not the broken recursive
-- vimscript join (fn#apply/fn#spread, never vendored).
-- ---------------------------------------------------------------------------

function M.get_journal_subpath()
  return path.join(vim.g.awiwi_home, "journal")
end

function M.get_asset_subpath()
  return path.join(vim.g.awiwi_home, "assets")
end

function M.get_recipe_subpath()
  return path.join(vim.g.awiwi_home, "recipes")
end

function M.get_journal_file_by_date(date_expr)
  local parsed = date.parse_date(date_expr)
  local parts = vim.split(parsed, "-", { plain = true })
  return path.join(M.get_journal_subpath(), parts[1], parts[2], parsed .. ".md")
end

-- ---------------------------------------------------------------------------
-- Bootstrap (§1-2, §37)
-- ---------------------------------------------------------------------------

--- Ensures the home subdirectory tree + task.log exist, then resumes an
--- active task if the most recent task.log record was left active (§37).
--- Idempotent; safe to call repeatedly. Returns false if g:awiwi_home unset.
function M.bootstrap()
  local home = vim.g.awiwi_home
  if not home or home == "" then
    return false
  end
  for _, d in ipairs({ "data", "journal", "assets", "recipes", "todos", "cache" }) do
    local dir = path.join(home, d)
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end
  local tlog = task_log_file()
  if vim.fn.filereadable(tlog) == 0 then
    local f = io.open(tlog, "a")
    if f then
      f:close()
    end
  end
  M.resume_active_task()
  return true
end

-- ---------------------------------------------------------------------------
-- open_file (§5-17). B-INIT-3 (left-split syntax-error) + B3 (independent
-- width/height axes) fixed.
-- ---------------------------------------------------------------------------

local XDG_OPEN_EXTS = { ods = true, odt = true, drawio = true }

function M.open_file(file, options)
  options = options or {}
  local extension = vim.fn.fnamemodify(file, ":e")
  if XDG_OPEN_EXTS[extension] then
    M.deps.system({ "xdg-open", file })
    return
  end

  local cmd
  if options.new_window then
    local position = options.position or "auto"
    if position == "auto" then
      position = util.window_split_below() and "bottom" or "right"
    end
    local prefix = ""
    local win_cmd
    local vertical = false
    if position == "left" then
      -- B-INIT-3: vimscript had `let win_cmd == 'vnew'` (E15). Intended a left
      -- vertical split, mirroring `right` — `leftabove` produces it.
      win_cmd = "vnew"
      prefix = "leftabove "
      vertical = true
    elseif position == "right" then
      win_cmd = "vnew"
      vertical = true
    elseif position == "top" then
      win_cmd = "new"
      prefix = "leftabove "
    else
      win_cmd = "new"
      if position ~= "bottom" then
        err(('wrong position for awiwi#open_file() specified: "%s"'):format(position))
      end
    end
    -- B3: vertical splits size from width, horizontal from height (the
    -- vimscript conflated both into one `height` slot).
    local size
    if vertical then
      size = tonumber(options.width) or 0
    else
      size = tonumber(options.height) or 0
    end
    cmd = string.format("%s %s%s", prefix, size > 0 and size or "", win_cmd)
  elseif options.new_tab then
    cmd = "tabnew"
  else
    cmd = "e"
  end

  if options.create_dirs then
    local dir = vim.fn.fnamemodify(file, ":p:h")
    vim.fn.mkdir(dir, "p")
  end

  local anchor = options.anchor or ""
  local jump_mod
  if anchor ~= "" then
    jump_mod = "+/\\c" .. anchor
  elseif options.last_line then
    jump_mod = "+"
  else
    jump_mod = ""
  end

  local is_new = options.template and vim.fn.filereadable(file) == 0
  M.deps.exec(string.format("%s %s %s", cmd, jump_mod, file))

  if is_new then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, options.template)
    if options.template_cursor then
      vim.api.nvim_win_set_cursor(0, { options.template_cursor, 0 })
      vim.cmd("startinsert!")
    end
  end
end

-- ---------------------------------------------------------------------------
-- edit_journal (§18-21) / edit_todo (§22)
-- ---------------------------------------------------------------------------

function M.edit_journal(date_expr, options)
  options = options or {}
  options.last_line = true
  local d = date.parse_date(date_expr)
  if d == date.get_today() then
    options.create_dirs = true
  end
  local ok_own, own_date = pcall(date.get_own_date)
  if ok_own and d == own_date then
    echo(("journal page '%s' already open"):format(d))
    return
  end
  local file = M.get_journal_file_by_date(d)
  if d > date.get_today() and not options.create_dirs and vim.fn.filewritable(file) ~= 1 then
    err(('trying to open file for future date "%s" without +create option'):format(d))
    return
  end
  options.template = { ("# %s"):format(d), "", "## " }
  options.template_cursor = 3
  M.open_file(file, options)
end

function M.edit_todo(name, options)
  local file = path.join(todos_subpath(), name .. ".md")
  M.open_file(file, options)
end

-- ---------------------------------------------------------------------------
-- get_current_task (§23-24). B-INIT-1: clean empty return, never throws.
-- ---------------------------------------------------------------------------

--- `s:format_tags` — splits the trailing suffix into a `(cont...)` token and
--- everything else.
local function format_tags(rem)
  local cont = ""
  local tags = {}
  local raw = vim.fn.split(rem, "\\s\\+[(@]\\@=")
  for _, tag in ipairs(raw) do
    tag = vim.trim(tag)
    if vim.fn.match(tag, "^(cont\\..*)$") == 0 then
      cont = tag
    else
      tags[#tags + 1] = tag
    end
  end
  return cont, tags
end

function M.get_current_task(only_main)
  local depth = only_main and "2" or "2,4"
  local pattern = table.concat({
    ("^\\(#\\{%s}\\)"):format(depth),
    "[[:space:]]\\+",
    "\\([^[:space:]].\\{-}\\)",
    "\\(",
    "@[a-zA-Z]\\+",
    "\\|",
    "(cont\\. from.*",
    "\\)\\?",
    "$",
  }, "")

  for line_nr = vim.fn.line("."), 1, -1 do
    local line = vim.fn.getline(line_nr)
    local m = vim.fn.matchlist(line, pattern)
    if #m > 0 then
      local marker, title, rem = m[2], m[3], m[4]
      local cont, tags = format_tags(rem)
      return { marker = marker, title = vim.trim(title), tags = tags, cont = cont }
    end
  end
  -- B-INIT-1: vimscript's fallback had invalid dict syntax (E720). Fixed.
  return { marker = "", title = "", tags = {}, cont = "" }
end

-- ---------------------------------------------------------------------------
-- insert_and_open_continuation (§25-27)
-- ---------------------------------------------------------------------------

function M.insert_and_open_continuation()
  local own_date = date.get_own_date()
  local today = date.parse_date("today")
  if own_date == today then
    error("AwiwiError: already on today's journal", 0)
  end
  local today_file = M.get_journal_file_by_date(today)
  local link = add_link(("continued on %s"):format(today), today_file)
  local current_task = M.get_current_task(true)
  if current_task.title == "" then
    error("AwiwiError: could not find task title", 0)
  end

  local own_file = M.get_journal_file_by_date(own_date)
  local back_link = add_link(("started on %s"):format(own_date), own_file, today_file)

  vim.fn.append(vim.fn.line("."), { link, "" })
  vim.cmd("write")
  M.edit_journal(today, { new_window = true, position = "top" })
  local lines = {
    "",
    ("%s %s (cont. from %s)"):format(current_task.marker, current_task.title, own_date),
    back_link,
    "",
  }
  vim.fn.append(vim.fn.line("$"), lines)
  vim.cmd("normal! G")
end

-- ---------------------------------------------------------------------------
-- get_all_journal_files (§28-31)
-- ---------------------------------------------------------------------------

function M.get_all_journal_files(opts)
  opts = opts or {}
  local parts = { M.get_journal_subpath() }
  for _, p in ipairs(vim.split(opts.date or "", "-", { plain = true })) do
    if p ~= "" then
      parts[#parts + 1] = p
    end
  end
  parts[#parts + 1] = "**"
  parts[#parts + 1] = "*.md"
  local pattern = path.join(unpack(parts))
  local files = vim.fn.glob(pattern, false, true)
  if not opts.full_path then
    files = vim.tbl_map(function(v)
      return vim.fn.fnamemodify(v, ":t:r")
    end, files)
  end
  table.sort(files)
  if opts.include_literals then
    vim.list_extend(files, { "previous day", "next day", "yesterday", "today" })
  end
  return files
end

-- ---------------------------------------------------------------------------
-- Active-task timer (§32-39)
-- ---------------------------------------------------------------------------

local function get_empty_task()
  return {
    title = "",
    marker = "",
    type = false,
    activity = {},
    state = "inactive",
    created = 0,
    updated = 0,
    duration = 0,
  }
end

M._active_task = get_empty_task()

local function log_line(level, msg)
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local line = string.format("[%s] %-5s - %s", ts, level:upper(), msg)
  local f = io.open(log_file(), "a")
  if not f then
    return false
  end
  f:write(line .. "\n")
  f:close()
  return true
end

local function log_task_action(task, action)
  log_line("INFO", ('%s task "%s"'):format(action, task.title))
  local f = io.open(task_log_file(), "a")
  if not f then
    return false
  end
  f:write(vim.json.encode(task) .. "\n")
  f:close()
  return true
end

local function read_lines(file)
  local f = io.open(file, "r")
  if not f then
    return {}
  end
  local lines = {}
  for l in f:lines() do
    lines[#lines + 1] = l
  end
  f:close()
  return lines
end

local function get_most_recent_task_from_file()
  local lines = read_lines(task_log_file())
  if #lines == 0 then
    return get_empty_task()
  end
  local ok, t = pcall(vim.json.decode, lines[#lines])
  if ok and type(t) == "table" then
    return t
  end
  return get_empty_task()
end

local function get_most_recent_task_activity(title)
  local task = get_empty_task()
  for _, l in ipairs(read_lines(task_log_file())) do
    local ok, t = pcall(vim.json.decode, l)
    if ok and type(t) == "table" and t.title == title then
      task = t
    end
  end
  return task
end

local function get_active_task()
  if M._active_task and M._active_task.state == "active" then
    return M._active_task
  end
  return get_empty_task()
end

function M.resume_active_task()
  local task = get_most_recent_task_from_file()
  if task.state == "active" then
    M._active_task = task
    vim.g.awiwi_active_task = vim.deepcopy(task)
  end
end

function M.activate_current_task()
  local current_task = M.get_current_task(true)
  if current_task.title == "" then
    err("not in a task section")
    return
  end
  local active_task = get_active_task()
  if active_task.state == "active" then
    if active_task.title == current_task.title then
      echo("task is already active")
      return
    else
      err(('you must deactive the active task "%s"'):format(active_task.title))
      return
    end
  end

  local recent_task = get_most_recent_task_from_file()
  local task
  if recent_task.title == current_task.title then
    task = recent_task
  else
    task = get_most_recent_task_activity(current_task.title)
  end
  if task.title == "" then
    task.title = current_task.title
    task.marker = current_task.marker
  end
  local ts = M.now()
  task.state = "active"
  task.updated = ts
  task.activity = task.activity or {}
  table.insert(task.activity, { action = "activate", ts = ts })
  log_task_action(task, "activate")
  M._active_task = task
  vim.g.awiwi_active_task = vim.deepcopy(task)
end

function M.deactivate_active_task()
  local task = get_active_task()
  if task.state ~= "active" then
    echo("no task active")
    return
  end
  local ts = M.now()
  local start_ts = task.activity[#task.activity].ts
  local duration = ts - start_ts
  table.insert(task.activity, { action = "deactivate", ts = ts })
  task.state = "inactive"
  task.updated = ts
  task.duration = task.duration + duration
  log_task_action(task, "deactivate")
  vim.g.awiwi_active_task = nil
  M._active_task = task
end

function M.add_active_task_to_airline()
  local t = vim.g.awiwi_active_task
  if not t or t.state ~= "active" then
    return ""
  end
  local now = M.now()
  local d = t.duration + now - t.activity[#t.activity].ts
  local fmt
  if d < 60 then
    fmt = ("%ds"):format(d)
  elseif d < 3600 then
    fmt = ("%dm %ds"):format(math.floor(d / 60), d % 60)
  elseif d < 86400 then
    fmt = ("%dh %dm"):format(math.floor(d / 3600), math.floor((d % 3600) / 60))
  else
    fmt = ("%dd %dh"):format(math.floor(d / 86400), math.floor((d % 86400) / 3600))
  end
  return ("[ %s (%s) ]"):format(t.title, fmt)
end

-- ---------------------------------------------------------------------------
-- open_link (§40-44). B-INIT-4: early return after empty-type error (fix).
-- ---------------------------------------------------------------------------

function M.open_link(options, link_arg)
  options = options or {}
  local link
  if link_arg ~= nil then
    link = util.determine_link_type(util.as_link(link_arg))
  else
    link = util.get_link_under_cursor()
  end
  if not link.type or link.type == "" then
    err(('cannot open link: "%s"'):format(tostring(link.target)))
    -- B-INIT-4: early return avoids the vimscript's redundant second error.
    return
  end
  local t = link.type
  if t == "browser" or t == "external" or t == "mail" then
    M.deps.system({ "xdg-open", link.target })
  elseif t == "asset" or t == "journal" or t == "recipe" then
    local dest = path.canonicalize(path.join(vim.fn.expand("%:p:h"), link.target))
    if link.anchor and link.anchor ~= "" then
      options.anchor = link.anchor
    end
    M.open_file(dest, options)
  elseif t == "image" then
    local dest = asset.resolve_image_link(link.target)
    if not dest then
      err(('cannot open link: "%s"'):format(tostring(link.target)))
      return
    end
    local opener = vim.deepcopy(vim.g.awiwi_image_opener or { "xdg-open" })
    opener[#opener + 1] = dest
    M.deps.system(opener)
  else
    err(('cannot open unknown link type "%s"'):format(t))
  end
end

-- ---------------------------------------------------------------------------
-- redact (§45-46)
-- ---------------------------------------------------------------------------

function M.redact()
  local line = vim.fn.getline(".")
  local pos = vim.fn.getcurpos()
  local new_line
  if vim.fn.match(line, "!!redacted") == -1 then
    local space = (line == "" or str.endswith(line, " ")) and "" or " "
    new_line = line .. space .. "!!redacted"
  else
    new_line = vim.fn.substitute(line, " *!!redacted", "", "g")
  end
  vim.fn.setline(".", new_line)
  vim.fn.setpos(".", pos)
end

-- ---------------------------------------------------------------------------
-- copy_file (§ copy) — echoes status, returns bool.
-- ---------------------------------------------------------------------------

function M.copy_file(p)
  local res = M.deps.system({ "xclip", "-selection", "clipboard", "-r", p }):wait()
  if res.code == 0 then
    echo(("[INFO] copied file %s to clipboard"):format(vim.fn.fnamemodify(p, ":h")))
    return true
  end
  echo(("[ERROR] could not copy file %s to clipboard"):format(vim.fn.fnamemodify(p, ":h")))
  return false
end

-- ---------------------------------------------------------------------------
-- insert_recipe_link (§47-49) / insert_journal_link (§50-51, B-INIT-2)
-- ---------------------------------------------------------------------------

function M.insert_recipe_link(recipe, options)
  options = options or {}
  local recipe_file = path.join(M.get_recipe_subpath(), recipe)
  local parts = vim.split(recipe_file, "/", { plain = true })
  local start = 1
  for i = #parts, 1, -1 do
    if parts[i] == "recipes" then
      start = i + 1
      break
    end
  end
  local file_name = path.join(unpack(parts, start))
  local rel = util.relativize(recipe_file)
  local anchor = options.anchor or ""
  local link
  if anchor == "" then
    link = ("[recipe %s](%s)"):format(file_name, rel)
  else
    link = ("[recipe %s: %s](%s#%s)"):format(file_name, anchor, rel, anchor)
  end
  insert_link_here(link)
end

function M.insert_journal_link(date_expr, options)
  options = options or {}
  local anchor = options.anchor or ""
  local d = date.parse_date(date_expr)
  local file = util.relativize(M.get_journal_file_by_date(d))
  local link
  if anchor == "" then
    link = ("[journal for %s](%s)"):format(d, file)
  else
    -- B-INIT-2: dropped the vimscript's stray `)` after the anchor text.
    link = ("[journal for %s: %s](%s#%s)"):format(d, anchor, file, anchor)
  end
  insert_link_here(link)
end

-- ---------------------------------------------------------------------------
-- handle_paste_in_insert_mode (§52-54)
-- ---------------------------------------------------------------------------

local MIME_PROBE_ORDER = { "text/plain", "image/jpg", "image/png", "image/gif", "image/bmp" }

--- Ported natively (asset.lua keeps its own copy private). Probes the X
--- clipboard MIME type via `xclip -o -t <mime> | file --mime-type -`.
function M.guess_selection_mime_type()
  for _, mime in ipairs(MIME_PROBE_ORDER) do
    local xclip = M.deps.system({ "xclip", "-selection", "clipboard", "-o", "-t", mime }, { text = true }):wait()
    local sniff = M.deps.system({ "file", "--mime-type", "-" }, { text = true, stdin = xclip.stdout or "" }):wait()
    local mime_type = (vim.trim(sniff.stdout or "")):match("(%S+)%s*$")
    if mime_type and not mime_type:find("empty", 1, true) then
      return mime_type
    end
  end
  return ""
end

function M.handle_paste_in_insert_mode()
  local type_ = M.guess_selection_mime_type()
  if type_ == "" then
    return
  elseif type_ == "text/plain" then
    vim.cmd('normal! "+p')
  else
    asset.create_asset_here_if_not_exists(asset.types.paste, {}, function(filename)
      if filename and filename ~= "" then
        vim.cmd("normal! f)l")
      end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- edit_meta_info (§55-61)
-- ---------------------------------------------------------------------------

function M.edit_meta_info(opts)
  opts = opts or {}
  if opts.delete == nil then
    opts.delete = false
  end
  opts.column = opts.column or ""

  local lineno = vim.fn.line(".")
  local line = vim.fn.getline(lineno)
  if vim.trim(line) == "" then
    return
  end
  local m = vim.fn.matchlist(line, "\\(\\s*\\)\\({[^}]\\+}\\)$")

  if #m == 0 and opts.delete then
    return
  end

  local spaces, blob
  if #m == 0 then
    spaces, blob = "", ""
  else
    spaces, blob = m[2], m[3]
  end
  local default = blob == "" and "{}" or blob
  local start = math.max(0, #line - #spaces - #blob - 1)

  if opts.delete then
    vim.fn.setline(lineno, line:sub(1, start + 1))
    hi.redraw_due_dates(true)
    return
  end

  local function finish(meta)
    if not meta or meta == "" then
      echo("no meta info specified. exiting")
      return
    end
    if blob == meta then
      return
    end
    vim.fn.setline(lineno, ("%s %s"):format(line:sub(1, start + 1), meta))
    hi.redraw_due_dates(true)
  end

  if opts.column ~= "" then
    local json = vim.json.decode(default)
    local function apply_val(val)
      if val == nil then
        return
      end
      val = vim.trim(val)
      if val == "" then
        echo("no meta info specified. exiting")
        return
      end
      if opts.column == "due" then
        -- Preserve the vimscript typo `^to\%[mmorow]\+$` verbatim (see Bugs).
        if vim.fn.match(val, "^to\\%[mmorow]\\+$") == 0 then
          val = "tomorrow"
        end
        json[opts.column] = date.to_iso_date(val)
      else
        json[opts.column] = val
      end
      finish(vim.json.encode(json))
    end
    if opts.args and #opts.args > 0 then
      apply_val(table.concat(opts.args, " "))
    else
      util.input({ prompt = ("meta info: %s="):format(opts.column), default = "" }, apply_val)
    end
  else
    util.input({ prompt = "meta info: ", default = default }, function(meta)
      if meta == nil then
        return
      end
      meta = vim.trim(meta)
      local ok, d = pcall(vim.json.decode, meta)
      if not ok then
        err(("meta info includes an error: %s"):format(tostring(d)))
        return
      end
      if type(d) == "table" and d.due ~= nil then
        d.due = date.to_iso_date(d.due)
        meta = vim.json.encode(d)
      end
      finish(meta)
    end)
  end
end

-- ---------------------------------------------------------------------------
-- show_toc_in_qlist (§62-68). B-INIT-5: dynamic quickfix-buffer re-check.
-- ---------------------------------------------------------------------------

--- Line-based `^```` fence toggle + ATX-heading scan. Dedicated ToC generator,
--- deliberately NOT the treesitter mask hi/syn use (§66).
local function generate_toc(file, max_level)
  local d = vim.fn.fnamemodify(file, ":t:r")
  local lines = {}
  local is_codeblock = false
  local i = 0
  for _, line in ipairs(vim.fn.readfile(file)) do
    i = i + 1
    if line == "# " .. d then
      -- own title heading, skip
    elseif line:match("^```") then
      is_codeblock = not is_codeblock
    elseif is_codeblock then
      -- inside fenced code, skip
    else
      local marker, title = line:match("^(#+) +(%S.*)$")
      if marker then
        local level = #marker - 2
        if level <= max_level then
          local padding = string.rep(" ", math.max(0, 3 - #tostring(i)))
          local indent = string.rep("..", level)
          lines[#lines + 1] =
            { filename = file, lnum = i, text = indent .. title, module = d .. padding }
        end
      end
    end
  end
  return lines
end

local function get_toc_title(year, month)
  local when = os.time({ year = tonumber(year), month = tonumber(month), day = 1, hour = 12 })
  return os.date("%B %Y", when)
end

--- Dynamic predicate replacing B-INIT-5's baked-in stale window number: is
--- there still a listed quickfix buffer anywhere?
function M._toc_should_refresh()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buftype == "quickfix" and vim.fn.buflisted(b) == 1 then
      return true
    end
  end
  return false
end

local TOC_AUGROUP = "AwiwiTocUpdate"

function M._add_toc_aucmd(buffer)
  local group = vim.api.nvim_create_augroup(TOC_AUGROUP, { clear = true })
  local function drop()
    pcall(vim.api.nvim_del_augroup_by_name, TOC_AUGROUP)
  end
  local function refresh()
    if not M._toc_should_refresh() then
      drop()
      return
    end
    local ok, own = pcall(date.get_own_date)
    if ok then
      M.show_toc_in_qlist({ date = own, show = false })
    end
  end
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, buffer = buffer, callback = refresh })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "*/journal/*.md",
    callback = function()
      if M._toc_should_refresh() then
        refresh()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufHidden", { group = group, buffer = buffer, callback = drop })
end

function M.show_toc_in_qlist(opts)
  opts = opts or {}
  local max_level = opts.max_level or 6
  local d = opts.date or ""
  local is_single_date = date.is_date(d)
  local files
  if is_single_date then
    files = { M.get_journal_file_by_date(d) }
  else
    files = M.get_all_journal_files({ date = d, full_path = true })
  end

  local topics = {}
  for _, f in ipairs(files) do
    for _, entry in ipairs(generate_toc(f, max_level)) do
      topics[#topics + 1] = entry
    end
  end
  vim.fn.setqflist(topics)

  local parts = d == "" and {} or vim.split(d, "-", { plain = true })
  local title
  if #parts == 0 then
    title = "topics"
  elseif #parts == 1 then
    title = ("topics %s"):format(parts[1])
  elseif is_single_date then
    title = ("topics %s"):format(date.to_nice_date(d))
  else
    title = get_toc_title(parts[1], parts[2])
  end
  -- Two separate setqflist calls (title without touching entries) — preserved.
  vim.fn.setqflist({}, "a", { title = title })

  if opts.show == nil or opts.show then
    local buffer = vim.api.nvim_get_current_buf()
    vim.cmd("copen")
    if is_single_date then
      M._add_toc_aucmd(buffer)
    end
  end
end

-- ---------------------------------------------------------------------------
-- fuzzy_search (§ search) — routed through picker.grep (ADR-flagged upgrade).
-- ---------------------------------------------------------------------------

function M.fuzzy_search(...)
  local args = { ... }
  if #args == 0 then
    err("Awiwi search: no pattern given")
    return
  end
  local pattern = table.concat(args, " ")
  local argv = {
    "rg", "-i", "-U", "--multiline-dotall", "--color=never",
    "--column", "--line-number", "--no-heading", "-g", "!awiwi*", pattern,
  }
  picker.grep({ argv = argv, prompt = "search" })
end

-- ---------------------------------------------------------------------------
-- folding (§ B7) — plain Lua foldexpr, no stringified-Funcref splice.
-- ---------------------------------------------------------------------------

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^%s*$") then
    return "-1"
  end
  local level = #(line:match("^#*") or "")
  if level > 0 then
    return ">" .. (level - 1)
  end
  return "="
end

-- ---------------------------------------------------------------------------
-- ftplugin list/checkbox Enter handling (§69-77) + append (§78) +
-- split-screen (§79) + todo cleanup (§84)
-- ---------------------------------------------------------------------------

local function get_line_start(prefix_space, list_char, infix_space, is_checklist)
  local line = { prefix_space, list_char }
  if is_checklist then
    line[#line + 1] = infix_space
    line[#line + 1] = "[ ]"
  end
  if list_char ~= "" then
    line[#line + 1] = " "
  end
  return table.concat(line)
end

local function pad(length, content)
  return string.rep(" ", length) .. (content or "")
end

function M.handle_enter_on_insert(mode, above, continue_paragraph)
  local line = vim.fn.getline(".")
  local cursor = vim.fn.getcurpos()
  local line_nr = cursor[2]
  local pos = cursor[3]
  local m = vim.fn.matchlist(
    line,
    "^\\([[:space:]]*\\)\\(\\([-*]\\)\\([[:space:]]\\+\\)\\)\\?\\(\\(\\[[ x]\\+\\]\\)\\([[:space:]]*\\)\\)\\?\\([^[:space:]].*$\\)\\?"
  )
  local o_cmd = above and "normal! O" or "normal! o"
  local is_trailing_cursor = cursor[5] > vim.fn.strchars(line)

  local prefix_space = m[2]
  local list_char = m[4]
  local infix_space = m[5]
  local checkbox = m[7]
  local actual_content = m[9]
  local is_checklist = checkbox ~= nil and checkbox ~= ""
  local is_list = list_char ~= nil and list_char ~= ""

  -- §69/§70: completely blank line
  if #line == 0 then
    if mode == "n" then
      vim.cmd(o_cmd)
    elseif above then
      vim.fn.append(line_nr - 1, "")
    else
      vim.fn.append(line_nr, "")
      cursor[2] = cursor[2] + 1
      vim.fn.setpos(".", cursor)
    end
    return
  end

  -- §70: list indicator but no content — de-indent / blank out, stay put
  if actual_content == nil or actual_content == "" then
    local new_line
    if prefix_space ~= "" then
      new_line = line:sub(3)
    elseif is_list then
      new_line = " " .. line:sub(2)
    else
      new_line = ""
    end
    vim.fn.setline(".", new_line)
    vim.cmd("startinsert")
    return
  end

  local marker = get_line_start(prefix_space, list_char, infix_space, is_checklist)
  local this_text, next_text, new_pos, append

  if is_trailing_cursor or mode == "n" then
    -- §71
    if str.endswith(vim.bo.ft, ".todo") then
      this_text = line
      next_text = ('%s {"created": "%s"}'):format(marker, os.date("%F"))
      new_pos = #marker + 1
      append = false
    else
      this_text = line
      next_text = continue_paragraph and pad(#marker) or marker
      new_pos = #next_text
      append = true
    end
  else
    -- §72: break mid-content
    local marker_len
    if pos == 1 then
      this_text = ""
      marker_len = 0
    else
      this_text = line:sub(1, pos - 1)
      marker_len = #marker
    end
    local start_pos = math.max(0, pos - 1)
    next_text = pad(marker_len, line:sub(start_pos + 1))
    if is_list and vim.g.awiwi_jump_to_end then
      new_pos = #next_text + 1
    else
      new_pos = marker_len + 1
    end
    append = false
  end

  if this_text ~= line then
    vim.fn.setline(".", this_text)
  end
  cursor[3] = new_pos
  if above then
    vim.fn.append(line_nr - 1, next_text)
  else
    cursor[2] = cursor[2] + 1
    vim.fn.append(line_nr, next_text)
  end
  vim.fn.setpos(".", cursor)
  if append then
    vim.cmd("startinsert!")
  else
    vim.cmd("startinsert")
  end
end

function M.handle_enter()
  if vim.fn.mode() ~= "n" then
    vim.cmd("stopinsert")
  end
  local line = vim.fn.getline(".")
  local pos = vim.fn.matchend(line, "^[[:space:]]*[-*][[:space:]]\\+\\[[ x]\\(\\]\\)\\@=")
  if pos == -1 then
    local m = vim.fn.matchstr(line, "^[[:space:]]*[-*][[:space:]]\\+")
    if m == "" then
      -- §73: not a bullet — plain <CR> fall-through (no buffer change).
      return
    end
    vim.cmd("startinsert!")
    return
  end

  local ch = line:sub(pos, pos)
  local cursor = vim.fn.getcurpos()
  local is_open = ch == " "
  local due_markers = markers.get_markers("due", { join = false, escape_mode = "vim" })
  local ms = table.concat(due_markers, "\\|")
  local pattern = ("\\(\\(%s\\)\\([[:space:]]\\+[[:digit:]-.:]\\+\\)\\{0,2}\\|(\\?\\(%s\\)\\([[:space:]]\\+[^[:space:])]\\+\\)*)\\?\\)"):format(
    ms,
    ms
  )
  local anti_pattern = "\\~\\~" .. pattern .. "\\~\\~"
  local due_pos
  local new_char
  if is_open then
    new_char = "x"
    local mm = vim.fn.matchstrpos(line, pattern)
    if mm[2] ~= -1 and line:sub(mm[2], mm[2]) ~= "~" then
      due_pos = { mm[2], mm[3] }
    end
  else
    new_char = " "
    local mm = vim.fn.matchstrpos(line, anti_pattern)
    if mm[2] ~= -1 then
      due_pos = { mm[2], mm[3] }
    end
  end

  local new_line = line:sub(1, pos - 1) .. new_char .. line:sub(pos + 1)
  if due_pos then
    local s, e = due_pos[1], due_pos[2]
    if is_open then
      new_line = new_line:sub(1, s) .. "~~" .. new_line:sub(s + 1, e) .. "~~" .. new_line:sub(e + 1)
      if cursor[3] >= e then
        cursor[3] = cursor[3] + 4
      elseif cursor[3] >= s then
        cursor[3] = cursor[3] + 2
      end
    else
      new_line = new_line:sub(1, s) .. new_line:sub(s + 3, e - 2) .. new_line:sub(e + 1)
      if cursor[3] >= e then
        cursor[3] = cursor[3] - 4
      elseif cursor[3] >= s then
        cursor[3] = cursor[3] - 2
      end
    end
  end
  vim.fn.setline(cursor[2], new_line)
  vim.fn.setpos(".", cursor)
  vim.cmd("silent w")
  vim.cmd("normal! j")
end

function M.append_to_line()
  local line = vim.fn.getline(".")
  local meta, start = hi.get_meta_and_pos(line)
  if vim.tbl_isempty(meta) then
    -- §78: no meta blob → plain append at end of line.
    vim.cmd("startinsert!")
    return
  end
  local cursor = vim.fn.getcurpos()
  if start > 0 and line:sub(start, start) ~= " " then
    line = line:sub(1, start) .. " " .. line:sub(start + 1)
    vim.fn.setline(cursor[2], line)
    start = start + 1
  end
  cursor[3] = start
  vim.fn.setpos(".", cursor)
  vim.cmd("startinsert")
end

--- `<C-x>`/`<C-v>` cmdline guard (§79): suppress the split flag on `:Awiwi`
--- commands. The vimscript checked `match(...) == 1`, which never fires (a
--- match at string start returns 0) — corrected per D12.
function M._split_screen_result(cmdtype, cmdline, direction)
  if cmdtype ~= ":" then
    return ""
  end
  local words = vim.split(vim.trim(cmdline), "%s+")
  if vim.fn.match(words[1] or "", "^Aw\\%[iwi]$") == 0 then
    return ""
  end
  return direction == "h" and " +hnew" or " +vnew"
end

function M.split_screen(direction)
  return M._split_screen_result(vim.fn.getcmdtype(), vim.fn.getcmdline(), direction)
end

--- §84 (B6 fix): scan every buffer line last→first (inclusive), delete lines
--- with a >15-day-old `{...created...}` blob; skip `* [ ]` open checkboxes and
--- blob-less lines. Pure Lua, no Python; no off-by-one, no phantom line 0.
function M.delete_old_tasks(bufnr)
  bufnr = bufnr or 0
  local today = date.get_today()
  local n = vim.api.nvim_buf_line_count(bufnr)
  for lnum = n, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
    if not vim.startswith(line, "* [ ]") then
      local blob = line:match("({[^}]+})$")
      if blob then
        local ok, meta = pcall(vim.json.decode, blob)
        if ok and type(meta) == "table" and meta.created then
          local okd, diff = pcall(date.diff_days, today, meta.created)
          if okd and diff > 15 then
            vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, {})
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Wiring: rebind cmd's T10 injection points + asset's opener to this façade.
-- ---------------------------------------------------------------------------

local cmd = require("awiwi.cmd")
cmd.deps.get_journal_subpath = M.get_journal_subpath
cmd.deps.get_asset_subpath = M.get_asset_subpath
cmd.deps.get_recipe_subpath = M.get_recipe_subpath
cmd.deps.get_journal_file_by_date = M.get_journal_file_by_date
cmd.deps.get_all_journal_files = M.get_all_journal_files
cmd.deps.insert_journal_link = M.insert_journal_link
cmd.deps.edit_journal = M.edit_journal
cmd.deps.insert_and_open_continuation = M.insert_and_open_continuation
cmd.deps.activate_current_task = M.activate_current_task
cmd.deps.deactivate_active_task = M.deactivate_active_task
cmd.deps.copy_file = M.copy_file
cmd.deps.insert_recipe_link = M.insert_recipe_link
cmd.deps.open_file = M.open_file
cmd.deps.fuzzy_search = M.fuzzy_search
cmd.deps.redact = M.redact
cmd.deps.edit_meta_info = M.edit_meta_info
cmd.deps.edit_todo = M.edit_todo
cmd.deps.show_toc_in_qlist = M.show_toc_in_qlist

-- date's prev/next resolution needs the real journal-file-date list
-- (T10.1 dogfood fix — the seam existed but was never wired, so
-- `:Awiwi journal previous`/`next` threw AwiwiDateError).
date.deps.journal_dates = M.get_all_journal_files

-- asset's opener default is a bare `:edit`; give it the real façade opener so
-- opening assets honors splits/anchors/xdg extensions.
asset.deps.open_file = M.open_file

-- server.config.get_markers defaulted to the now-deleted VimL `awiwi#get_markers`
-- (server.md gotcha) — point it at the ported markers module. join=false
-- matches the legacy writer: config.json carries marker *lists*, not the
-- pipe-joined strings get_markers defaults to (B14, found in S17.3 dogfood).
local server = require("awiwi.server")
server.config.get_markers = function(marker)
  return markers.get_markers(marker, { join = false })
end

-- Bootstrap on load (no-op if g:awiwi_home is unset).
if vim.g.awiwi_home and vim.g.awiwi_home ~= "" then
  pcall(M.bootstrap)
end

return M
