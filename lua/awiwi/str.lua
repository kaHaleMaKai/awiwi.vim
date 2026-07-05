-- Leaf string-predicate helpers (startswith/endswith/contains/is_empty).
-- Pure Lua, byte-based, no vim.* dependency (see handovers/lua-port/str.md).
--
-- Deviation from vimscript source (Bstr-2, intentional): comparisons here are
-- always byte-exact/case-sensitive. The vimscript `==` operator is sensitive
-- to `'ignorecase'`, which made startswith/endswith silently case-insensitive
-- under `set ignorecase`. This port closes that latent bug rather than
-- reproducing it.

local M = {}

function M.startswith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

function M.endswith(s, suffix)
  if #suffix == 0 then return true end
  return s:sub(-#suffix) == suffix
end

function M.contains(s, part)
  if #part == 0 then return true end
  return s:find(part, 1, true) ~= nil
end

function M.is_empty(s)
  return s:match("^%s*$") ~= nil
end

return M
