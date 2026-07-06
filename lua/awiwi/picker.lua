-- The single UI seam for every picker cmd.lua needs. cmd.lua must NEVER call
-- fzf#run/fzf#vim#* or telescope directly — it hands items/prompt/on_choice to
-- one of the three functions here and this module chooses a backend.
--
-- Backend selection (orchestrator ADR):
--   * Default: the always-available `vim.ui.select` (no plugin dependency;
--     headless-testable by stubbing `deps.ui_select`). UX-degraded for file
--     pickers (no recursive fuzzy path finder — a flat glob + select) and for
--     live-grep pickers (no live-reload — rg is run ONCE via `vim.system` and
--     the materialized result list is handed to the list picker), but correct.
--   * Auto-upgrade: if `require('telescope.*')` succeeds at call time, a
--     telescope-backed list picker is built instead. The telescope modules are
--     loaded through `deps.require` so specs can inject a fake telescope and
--     smoke-test the construction path without the real plugin installed.
--
-- Picker taxonomy (per picker.md's own doc note):
--   * list pickers  — M.select (fixed in-memory item list; P2, P4-fixed)
--   * file pickers  — M.files  (directory-scoped file list; P1, P3)
--   * live-grep     — M.grep   (materialize-then-pick; P5, entries C32)

local pathlib = require("awiwi.path")

local M = {}

--- Overridable dependencies (mockable in tests). `require` is the single seam
--- through which telescope modules are loaded — a fake telescope injected here
--- exercises the telescope construction path with no real plugin present.
M.deps = {
  require = require,
  ui_select = function(items, opts, on_choice)
    vim.ui.select(items, opts, on_choice)
  end,
  system = function(cmd, opts)
    return vim.system(cmd, opts)
  end,
}

--- Strip SGR ANSI color escapes (rg `--color=always` output).
local function strip_ansi(s)
  return (s:gsub("\27%[[0-9;]*m", ""))
end

--- Load telescope's picker/finder/config/actions modules through `deps.require`,
--- returning nil if telescope is not available (any module missing).
local function load_telescope()
  local req = M.deps.require
  local ok, pickers = pcall(req, "telescope.pickers")
  if not ok then
    return nil
  end
  local ok2, finders = pcall(req, "telescope.finders")
  local ok3, conf_mod = pcall(req, "telescope.config")
  local ok4, actions = pcall(req, "telescope.actions")
  local ok5, action_state = pcall(req, "telescope.actions.state")
  if not (ok2 and ok3 and ok4 and ok5) then
    return nil
  end
  return {
    pickers = pickers,
    finders = finders,
    conf = conf_mod.values,
    actions = actions,
    action_state = action_state,
  }
end

--- Telescope-backed single-select over a materialized `items` list.
local function telescope_select(ts, items, prompt, format_item, on_choice)
  ts.pickers
    .new({}, {
      prompt_title = prompt,
      finder = ts.finders.new_table({
        results = items,
        entry_maker = function(entry)
          local display = format_item(entry)
          return { value = entry, display = display, ordinal = display }
        end,
      }),
      sorter = ts.conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, _map)
        ts.actions.select_default:replace(function()
          ts.actions.close(prompt_bufnr)
          local selection = ts.action_state.get_selected_entry()
          if selection ~= nil then
            on_choice(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

--- List picker: pick one of `opts.items`, call `opts.on_choice(item)` (never
--- called on cancel). `opts.format_item` renders each item (default tostring).
--- Uses telescope when available, else `vim.ui.select`.
function M.select(opts)
  opts = opts or {}
  local items = opts.items or {}
  local prompt = opts.prompt or "Select"
  local format_item = opts.format_item or tostring
  local on_choice = opts.on_choice or function() end

  local ts = load_telescope()
  if ts then
    return telescope_select(ts, items, prompt, format_item, on_choice)
  end

  M.deps.ui_select(items, { prompt = prompt, format_item = format_item }, function(choice)
    if choice == nil then
      return
    end
    on_choice(choice)
  end)
end

--- Flat recursive file list under `dir` (readable files only), sorted. This is
--- the degraded stand-in for fzf.vim's own recursive fuzzy file browser.
local function list_files(dir)
  local matches = vim.fn.glob(pathlib.join(dir, "**", "*"), false, true)
  local files = {}
  for _, m in ipairs(matches) do
    if vim.fn.filereadable(m) == 1 then
      files[#files + 1] = m
    end
  end
  table.sort(files)
  return files
end

--- File picker over `opts.dir`. `opts.on_choice(fullpath)` defaults to `:edit`.
--- Items are displayed relative to `dir`, but the FULL path is handed to the
--- sink (callers that want a name relativize it themselves).
function M.files(opts)
  opts = opts or {}
  local dir = opts.dir
  local prompt = opts.prompt or "Files"
  local on_choice = opts.on_choice
    or function(file)
      vim.cmd("edit " .. vim.fn.fnameescape(file))
    end

  M.select({
    items = list_files(dir),
    prompt = prompt,
    format_item = function(f)
      return pathlib.relativize(f, dir)
    end,
    on_choice = on_choice,
  })
end

--- Parse an `rg --column` result line: `file:line:col:text`.
local function parse_grep_line(line)
  local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
  if file then
    return file, tonumber(lnum), tonumber(col), text
  end
  file, lnum, text = line:match("^(.-):(%d+):(.*)$")
  if file then
    return file, tonumber(lnum), 1, text
  end
  return nil
end

--- Default grep sink: jump to the parsed location.
local function default_grep_jump(file, lnum, col)
  if not file then
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, (col or 1) - 1 })
  end
end

--- Live-grep picker, materialize-then-pick. Runs `opts.argv` via `vim.system`
--- (optionally piping its stdout through `opts.filter_argv` — the `rg -v` due
--- anti-pattern pass, which must see the raw colored output), strips ANSI,
--- drops empty lines, applies `opts.transform` (if any) per line, then selects.
--- `opts.on_choice(file, lnum, col, text)` defaults to jumping to the location
--- (B2 fix: `entries` gets a real, navigable sink instead of fzf's sinkless
--- `fzf#run`).
function M.grep(opts)
  opts = opts or {}
  local result = M.deps.system(opts.argv, { text = true }):wait()
  local stdout = result.stdout or ""

  if opts.filter_argv then
    local filtered = M.deps.system(opts.filter_argv, { text = true, stdin = stdout }):wait()
    stdout = filtered.stdout or ""
  end

  local transform = opts.transform
  local lines = {}
  for _, raw in ipairs(vim.split(stdout, "\n", { plain = true })) do
    local line = strip_ansi(raw)
    if line ~= "" then
      if transform then
        line = transform(line)
      end
      lines[#lines + 1] = line
    end
  end

  local on_choice = opts.on_choice or default_grep_jump
  M.select({
    items = lines,
    prompt = opts.prompt or "grep",
    on_choice = function(line)
      local file, lnum, col, text = parse_grep_line(line)
      on_choice(file, lnum, col, text)
    end,
  })
end

return M
