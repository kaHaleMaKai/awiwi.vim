-- Buffer-local visual decoration for awiwi markdown buffers: due/created-date
-- end-of-line badges on unchecked todo checklist lines, a horizontal-rule
-- extension after ATX heading lines, and three pure title-string helpers
-- consumed by the optional `entitlement.nvim` integration.
--
-- No persistence, no network, no shelling out. See handovers/lua-port/hi.md
-- for the full behavior contract and the vimscript bugs fixed/preserved in
-- this port (B9, hi-1..hi-5).

local date = require("awiwi.date")
local path = require("awiwi.path")
local str = require("awiwi.str")

local M = {}

-- Namespaces: names preserved byte-identical to the vimscript original (kept
-- separate per concern -- clearing due-date badges must never touch header
-- rules and vice versa).
local ns_todo_dates = vim.api.nvim_create_namespace("awiwi-todo-dates")
local ns_hlines = vim.api.nvim_create_namespace("awiwi-horizontal-lines")

M.ns_todo_dates = ns_todo_dates
M.ns_hlines = ns_hlines

-- Due-date/created-date badges -----------------------------------------

--- `s:format_days` port: format a signed day-count into a `{text, hl_group}`
--- virtual-text chunk. `days == 0` -> "TODAY"; overdue (`days < 0`) is always
--- `awiwiUrgent` regardless of magnitude; future (`days > 0`) is
--- `awiwiFutureDueDate` at >=1 week out, else `awiwiNearDueDate`.
local function format_days(days)
  if days == 0 then
    return { "TODAY", "awiwiUrgent" }
  end

  local n = math.abs(days)
  local w = math.floor(n / 7)
  local d = n % 7
  local message
  if w > 0 and d > 0 then
    message = string.format("%dw, %dd", w, d)
  elseif w > 0 then
    message = string.format("%dw", w)
  else
    message = string.format("%dd", d)
  end

  if days < 0 then
    return { string.format("[ %s ago ]", message), "awiwiUrgent" }
  end
  return { string.format("[ in %s ]", message), w > 0 and "awiwiFutureDueDate" or "awiwiNearDueDate" }
end

--- Match an *unchecked* `*`-bulleted checklist line and its trailing
--- `{...}` JSON blob (>=1 byte inside, anchored to end-of-line -- no
--- trailing whitespace tolerated, hi-2 preserved). Returns
--- `blob, start1, end1` (1-indexed, `string.find`-shaped) or `nil` if either
--- condition fails.
local function match_checklist_blob(line)
  if not line:match("^%s*%* %[ %] ") then
    return nil, nil, nil
  end
  local s, e = line:find("{[^{]+}$")
  if not s then
    return nil, nil, nil
  end
  return line:sub(s, e), s, e
end

--- `awiwi#hi#get_meta_and_pos` port. Returns `meta, start0, end0` where
--- `start0`/`end0` are 0-indexed byte offsets of the matched `{...}` blob
--- (`start0` = offset of `{`, `end0` = offset just past `}`). On no-match or
--- JSON-decode failure (the *only* decode-error case handled, mirroring the
--- vimscript `catch /E474/`), returns `{}, -1, -1`.
function M.get_meta_and_pos(line)
  local blob, s, e = match_checklist_blob(line)
  if not blob then
    return {}, -1, -1
  end
  local ok, decoded = pcall(vim.json.decode, blob)
  if not ok then
    return {}, -1, -1
  end
  return decoded, s - 1, e
end

--- `awiwi#hi#draw_due_dates` port. hi-1 fix: day-diff via
--- `require('awiwi.date').diff_days` (pure calendar math, no `os.time`
--- `luaeval` hack, no DST/timezone dependence). hi-3 fix: the whole per-line
--- body is wrapped in `pcall` so one malformed line can't abort the redraw
--- for the rest of the buffer.
function M.draw_due_dates()
  local today = date.get_today()
  local nlines = vim.api.nvim_buf_line_count(0)
  for lnum0 = 0, nlines - 1 do
    pcall(function()
      local line = vim.api.nvim_buf_get_lines(0, lnum0, lnum0 + 1, false)[1] or ""
      local meta = M.get_meta_and_pos(line)
      if next(meta) == nil then
        return
      end

      local text
      if meta.due ~= nil then
        local ok2, chunk = pcall(function()
          return format_days(date.diff_days(meta.due, today))
        end)
        if ok2 then
          text = { chunk }
        else
          text = { { "bad meta info: " .. tostring(chunk), "awiwiUrgent" } }
        end
      elseif meta.created ~= nil then
        text = { { meta.created, "awiwiCreatedDate" } }
      else
        text = {}
      end

      vim.api.nvim_buf_set_extmark(0, ns_todo_dates, lnum0, 0, {
        virt_text = text,
        virt_text_pos = "eol",
      })
    end)
  end
end

--- `awiwi#hi#clear_due_dates` port: unconditionally clear the whole buffer's
--- extmarks in the due-date namespace.
function M.clear_due_dates()
  vim.api.nvim_buf_clear_namespace(0, ns_todo_dates, 0, -1)
end

--- `awiwi#hi#redraw_due_dates` port. Debounced clear+redraw: runs iff
--- `force_redraw`, or the buffer is `&modified`, or the per-window
--- `w:last_redraw` cache (0 if unset) is older than the file's on-disk
--- mtime. On redraw, stamps `w:last_redraw` with the current wall-clock time
--- (not the file's mtime).
function M.redraw_due_dates(force_redraw)
  force_redraw = force_redraw or false
  local last_redraw = vim.w.last_redraw or 0
  local mtime = vim.fn.getftime(vim.fn.expand("%:p"))
  if force_redraw or vim.bo.modified or last_redraw < mtime then
    M.clear_due_dates()
    M.draw_due_dates()
    vim.w.last_redraw = os.time()
  end
end

-- Header rules ------------------------------------------------------------

-- Cache the compiled treesitter query -- static string, safe to parse once.
local structural_query

local function get_structural_query()
  if not structural_query then
    structural_query = vim.treesitter.query.parse("markdown", [[
      (atx_heading) @heading
      (fenced_code_block) @code
      (indented_code_block) @code
    ]])
  end
  return structural_query
end

--- B9 structural pass (treesitter, replaces the manual backtick-only fence
--- toggle): parse `bufnr` with nvim's bundled `markdown` parser and return
--- the parsed tree's root plus the compiled query, or `nil, nil` if the
--- buffer can't be parsed (defensive -- should not happen for `filetype =
--- markdown`/`awiwi` buffers, but never throws).
local function parse_structure(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return nil
  end
  local ok2, trees = pcall(function()
    return parser:parse()
  end)
  if not ok2 or not trees or not trees[1] then
    return nil
  end
  return trees[1]:root()
end

--- `M.headings(bufnr) -> { {lnum, level, text}, ... }`, one entry per
--- `atx_heading` node in document order (`lnum` 0-indexed). `level` is
--- 1..6 (the grammar itself caps ATX headings at 6 `#` -- 7+ `#` is not
--- parsed as a heading at all, see hi-5 note in the module handover).
--- `text` is the heading's inline content, or `nil` for an empty heading.
--- Exposed for T6b (`syn`) reuse, per the brief's structural-pass API.
function M.headings(bufnr)
  bufnr = bufnr or 0
  local root = parse_structure(bufnr)
  if not root then
    return {}
  end

  local headings = {}
  local query = get_structural_query()
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "heading" then
      local level, text
      for child, field in node:iter_children() do
        local lvl = child:type():match("^atx_h(%d)_marker$")
        if lvl then
          level = tonumber(lvl)
        end
        if field == "heading_content" then
          text = vim.treesitter.get_node_text(child, bufnr)
        end
      end
      local lnum = node:range()
      headings[#headings + 1] = { lnum = lnum, level = level, text = text }
    end
  end
  table.sort(headings, function(a, b)
    return a.lnum < b.lnum
  end)
  return headings
end

--- `M.code_line_mask(bufnr) -> { [0-indexed lnum] = true, ... }` covering
--- every line inside a `fenced_code_block` (both `` ``` `` and `~~~`
--- delimiters -- same grammar node) or `indented_code_block` node,
--- including the delimiter lines themselves (matching the old
--- skip-fence-lines behavior). This closes B9: the old regex scanner only
--- recognized backtick fences and had no concept of indented code blocks.
--- Exposed for T6b (`syn`) reuse.
function M.code_line_mask(bufnr)
  bufnr = bufnr or 0
  local mask = {}
  local root = parse_structure(bufnr)
  if not root then
    return mask
  end

  local query = get_structural_query()
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "code" then
      local srow, _, erow = node:range()
      for row = srow, erow - 1 do
        mask[row] = true
      end
    end
  end
  return mask
end

--- `awiwi#hi#draw_horizontal_lines` port. Clears the header-rule namespace
--- for the whole buffer, then draws one end-of-line rule per ATX heading not
--- masked as inside a code block. hi-4 preserved: rule width uses byte
--- length (`#line`), not display width. hi-5: moot after the B9 treesitter
--- switch -- the grammar itself never parses 7+ `#` as a heading, so there's
--- no out-of-range `level` to clamp.
function M.draw_horizontal_lines()
  vim.api.nvim_buf_clear_namespace(0, ns_hlines, 0, -1)
  local width = vim.api.nvim_win_get_width(0)
  local mask = M.code_line_mask(0)

  for _, h in ipairs(M.headings(0)) do
    if not mask[h.lnum] then
      local line = vim.api.nvim_buf_get_lines(0, h.lnum, h.lnum + 1, false)[1] or ""
      local rem = width - #line - 2
      if rem > 0 then
        local level = h.level or 1
        local fillchar = level <= 2 and "━" or "─"
        local hline = " " .. fillchar:rep(rem)
        local hlgroup = string.format("markdownH%d", level)
        vim.api.nvim_buf_set_extmark(0, ns_hlines, h.lnum, 0, {
          virt_text = { { hline, hlgroup } },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

-- Title helpers -------------------------------------------------------------

--- `awiwi#hi#get_recipe_title` port. COORD-1: calls the (already fixed)
--- `path.relativize` directly -- does NOT replicate the vimscript
--- workaround (hi.vim:129-130) that manually stripped a spurious leading
--- path component to compensate for the old buggy `relativize`; doing so on
--- top of the fixed function would double-cancel and silently eat one path
--- component too many. `awiwi#get_recipe_subpath()` is a T10 façade
--- dependency (not yet ported) -- called via vimscript interop.
function M.get_recipe_title()
  local file = vim.fn.expand("%:p")
  local subpath = vim.fn["awiwi#get_recipe_subpath"]()
  local rel = path.relativize(file, subpath)
  return rel:sub(1, -4)
end

--- `awiwi#hi#get_asset_title` port: last 4 path components are
--- `[year, month, day, filename]` (fixed `assets/{y}/{m}/{d}/{name}.md`
--- layout); joins the first 3 with `-`, strips a `.md` suffix from the
--- filename only if present.
function M.get_asset_title()
  local file = vim.fn.expand("%:p")
  local parts = path.split(file)
  local n = #parts
  local year, month, day, name = parts[n - 3], parts[n - 2], parts[n - 1], parts[n]
  if str.endswith(name, ".md") then
    name = name:sub(1, -4)
  end
  local datestr = table.concat({ year, month, day }, "-")
  return string.format("%s [%s]", name, datestr)
end

--- `awiwi#hi#get_journal_title` port: pure delegate, no logic of its own.
function M.get_journal_title()
  return date.to_nice_date(date.get_own_date())
end

return M
