local util = require("awiwi.util")

describe("util.escape_pattern", function()
  it("escapes space, tab, ., *, backslash, [, ]", function()
    eq("a\\.b\\*c\\[d\\]", util.escape_pattern("a.b*c[d]"))
  end)
  it("empty string is a no-op", function() eq("", util.escape_pattern("")) end)
  it("escapes space and tab", function() eq("a\\ b\\\tc", util.escape_pattern("a b\tc")) end)
  it("leaves untouched characters alone", function()
    eq("abcXYZ123_-", util.escape_pattern("abcXYZ123_-"))
  end)
end)

describe("util.get_search_engine", function()
  local saved
  local function set(v) vim.g.awiwi_search_engine = v end

  it("unset defaults to plain", function()
    saved = vim.g.awiwi_search_engine
    vim.g.awiwi_search_engine = nil
    eq("plain", util.get_search_engine())
    vim.g.awiwi_search_engine = saved
  end)

  it("'plain' stays plain", function()
    saved = vim.g.awiwi_search_engine
    set("plain")
    eq("plain", util.get_search_engine())
    vim.g.awiwi_search_engine = saved
  end)

  it("bogus value falls back to plain", function()
    saved = vim.g.awiwi_search_engine
    set("bogus")
    eq("plain", util.get_search_engine())
    vim.g.awiwi_search_engine = saved
  end)

  it("'regex' passes through", function()
    saved = vim.g.awiwi_search_engine
    set("regex")
    eq("regex", util.get_search_engine())
    vim.g.awiwi_search_engine = saved
  end)

  it("'fuzzy' passes through", function()
    saved = vim.g.awiwi_search_engine
    set("fuzzy")
    eq("fuzzy", util.get_search_engine())
    vim.g.awiwi_search_engine = saved
  end)
end)

describe("util.get_argument_number", function()
  it("empty string", function() eq(0, util.get_argument_number("")) end)
  it("bare command, no trailing space", function() eq(0, util.get_argument_number("Awiwi")) end)
  it("bare command with trailing space", function() eq(1, util.get_argument_number("Awiwi ")) end)
  it("command + one argument", function() eq(1, util.get_argument_number("Awiwi journal")) end)
  it("command + one argument + trailing space", function()
    eq(2, util.get_argument_number("Awiwi journal "))
  end)
  it("double space between words collapses to one separator", function()
    eq(1, util.get_argument_number("Awiwi  journal"))
  end)
end)

describe("util.match_subcommands", function()
  local subcommands = { "journal", "jump", "asset" }
  local saved

  local function with_engine(engine, fn)
    saved = vim.g.awiwi_search_engine
    vim.g.awiwi_search_engine = engine
    local ok_, err = pcall(fn)
    vim.g.awiwi_search_engine = saved
    if not ok_ then error(err, 0) end
  end

  it("empty ArgLead returns all candidates unchanged regardless of engine", function()
    with_engine("fuzzy", function()
      eq(subcommands, util.match_subcommands(subcommands, ""))
    end)
  end)

  it("plain engine filters by prefix, order preserved", function()
    with_engine("plain", function()
      eq({ "journal", "jump" }, util.match_subcommands(subcommands, "j"))
    end)
  end)

  it("regex engine filters by vim regex match, order preserved", function()
    with_engine("regex", function()
      eq({ "journal", "jump" }, util.match_subcommands(subcommands, "^j"))
    end)
  end)

  it("fuzzy engine matches subsequences and scores by span width", function()
    with_engine("fuzzy", function()
      eq({ "journal" }, util.match_subcommands(subcommands, "jn"))
    end)
  end)
end)

describe("util.input", function()
  it("forwards opts through to vim.ui.input unmodified when no completion", function()
    local orig = vim.ui.input
    local captured
    vim.ui.input = function(opts, cb)
      captured = opts
      cb("answer")
    end
    local received
    util.input({ prompt = "foo: " }, function(r) received = r end)
    vim.ui.input = orig
    eq("foo: ", captured.prompt)
    eq("answer", received)
  end)

  it("rewrites a bare completion value with a customlist prefix", function()
    local orig = vim.ui.input
    local captured
    vim.ui.input = function(opts, cb)
      captured = opts
      cb(nil)
    end
    util.input({ prompt = "x", completion = "foo" }, function() end)
    vim.ui.input = orig
    eq("customlist,foo", captured.completion)
  end)

  it("leaves an already-customlist completion value untouched", function()
    local orig = vim.ui.input
    local captured
    vim.ui.input = function(opts, cb)
      captured = opts
      cb(nil)
    end
    util.input({ prompt = "x", completion = "customlist,foo" }, function() end)
    vim.ui.input = orig
    eq("customlist,foo", captured.completion)
  end)

  it("forwards nil on cancel without coercing to empty string (B-util-1 fix)", function()
    local orig = vim.ui.input
    vim.ui.input = function(_, cb) cb(nil) end
    local received = "sentinel"
    local called = false
    util.input({ prompt = "x" }, function(r)
      received = r
      called = true
    end)
    vim.ui.input = orig
    ok(called, "on_confirm must be called")
    eq(nil, received)
  end)
end)

describe("util.window_split_below", function()
  it("true when width < 3x height (tallish window)", function()
    local orig_w, orig_h = vim.api.nvim_win_get_width, vim.api.nvim_win_get_height
    vim.api.nvim_win_get_width = function() return 10 end
    vim.api.nvim_win_get_height = function() return 10 end
    local result = util.window_split_below()
    vim.api.nvim_win_get_width = orig_w
    vim.api.nvim_win_get_height = orig_h
    eq(true, result)
  end)

  it("false when width >= 3x height (wide window)", function()
    local orig_w, orig_h = vim.api.nvim_win_get_width, vim.api.nvim_win_get_height
    vim.api.nvim_win_get_width = function() return 30 end
    vim.api.nvim_win_get_height = function() return 10 end
    local result = util.window_split_below()
    vim.api.nvim_win_get_width = orig_w
    vim.api.nvim_win_get_height = orig_h
    eq(false, result)
  end)
end)

describe("util.as_link", function()
  it("a table input is shallow-copied", function()
    local input = { target = "a", type = "b", anchor = "c" }
    local result = util.as_link(input)
    eq(input, result)
    ok(result ~= input, "must be a copy, not the same table")
  end)

  it("a plain URL string has no anchor", function()
    eq({ target = "https://example.com", type = "", anchor = "" }, util.as_link("https://example.com"))
  end)

  it("splits target#anchor on the single #", function()
    eq({ target = "foo", type = "", anchor = "bar" }, util.as_link("foo#bar"))
  end)

  it("empty string", function() eq({ target = "", type = "", anchor = "" }, util.as_link("")) end)

  it("no # at all does not throw (B-util-2 fix)", function()
    eq({ target = "foo", type = "", anchor = "" }, util.as_link("foo"))
  end)

  it("2+ # splits on the first one only (B-util-2 fix)", function()
    eq({ target = "a", type = "", anchor = "b#c" }, util.as_link("a#b#c"))
  end)
end)

describe("util.determine_link_type", function()
  it("http(s) URL -> browser, anchor re-appended verbatim", function()
    local result = util.determine_link_type(util.as_link("https://x#sec"))
    eq("browser", result.type)
    eq("https://x#sec", result.target)
  end)

  it("mailto: -> mail", function()
    eq("mail", util.determine_link_type(util.as_link("mailto:a@b.com")).type)
  end)

  it("other scheme -> external", function()
    eq("external", util.determine_link_type(util.as_link("ssh://foo")).type)
  end)

  it("path containing /recipes/ -> recipe", function()
    eq("recipe", util.determine_link_type(util.as_link("./recipes/foo.md")).type)
  end)

  it("path containing /assets/ -> asset", function()
    eq("asset", util.determine_link_type(util.as_link("./assets/2024/01/01/foo.md")).type)
  end)

  it("journal-shaped path -> journal", function()
    eq("journal", util.determine_link_type(util.as_link("./journal/2024/01/2024-01-01.md")).type)
  end)

  it("journal path anchor becomes a fuzzy heading-search pattern", function()
    local result =
      util.determine_link_type(util.as_link("./journal/2024/01/2024-01-01.md#some-heading"))
    eq("journal", result.type)
    eq(".*s.*o.*m.*e.*h.*e.*a.*d.*i.*n.*g.*", result.anchor)
  end)

  it("B-util-3 fix: non-journal-looking target is NOT mislabeled 'journal'", function()
    eq("", util.determine_link_type(util.as_link("random-non-matching-target")).type)
  end)

  it("already-image type is left unchanged (short-circuit)", function()
    local link = { target = "foo.png", type = "image", anchor = "" }
    eq(link, util.determine_link_type(link))
  end)
end)

describe("util.get_link_under_cursor", function()
  local function with_buffer(lines, row, col, fn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local prev_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { row, col })
    local ok_, err = pcall(fn)
    pcall(vim.api.nvim_set_current_win, prev_win)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if not ok_ then error(err, 0) end
  end

  it("parses a markdown link bracketing the cursor, with anchor split off", function()
    with_buffer({ "see [text](target#anchor) here" }, 1, 6, function()
      local link = util.get_link_under_cursor()
      eq("target", link.target)
      eq(".*a.*n.*c.*h.*o.*r.*", link.anchor)
      eq("", link.type)
    end)
  end)

  it("bang before brackets marks the link as an image", function()
    with_buffer({ "see ![alt](img.png) here" }, 1, 6, function()
      local link = util.get_link_under_cursor()
      eq("image", link.type)
      eq("img.png", link.target)
    end)
  end)

  it("redmine-issue WORD short-circuits to a hardcoded redmine link", function()
    with_buffer({ "see issue #12345 please" }, 1, 12, function()
      local link = util.get_link_under_cursor()
      eq("https://redmine.pmd5.org/issues/12345", link.target)
      eq("browser", link.type)
      eq("", link.anchor)
    end)
  end)

  it("no brackets around the cursor returns an empty link", function()
    with_buffer({ "no links here" }, 1, 3, function()
      local link = util.get_link_under_cursor()
      eq("", link.target)
      eq("", link.type)
      eq("", link.anchor)
    end)
  end)
end)

describe("util.relativize", function()
  it("calls path.relativize(path, path.absolute(other)) in that order", function()
    local pathlib = require("awiwi.path")
    local orig_abs, orig_rel = pathlib.absolute, pathlib.relativize
    local calls = {}
    pathlib.absolute = function(p)
      calls[#calls + 1] = { "absolute", p }
      return "ABS:" .. p
    end
    pathlib.relativize = function(p, o)
      calls[#calls + 1] = { "relativize", p, o }
      return "RESULT"
    end
    local result = util.relativize("a/b", "c/d")
    pathlib.absolute = orig_abs
    pathlib.relativize = orig_rel
    eq("RESULT", result)
    eq({ "absolute", "c/d" }, calls[1])
    eq({ "relativize", "a/b", "ABS:c/d" }, calls[2])
  end)

  it("uses the current buffer's file path when other is omitted", function()
    local pathlib = require("awiwi.path")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "/tmp/awiwi-util-spec/file.md")
    local prev_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(buf)
    local expected_name = vim.api.nvim_buf_get_name(0)

    local orig_abs, orig_rel = pathlib.absolute, pathlib.relativize
    local seen
    pathlib.absolute = function(p)
      seen = p
      return "ABS:" .. p
    end
    pathlib.relativize = function(_, o) return o end

    local result = util.relativize("a/b")

    pathlib.absolute = orig_abs
    pathlib.relativize = orig_rel
    pcall(vim.api.nvim_set_current_win, prev_win)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    eq(expected_name, seen)
    eq("ABS:" .. expected_name, result)
  end)
end)

describe("util.get_code_block_lines / util.select_code_block", function()
  local lines = {
    "before",
    "```lua",
    "local x = 1",
    "local y = 2",
    "```",
    "after",
  }

  local function with_buffer(row, fn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local prev_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    local ok_, err = pcall(fn)
    pcall(vim.api.nvim_set_current_win, prev_win)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if not ok_ then error(err, 0) end
  end

  it("cursor on the fence line itself returns {-1, -1}", function()
    with_buffer(2, function() eq({ -1, -1 }, util.get_code_block_lines(true)) end)
  end)

  it("cursor inside, inclusive=true includes the fence lines", function()
    with_buffer(3, function() eq({ 2, 5 }, util.get_code_block_lines(true)) end)
  end)

  it("cursor inside, inclusive=false excludes the fence lines", function()
    with_buffer(3, function() eq({ 3, 4 }, util.get_code_block_lines(false)) end)
  end)

  it("no closing fence returns {-1, -1}", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "```lua", "local x = 1" })
    local prev_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    eq({ -1, -1 }, util.get_code_block_lines(true))
    pcall(vim.api.nvim_set_current_win, prev_win)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("select_code_block visually selects the expected line span", function()
    with_buffer(3, function()
      util.select_code_block(false)
      eq("V", vim.fn.mode())
      -- '< / '> marks aren't updated until visual mode is left; line('v')
      -- reflects the live visual-area start while still selecting.
      local start_line = vim.fn.line("v")
      local end_line = vim.fn.line(".")
      eq(3, start_line)
      eq(4, end_line)
      vim.cmd("normal! \27") -- leave visual mode
    end)
  end)

  it("select_code_block on a fence line is a silent no-op", function()
    with_buffer(2, function()
      local mode_before = vim.fn.mode()
      util.select_code_block(true)
      eq(mode_before, vim.fn.mode())
    end)
  end)
end)
