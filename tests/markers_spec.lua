local markers = require("awiwi.markers")

--- Restores `vim.g.awiwi_custom_<type>_markers` to `nil` after `fn()` runs,
--- regardless of whether it set the global itself.
local function with_custom(type_, list, fn)
  local key = "awiwi_custom_" .. type_ .. "_markers"
  local saved = vim.g[key]
  vim.g[key] = list
  local ok, err = pcall(fn)
  vim.g[key] = saved
  if not ok then
    error(err, 0)
  end
end

describe("markers.get_markers", function()
  it("defaults: joins with '|' (rg mode) and includes escaped built-ins", function()
    local result = markers.get_markers("todo")
    ok(type(result) == "string", "expected a joined string")
    ok(result:find("TODO", 1, true) ~= nil, result)
    ok(result:find("@todo", 1, true) ~= nil, result)
    -- Bug #1 fix: the open-task-bullet alternative is rg-flavored, not the
    -- dead/broken vim-regex fragment (`\(`, `\)`, `\zs`).
    ok(not result:find("\\zs", 1, true), "expected no dead vim-regex fragment: " .. result)
    ok(not result:find("\\(", 1, true), "expected no vim-regex grouping: " .. result)
  end)

  it("Bug #1 fix: the todo+rg extra alternative actually matches an open task bullet via rg", function()
    local result = markers.get_markers("todo")
    -- last alternative should be a valid, self-contained rg pattern that
    -- matches a real open task-list bullet.
    local rg = vim.system({ "rg", "-e", result }, { stdin = "- [ ] buy milk\n", text = true }):wait()
    eq(0, rg.code)
    ok(rg.stdout:find("buy milk", 1, true) ~= nil, rg.stdout)
  end)

  it("get_markers('due', {escape_mode='vim'}) escapes the space in 'DUE TO'", function()
    local result = markers.get_markers("due", { escape_mode = "vim" })
    ok(result:find("DUE\\ TO", 1, true) ~= nil, result)
    ok(result:find("\\|", 1, true) ~= nil, "expected \\| join: " .. result)
  end)

  it("get_markers('due', {escape_mode='rg'}) leaves the space in 'DUE TO' unescaped", function()
    local result = markers.get_markers("due", { escape_mode = "rg" })
    ok(result:find("DUE TO", 1, true) ~= nil, result)
    ok(not result:find("DUE\\ TO", 1, true), result)
  end)

  it("get_markers('onhold', {join=false}) returns the four entries in order, no dedupe", function()
    local result = markers.get_markers("onhold", { join = false })
    eq({ "ONHOLD", "HOLD", "@onhole", "@onhold" }, result)
  end)

  it("appends custom markers after the built-ins, order preserved", function()
    with_custom("urgent", { "@blocker" }, function()
      local result = markers.get_markers("urgent", { join = false })
      eq({
        "FIXME",
        "CRITICAL",
        "URGENT",
        "IMPORTANT",
        "@fixme",
        "@critical",
        "@urgent",
        "@important",
        "@blocker",
      }, result)
    end)
  end)

  it("re-reads g:awiwi_custom_<type>_markers fresh on every call (no caching)", function()
    with_custom("urgent", { "@first" }, function()
      local first = markers.get_markers("urgent", { join = false })
      eq("@first", first[#first])
    end)
    with_custom("urgent", { "@second" }, function()
      local second = markers.get_markers("urgent", { join = false })
      eq("@second", second[#second])
    end)
  end)

  it("throws AwiwiError mentioning the bogus type", function()
    local ok_, err = pcall(markers.get_markers, "bogus_type")
    ok(not ok_, "expected an error")
    ok(tostring(err):find("bogus_type", 1, true) ~= nil, tostring(err))
  end)

  it("adjacent-duplicate custom markers collapse to one (uniq is adjacent-only)", function()
    with_custom("delegate", { "@@", "@@" }, function()
      local result = markers.get_markers("delegate", { join = false })
      eq({ "@@" }, result)
    end)
  end)

  it("non-adjacent duplicate custom marker is preserved (not deduped)", function()
    with_custom("urgent", { "@urgent" }, function()
      local result = markers.get_markers("urgent", { join = false })
      -- '@urgent' already exists earlier in the built-in list, non-adjacently
      -- to the appended duplicate -> both survive.
      local count = 0
      for _, v in ipairs(result) do
        if v == "@urgent" then
          count = count + 1
        end
      end
      eq(2, count)
    end)
  end)

  it("get_markers('delegate') is a single escaped '@@' entry", function()
    eq("@@", markers.get_markers("delegate"))
  end)
end)
