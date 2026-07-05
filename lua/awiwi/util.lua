-- Grab-bag of helpers used across the plugin's live (`:Awiwi`-reachable)
-- surface: pattern-escaping, subcommand-completion matching (3 search
-- engines), an `input()` wrapper, markdown-link parsing/classification, code-
-- block text objects, and a thin `path.relativize` convenience wrapper.
--
-- Scope: only the ~12 functions reachable from the shipped command surface
-- are ported here (group A of handovers/lua-port/util.md). Dropped per the
-- brief's scope recommendation (orchestrator-confirmed):
--   - group B (zero callers anywhere): `join_nonempty`, `copy_code_block`,
--     `get_visual_selection` (the last is invalid vimscript syntax anyway).
--   - group C (dao.vim/task.vim-only, both dead/unreachable from `:Awiwi`):
--     `get_resource`, `empty_resources_cache`, `get_iso_timestamp`,
--     `get_epoch_seconds`, `is_null`, `id_or_null`, `unique`, `has_element`.
--
-- See handovers/lua-port/util.md for the full behavior contract and bug list.

local str = require("awiwi.str")
local pathlib = require("awiwi.path")

local M = {}

--- Backslash-escape space, tab, `.`, `*`, `\`, `[`, `]` in `pattern`. Pure,
--- byte-based. Matches vimscript's `escape(pattern, " \t.*\\[]")` exactly.
local ESCAPE_SET = {
  [" "] = true,
  ["\t"] = true,
  ["."] = true,
  ["*"] = true,
  ["\\"] = true,
  ["["] = true,
  ["]"] = true,
}

function M.escape_pattern(pattern)
  return (pattern:gsub(".", function(c)
    if ESCAPE_SET[c] then
      return "\\" .. c
    end
    return c
  end))
end

--- 'plain' | 'regex' | 'fuzzy', read from `g:awiwi_search_engine`. Defaults
--- (and falls back) to 'plain' for anything else, including unset/bogus.
function M.get_search_engine()
  local engine = vim.g.awiwi_search_engine or "plain"
  if engine == "regex" or engine == "fuzzy" then
    return engine
  end
  return "plain"
end

--- Count how many whitespace-separated "words" `expr` splits into (runs of
--- `[[:space:]]+` collapse to one separator), minus 1 — used by cmd-line
--- completion to know which `:Awiwi` argument slot the cursor sits in. A
--- trailing run of whitespace produces a final empty field, which is what
--- bumps the count when the cursor is positioned to start a new argument.
function M.get_argument_number(expr)
  local fields = 0
  local pos = 1
  while true do
    local s, e = expr:find("%s+", pos)
    if not s then
      fields = fields + 1
      break
    end
    fields = fields + 1
    pos = e + 1
  end
  return fields - 1
end

--- Filter/sort `subcommands` for `:Awiwi` completion against `ArgLead`,
--- behavior depending on `get_search_engine()`. Empty `ArgLead` always
--- returns all candidates unchanged (short-circuited before engine dispatch).
function M.match_subcommands(subcommands, ArgLead)
  if ArgLead == "" then
    local copy = {}
    for i, v in ipairs(subcommands) do
      copy[i] = v
    end
    return copy
  end

  local engine = M.get_search_engine()

  if engine == "plain" then
    local result = {}
    for _, v in ipairs(subcommands) do
      if str.startswith(v, ArgLead) then
        result[#result + 1] = v
      end
    end
    return result
  end

  if engine == "regex" then
    local result = {}
    for _, v in ipairs(subcommands) do
      if vim.fn.match(v, ArgLead) > -1 then
        result[#result + 1] = v
      end
    end
    return result
  end

  -- fuzzy: subsequence match, pattern built from ArgLead's chars joined by
  -- '.\{-}' (each char escaped), scored by match span width (narrower span
  -- ranks first), ties broken by ascending name.
  local pieces = {}
  for i = 1, #ArgLead do
    pieces[#pieces + 1] = M.escape_pattern(ArgLead:sub(i, i))
  end
  local pattern = table.concat(pieces, [[.\{-}]])

  local items = {}
  for _, v in ipairs(subcommands) do
    local m = vim.fn.matchstrpos(v, pattern)
    if m[1] ~= "" then
      items[#items + 1] = { name = v, score = m[3] - m[2] }
    end
  end
  table.sort(items, function(a, b)
    if a.score ~= b.score then
      return a.score < b.score
    end
    return a.name < b.name
  end)
  local result = {}
  for i, it in ipairs(items) do
    result[i] = it.name
  end
  return result
end

--- Prompt the user, `vim.ui.input`-shaped: `M.input(opts, on_confirm)`
--- mirrors `vim.ui.input`'s own signature exactly (nvim-idiomatic, and
--- transparently overridable by UI plugins like dressing.nvim/snacks.nvim).
--- Convenience: a bare `opts.completion` value (not already prefixed with
--- 'customlist') is rewritten to `'customlist,' .. opts.completion`, mirroring
--- the vimscript original's convenience for callers passing a bare function
--- name. `on_confirm` receives whatever `vim.ui.input` passes through
--- unmodified — including `nil` on cancel/Ctrl-C (this is the fix for
--- B-util-1: the vimscript original left `text` unset and threw
--- `E121: Undefined variable: text` on Ctrl-C instead of a clean cancel).
--- See "## Ported" in handovers/lua-port/util.md for the input-migration
--- pattern the T5/T9 callers need (nested on_confirm callbacks replacing
--- sequential synchronous `input()` calls).
function M.input(opts, on_confirm)
  opts = opts or {}
  if opts.completion and not str.startswith(opts.completion, "customlist") then
    opts.completion = "customlist," .. opts.completion
  end
  vim.ui.input(opts, on_confirm)
end

--- True when the current window is "tallish" (width < 3x height) — signal to
--- prefer a horizontal ("below") split over a vertical ("right") one.
function M.window_split_below()
  local width = vim.api.nvim_win_get_width(0)
  local height = vim.api.nvim_win_get_height(0)
  return (width / (1.0 * height)) < 3
end

--- vimscript-style 0-indexed strridx: byte offset of the last occurrence of
--- `needle` in `haystack`, or -1 if absent.
local function strridx(haystack, needle)
  local last = -1
  local from = 1
  while true do
    local s = haystack:find(needle, from, true)
    if not s then
      break
    end
    last = s - 1
    from = s + 1
  end
  return last
end

--- vimscript-style 0-indexed stridx: byte offset of the first occurrence of
--- `needle` in `haystack` at or after 0-indexed `from`, or -1 if absent.
local function stridx(haystack, needle, from)
  local s = haystack:find(needle, from + 1, true)
  if not s then
    return -1
  end
  return s - 1
end

--- Split `link` on the first `#` only (B-util-2 fix): the vimscript original
--- required exactly one `#` in the string (`split(link, '#')` demanding a
--- 2-element result) and threw `E688`/`E687` on 0 or 2+ occurrences. This
--- degrades gracefully instead: no `#` -> empty anchor; 2+ `#` -> only the
--- first one splits, the rest stay part of the anchor.
local function split_link_and_anchor(link)
  local idx = link:find("#", 1, true)
  if not idx then
    return link, ""
  end
  return link:sub(1, idx - 1), link:sub(idx + 1)
end

--- Normalize `link` (string or already-a-link table) into a
--- `{target, type, anchor}` table. A table input is shallow-copied; a string
--- is split into target/anchor (see `split_link_and_anchor`) with `type=''`.
function M.as_link(link)
  if type(link) == "table" then
    local copy = {}
    for k, v in pairs(link) do
      copy[k] = v
    end
    return copy
  end
  local target, anchor = split_link_and_anchor(link)
  return { target = target, type = "", anchor = anchor }
end

--- Classify `link.target` (returns a copy, doesn't mutate `link`). First
--- match wins: already 'image' (set by the caller) -> unchanged; `http(s)://`
--- -> 'browser'; `mailto:` -> 'mail'; any other `scheme://` -> 'external';
--- contains `.*/recipes/*` -> 'recipe'; contains `.*/assets/*` -> 'asset';
--- else, matches a journal-file-shaped path -> 'journal', otherwise stays
--- `''`.
---
--- B-util-3 fix: the vimscript original's journal branch used the raw
--- (possibly negative) integer return of `match()` as a boolean instead of
--- comparing `> -1` like every other branch, so it fired almost
--- unconditionally — non-journal-looking targets were mislabeled 'journal'
--- and a target matching right at index 0 was (accidentally) skipped. Fixed
--- here to only classify as 'journal' on an actual match; this is a
--- user-visible behavior change from the shipped vimscript, flagged for the
--- human/ADR per the brief.
---
--- Anchor handling (only when `link.anchor` is non-empty): 'browser'/'mail'/
--- 'external' re-append the anchor verbatim as a URL fragment; every other
--- type turns the anchor into a loose "fuzzy heading search" pattern (strip
--- non-alnum/underscore chars, then interleave `.*` after every remaining
--- character, prefixed with a literal `.*`).
function M.determine_link_type(link)
  local result = {}
  for k, v in pairs(link) do
    result[k] = v
  end

  if result.type == "image" then
    return result
  elseif vim.fn.match(result.target, [[^https\?://]]) > -1 then
    result.type = "browser"
  elseif str.startswith(result.target, "mailto:") then
    result.type = "mail"
  elseif vim.fn.match(result.target, [[^[a-z]\+://]]) > -1 then
    result.type = "external"
  elseif vim.fn.match(result.target, [[\..*/recipes/.*]]) > -1 then
    result.type = "recipe"
  elseif vim.fn.match(result.target, [[\..*/assets/.*]]) > -1 then
    result.type = "asset"
  elseif
    vim.fn.match(
      result.target,
      [[/\(journal/\)\?\([0-9]\{4}/\)\?\([0-9]\{2}/\)\?\d\{4}-\d\{2}-\d\{2}.md$]]
    ) > -1
  then
    result.type = "journal"
  end

  if result.anchor ~= "" then
    if result.type == "browser" or result.type == "mail" or result.type == "external" then
      result.target = result.target .. "#" .. result.anchor
    else
      -- Net effect of the vimscript original's two chained substitutes
      -- (strip `^#+\s+`-or-any-non-alnum char, then interleave `.*`): since
      -- the character-class alternative already strips every non-alnum
      -- char one at a time under the `g` flag, the leading-heading-marker
      -- alternative is redundant in practice — a single strip-then-
      -- interleave reproduces the identical final string.
      local fuzzy = result.anchor:gsub("[^%w_]", "")
      fuzzy = fuzzy:gsub(".", "%0.*")
      result.anchor = ".*" .. fuzzy
    end
  end

  return result
end

--- Redmine-issue short-circuit pattern: `#` followed by 5+ digits anywhere
--- in the WORD under the cursor.
local REDMINE_PATTERN = "#(%d%d%d%d%d+)"

--- Link (see `as_link`) under the cursor in the current window/buffer.
--- First checks the WORD under the cursor for a redmine-issue reference
--- (`#12345`+) and short-circuits to a hardcoded
--- `https://redmine.pmd5.org/issues/<N>` link if found (hardcoded internal
--- hostname, not a `g:awiwi_*` setting — preserved as-is from the vimscript
--- original). Otherwise scans the current line for a markdown link
--- `[text](target#anchor)` bracketing the cursor column, returning an empty
--- link (`as_link('')`) if the brackets don't bracket correctly. A `![...]`
--- (bang immediately before `[`) sets `type='image'` pre-emptively.
function M.get_link_under_cursor()
  local cword = vim.fn.expand("<cWORD>")
  local issue = cword:match(REDMINE_PATTERN)
  if issue then
    local link = M.as_link(("https://redmine.pmd5.org/issues/%d"):format(tonumber(issue)))
    return M.determine_link_type(link)
  end

  local link = M.as_link("")
  local line = vim.fn.getline(".")
  local col = vim.fn.col(".") - 1

  local open_bracket = strridx(line:sub(1, col + 1), "[")
  if open_bracket == -1 then
    col = col + 1
    open_bracket = strridx(line:sub(1, col + 1), "[")
  end
  if open_bracket == -1 then
    return link
  end

  local closing_parens = stridx(line, ")", col)
  if closing_parens == -1 then
    return link
  end
  local closing_bracket = stridx(line:sub(1, closing_parens + 1), "]", open_bracket)
  if closing_bracket == -1 then
    return link
  end
  if
    open_bracket > closing_bracket
    or line:sub(closing_bracket + 2, closing_bracket + 2) ~= "("
    or closing_parens < closing_bracket
  then
    return link
  end

  if open_bracket > 0 and line:sub(open_bracket, open_bracket) == "!" then
    link.type = "image"
  end

  link.target = line:sub(closing_bracket + 3, closing_parens)
  link.target, link.anchor = split_link_and_anchor(link.target)
  return M.determine_link_type(link)
end

--- `path` relativized against `other` (or, if omitted, the current buffer's
--- file path) after making `other` absolute first. Thin wrapper delegating
--- entirely to the already-ported `path` module.
function M.relativize(path, other)
  local other_file = pathlib.absolute(other or vim.api.nvim_buf_get_name(0))
  return pathlib.relativize(path, other_file)
end

local FENCE = "```"

--- `{start, end}` line range of the fenced code block the cursor is assumed
--- to be inside (fence matched via `str.startswith`, not treesitter). Scans
--- backward for the opening fence and forward for the closing one. Returns
--- `{-1, -1}` (printing a non-throwing error via `nvim_err_writeln`, mirroring
--- the vimscript original's uncaught `echoerr`) when the cursor is on a fence
--- line itself, no opening fence is found above, or no closing fence is found
--- below. `inclusive=true` includes the fence lines in the range; `false`
--- excludes them.
function M.get_code_block_lines(inclusive)
  local bad_result = { -1, -1 }
  local current_line = vim.fn.line(".")

  if str.startswith(vim.fn.getline(current_line), FENCE) then
    vim.api.nvim_err_writeln("[ERROR] not inside of a code block")
    return bad_result
  end

  local block_start = -1
  for line = current_line - 1, 1, -1 do
    if str.startswith(vim.fn.getline(line), FENCE) then
      block_start = line
      break
    end
  end
  if block_start == -1 then
    vim.api.nvim_err_writeln("[ERROR] not inside of a code block")
    return bad_result
  end

  local block_end = -1
  local last_line = vim.fn.line("$")
  for line = current_line + 1, last_line do
    if str.startswith(vim.fn.getline(line), FENCE) then
      block_end = line
      break
    end
  end
  if block_end == -1 then
    vim.api.nvim_err_writeln("[ERROR] cannot find end of code block")
    return bad_result
  end

  local offset = inclusive and 0 or 1
  return { block_start + offset, block_end - offset }
end

--- Visually (linewise) select the fenced code block around the cursor, per
--- `get_code_block_lines`. Silently no-ops if the cursor isn't inside a code
--- block (the error was already reported by `get_code_block_lines`). Wired
--- to the `aP`/`iP` text-object mappings in `ftdetect/awiwi.vim`.
function M.select_code_block(inclusive)
  local lines = M.get_code_block_lines(inclusive)
  if lines[1] == -1 then
    return
  end
  vim.cmd(("normal! %dggV%dgg"):format(lines[1], lines[2]))
end

return M
