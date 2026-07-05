local hi = require("awiwi.hi")
local date = require("awiwi.date")

-- Test isolation helpers ----------------------------------------------------

--- Runs `fn(buf)` with a fresh scratch buffer as the current buffer,
--- restoring the previous window/buffer afterward.
local function with_scratch_buffer(lines, fn, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, opts.scratch ~= false)
  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  local prev_win = vim.api.nvim_get_current_win()
  local prev_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(buf)
  local ok, err = pcall(fn, buf)
  pcall(vim.api.nvim_set_current_win, prev_win)
  pcall(vim.api.nvim_win_set_buf, prev_win, prev_buf)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  if not ok then
    error(err, 0)
  end
end

--- Runs `fn(home)` with `vim.g.awiwi_home` pointed at a fresh scratch
--- tempdir, restoring the previous global afterward.
local function with_home(fn)
  local home = vim.fn.tempname()
  vim.fn.mkdir(home, "p")
  local saved = vim.g.awiwi_home
  vim.g.awiwi_home = home
  local ok, err = pcall(fn, home)
  vim.g.awiwi_home = saved
  if not ok then
    error(err, 0)
  end
end

local function extmarks(bufnr, ns)
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

-- awiwi.hi.get_meta_and_pos ---------------------------------------------

describe("hi.get_meta_and_pos", function()
  it("matches an unchecked checklist line with a trailing JSON blob", function()
    local line = '* [ ] buy milk {"due":"2026-07-06"}'
    local meta, s, e = hi.get_meta_and_pos(line)
    eq({ due = "2026-07-06" }, meta)
    local expect_s, expect_e = line:find("{[^{]+}$")
    eq(expect_s - 1, s)
    eq(expect_e, e)
  end)

  it("does not match a checked box", function()
    local meta, s, e = hi.get_meta_and_pos('* [x] buy milk {"due":"2026-07-06"}')
    eq({}, meta)
    eq(-1, s)
    eq(-1, e)
  end)

  it("does not match a wrong bullet character", function()
    local meta, s, e = hi.get_meta_and_pos('- [ ] buy milk {"due":"2026-07-06"}')
    eq({}, meta)
    eq(-1, s)
    eq(-1, e)
  end)

  it("does not match with trailing whitespace after the blob", function()
    local meta = hi.get_meta_and_pos('* [ ] buy milk {"due":"2026-07-06"} ')
    eq({}, meta)
  end)

  it("does not match an empty {} blob (hi-2 preserved)", function()
    local meta = hi.get_meta_and_pos("* [ ] buy milk {}")
    eq({}, meta)
  end)

  it("swallows JSON decode failure", function()
    local meta, s, e = hi.get_meta_and_pos("* [ ] buy milk {not json}")
    eq({}, meta)
    eq(-1, s)
    eq(-1, e)
  end)

  it("does not match plain prose with no checklist marker", function()
    local meta = hi.get_meta_and_pos("just prose, no checklist")
    eq({}, meta)
  end)
end)

-- format_days, exercised through draw_due_dates' visible badge --------------

describe("hi.draw_due_dates badge formatting", function()
  local function due_badge(offset_days)
    local t = os.date("*t")
    local due = os.date(
      "%Y-%m-%d",
      os.time({ year = t.year, month = t.month, day = t.day + offset_days, hour = 12 })
    )
    local result
    with_scratch_buffer({ string.format('* [ ] task {"due":"%s"}', due) }, function(buf)
      hi.draw_due_dates()
      local marks = extmarks(buf, hi.ns_todo_dates)
      eq(1, #marks)
      result = marks[1][4].virt_text[1]
    end)
    return result
  end

  it("days == 0 -> TODAY / awiwiUrgent", function()
    eq({ "TODAY", "awiwiUrgent" }, due_badge(0))
  end)

  it("days == -3 -> [ 3d ago ] / awiwiUrgent", function()
    eq({ "[ 3d ago ]", "awiwiUrgent" }, due_badge(-3))
  end)

  it("days == -10 -> [ 1w, 3d ago ] / awiwiUrgent", function()
    eq({ "[ 1w, 3d ago ]", "awiwiUrgent" }, due_badge(-10))
  end)

  it("days == -14 -> [ 2w ago ] / awiwiUrgent", function()
    eq({ "[ 2w ago ]", "awiwiUrgent" }, due_badge(-14))
  end)

  it("days == 3 -> [ in 3d ] / awiwiNearDueDate", function()
    eq({ "[ in 3d ]", "awiwiNearDueDate" }, due_badge(3))
  end)

  it("days == 10 -> [ in 1w, 3d ] / awiwiFutureDueDate", function()
    eq({ "[ in 1w, 3d ]", "awiwiFutureDueDate" }, due_badge(10))
  end)

  it("days == 14 -> [ in 2w ] / awiwiFutureDueDate", function()
    eq({ "[ in 2w ]", "awiwiFutureDueDate" }, due_badge(14))
  end)
end)

-- awiwi.hi.draw_due_dates (integration) --------------------------------

describe("hi.draw_due_dates", function()
  it("sets a badge for a 'created' meta line, verbatim text", function()
    with_scratch_buffer({ '* [ ] task {"created":"2026-01-01"}' }, function(buf)
      hi.draw_due_dates()
      local marks = extmarks(buf, hi.ns_todo_dates)
      eq(1, #marks)
      eq({ { "2026-01-01", "awiwiCreatedDate" } }, marks[1][4].virt_text)
    end)
  end)

  it("sets an extmark with no visible content for meta with neither due nor created", function()
    with_scratch_buffer({ '* [ ] task {"foo":"bar"}' }, function(buf)
      hi.draw_due_dates()
      local marks = extmarks(buf, hi.ns_todo_dates)
      eq(1, #marks)
      -- an empty virt_text chunk list renders nothing; nvim doesn't surface
      -- an empty list back out of extmark details, only its absence
      eq(nil, marks[1][4].virt_text)
    end)
  end)

  it("sets no extmark on a non-checklist line", function()
    with_scratch_buffer({ "not a checklist item" }, function(buf)
      hi.draw_due_dates()
      eq(0, #extmarks(buf, hi.ns_todo_dates))
    end)
  end)

  it("replaces the badge with 'bad meta info: ...' (awiwiUrgent) when due-date computation throws", function()
    with_scratch_buffer({ '* [ ] task {"due":"not-a-date"}' }, function(buf)
      hi.draw_due_dates()
      local marks = extmarks(buf, hi.ns_todo_dates)
      eq(1, #marks)
      local chunk = marks[1][4].virt_text[1]
      eq("awiwiUrgent", chunk[2])
      ok(chunk[1]:match("^bad meta info: "), chunk[1])
    end)
  end)

  it("hi-3 fix: an unrelated exception on one line doesn't abort the whole redraw", function()
    with_scratch_buffer({
      '* [ ] good {"created":"2026-01-01"}',
      '* [ ] boom {"created":"2026-02-02"}',
      '* [ ] good2 {"created":"2026-03-03"}',
    }, function(buf)
      local orig = hi.get_meta_and_pos
      hi.get_meta_and_pos = function(line)
        if line:find("boom", 1, true) then
          error("simulated unrelated exception")
        end
        return orig(line)
      end

      local ok_, err = pcall(hi.draw_due_dates)
      hi.get_meta_and_pos = orig

      ok(ok_, "draw_due_dates should not propagate a single line's exception: " .. tostring(err))

      local marks = extmarks(buf, hi.ns_todo_dates)
      local rows = {}
      for _, m in ipairs(marks) do
        rows[m[2]] = true
      end
      ok(rows[0], "expected badge on line 0")
      ok(rows[2], "expected badge on line 2")
      ok(not rows[1], "expected no badge on the throwing line")
    end)
  end)
end)

-- awiwi.hi.clear_due_dates / redraw_due_dates ----------------------------

describe("hi.clear_due_dates", function()
  it("removes every extmark in the due-date namespace", function()
    with_scratch_buffer({ '* [ ] task {"created":"2026-01-01"}' }, function(buf)
      hi.draw_due_dates()
      ok(#extmarks(buf, hi.ns_todo_dates) > 0, "expected at least one extmark before clear")
      hi.clear_due_dates()
      eq(0, #extmarks(buf, hi.ns_todo_dates))
    end)
  end)
end)

describe("hi.redraw_due_dates", function()
  it("is a no-op when unmodified and w:last_redraw is newer than file mtime", function()
    with_scratch_buffer({ '* [ ] task {"created":"2026-01-01"}' }, function(buf)
      local calls = 0
      local orig = hi.draw_due_dates
      hi.draw_due_dates = function(...)
        calls = calls + 1
        return orig(...)
      end

      vim.w.last_redraw = os.time() + 100000 -- far in the future, definitely > mtime
      vim.bo[buf].modified = false

      hi.redraw_due_dates(false)

      hi.draw_due_dates = orig
      eq(0, calls)
    end)
  end)

  it("redraws when force_redraw is true regardless of modified/mtime state", function()
    with_scratch_buffer({ '* [ ] task {"created":"2026-01-01"}' }, function(buf)
      local calls = 0
      local orig = hi.draw_due_dates
      hi.draw_due_dates = function(...)
        calls = calls + 1
        return orig(...)
      end

      vim.w.last_redraw = os.time() + 100000
      vim.bo[buf].modified = false

      hi.redraw_due_dates(true)

      hi.draw_due_dates = orig
      eq(1, calls)
    end)
  end)

  it("redraws when the buffer is modified", function()
    -- scratch buffers (nvim_create_buf(_, true)) can never report 'modified'
    -- (nvim forces it off), so this case needs a plain, non-scratch buffer.
    with_scratch_buffer({ '* [ ] task {"created":"2026-01-01"}' }, function(buf)
      local calls = 0
      local orig = hi.draw_due_dates
      hi.draw_due_dates = function(...)
        calls = calls + 1
        return orig(...)
      end

      vim.w.last_redraw = os.time() + 100000
      vim.bo[buf].modified = true

      hi.redraw_due_dates(false)

      hi.draw_due_dates = orig
      eq(1, calls)
      vim.bo[buf].modified = false
    end, { scratch = false })
  end)

  it("stamps w:last_redraw with current wall-clock time on redraw", function()
    with_scratch_buffer({ '* [ ] task {"created":"2026-01-01"}' }, function()
      vim.w.last_redraw = 0
      local before = os.time()
      hi.redraw_due_dates(true)
      local after = os.time()
      ok(vim.w.last_redraw >= before and vim.w.last_redraw <= after, "expected last_redraw stamped to now")
    end)
  end)
end)

-- awiwi.hi.draw_horizontal_lines (treesitter structural pass, B9) -----------

describe("hi.draw_horizontal_lines", function()
  it("draws a rule on an H1 heading, level<=2 fill char, markdownH1 group", function()
    with_scratch_buffer({ "# H1", "some text" }, function(buf)
      hi.draw_horizontal_lines()
      local marks = extmarks(buf, hi.ns_hlines)
      eq(1, #marks)
      eq(0, marks[1][2]) -- row
      local chunk = marks[1][4].virt_text[1]
      eq("markdownH1", chunk[2])
      ok(chunk[1]:find("━", 1, true) ~= nil, "expected heavy fill char for level<=2")
    end)
  end)

  it("uses the light fill char and markdownH3 group for an H3 heading", function()
    with_scratch_buffer({ "### H3", "text" }, function(buf)
      hi.draw_horizontal_lines()
      local marks = extmarks(buf, hi.ns_hlines)
      eq(1, #marks)
      local chunk = marks[1][4].virt_text[1]
      eq("markdownH3", chunk[2])
      ok(chunk[1]:find("─", 1, true) ~= nil, "expected light fill char for level>2")
      ok(chunk[1]:find("━", 1, true) == nil, "expected no heavy fill char")
    end)
  end)

  it("hi-4 preserved: rule width is byte length, not display width, for multibyte headings", function()
    with_scratch_buffer({ "# héllo" }, function(buf)
      hi.draw_horizontal_lines()
      local width = vim.api.nvim_win_get_width(0)
      local line = "# héllo"
      local marks = extmarks(buf, hi.ns_hlines)
      eq(1, #marks)
      local rule = marks[1][4].virt_text[1][1]
      -- 1 leading space + `rem` copies of the (multi-byte) fill char
      local expect_rem = width - #line - 2
      local _, count = rule:gsub("━", "")
      eq(expect_rem, count)
    end)
  end)

  it("hi-5 moot after B9: 7+ '#' is not an ATX heading under CommonMark, no rule drawn", function()
    with_scratch_buffer({ "####### not really a heading" }, function(buf)
      hi.draw_horizontal_lines()
      eq(0, #extmarks(buf, hi.ns_hlines))
      eq(0, #hi.headings(buf))
    end)
  end)

  it("draws zero rules for a heading-looking line inside a backtick fence", function()
    with_scratch_buffer({ "```", "# not a heading", "```" }, function(buf)
      hi.draw_horizontal_lines()
      eq(0, #extmarks(buf, hi.ns_hlines))
    end)
  end)

  it("B9 regression: draws zero rules inside a ~~~ fence", function()
    with_scratch_buffer({ "~~~", "# not a heading", "~~~" }, function(buf)
      hi.draw_horizontal_lines()
      eq(0, #extmarks(buf, hi.ns_hlines))
    end)
  end)

  it("B9 regression: draws zero rules for an indented code block", function()
    with_scratch_buffer({ "    # not a heading (indented code)" }, function(buf)
      hi.draw_horizontal_lines()
      eq(0, #extmarks(buf, hi.ns_hlines))
    end)
  end)

  it("draws zero rules when rem <= 0 (heading long enough to fill the window)", function()
    -- a sole window in a tabpage can't be shrunk via nvim_win_set_width (no
    -- neighbor to give the space to), so exercise the rem<=0 branch with a
    -- heading line long enough relative to the window's actual width instead.
    with_scratch_buffer(nil, function(buf)
      local width = vim.api.nvim_win_get_width(0)
      local heading = "# " .. string.rep("x", width - 2)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { heading })
      hi.draw_horizontal_lines()
      eq(0, #extmarks(buf, hi.ns_hlines))
    end)
  end)

  it("clears its own namespace on every call (no stale rules)", function()
    with_scratch_buffer({ "# H1" }, function(buf)
      hi.draw_horizontal_lines()
      eq(1, #extmarks(buf, hi.ns_hlines))
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "no heading here" })
      hi.draw_horizontal_lines()
      eq(0, #extmarks(buf, hi.ns_hlines))
    end)
  end)
end)

-- structural pass API (M.headings / M.code_line_mask), for T6b reuse --------

describe("hi.headings / hi.code_line_mask (structural pass)", function()
  it("headings: one entry per atx_heading, in document order, with level", function()
    with_scratch_buffer({ "# H1", "text", "## H2" }, function(buf)
      local headings = hi.headings(buf)
      eq(2, #headings)
      eq(0, headings[1].lnum)
      eq(1, headings[1].level)
      eq(2, headings[2].lnum)
      eq(2, headings[2].level)
    end)
  end)

  it("code_line_mask covers fenced (backtick), fenced (~~~) and indented blocks, delimiters included", function()
    with_scratch_buffer({
      "```",
      "code",
      "```",
      "~~~",
      "code2",
      "~~~",
      "    indented code",
    }, function(buf)
      local mask = hi.code_line_mask(buf)
      for i = 0, 2 do
        ok(mask[i], "expected line " .. i .. " masked (backtick fence)")
      end
      for i = 3, 5 do
        ok(mask[i], "expected line " .. i .. " masked (tilde fence)")
      end
      ok(mask[6], "expected indented code line masked")
    end)
  end)
end)

-- title helpers -----------------------------------------------------------

describe("hi.get_recipe_title", function()
  it("relativizes against the recipe subpath and strips a .md suffix", function()
    with_home(function(home)
      local subpath = home .. "/recipes"
      local saved_fn = vim.fn["awiwi#get_recipe_subpath"]
      vim.fn["awiwi#get_recipe_subpath"] = function()
        return subpath
      end

      with_scratch_buffer(nil, function(buf)
        vim.api.nvim_buf_set_name(buf, subpath .. "/cooking/pasta.md")
        eq("cooking/pasta", hi.get_recipe_title())
      end)

      vim.fn["awiwi#get_recipe_subpath"] = saved_fn
    end)
  end)
end)

describe("hi.get_asset_title", function()
  it("formats 'name [yyyy-mm-dd]' from the last 4 path components", function()
    with_scratch_buffer(nil, function(buf)
      vim.api.nvim_buf_set_name(buf, "/whatever/assets/2026/07/05/my-note.md")
      eq("my-note [2026-07-05]", hi.get_asset_title())
    end)
  end)

  it("keeps a non-.md asset filename whole", function()
    with_scratch_buffer(nil, function(buf)
      vim.api.nvim_buf_set_name(buf, "/whatever/assets/2026/07/05/photo.png")
      eq("photo.png [2026-07-05]", hi.get_asset_title())
    end)
  end)
end)

describe("hi.get_journal_title", function()
  it("delegates to date.to_nice_date(date.get_own_date())", function()
    with_scratch_buffer(nil, function(buf)
      vim.api.nvim_buf_set_name(buf, "/whatever/journal/2026/07/2026-07-05.md")
      eq(date.to_nice_date("2026-07-05"), hi.get_journal_title())
    end)
  end)
end)
