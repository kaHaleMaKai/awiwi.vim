-- Single source of truth for the fixed "marker keyword" vocabularies
-- (`TODO`, `FIXME`, `@urgent`, `DUE`, ...) that classify journal/todo lines,
-- plus the escaping/joining logic that turns those vocabularies into either a
-- Vim-regex alternation (for `syn.lua`) or an rg/PCRE-flavored alternation
-- (for `cmd.lua`'s `rg`-based `Awiwi tags`/`search` and `server.lua`'s
-- `config.json`). Pure data + string transforms -- no buffers, no files, no
-- shelling out.
--
-- Port of `autoload/awiwi.vim:43-66` (marker word lists) and
-- `autoload/awiwi.vim:179-204` (`awiwi#get_markers`). See
-- handovers/lua-port/markers.md for the full behavior contract.

local util = require("awiwi.util")

local M = {}

--- The ten built-in marker vocabularies, exact strings preserved verbatim
--- (`@onhole` is a documented typo for `@onhold`, kept as a permanent
--- backward-compat alias -- see syn.md B3 cross-reference/ADR note).
M.lists = {
  todo = { "TODO", "@todo" },
  onhold = { "ONHOLD", "HOLD", "@onhole", "@onhold" },
  urgent = { "FIXME", "CRITICAL", "URGENT", "IMPORTANT", "@fixme", "@critical", "@urgent", "@important" },
  delegate = { "@@" },
  question = { "QUESTION", "q?", "Q?" },
  due = { "DUE", "DUE TO", "UNTIL", "@until", "@due" },
  incident = { "@incident" },
  change = { "@change" },
  issue = { "@issue" },
  bug = { "@bug" },
}

--- Bug #1 fix (see markers.md): the legacy vimscript appended a fragment
--- written in Vim-regex syntax (`\(`, `\)`, `\zs`) into an otherwise
--- rg/PCRE-flavored joined pattern. Verified empirically against the real
--- `rg` binary (regex crate): `\(`/`\)` are literal parens, not grouping, and
--- `\z` is the "end of haystack" anchor -- so `\zs` is `\z` (end-of-haystack)
--- immediately followed by a required literal `s`, which can never match;
--- the fragment compiles (doesn't break the whole joined pattern) but is
--- permanent dead weight. Fixed here with a real rg-flavored equivalent that
--- matches an open task-list bullet (`- [ ]`); no `(?m)` multiline anchor is
--- needed since `cmd.lua`'s `rg` invocation processes input line-by-line by
--- default (rg only needs `-U`/`--multiline` to change that, which it
--- doesn't use).
local OPEN_TASK_BULLET_RG = "^\\s*[-*]\\s+\\[\\s+\\]"

--- `s:escape_rg_pattern` port (`autoload/awiwi.vim:266-268`): backslash-escape
--- `.`, `*`, `?`, `\`, `[`, `]` -- notably NOT whitespace, unlike
--- `util.escape_pattern`'s vim-mode escaper. Private to this module (never
--- exposed as `awiwi#util#...` in the original either).
local RG_ESCAPE_SET = {
  ["."] = true,
  ["*"] = true,
  ["?"] = true,
  ["\\"] = true,
  ["["] = true,
  ["]"] = true,
}

local function escape_rg_pattern(pattern)
  return (pattern:gsub(".", function(c)
    if RG_ESCAPE_SET[c] then
      return "\\" .. c
    end
    return c
  end))
end

--- vimscript `uniq()` port: adjacent-duplicates-only dedupe, first occurrence
--- kept, insertion order preserved. Deliberately NOT a full-list dedupe --
--- see markers.md "preserve, don't silently improve" note.
local function uniq_adjacent(list)
  local result = {}
  for i, v in ipairs(list) do
    if i == 1 or list[i - 1] ~= v then
      result[#result + 1] = v
    end
  end
  return result
end

--- `awiwi#get_markers` port (`autoload/awiwi.vim:179-204`).
--- `type` must be one of `M.lists`' keys; anything else `error()`s with an
--- `AwiwiError: type <type> does not exist` message (callers don't
--- pattern-match on the message content, confirmed in the brief).
--- `opts.escape_mode`: `'rg'` (default) or `'vim'`. `opts.join`: default
--- `true` -- a single `'|'` (rg) / `'\|'` (vim) joined string; `false` -- the
--- unjoined list of escaped entries.
function M.get_markers(type_, opts)
  opts = opts or {}
  local escape_mode = opts.escape_mode or "rg"
  local join = opts.join
  if join == nil then
    join = true
  end

  local builtin = M.lists[type_]
  if not builtin then
    error(("AwiwiError: type %s does not exist"):format(type_), 2)
  end

  local combined = {}
  for _, v in ipairs(builtin) do
    combined[#combined + 1] = v
  end
  local custom = vim.g["awiwi_custom_" .. type_ .. "_markers"] or {}
  for _, v in ipairs(custom) do
    combined[#combined + 1] = v
  end

  local escape = escape_mode == "vim" and util.escape_pattern or escape_rg_pattern
  local escaped = {}
  for i, v in ipairs(combined) do
    escaped[i] = escape(v)
  end

  if type_ == "todo" and escape_mode == "rg" then
    escaped[#escaped + 1] = OPEN_TASK_BULLET_RG
  end

  local result = uniq_adjacent(escaped)

  if not join then
    return result
  end

  local sep = escape_mode == "vim" and [[\|]] or "|"
  return table.concat(result, sep)
end

return M
