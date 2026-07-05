-- Filesystem-path string manipulation (join, split, absolutize, relativize,
-- canonicalize). Pure over its arguments except `absolute()`, which resolves
-- against Neovim's cwd/env via `vim.fn.expand`/`vim.fs.abspath` (no
-- filesystem stat, see B-PATH-9 fix below).
--
-- See handovers/lua-port/path.md for the full behavior contract and the
-- vimscript bugs fixed in this port (B-PATH-2, -3, -5, -6, -7, -9).

local str = require("awiwi.str")

local M = {}

--- Join `path` with zero or more segments, deduping the `/` boundary between
--- each pair (never doubled, never missing). With zero variadic args, strips
--- exactly one trailing slash from `path` (B-PATH-5 fix: `join('/') == '/'`,
--- not `''`). An empty segment is a no-op in the fold, it never truncates the
--- remaining segments (B-PATH-3 fix). 3+ args are native varargs, no external
--- plugin dependency (B-PATH-2 fix — `fn#apply`/`fn#spread` are dropped).
function M.join(path, ...)
  local result = vim.fs.joinpath(path, ...)
  if result ~= "/" and result:sub(-1) == "/" then
    result = result:sub(1, -2)
  end
  return result
end

--- Resolve `path` to an absolute path: expands `~`, `~user`, `$ENV_VARS` and
--- Vim special keywords (`%`, `#`, ...) via `vim.fn.expand`, then resolves
--- against Neovim's cwd via `vim.fs.abspath`. Unlike the vimscript original,
--- never appends a spurious trailing slash based on whether the path exists
--- as a directory on disk (B-PATH-9 fix: no filesystem stat at all).
function M.absolute(path)
  return vim.fs.abspath(vim.fn.expand(path))
end

--- True iff `path` starts with `/`. Note `~/foo` and `""` are NOT absolute.
function M.is_absolute(path)
  return str.startswith(path, "/")
end

--- Strict complement of `is_absolute`.
function M.is_relative(path)
  return not M.is_absolute(path)
end

--- Split `path` on `/`, collapsing leading/trailing empty components but
--- preserving embedded ones from doubled slashes (`split('a//b') ==
--- {'a','','b'}`). If `path` is absolute, a literal `'/'` sentinel is
--- prepended, so `join(unpack(split(p))) == p` round-trips for absolute
--- paths (except the root case, handled specially by `join`/`canonicalize`).
function M.split(path)
  local parts = vim.split(path, "/", { plain = true, trimempty = true })
  if M.is_absolute(path) then
    table.insert(parts, 1, "/")
  end
  return parts
end

--- Return `path` relative to `relative_to`'s containing directory (i.e.
--- `relative_to` is treated as a FILE path — its own last component is
--- always excluded from the emitted `..` count; pass a directory here and
--- you'll get one extra `..`/matched-directory-name than you probably want,
--- per B-PATH-7's contract note).
---
--- B-PATH-7 fix: when relative_to's components are a full prefix of path's,
--- this now correctly emits zero `..` segments (was off-by-one) and returns
--- `'.'` for identical inputs (was a truncated result / would-be crash).
--- Coordination note for T6a (hi.vim port): the vimscript workaround at
--- hi.vim:129-130 that manually strips the result's first split component to
--- compensate for the old bug MUST NOT be re-applied on top of this fixed
--- Lua version — see handovers/lua-port/path.md B-PATH-7 and this module's
--- "## Ported" section.
function M.relativize(path, relative_to)
  if M.is_absolute(path) and M.is_relative(relative_to) then
    return path
  end

  local p = M.split(path)
  local r = M.split(relative_to)
  local length = math.min(#p, #r)

  -- Fixed common-prefix search: `common` defaults to a full match over the
  -- compared range (fixes B-PATH-7); it is only lowered on an actual
  -- mismatch.
  local common = length
  for i = 1, length do
    if p[i] ~= r[i] then
      common = i - 1
      break
    end
  end

  -- relative_to's own last component is excluded from the `..` count;
  -- clamped at 0 so a fully-matching common prefix never underflows.
  local up_count = math.max(0, #r - 1 - common)

  local parts = {}
  for _ = 1, up_count do
    parts[#parts + 1] = ".."
  end
  for i = common + 1, #p do
    parts[#parts + 1] = p[i]
  end

  if #parts == 0 then
    return "."
  end
  return M.join(unpack(parts))
end

--- Purely lexical path normalization: drops `.` and empty components, pops
--- the previous component on `..`. Never touches the filesystem, never
--- resolves symlinks. B-PATH-6 fix: never crashes on an underflowing `..`;
--- clamps at the root for absolute paths and preserves leading `..` for
--- relative paths (delegates to `vim.fs.normalize`, which already implements
--- exactly this fixed semantics — see handovers/lua-port/path.md Port notes).
function M.canonicalize(path)
  return vim.fs.normalize(path, { expand_env = false })
end

return M
