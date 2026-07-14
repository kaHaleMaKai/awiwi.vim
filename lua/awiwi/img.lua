-- Optional inline-image rendering in the terminal via snacks.nvim's `image`
-- module. Silent auto-upgrade dependency (ADR D7, same seam pattern as
-- `awiwi.picker`'s telescope auto-upgrade): with no snacks.nvim installed,
-- every entry point here silently no-ops (returns false / nil) so callers
-- never need to branch on "is snacks present".

local M = {}

--- Overridable dependency (mockable in tests). `require` is the single seam
--- through which snacks/snacks.image are loaded — a fake snacks injected here
--- exercises the attach path with no real plugin present.
M.deps = { require = require }

-- Guards so repeated `M.attach` calls don't stack resolver wrappers on the
-- same `snacks.image` module table. Keyed by the module table itself (weak
-- keys) rather than a single flag: in production `require("snacks.image")`
-- is a singleton, so this behaves like a one-shot flag; in specs, each test
-- injects a fresh fake module table and gets its own independent guard.
local chained_modules = setmetatable({}, { __mode = "k" })

--- Pure resolution of an `image`-link target to an asset file path, delegated
--- to `awiwi.asset.resolve_image_link` (S18.1). `nil` means "not ours" (a
--- relative path, an http(s) URL, or an absolute path outside the asset
--- date-tree) — the caller falls through to snacks' own file-relative
--- resolution.
function M.resolve(_file, src)
  return require("awiwi.asset").resolve_image_link(src)
end

--- `vim.g.awiwi_inline_images` opts out inline rendering; unset/nil defaults
--- to enabled. Both `false` and `0` count as "disabled" (vimscript-style
--- falsy-int compatibility for the config surface).
function M.enabled()
  local v = vim.g.awiwi_inline_images
  return v ~= false and v ~= 0
end

--- Attach snacks.nvim's image rendering to `bufnr`. Returns true only if the
--- backend accepted the buffer; false (silently, no error) whenever inline
--- images are disabled, snacks.nvim isn't installed, or snacks itself throws
--- on attach.
function M.attach(bufnr)
  if not M.enabled() then
    return false
  end

  local req = M.deps.require
  local ok_snacks = pcall(req, "snacks")
  if not ok_snacks then
    return false
  end
  local ok_image, image = pcall(req, "snacks.image")
  if not ok_image then
    return false
  end

  -- Load-bearing: without a registered `markdown` parser for these
  -- filetypes, `vim.treesitter.get_parser` fails on `filetype=awiwi` buffers
  -- and snacks' doc scan can't run. `register` is idempotent, so repeat
  -- attaches are harmless.
  vim.treesitter.language.register(
    "markdown",
    { "awiwi", "awiwi.todo", "awiwi.asset", "awiwi.recipe" }
  )

  if not chained_modules[image] then
    local previous = image.config.resolve
    image.config.resolve = function(file, src)
      local resolved = M.resolve(file, src)
      if resolved ~= nil then
        return resolved
      end
      if previous then
        return previous(file, src)
      end
      return nil
    end
    chained_modules[image] = true
  end

  local ok_attach = pcall(image.doc.attach, bufnr)
  if not ok_attach then
    return false
  end
  return true
end

return M
