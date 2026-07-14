local asset = require("awiwi.asset")
local util = require("awiwi.util")
local date = require("awiwi.date")

-- Test isolation helpers -----------------------------------------------

--- Runs `fn(home)` with `vim.g.awiwi_home` pointed at a fresh scratch tempdir,
--- restoring the previous global afterward.
local function with_home(fn)
  local home = vim.fn.tempname()
  vim.fn.mkdir(home, "p")
  local saved = vim.g.awiwi_home
  vim.g.awiwi_home = home
  local ok_, err = pcall(fn, home)
  vim.g.awiwi_home = saved
  if not ok_ then error(err, 0) end
end

--- Runs `fn()` with a fresh scratch buffer named `name` as the current
--- buffer (so `date.get_own_date()` can read it), restoring the previous
--- window/buffer afterward.
local function with_named_buffer(name, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  local prev_win = vim.api.nvim_get_current_win()
  local prev_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(buf)
  local ok_, err = pcall(fn)
  pcall(vim.api.nvim_set_current_win, prev_win)
  pcall(vim.api.nvim_win_set_buf, prev_win, prev_buf)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  if not ok_ then error(err, 0) end
end

--- A journal-shaped buffer name for `date_str` (`YYYY-MM-DD`) under `home`.
local function journal_buffer_name(home, date_str)
  local y, m = date_str:match("^(%d%d%d%d)-(%d%d)-%d%d$")
  return home .. "/journal/" .. y .. "/" .. m .. "/" .. date_str .. ".md"
end

--- Stubs `awiwi.util.input` to answer a queue of canned responses (in call
--- order); a response may be a function of `opts` (e.g. to echo back
--- `opts.default`). Returns a restore function.
local function stub_input(responses)
  local orig = util.input
  local i = 0
  util.input = function(opts, on_confirm)
    i = i + 1
    local r = responses[i]
    if type(r) == "function" then
      on_confirm(r(opts))
    else
      on_confirm(r)
    end
  end
  return function() util.input = orig end
end

--- Captures links passed to `asset.deps.insert_link_here`, without touching
--- any real buffer. Returns (captured_links_table, restore_fn).
local function stub_insert_link_here()
  local orig = asset.deps.insert_link_here
  local links = {}
  asset.deps.insert_link_here = function(link) links[#links + 1] = link end
  return links, function() asset.deps.insert_link_here = orig end
end

-- awiwi.asset.types ------------------------------------------------------

describe("asset.types", function()
  it("owns the three asset-type string constants (cycle-break contract)", function()
    eq("empty", asset.types.empty)
    eq("url", asset.types.url)
    eq("paste", asset.types.paste)
  end)
end)

-- awiwi.asset.get_asset_path ----------------------------------------------

describe("asset.get_asset_path", function()
  it("joins asset subpath / year / month / day / name", function()
    with_home(function(home)
      eq(home .. "/assets/2026/07/05/photo.png", asset.get_asset_path("2026-07-05", "photo.png"))
    end)
  end)

  it("throws on a malformed date (not exactly 2 '-' separators)", function()
    local ok_, err = pcall(asset.get_asset_path, "2026-07", "x")
    ok(not ok_, "expected an error")
    ok(err:match("AwiwiAssetError"), err)

    local ok2, err2 = pcall(asset.get_asset_path, "2026-07-05-06", "x")
    ok(not ok2, "expected an error")
    ok(err2:match("AwiwiAssetError"), err2)
  end)
end)

-- awiwi.asset.create_asset_link -------------------------------------------

describe("asset.create_asset_link", function()
  it("empty input (no name, aborted) returns the ('','','') sentinel, no fs/buffer writes", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore = stub_input({ "" })
        local result
        asset.create_asset_link({}, function(name, filename, link) result = { name, filename, link } end)
        restore()
        eq({ "", "", "" }, result)
      end)
    end)
  end)

  it("derives the default filename by slugifying the name, echoed back as the second prompt's default", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local seen_default
        local restore = stub_input({
          "My Recipe Notes",
          function(opts)
            seen_default = opts.default
            return opts.default
          end,
        })
        local result
        asset.create_asset_link({}, function(name, filename, link) result = { name, filename, link } end)
        restore()
        eq("my-recipe-notes", seen_default)
        eq("my-recipe-notes", result[2])
        eq("My Recipe Notes", result[1])
      end)
    end)
  end)

  it("escapes [ and ] in the link text only, leaving the returned name untouched", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore = stub_input({
          "Foo [bar]",
          function(opts) return opts.default end,
        })
        local result
        asset.create_asset_link({}, function(name, filename, link) result = { name, filename, link } end)
        restore()
        eq("Foo [bar]", result[1])
        ok(result[3]:match("^%[Foo \\%[bar\\%]%]%(.+%)$") ~= nil, result[3])
      end)
    end)
  end)

  it("aborting the second (filename) prompt also returns the sentinel", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore = stub_input({ "some name", "" })
        local result
        asset.create_asset_link({}, function(name, filename, link) result = { name, filename, link } end)
        restore()
        eq({ "", "", "" }, result)
      end)
    end)
  end)

  it("uses opts.name directly, skipping the first prompt", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local prompts = {}
        local restore = stub_input({
          function(opts)
            prompts[#prompts + 1] = opts.prompt
            return opts.default
          end,
        })
        local result
        asset.create_asset_link({ name = "already named" }, function(name, filename, link)
          result = { name, filename, link }
        end)
        restore()
        eq({ "asset file: " }, prompts)
        eq("already-named", result[2])
      end)
    end)
  end)
end)

-- awiwi.asset.create_asset_here_if_not_exists ------------------------------

describe("asset.create_asset_here_if_not_exists", function()
  it("creates a not-yet-existing empty asset: parent dirs, template file, link inserted, filename returned",
    function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore_input = stub_input({ function(opts) return opts.default end })
        local links, restore_links = stub_insert_link_here()

        local filename
        asset.create_asset_here_if_not_exists(
          asset.types.empty,
          { name = "drawio test", suffix = ".drawio" },
          function(f) filename = f end
        )

        restore_input()
        restore_links()

        eq("drawio-test.drawio", filename)
        local path = asset.get_asset_path("2026-07-05", filename)
        eq(1, vim.fn.filereadable(path))
        local content = table.concat(vim.fn.readfile(path), "\n")
        local id = content:match('diagram id="([^"]+)"')
        ok(id ~= nil, "expected a diagram id attribute")
        eq(20, #id)
        ok(id:match("^[A-Za-z0-9]+$") ~= nil, id)
        eq(1, #links)
      end)
    end)
  end)

  it("B4 regression: creating two drawio assets in the same process both succeed", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        for _, name in ipairs({ "drawio one", "drawio two" }) do
          local restore_input = stub_input({ function(opts) return opts.default end })
          local links, restore_links = stub_insert_link_here()
          local filename
          asset.create_asset_here_if_not_exists(
            asset.types.empty,
            { name = name, suffix = ".drawio" },
            function(f) filename = f end
          )
          restore_input()
          restore_links()
          ok(filename ~= nil and filename ~= "", "expected a filename for " .. name)
          eq(1, vim.fn.filereadable(asset.get_asset_path("2026-07-05", filename)))
        end
      end)
    end)
  end)

  it("skips creation when the target already exists, but still inserts the link and returns the filename",
    function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local path = asset.get_asset_path("2026-07-05", "already-there.txt")
        vim.fn.mkdir(vim.fs.dirname(path), "p")
        vim.fn.writefile({ "existing content" }, path)

        local restore_input = stub_input({ function(opts) return opts.default end })
        local links, restore_links = stub_insert_link_here()

        local filename
        asset.create_asset_here_if_not_exists(
          asset.types.empty,
          { name = "already there.txt" },
          function(f) filename = f end
        )

        restore_input()
        restore_links()

        eq("already-there.txt", filename)
        eq({ "existing content" }, vim.fn.readfile(path))
        eq(1, #links)
      end)
    end)
  end)

  it("image-extension filename gets the absolute embed link, not create_asset_link's relative link",
    function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore_input = stub_input({ function(opts) return opts.default end })
        asset.deps.paste_file = function() return true end
        local links, restore_links = stub_insert_link_here()

        local filename
        asset.create_asset_here_if_not_exists(asset.types.paste, { name = "screenshot" }, function(f)
          filename = f
        end)

        restore_input()
        restore_links()

        eq("screenshot.png", filename)
        eq({ "![screenshot](/assets/2026-07-05/screenshot.png)" }, links)
      end)
    end)
  end)

  it("non-image extension keeps create_asset_link's relative markdown link", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore_input = stub_input({ function(opts) return opts.default end })
        local links, restore_links = stub_insert_link_here()

        local filename
        asset.create_asset_here_if_not_exists(asset.types.empty, { name = "notes.txt" }, function(f)
          filename = f
        end)

        restore_input()
        restore_links()

        eq("notes.txt", filename)
        eq(1, #links)
        ok(links[1]:match("^%[notes%.txt%]%(.+%)$") ~= nil, links[1])
      end)
    end)
  end)

  it("case-sensitive image match: .JPG does not get embed treatment", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore_input = stub_input({ function(opts) return "PHOTO.JPG" end })
        local links, restore_links = stub_insert_link_here()

        asset.create_asset_here_if_not_exists(asset.types.empty, { name = "photo" }, function() end)

        restore_input()
        restore_links()

        ok(not links[1]:match("^!"), links[1])
      end)
    end)
  end)

  it("aborting naming inserts the empty sentinel link and returns '' without touching the filesystem",
    function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local restore_input = stub_input({ "" })
        local links, restore_links = stub_insert_link_here()

        local filename
        asset.create_asset_here_if_not_exists(asset.types.empty, {}, function(f) filename = f end)

        restore_input()
        restore_links()

        eq("", filename)
        eq({ "" }, links)
        eq({}, asset.get_all_asset_files())
      end)
    end)
  end)

  it("invoked outside a journal/asset buffer throws and creates nothing", function()
    with_home(function(home)
      local buf = vim.api.nvim_create_buf(false, true)
      local prev_win = vim.api.nvim_get_current_win()
      local prev_buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_set_current_buf(buf)

      local restore_input = stub_input({ function(opts) return opts.default end, function(opts) return opts.default end })
      local ok_, err = pcall(
        asset.create_asset_here_if_not_exists,
        asset.types.empty,
        { name = "whatever" },
        function() end
      )
      restore_input()

      pcall(vim.api.nvim_set_current_win, prev_win)
      pcall(vim.api.nvim_win_set_buf, prev_win, prev_buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })

      ok(not ok_, "expected create_asset_here_if_not_exists to throw")
      ok(date.is_date_error(err), err)
      eq({}, asset.get_all_asset_files())
    end)
  end)
end)

-- awiwi.asset.insert_asset_link ---------------------------------------------

describe("asset.insert_asset_link", function()
  it("without anchor: '[asset name, date](path)'", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local links, restore = stub_insert_link_here()
        asset.insert_asset_link("2026-07-05", "foo.png")
        restore()
        eq(1, #links)
        ok(links[1]:match("^%[asset foo%.png, 2026%-07%-05%]%(.+%)$") ~= nil, links[1])
      end)
    end)
  end)

  it("with anchor: '[asset name: anchor, date](path#anchor)'", function()
    with_home(function(home)
      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local links, restore = stub_insert_link_here()
        asset.insert_asset_link("2026-07-05", "foo.png", { anchor = "intro" })
        restore()
        eq(1, #links)
        ok(links[1]:match("^%[asset foo%.png: intro, 2026%-07%-05%]%(.+#intro%)$") ~= nil, links[1])
      end)
    end)
  end)
end)

-- awiwi.asset.get_journal_for_current_asset ---------------------------------

describe("asset.get_journal_for_current_asset", function()
  it("derives year/month/day from the 3 directory components above the asset file", function()
    with_home(function(home)
      with_named_buffer(home .. "/assets/2026/07/05/photo.png", function()
        local seen
        local orig = asset.deps.get_journal_file_by_date
        asset.deps.get_journal_file_by_date = function(d)
          seen = d
          return "JOURNAL:" .. d
        end
        local result = asset.get_journal_for_current_asset()
        asset.deps.get_journal_file_by_date = orig
        eq("2026-07-05", seen)
        eq("JOURNAL:2026-07-05", result)
      end)
    end)
  end)
end)

-- awiwi.asset.open_asset_by_name (B-new-1) -----------------------------------

describe("asset.open_asset_by_name", function()
  local function with_write_spy(fn)
    local orig_cmd = vim.cmd
    local write_calls = 0
    vim.cmd = function(arg)
      if arg == "write" then write_calls = write_calls + 1 end
      return orig_cmd(arg)
    end
    local prev_win = vim.api.nvim_get_current_win()
    local prev_buf = vim.api.nvim_get_current_buf()
    local ok_, err = pcall(fn, function() return write_calls end)
    vim.cmd = orig_cmd
    pcall(vim.api.nvim_set_current_win, prev_win)
    -- the spy'd open_asset_by_name really `:edit`s the asset. `:edit` from
    -- the pristine unnamed startup buffer REUSES that buffer (renames it in
    -- place), so restoring prev_buf would keep the dated asset name and leak
    -- it as the current buffer into later spec files (get_own_date() reads
    -- the current buffer name). Park the window on a fresh scratch buffer
    -- and wipe anything named like an asset instead.
    local fresh = vim.api.nvim_create_buf(true, false)
    pcall(vim.api.nvim_win_set_buf, prev_win, fresh)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= fresh and vim.api.nvim_buf_get_name(b):find("/assets/", 1, true) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    if not ok_ then error(err, 0) end
  end

  it("creates the parent directory and writes a not-yet-existing asset (explicit create-on-open)",
    function()
    with_home(function(home)
      with_write_spy(function(write_calls)
        asset.open_asset_by_name("2026-07-05", "foo.txt", {})
        local path = asset.get_asset_path("2026-07-05", "foo.txt")
        eq(1, vim.fn.isdirectory(vim.fs.dirname(path)))
        eq(1, write_calls())
        eq(1, vim.fn.filereadable(path))
      end)
    end)
  end)

  it("B-new-1 fix: does not rewrite an already-existing asset", function()
    with_home(function(home)
      local path = asset.get_asset_path("2026-07-05", "foo.txt")
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({ "hello" }, path)

      with_write_spy(function(write_calls)
        asset.open_asset_by_name("2026-07-05", "foo.txt", {})
        eq(0, write_calls())
        eq({ "hello" }, vim.fn.readfile(path))
      end)
    end)
  end)

  it("open_asset delegates to open_asset_by_name using the current buffer's own date", function()
    with_home(function(home)
      -- Pre-create the target so the (already-existing-asset) no-write branch
      -- is taken; this test is only about date delegation, not the write
      -- behavior (covered above) — avoids `write`ing the scratch test buffer.
      local path = asset.get_asset_path("2026-07-05", "foo.txt")
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({}, path)

      with_named_buffer(journal_buffer_name(home, "2026-07-05"), function()
        local seen
        local orig = asset.deps.open_file
        asset.deps.open_file = function(path) seen = path end
        local ok_, err = pcall(asset.open_asset, "foo.txt", {})
        asset.deps.open_file = orig
        if not ok_ then error(err, 0) end
        eq(asset.get_asset_path("2026-07-05", "foo.txt"), seen)
      end)
    end)
  end)
end)

-- awiwi.asset.open_asset_sink -------------------------------------------------

describe("asset.open_asset_sink", function()
  it("splits 'date:name' and delegates to open_asset_by_name", function()
    with_home(function()
      local seen
      local orig = asset.deps.open_file
      asset.deps.open_file = function(path) seen = path end
      -- open_file is stubbed (no :edit happens), so swallow the create
      -- path's follow-up :write too — it would hit the unnamed test-runner
      -- buffer and E32 (it only ever "worked" against a buffer leaked by an
      -- earlier spec, see with_write_spy's cleanup comment)
      local orig_cmd = vim.cmd
      vim.cmd = function(arg)
        if arg == "write" then return end
        return orig_cmd(arg)
      end
      local ok_, err = pcall(asset.open_asset_sink, "2026-07-05:foo.txt")
      vim.cmd = orig_cmd
      asset.deps.open_file = orig
      if not ok_ then error(err, 0) end
      eq(asset.get_asset_path("2026-07-05", "foo.txt"), seen)
    end)
  end)

  it("throws on a malformed 'date:name' expr", function()
    local ok_, err = pcall(asset.open_asset_sink, "no-colon-here")
    ok(not ok_)
    ok(err:match("AwiwiAssetError"), err)
  end)
end)

-- awiwi.asset.get_all_asset_files ---------------------------------------------

describe("asset.get_all_asset_files", function()
  it("returns files sorted ascending by date then name, regardless of on-disk order", function()
    with_home(function(home)
      local entries = {
        { "2026-07-06", "b.png" },
        { "2026-07-05", "z.png" },
        { "2026-07-05", "a.png" },
      }
      for _, e in ipairs(entries) do
        local path = asset.get_asset_path(e[1], e[2])
        vim.fn.mkdir(vim.fs.dirname(path), "p")
        vim.fn.writefile({}, path)
      end

      local files = asset.get_all_asset_files()
      eq({
        { date = "2026-07-05", name = "a.png" },
        { date = "2026-07-05", name = "z.png" },
        { date = "2026-07-06", name = "b.png" },
      }, files)
    end)
  end)

  it("ignores directories, returns empty list for an empty asset tree", function()
    with_home(function() eq({}, asset.get_all_asset_files()) end)
  end)
end)

-- awiwi.asset.resolve_image_link ------------------------------------------

describe("asset.resolve_image_link", function()
  it("resolves an absolute target whose parent dir is a YYYY-MM-DD date", function()
    with_home(function(home)
      eq(
        home .. "/assets/2024/03/05/pic.png",
        asset.resolve_image_link("/assets/2024-03-05/pic.png")
      )
      eq(
        home .. "/assets/2024/03/05/pic.png",
        asset.resolve_image_link("/x/2024-03-05/pic.png")
      )
    end)
  end)

  it("returns nil for a relative target", function()
    with_home(function()
      eq(nil, asset.resolve_image_link("2024-03-05/pic.png"))
      eq(nil, asset.resolve_image_link("./img.png"))
    end)
  end)

  it("returns nil for an http(s) URL", function()
    with_home(function()
      eq(nil, asset.resolve_image_link("http://example.com/pic.png"))
      eq(nil, asset.resolve_image_link("https://example.com/pic.png"))
    end)
  end)

  it("returns nil when the absolute target's parent dir is not a date", function()
    with_home(function()
      eq(nil, asset.resolve_image_link("/tmp/pic.png"))
    end)
  end)

  it("resolves through the M.deps.get_asset_subpath() seam", function()
    with_home(function()
      local orig = asset.deps.get_asset_subpath
      asset.deps.get_asset_subpath = function() return "/custom/assets" end
      local result = asset.resolve_image_link("/assets/2024-03-05/pic.png")
      asset.deps.get_asset_subpath = orig
      eq("/custom/assets/2024/03/05/pic.png", result)
    end)
  end)
end)
