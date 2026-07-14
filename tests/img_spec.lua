-- Acceptance specs for lua/awiwi/img.lua — optional inline-image rendering
-- via snacks.nvim's `image` module, a silent auto-upgrade dependency (ADR
-- D7, same seam pattern as awiwi.picker's telescope auto-upgrade). The real
-- snacks.nvim is never required for this suite to pass: a FAKE backend is
-- injected through `img.deps.require`.

local img = require("awiwi.img")
local asset = require("awiwi.asset")

--- Runs `fn(home)` with `vim.g.awiwi_home` pointed at a fresh scratch
--- tempdir, restoring the previous global afterward (mirrors asset_spec.lua).
local function with_home(fn)
  local home = vim.fn.tempname()
  vim.fn.mkdir(home, "p")
  local saved = vim.g.awiwi_home
  vim.g.awiwi_home = home
  local ok_, err = pcall(fn, home)
  vim.g.awiwi_home = saved
  if not ok_ then
    error(err, 0)
  end
end

--- Snapshot/restore img.deps and vim.g.awiwi_inline_images around each test.
local function with_env(overrides, fn)
  local saved_require = img.deps.require
  local saved_flag = vim.g.awiwi_inline_images
  if overrides.require ~= nil then
    img.deps.require = overrides.require
  end
  if overrides.enabled ~= nil then
    vim.g.awiwi_inline_images = overrides.enabled
  end
  local ok_, err = pcall(fn)
  img.deps.require = saved_require
  vim.g.awiwi_inline_images = saved_flag
  if not ok_ then
    error(err, 0)
  end
end

--- Fake `snacks.image` module: records `doc.attach` calls, exposes a
--- `config.resolve` field that specs may pre-populate to simulate a
--- pre-existing resolver, and can optionally throw on attach.
local function fake_snacks_image(opts)
  opts = opts or {}
  local rec = { attach_calls = {}, chained_calls = 0 }
  local mod = {
    config = { resolve = opts.previous_resolve },
    doc = {
      attach = function(bufnr)
        if opts.attach_throws then
          error("snacks blew up")
        end
        rec.attach_calls[#rec.attach_calls + 1] = bufnr
      end,
    },
  }
  return mod, rec
end

--- Fake `require` that resolves "snacks" and "snacks.image" to the given
--- fake image module (and errors for everything else, though img.lua never
--- asks for anything else).
local function fake_require(image_mod)
  return function(name)
    if name == "snacks" then
      return { image = image_mod }
    elseif name == "snacks.image" then
      return image_mod
    end
    error("module '" .. name .. "' not found", 0)
  end
end

--- Fake `require` simulating "no snacks.nvim installed": both requires throw.
local function no_snacks_require(name)
  error("module '" .. name .. "' not found: " .. name, 0)
end

describe("img.resolve", function()
  it("maps an absolute date-tree src to the resolved asset path", function()
    with_home(function(home)
      eq(
        home .. "/assets/2024/03/05/pic.png",
        img.resolve("/some/file.md", "/assets/2024-03-05/pic.png")
      )
    end)
  end)

  it("returns nil for a relative src (defers to snacks)", function()
    with_home(function()
      eq(nil, img.resolve("/some/file.md", "./pic.png"))
    end)
  end)

  it("delegates to asset.resolve_image_link", function()
    with_home(function()
      eq(asset.resolve_image_link("/tmp/pic.png"), img.resolve("/some/file.md", "/tmp/pic.png"))
    end)
  end)
end)

describe("img.enabled", function()
  it("defaults to true when unset", function()
    with_env({ enabled = nil }, function()
      vim.g.awiwi_inline_images = nil
      eq(true, img.enabled())
    end)
  end)

  it("is false when vim.g.awiwi_inline_images = false", function()
    with_env({ enabled = false }, function()
      eq(false, img.enabled())
    end)
  end)

  it("is false when vim.g.awiwi_inline_images = 0", function()
    with_env({ enabled = 0 }, function()
      eq(false, img.enabled())
    end)
  end)
end)

describe("img.attach", function()
  it("returns false with no backend available (require throws)", function()
    with_env({ require = no_snacks_require }, function()
      local buf = vim.api.nvim_create_buf(false, true)
      eq(false, img.attach(buf))
    end)
  end)

  it("returns false when disabled, even with a working fake backend", function()
    local image_mod, rec = fake_snacks_image()
    with_env({ require = fake_require(image_mod), enabled = false }, function()
      local buf = vim.api.nvim_create_buf(false, true)
      eq(false, img.attach(buf))
      eq(0, #rec.attach_calls)
    end)
  end)

  it("happy path: attaches, calls doc.attach with bufnr, registers markdown parser", function()
    local image_mod, rec = fake_snacks_image()
    with_env({ require = fake_require(image_mod) }, function()
      -- no `filetype = "awiwi"` here: that would fire the real ftplugin,
      -- whose own attach call (T20 wiring) double-counts against the fake.
      -- attach() has no filetype check; ftplugin wiring is ftplugin_spec's job.
      local buf = vim.api.nvim_create_buf(false, true)
      local result = img.attach(buf)
      eq(true, result)
      eq({ buf }, rec.attach_calls)
      eq("markdown", vim.treesitter.language.get_lang("awiwi"))
    end)
  end)

  it("chains (not clobbers) a pre-existing config.resolve", function()
    local chained = { calls = {} }
    local previous_resolve = function(file, src)
      chained.calls[#chained.calls + 1] = { file, src }
      return "PREVIOUS:" .. src
    end
    local image_mod = fake_snacks_image({ previous_resolve = previous_resolve })
    with_env({ require = fake_require(image_mod) }, function()
      with_home(function(home)
        local buf = vim.api.nvim_create_buf(false, true)
        img.attach(buf)

        -- our resolver wins for asset-tree srcs
        local ours = image_mod.config.resolve("/some/file.md", "/assets/2024-03-05/pic.png")
        eq(home .. "/assets/2024/03/05/pic.png", ours)
        eq(0, #chained.calls)

        -- falls through to the previous resolver when M.resolve yields nil
        local fallback = image_mod.config.resolve("/some/file.md", "./relative.png")
        eq("PREVIOUS:./relative.png", fallback)
        eq(1, #chained.calls)
      end)
    end)
  end)

  it("double attach does not stack resolvers", function()
    local chained = { calls = {} }
    local previous_resolve = function(_file, src)
      chained.calls[#chained.calls + 1] = src
      return "PREVIOUS:" .. src
    end
    local image_mod = fake_snacks_image({ previous_resolve = previous_resolve })
    with_env({ require = fake_require(image_mod) }, function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)
      img.attach(buf1)
      img.attach(buf2)

      image_mod.config.resolve("/some/file.md", "./relative.png")
      eq(1, #chained.calls)
    end)
  end)
end)
