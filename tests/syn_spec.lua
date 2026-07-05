local syn = require("awiwi.syn")

--- Runs `fn(buf)` with a fresh scratch buffer as the current buffer,
--- restoring the previous window/buffer afterward. Also clears syn's own
--- namespaces before/after so each `it` starts from a clean slate.
local function with_buffer(lines, fn, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = opts.filetype or "markdown"
  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  local prev_win = vim.api.nvim_get_current_win()
  local prev_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(buf)
  if opts.conceallevel then
    vim.wo.conceallevel = opts.conceallevel
  end
  local ok, err = pcall(fn, buf)
  pcall(vim.api.nvim_set_current_win, prev_win)
  pcall(vim.api.nvim_win_set_buf, prev_win, prev_buf)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  if not ok then
    error(err, 0)
  end
end

local function marks(bufnr, ns)
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

--- Finds the (first) extmark in `list` whose hl_group matches `hl`.
local function find_hl(list, hl)
  for _, m in ipairs(list) do
    if m[4].hl_group == hl then
      return m
    end
  end
  return nil
end

local function with_g(overrides, fn)
  -- NOTE: can't use a plain `saved[k] = vim.g[k]` table for restoration --
  -- assigning `nil` never creates a table entry, so `pairs(saved)` would
  -- silently skip (and thus never restore) any key that was unset before
  -- the override. Keep the key list separately.
  local keys, saved = {}, {}
  for k, v in pairs(overrides) do
    keys[#keys + 1] = k
    saved[k] = vim.g[k]
    vim.g[k] = v
  end
  local ok, err = pcall(fn)
  for _, k in ipairs(keys) do
    vim.g[k] = saved[k]
  end
  if not ok then
    error(err, 0)
  end
end

describe("syn.attach structural: list bullets", function()
  it("1. top-level bullet gets awiwiList1 on '- '", function()
    with_buffer({ "- foo" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_structure), "awiwiList1")
      ok(m ~= nil, "expected an awiwiList1 extmark")
      eq(0, m[2]) -- row
      eq(0, m[3]) -- start col
      eq(2, m[4].end_col)
    end)
  end)

  it("2. nested (indented) bullet gets awiwiList2", function()
    with_buffer({ "- top", "  - nested" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_structure), "awiwiList2")
      ok(m ~= nil, "expected an awiwiList2 extmark")
      eq(1, m[2])
      eq(2, m[3])
      eq(4, m[4].end_col)
    end)
  end)

  it("3. open task checkbox gets awiwiTaskListOpen1, no competing awiwiList1 on the same line", function()
    with_buffer({ "- [ ] foo" }, function(buf)
      syn.attach(buf)
      local structure = marks(buf, syn.ns_structure)
      local task = find_hl(structure, "awiwiTaskListOpen1")
      ok(task ~= nil, "expected an awiwiTaskListOpen1 extmark")
      eq(0, task[2])
      eq(0, task[3])
      -- no separate awiwiList1 extmark on the same line (single winning
      -- extmark per bullet, see syn.md Port notes "Priority/ordering")
      for _, m in ipairs(structure) do
        if m[2] == 0 then
          ok(m[4].hl_group ~= "awiwiList1", "did not expect a competing awiwiList1 extmark")
        end
      end
    end)
  end)

  it("nested open task checkbox gets awiwiTaskListOpen2", function()
    with_buffer({ "- top", "  - [ ] nested" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_structure), "awiwiTaskListOpen2")
      ok(m ~= nil, "expected an awiwiTaskListOpen2 extmark")
    end)
  end)

  it("4. canceled (struck-through) list item gets awiwiCanceledList spanning bullet to EOL", function()
    with_buffer({ "- ~~cancelled item~~" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_structure), "awiwiCanceledList")
      ok(m ~= nil, "expected an awiwiCanceledList extmark")
      eq(0, m[3])
      eq(#"- ~~cancelled item~~", m[4].end_col)
      eq("htmlStrike", vim.api.nvim_get_hl(0, { name = "awiwiCanceledList" }).link)
    end)
  end)

  it("completed task checkbox gets awiwiTaskListDone, stripped of trailing {meta}", function()
    with_buffer({ '- [x] done thing {"due":"2026-01-01"}' }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_structure), "awiwiTaskListDone")
      ok(m ~= nil, "expected an awiwiTaskListDone extmark")
      eq(0, m[3])
      -- strike-through stops at "thing", trimming the space(s) before the
      -- trailing {meta} blob too (not just the blob itself).
      eq(#"- [x] done thing", m[4].end_col)
      eq("htmlStrike", vim.api.nvim_get_hl(0, { name = "awiwiTaskListDone" }).link)
    end)
  end)
end)

describe("syn.attach markers: word/whitespace-bounded keywords", function()
  it("5. 'TODO buy milk' highlights TODO only (word-bounded)", function()
    with_buffer({ "TODO buy milk" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiTodo")
      ok(m ~= nil, "expected an awiwiTodo extmark")
      eq(0, m[3])
      eq(4, m[4].end_col)
    end)
  end)

  it("5b. 'TODOING' does not match TODO (boundary check)", function()
    with_buffer({ "TODOING nonsense" }, function(buf)
      syn.attach(buf)
      ok(find_hl(marks(buf, syn.ns_markers), "awiwiTodo") == nil, "expected no awiwiTodo match")
    end)
  end)

  it("6. TODO inside a fenced code block is masked (B10 fix)", function()
    with_buffer({ "```lua", "-- TODO in code", "```" }, function(buf)
      syn.attach(buf)
      ok(find_hl(marks(buf, syn.ns_markers), "awiwiTodo") == nil, "expected no awiwiTodo match inside fence")
      ok(find_hl(marks(buf, syn.ns_structure), "awiwiList1") == nil, "expected no list-marker match inside fence")
    end)
  end)

  it("urgent marker 'FIXME' highlights word-bounded, case-sensitive", function()
    with_buffer({ "FIXME this now" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiUrgent")
      ok(m ~= nil, "expected an awiwiUrgent extmark")
      eq(0, m[3])
      eq(5, m[4].end_col)
    end)
  end)

  it("due marker 'DUE' highlights", function()
    with_buffer({ "DUE tomorrow" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiDue")
      ok(m ~= nil, "expected an awiwiDue extmark")
    end)
  end)

  it("@change/@incident/@issue/@bug highlight as awiwiUrgent-linked groups", function()
    with_buffer({ "@change something", "@incident x", "@issue y", "@bug z" }, function(buf)
      syn.attach(buf)
      local structure = marks(buf, syn.ns_markers)
      ok(find_hl(structure, "awiwiChange") ~= nil, "expected awiwiChange")
      ok(find_hl(structure, "awiwiIncident") ~= nil, "expected awiwiIncident")
      ok(find_hl(structure, "awiwiIssue") ~= nil, "expected awiwiIssue")
      ok(find_hl(structure, "awiwiBug") ~= nil, "expected awiwiBug")
      eq("awiwiUrgent", vim.api.nvim_get_hl(0, { name = "awiwiChange" }).link)
    end)
  end)

  it("delegate '@@jdoe' highlights as awiwiDelegate", function()
    with_buffer({ "ping @@jdoe please" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiDelegate")
      ok(m ~= nil, "expected an awiwiDelegate extmark")
      eq(5, m[3])
      eq(#"ping @@jdoe", m[4].end_col)
    end)
  end)
end)

describe("syn.attach: !!redacted (item 2, unmasked)", function()
  it("7. redacts from the tag to EOL, with tag/cause sub-highlights", function()
    with_buffer({ "!!redacted this is secret" }, function(buf)
      syn.attach(buf)
      local structure = marks(buf, syn.ns_markers)
      local region = find_hl(structure, "awiwiRedacted")
      local tag = find_hl(structure, "awiwiRedactedTag")
      local cause = find_hl(structure, "awiwiRedactedCause")
      ok(region ~= nil, "expected awiwiRedacted")
      ok(tag ~= nil, "expected awiwiRedactedTag")
      ok(cause ~= nil, "expected awiwiRedactedCause")
      eq(0, region[3])
      eq(#"!!redacted this is secret", region[4].end_col)
      eq(0, tag[3])
      eq(#"!!redacted", tag[4].end_col)
      eq(#"!!redacted", cause[3])
      eq(#"!!redacted this is secret", cause[4].end_col)
    end)
  end)

  it("fires even inside a fenced code block (no code-mask exclusion, per brief)", function()
    with_buffer({ "```", "!!redacted inside a fence", "```" }, function(buf)
      syn.attach(buf)
      ok(find_hl(marks(buf, syn.ns_markers), "awiwiRedactedTag") ~= nil, "expected redaction inside fence")
    end)
  end)
end)

describe("syn.attach: link concealment and colors", function()
  it("8. internal link: brackets concealed, destination concealed to the internal-target char", function()
    with_buffer({ "[my link](./other.md)" }, function(buf, _)
      vim.wo.conceallevel = 2
      syn.attach(buf)
      local links = marks(buf, syn.ns_links)

      local name_start = find_hl(links, "awiwiLinkNameStart")
      ok(name_start ~= nil)
      eq("▶", name_start[4].conceal)

      local name_end = find_hl(links, "awiwiLinkNameEnd")
      ok(name_end ~= nil)
      eq(" ", name_end[4].conceal) -- B1 fix: end char, not the start char again

      local name = find_hl(links, "awiwiLinkName")
      ok(name ~= nil)
      eq(1, name[3])
      eq(1 + #"my link", name[4].end_col)
      local hl = vim.api.nvim_get_hl(0, { name = "awiwiLinkName" })
      eq("#afaf00", hl.fg and string.format("#%06x", hl.fg) or nil)
      ok(hl.underline == true, "expected underline style")

      -- destination './other.md' is an internal target: concealed whole
      local dest_col = #"[my link]("
      local internal = nil
      for _, m in ipairs(links) do
        if m[3] == dest_col and m[4].conceal == "…" then
          internal = m
        end
      end
      ok(internal ~= nil, "expected the internal target concealed to '…'")
    end)
  end)

  it("9. external link: protocol hidden, domain gray, path concealed", function()
    with_buffer({ "[ext](https://www.example.com/path)" }, function(buf)
      vim.wo.conceallevel = 2
      syn.attach(buf)
      local links = marks(buf, syn.ns_links)

      local protocol = find_hl(links, "awiwiLinkProtocol")
      ok(protocol ~= nil, "expected awiwiLinkProtocol")
      eq("", protocol[4].conceal)

      local domain = find_hl(links, "awiwiLinkDomain")
      ok(domain ~= nil, "expected awiwiLinkDomain")
      eq(nil, domain[4].conceal)
      local hl = vim.api.nvim_get_hl(0, { name = "awiwiLinkDomain" })
      eq("#808080", hl.fg and string.format("#%06x", hl.fg) or nil)

      local path = find_hl(links, "awiwiLinkPath")
      ok(path ~= nil, "expected awiwiLinkPath")
      eq("", path[4].conceal)
    end)
  end)

  it("10. g:awiwi_highlight_links=false: no link/redmine extmarks, attach does not error (B12)", function()
    with_g({ awiwi_highlight_links = false }, function()
      with_buffer({ "[ext](https://example.com)", "see #12345" }, function(buf)
        local attach_ok = pcall(syn.attach, buf)
        ok(attach_ok, "M.attach must not error when awiwi_highlight_links is false")
        eq(0, #marks(buf, syn.ns_links))
        ok(find_hl(marks(buf, syn.ns_markers), "awiwiRedmineIssue") == nil, "expected no redmine extmark either")
      end)
    end)
  end)

  it("g:awiwi_conceal_links=false: no error, colors still applied, nothing concealed", function()
    with_g({ awiwi_conceal_links = false }, function()
      with_buffer({ "[ext](https://www.example.com/path)" }, function(buf)
        local attach_ok = pcall(syn.attach, buf)
        ok(attach_ok, "M.attach must not error when awiwi_conceal_links is false (B2 regression)")
        local links = marks(buf, syn.ns_links)
        local protocol = find_hl(links, "awiwiLinkProtocol")
        ok(protocol ~= nil, "expected awiwiLinkProtocol still colored")
        eq(nil, protocol[4].conceal)
      end)
    end)
  end)
end)

describe("syn.attach: Redmine issue references (item 29)", function()
  it("11. '#12345' (5+ digits, preceded by whitespace) highlights; '#1234' does not", function()
    with_buffer({ "see #12345 and #1234 here" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiRedmineIssue")
      ok(m ~= nil, "expected an awiwiRedmineIssue extmark")
      eq(4, m[3])
      eq(10, m[4].end_col)
      local hl = vim.api.nvim_get_hl(0, { name = "awiwiRedmineIssue" })
      ok(hl.bold == true, "expected bold")
    end)

    with_buffer({ "only #1234 here" }, function(buf)
      syn.attach(buf)
      ok(find_hl(marks(buf, syn.ns_markers), "awiwiRedmineIssue") == nil, "expected no match for 4 digits")
    end)
  end)
end)

describe("syn.attach: modeline block (item 31, unmasked carve-out)", function()
  it("12. 'vim: ft=markdown' inside a fenced code block still highlights", function()
    with_buffer({ "```", "<!-- vim: ft=markdown -->", "```" }, function(buf)
      syn.attach(buf)
      local structure = marks(buf, syn.ns_markers)
      ok(find_hl(structure, "awiwiFileTypePrefix") ~= nil, "expected awiwiFileTypePrefix inside fence")
      ok(find_hl(structure, "awiwiFileType") ~= nil, "expected awiwiFileType inside fence")
    end)
  end)

  it("prefix highlight excludes the leading junk (e.g. '<!-- '); value spans to EOL", function()
    with_buffer({ "<!-- vim: ft=markdown -->" }, function(buf)
      syn.attach(buf)
      local structure = marks(buf, syn.ns_markers)
      local prefix = find_hl(structure, "awiwiFileTypePrefix")
      local value = find_hl(structure, "awiwiFileType")
      -- legacy's `\zs` resets the prefix match to start right after the
      -- leading junk -- only "vim: ft=" itself gets awiwiFileTypePrefix.
      eq(#"<!-- ", prefix[3])
      eq(#"<!-- vim: ft=", prefix[4].end_col)
      eq(#"<!-- vim: ft=", value[3])
      eq(#"<!-- vim: ft=markdown -->", value[4].end_col)
    end)
  end)
end)

describe("syn.setup_highlights: .todo-only groups always defined (item 13)", function()
  it("13. awiwiCreatedDate/awiwiFutureDueDate/awiwiNearDueDate exist after setup", function()
    syn.setup_highlights()
    for _, name in ipairs({ "awiwiCreatedDate", "awiwiFutureDueDate", "awiwiNearDueDate" }) do
      local hl = vim.api.nvim_get_hl(0, { name = name })
      ok(next(hl) ~= nil, "expected " .. name .. " to be defined")
    end
  end)

  it("conceals the trailing {meta} blob on a .todo-filetype checklist line", function()
    with_buffer({ '* [ ] task {"due":"2026-01-01"}' }, function(buf)
      vim.wo.conceallevel = 2
      syn.attach(buf)
      local m = marks(buf, syn.ns_markers)
      local found = false
      for _, mk in ipairs(m) do
        if mk[4].conceal == "" and mk[4].end_col == #'* [ ] task {"due":"2026-01-01"}' then
          found = true
        end
      end
      ok(found, "expected a bare-conceal extmark over the trailing {meta} blob")
      -- NOTE: deliberately not the real "awiwi.todo" filetype -- setting it
      -- on a headless scratch buffer makes Neovim's own filetype-triggered
      -- `:runtime! syntax/awiwi.vim` autocommand load the *legacy* syntax
      -- file (since "awiwi" is one of the dot-separated compound-filetype
      -- components), polluting the global highlight namespace with the
      -- very B3 typo'd group names this module fixes. `str.endswith` only
      -- cares about the ".todo" suffix, so any non-colliding stand-in
      -- exercises the same code path without that side effect.
    end, { filetype = "journal.todo" })
  end)
end)

describe("syn.setup_highlights: B3 renames", function()
  it("14. awiwiQuestionn/awiwiOnHole do not exist; awiwiQuestion/awiwiOnHold do", function()
    syn.setup_highlights()
    local qn = vim.api.nvim_get_hl(0, { name = "awiwiQuestionn" })
    local oh = vim.api.nvim_get_hl(0, { name = "awiwiOnHole" })
    eq(0, next(qn) and 1 or 0)
    eq(0, next(oh) and 1 or 0)

    local q = vim.api.nvim_get_hl(0, { name = "awiwiQuestion" })
    local o = vim.api.nvim_get_hl(0, { name = "awiwiOnHold" })
    ok(next(q) ~= nil, "expected awiwiQuestion to be defined")
    ok(next(o) ~= nil, "expected awiwiOnHold to be defined")
  end)

  it("'@onhole' (typo) still triggers the onhold marker highlight (backward-compat alias)", function()
    with_buffer({ "@onhole waiting on client" }, function(buf)
      syn.attach(buf)
      ok(find_hl(marks(buf, syn.ns_markers), "awiwiOnHold") ~= nil, "expected @onhole to still highlight as awiwiOnHold")
    end)
  end)
end)

describe("syn.detach / M.attach idempotency", function()
  it("detach clears every namespace this module owns", function()
    with_buffer({ "- foo", "TODO bar" }, function(buf)
      syn.attach(buf)
      ok(#marks(buf, syn.ns_structure) + #marks(buf, syn.ns_markers) > 0, "expected some extmarks before detach")
      syn.detach(buf)
      eq(0, #marks(buf, syn.ns_structure))
      eq(0, #marks(buf, syn.ns_links))
      eq(0, #marks(buf, syn.ns_markers))
    end)
  end)

  it("re-attaching does not accumulate stale extmarks", function()
    with_buffer({ "- foo" }, function(buf)
      syn.attach(buf)
      local before = #marks(buf, syn.ns_structure)
      syn.attach(buf)
      local after = #marks(buf, syn.ns_structure)
      eq(before, after)
    end)
  end)
end)

describe("syn: bad-spaces nag (item 11)", function()
  it("extra spaces after a bullet get awiwiListBadSpaces", function()
    with_buffer({ "-   foo" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiListBadSpaces")
      ok(m ~= nil, "expected an awiwiListBadSpaces extmark")
    end)
  end)

  it("extra spaces after a checkbox get awiwiListBadSpacesAfterCheckbox", function()
    with_buffer({ "- [ ]   foo" }, function(buf)
      syn.attach(buf)
      local m = find_hl(marks(buf, syn.ns_markers), "awiwiListBadSpacesAfterCheckbox")
      ok(m ~= nil, "expected an awiwiListBadSpacesAfterCheckbox extmark")
    end)
  end)

  it("a single canonical space after a bullet is not flagged", function()
    with_buffer({ "- foo" }, function(buf)
      syn.attach(buf)
      ok(find_hl(marks(buf, syn.ns_markers), "awiwiListBadSpaces") == nil, "expected no bad-spaces match")
    end)
  end)
end)
