-- Buffer-local structural + line-local decoration for awiwi markdown
-- buffers, replacing the legacy `:syntax` file (`syntax/awiwi.vim`) with a
-- single treesitter-driven extmark repaint pass, plus a small set of
-- "marker keyword" / modeline / redaction highlights that are inherently
-- line-local text patterns, not markdown structure.
--
-- No `b:current_syntax`/`:syntax` side effects -- extmarks only. See
-- handovers/lua-port/syn.md for the full behavior contract and the bug
-- list (B1-B12) fixed/preserved below.
--
-- BUILT + HEADLESS-TESTED ONLY in this transaction (T6b): nothing here is
-- wired into ftplugin/ftdetect or calls `vim.treesitter.start` outside
-- specs. Activation is T10's job.

local hi = require("awiwi.hi")
local markers = require("awiwi.markers")
local str = require("awiwi.str")

local M = {}

-- Namespaces: one per concern (mirrors hi.lua's convention), so a future
-- selective-disable toggle or M.detach can clear one concern without
-- nuking the others.
local ns_structure = vim.api.nvim_create_namespace("awiwi-syn-structure")
local ns_links = vim.api.nvim_create_namespace("awiwi-syn-links")
local ns_markers = vim.api.nvim_create_namespace("awiwi-syn-markers")

M.ns_structure = ns_structure
M.ns_links = ns_links
M.ns_markers = ns_markers

local ALL_NAMESPACES = { ns_structure, ns_links, ns_markers }

--- Clears every namespace this module owns for `bufnr` (used by
--- `M.attach` before repainting, by `M.detach`, and by tests to reset
--- state between cases).
function M.detach(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  for _, ns in ipairs(ALL_NAMESPACES) do
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

-- Static + dynamic highlight groups --------------------------------------

--- One-time (module-load-time is fine, idempotent, safe to call more than
--- once) `nvim_set_hl` calls for every color in the contract. Link-color
--- groups (`awiwiLinkName`/`awiwiLinkDomain`/... , `awiwiRedmineIssue`)
--- read `g:awiwi_link_color`/`g:awiwi_domain_color`/`g:awiwi_link_style`
--- fresh on every call too (cheap, and these aren't expected to change
--- mid-session per the legacy `:syntax`-load-time semantics, but re-reading
--- costs nothing and picks up a `g:` change before the first `M.attach`).
---
--- B3 fix: `awiwiQuestionn`/`awiwiOnHole` (double-n / missing "d" typos in
--- the legacy group names) renamed to `awiwiQuestion`/`awiwiOnHold` here.
--- B11 fix: `awiwiLinkNameStart`/`awiwiLinkNameEnd` get `link_style`/
--- `link_color` directly (the legacy `for group in ['Name','Start','End']`
--- loop only ever landed on `awiwiLinkName` since `awiwiLinkStart`/
--- `awiwiLinkEnd` don't exist as groups anywhere else in the file).
--- B12 fix: `awiwiDateOverlay` dropped entirely (dead code, and reading
--- `link_color` outside the `awiwi_highlight_links` guard crashed legacy
--- with `E121` when that flag was falsy -- moot here since it's gone).
function M.setup_highlights()
  local set = vim.api.nvim_set_hl

  set(0, "awiwiUrgent", { fg = "#d7ff00", bg = "#807000", bold = true })
  set(0, "awiwiDelegate", { fg = "#20e020", italic = true })
  set(0, "awiwiDue", { fg = "#d7ff00", bold = true })
  set(0, "awiwiList1", { fg = "#808000", bold = true })
  set(0, "awiwiList2", { fg = "#0087af", bold = true })
  set(0, "awiwiListBadSpaces", { bg = "#626262", bold = true })
  set(0, "awiwiListBadSpacesAfterCheckbox", { bg = "#626262", bold = true })
  set(0, "awiwiTaskListOpen1", { fg = "#808000", bold = true })
  set(0, "awiwiTaskListOpen2", { fg = "#0087af", bold = true })
  set(0, "awiwiFileTypePrefix", { fg = "#9e9e9e" })
  set(0, "awiwiFileType", { fg = "#808000", bold = true })
  set(0, "awiwiLinkPath", { fg = "#9e9e9e" })
  set(0, "awiwiRedminePath", { fg = "#9e9e9e" }) -- dead (no match/region uses it), kept for parity
  set(0, "awiwiRedactedCause", { fg = "#8a8a8a", bold = true })
  set(0, "awiwiRedactedTag", { link = "awiwiUrgent" })
  set(0, "awiwiRedacted", {}) -- legacy region has no color of its own either

  set(0, "awiwiTodo", { fg = "#808000", bold = true })
  set(0, "awiwiQuestion", { fg = "#808000", bold = true }) -- B3: was awiwiQuestionn
  set(0, "awiwiOnHold", { fg = "#808000", bold = true }) -- B3: was awiwiOnHole
  set(0, "awiwiChange", { link = "awiwiUrgent" })
  set(0, "awiwiIncident", { link = "awiwiUrgent" })
  set(0, "awiwiIssue", { link = "awiwiUrgent" })
  set(0, "awiwiBug", { link = "awiwiUrgent" })

  set(0, "awiwiCanceledList", { link = "htmlStrike" })
  set(0, "awiwiTaskListDone", { link = "htmlStrike" })

  -- .todo-only task metadata colors (hi.lua's due-date badges depend on
  -- these names existing regardless of the current buffer's filetype).
  set(0, "awiwiCreatedDate", { fg = "#585858", italic = true })
  set(0, "awiwiFutureDueDate", { fg = "#5fd700", bold = true })
  set(0, "awiwiNearDueDate", { fg = "#d7ff00", bold = true, bg = "#5f0000" })

  local link_color = vim.g.awiwi_link_color or "#afaf00"
  local domain_color = vim.g.awiwi_domain_color or "#808080"
  local link_style = vim.g.awiwi_link_style or "underline"

  local name_attrs = { fg = link_color }
  name_attrs[link_style] = true
  set(0, "awiwiLinkName", name_attrs)
  set(0, "awiwiLinkNameStart", vim.deepcopy(name_attrs))
  set(0, "awiwiLinkNameEnd", vim.deepcopy(name_attrs))

  set(0, "awiwiLinkDomain", { fg = domain_color })
  set(0, "awiwiLinkUrlStart", { fg = domain_color })
  set(0, "awiwiLinkUrlEnd", { fg = domain_color })
  set(0, "awiwiLinkProtocol", { fg = domain_color }) -- B2 fix: `printd` typo dropped, always set
  set(0, "awiwiRedmineIssue", { fg = link_color, bold = true })
end

-- g: config readers -------------------------------------------------------

local function gbool(name, default)
  local v = vim.g[name]
  if v == nil then
    return default
  end
  return v
end

local function gstr(name, default)
  local v = vim.g[name]
  if v == nil then
    return default
  end
  return v
end

-- Structural (treesitter) pass --------------------------------------------

local structure_query = vim.treesitter.query.parse("markdown", [[
(list_item) @list_item
]])

--- Recursively collects `{node, depth}` for every `list_item` node in the
--- tree, `depth` 0 for a top-level item, incrementing per list nesting
--- level (real treesitter ancestor depth -- see syn.md Port notes: a
--- genuine improvement over the legacy 0-or-2-leading-spaces hack, though
--- this module only maps depth 0 vs depth>=1 onto the existing two-color
--- (`List1`/`List2`) contract, per the brief's scope).
local function collect_list_items(root)
  local items = {}
  local function walk(node, depth)
    for child in node:iter_children() do
      if child:type() == "list_item" then
        items[#items + 1] = { node = child, depth = depth }
        walk(child, depth + 1)
      else
        walk(child, depth)
      end
    end
  end
  walk(root, 0)
  return items
end

local MARKER_TYPES = { "list_marker_minus", "list_marker_star" }

--- Direct-children-only lookup of a `list_item` node's own bullet marker
--- and (if present) its own task-list checkbox marker -- does NOT recurse
--- into a nested `list` child, so a nested item's own marker is never
--- mistaken for its parent's.
local function list_item_parts(item_node)
  local marker, task
  for child in item_node:iter_children() do
    local t = child:type()
    if t == "list_marker_minus" or t == "list_marker_star" then
      marker = child
    elseif t == "task_list_marker_checked" or t == "task_list_marker_unchecked" then
      task = child
    end
  end
  return marker, task
end

--- `{[^{]+}$` port (hi.lua's `match_checklist_blob` uses the identical
--- trailing-JSON-blob shape; duplicated here as a 12-char local literal
--- rather than reaching into hi.lua's private helper).
local function trailing_meta_start(line)
  local s = line:find("{[^{]+}$")
  return s
end

--- Paints list bullets (item 9), open task checkboxes (item 12),
--- completed task checkbox strike-through (item 14) and canceled
--- (`~~struck~~`) list items (item 10) into `ns_structure`. All four are
--- mutually exclusive per bullet -- exactly one extmark per list item,
--- matching the legacy "checkbox/strike wins over the generic bullet"
--- visible net effect without needing extmark-priority games (see syn.md
--- Port notes "Priority/ordering").
local function paint_structure(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return
  end
  local trees = parser:parse()
  if not trees or not trees[1] then
    return
  end
  local root = trees[1]:root()

  for _, item in ipairs(collect_list_items(root)) do
    local marker, task = list_item_parts(item.node)
    if marker then
      local lnum, scol = marker:range()
      local _, _, _, mecol = marker:range()
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
      local suffix2 = item.depth >= 1 and "2" or "1"

      if task then
        local _, _, _, tecol = task:range()
        local task_type = task:type()
        if task_type == "task_list_marker_checked" then
          local meta_s = trailing_meta_start(line)
          local content_end = meta_s and (meta_s - 1) or (#line + 1)
          while content_end > tecol + 1 and line:sub(content_end - 1, content_end - 1):match("%s") do
            content_end = content_end - 1
          end
          vim.api.nvim_buf_set_extmark(bufnr, ns_structure, lnum, scol, {
            end_col = math.max(content_end - 1, tecol),
            hl_group = "awiwiTaskListDone",
          })
        else
          vim.api.nvim_buf_set_extmark(bufnr, ns_structure, lnum, scol, {
            end_col = tecol,
            hl_group = "awiwiTaskListOpen" .. suffix2,
          })
        end
      else
        local rest = line:sub(mecol + 1)
        if rest:sub(1, 2) == "~~" then
          vim.api.nvim_buf_set_extmark(bufnr, ns_structure, lnum, scol, {
            end_col = #line,
            hl_group = "awiwiCanceledList",
          })
        else
          vim.api.nvim_buf_set_extmark(bufnr, ns_structure, lnum, scol, {
            end_col = mecol,
            hl_group = "awiwiList" .. suffix2,
          })
        end
      end
    end
  end
end

-- Link pass (markdown_inline) ---------------------------------------------

local inline_link_query = vim.treesitter.query.parse("markdown_inline", [[
(inline_link
  (link_text) @text
  (link_destination) @dest)
]])

--- Empty string means "bare conceal" (hide entirely); nvim's extmark
--- `conceal` field already treats `""` that way, so no translation needed
--- beyond reading the `g:` default.
local function conceal_char(name, default)
  return gstr(name, default)
end

--- Paints link regions (items 16-28) into `ns_links`: name/target
--- brackets and parens, internal-vs-external destination classification,
--- and conceal per `g:awiwi_conceal_*` -- only when
--- `g:awiwi_highlight_links` (default true) is truthy (item 15's master
--- switch). B1 fix: `]`'s conceal char reads
--- `g:awiwi_conceal_link_end_char` (legacy copy-pasted the *start*-char
--- global here instead).
local function paint_links(bufnr)
  if not gbool("awiwi_highlight_links", true) then
    return
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return
  end
  parser:parse(true)
  local children = parser:children()
  local inline = children["markdown_inline"]
  if not inline then
    return
  end

  local conceal_on = gbool("awiwi_conceal_links", true)
  local start_char = conceal_char("awiwi_conceal_link_start_char", "▶")
  local end_char = conceal_char("awiwi_conceal_link_end_char", " ")
  local target_char = conceal_char("awiwi_conceal_link_target_char", "")
  local internal_char = conceal_char("awiwi_conceal_link_internal_target_char", "…")

  local set_extmark = vim.api.nvim_buf_set_extmark

  local function maybe_conceal(opts, char)
    if conceal_on then
      opts.conceal = char
    end
    return opts
  end

  inline:for_each_tree(function(tree)
    for _, match in inline_link_query:iter_matches(tree:root(), bufnr, 0, -1, { all = true }) do
      local text_node = match[1] and match[1][1]
      local dest_node = match[2] and match[2][1]
      if text_node and dest_node then
        local tr, tsc, _, tec = text_node:range()
        local dr, dsc, _, dec = dest_node:range()

        -- '[' .. name .. ']'
        set_extmark(bufnr, ns_links, tr, tsc - 1, maybe_conceal({ end_col = tsc, hl_group = "awiwiLinkNameStart" }, start_char))
        set_extmark(bufnr, ns_links, tr, tsc, { end_col = tec, hl_group = "awiwiLinkName" })
        set_extmark(bufnr, ns_links, tr, tec, maybe_conceal({ end_col = tec + 1, hl_group = "awiwiLinkNameEnd" }, end_char))

        -- '(' .. destination .. ')'
        set_extmark(bufnr, ns_links, tr, tec + 1, { end_col = tec + 2, hl_group = "awiwiLinkUrlStart" })
        set_extmark(bufnr, ns_links, dr, dec, { end_col = dec + 1, hl_group = "awiwiLinkUrlEnd" })

        local dest = vim.treesitter.get_node_text(dest_node, bufnr)
        if dest:match("^https?://") then
          local proto_len = #(dest:match("^https?://w?w?w?%.?") or dest:match("^https?://"))
          local rest = dest:sub(proto_len + 1)
          local path_start = rest:find("/")
          set_extmark(
            bufnr,
            ns_links,
            dr,
            dsc,
            maybe_conceal({ end_col = dsc + proto_len, hl_group = "awiwiLinkProtocol" }, "")
          )
          local domain_end = path_start and (dsc + proto_len + path_start - 1) or dec
          set_extmark(bufnr, ns_links, dr, dsc + proto_len, { end_col = domain_end, hl_group = "awiwiLinkDomain" })
          if path_start then
            set_extmark(
              bufnr,
              ns_links,
              dr,
              domain_end,
              maybe_conceal({ end_col = dec, hl_group = "awiwiLinkPath" }, target_char)
            )
          end
        elseif dest:match("^[./]") then
          set_extmark(bufnr, ns_links, dr, dsc, maybe_conceal({ end_col = dec }, internal_char))
        end
      end
    end
  end)
end

-- Redmine issue references (item 29) --------------------------------------

--- `\(^\|\s\)\zs#[0-9]\{5,}` port: a `#` preceded by line-start or
--- whitespace, followed by 5-or-more digits (as many as present).
local function paint_redmine(bufnr, lnum, line)
  local search_from = 1
  while true do
    local s = line:find("#", search_from, true)
    if not s then
      return
    end
    local before_ok = s == 1 or line:sub(s - 1, s - 1):match("%s") ~= nil
    if before_ok then
      local digits = line:match("^#(%d+)", s)
      if digits and #digits >= 5 then
        vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, s - 1, {
          end_col = s - 1 + 1 + #digits,
          hl_group = "awiwiRedmineIssue",
        })
      end
    end
    search_from = s + 1
  end
end

-- Marker keywords (items 2-7) ----------------------------------------------

local function is_keyword_char(c)
  return c ~= nil and c ~= "" and c:match("[%w_]") ~= nil
end

local function ws_or_edge_ok(line, before_pos, after_pos)
  local before_ok = before_pos < 1 or line:sub(before_pos, before_pos):match("%s") ~= nil
  local after_ok = after_pos > #line or line:sub(after_pos, after_pos):match("%s") ~= nil
  return before_ok and after_ok
end

local function word_edge_ok(line, before_pos, after_pos)
  local before_char = before_pos >= 1 and line:sub(before_pos, before_pos) or nil
  local after_char = after_pos <= #line and line:sub(after_pos, after_pos) or nil
  return not is_keyword_char(before_char) and not is_keyword_char(after_char)
end

--- Finds every non-overlapping occurrence of literal `token` in `line`
--- whose surroundings satisfy `boundary_ok(line, before_pos, after_pos)`
--- (`before_pos`/`after_pos` are the 1-indexed positions immediately
--- before/after the match; the boundary itself is never consumed, mirrors
--- the legacy patterns' `\zs`/`\@=` lookaround).
local function find_tokens(line, tokens, boundary_ok)
  local spans = {}
  for _, token in ipairs(tokens) do
    if token ~= "" then
      local search_from = 1
      while true do
        local s, e = line:find(token, search_from, true)
        if not s then
          break
        end
        if boundary_ok(line, s - 1, e + 1) then
          spans[#spans + 1] = { s = s, e = e }
        end
        search_from = s + 1
      end
    end
  end
  return spans
end

--- Raw (unescaped), custom-marker-merged vocabulary for `type_` --
--- `markers.get_markers`'s escaping is the wrong shape for the plain
--- literal-substring search this module does (no regex engine involved),
--- so this reads `markers.lists` (the shared, already-exposed raw table)
--- directly and merges `g:awiwi_custom_<type>_markers` the same way
--- `markers.get_markers` does, rather than reimplementing marker
--- vocabularies here (DRY: builtin lists still come from `markers.lua`,
--- only the tiny custom-merge loop is duplicated because it's cheaper
--- than round-tripping through escape/unescape).
local function marker_tokens(type_)
  local tokens = {}
  for _, v in ipairs(markers.lists[type_]) do
    tokens[#tokens + 1] = v
  end
  for _, v in ipairs(vim.g["awiwi_custom_" .. type_ .. "_markers"] or {}) do
    tokens[#tokens + 1] = v
  end
  return tokens
end

local TAG_GROUPS = {
  { tag = "@change", hl = "awiwiChange" },
  { tag = "@incident", hl = "awiwiIncident" },
  { tag = "@issue", hl = "awiwiIssue" },
  { tag = "@bug", hl = "awiwiBug" },
}

local SIMPLE_MARKER_GROUPS = {
  { type_ = "todo", hl = "awiwiTodo" },
  { type_ = "question", hl = "awiwiQuestion" }, -- B3: was awiwiQuestionn
  { type_ = "onhold", hl = "awiwiOnHold" }, -- B3: was awiwiOnHole (keeps '@onhole' alias, see markers.lua)
}

--- `@@[-a-zA-Z.,+_0-9@]+[a-zA-Z0-9]` port (item 6, hardcoded, independent
--- of `markers.lua`'s `delegate` list): finds every `@@`-prefixed token
--- ending in an alphanumeric character.
local function paint_delegate(bufnr, lnum, line)
  local search_from = 1
  while true do
    local s = line:find("@@", search_from, true)
    if not s then
      return
    end
    local rest = line:match("^[%w%.,%+%-_@]+", s + 2)
    if rest then
      while #rest > 0 and not rest:sub(-1):match("%w") do
        rest = rest:sub(1, -2)
      end
      if #rest >= 2 then
        vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, s - 1, {
          end_col = s - 1 + 2 + #rest,
          hl_group = "awiwiDelegate",
        })
      end
    end
    search_from = s + 1
  end
end

--- `[[:space:]]\+\[[[:space:]]+\]\)\zs \+` / `...\[[ x]\] \)\zs \+` port
--- (item 11, "bad spaces" nag): one-or-more extra spaces right after a
--- bullet (optionally after its checkbox). Only the more specific
--- `AfterCheckbox` group is emitted when a checkbox is present (same net
--- visible span the legacy definition-order tie-break produces).
local function paint_bad_spaces(bufnr, lnum, line)
  -- NOTE: Lua patterns don't support an optional *group* (`(...)?`) the
  -- way regex does -- `?` only quantifies a single preceding character
  -- class, so `(%[[ x]%] ?)?` would actually require a literal `?` in the
  -- text and silently fail to match otherwise. Try the checkbox-inclusive
  -- shape first, falling back to the bare-bullet shape.
  local indent, bullet_ws, checkbox = line:match("^(%s*)[-*](%s+)(%[[ x]%] ?)")
  if not indent then
    indent, bullet_ws = line:match("^(%s*)[-*](%s+)")
  end
  if not indent then
    return
  end
  local prefix_len = #indent + 1 -- indent + bullet char
  if checkbox then
    -- indent + bullet + >=1 ws + checkbox(+space) already consumed; any
    -- further run of spaces right after that is the "extra" nag span.
    local consumed = prefix_len + #bullet_ws + #checkbox
    local extra = line:match("^( +)", consumed + 1)
    if extra then
      vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, consumed, {
        end_col = consumed + #extra,
        hl_group = "awiwiListBadSpacesAfterCheckbox",
      })
    end
  elseif #bullet_ws > 1 then
    -- indent + bullet + exactly one canonical space consumed; the rest of
    -- the whitespace run is "extra".
    local consumed = prefix_len + 1
    vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, consumed, {
      end_col = prefix_len + #bullet_ws,
      hl_group = "awiwiListBadSpaces",
    })
  end
end

--- `!!redacted...` (item 2, case-sensitive, deliberately NOT masked --
--- redaction is a user-typed directive that should fire even inside a
--- fenced code block someone redacted on purpose, per syn.md).
local function paint_redacted(bufnr, lnum, line)
  local s = line:find("!!redacted", 1, true)
  if not s then
    return
  end
  local tag_end = s - 1 + #"!!redacted"
  vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, s - 1, {
    end_col = #line,
    hl_group = "awiwiRedacted",
  })
  vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, s - 1, {
    end_col = tag_end,
    hl_group = "awiwiRedactedTag",
  })
  local rest = line:sub(tag_end + 1)
  local ws_s = rest:find("%s+")
  if ws_s then
    vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, tag_end + ws_s - 1, {
      end_col = #line,
      hl_group = "awiwiRedactedCause",
    })
  end
end

--- `^[^a-zA-Z0-9_]*vim: ft=[a-z].*$` port (item 31, modeline block).
--- Deliberately NOT masked -- a `vim: ft=` modeline can legitimately
--- appear inside a fenced code block (e.g. a pasted vimrc snippet), see
--- syn.md's explicit carve-out.
---
--- The leading junk (`^[^a-zA-Z0-9_]*`, e.g. an HTML comment's `<!-- `) is
--- consumed but never itself highlighted -- legacy's `awiwiFileTypePrefix`
--- match uses `\zs` to reset its match start to just after that junk, so
--- only `vim: ft=` gets `awiwiFileTypePrefix`, and `awiwiFileType` covers
--- everything from the value onward through EOL.
---
--- B-syn-new-1 (new, this transaction, fixed in port): the legacy
--- `awiwiFileTypePrefix` sub-pattern (`vim: ft?\( [a-z].*\)\@=`) requires a
--- literal `?` that never occurs in real `vim: ft=xxx` text (typo for
--- `=`), so the prefix sub-highlight was permanently dead in the shipped
--- file; restored here to the evidently intended `vim: ft=` literal match.
local function paint_modeline(bufnr, lnum, line)
  local junk, prefix, value = line:match("^([^%w_]*)(vim: ft=)(%l.*)$")
  if not prefix then
    return
  end
  local prefix_start = #junk
  local prefix_end = prefix_start + #prefix
  vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, prefix_start, {
    end_col = prefix_end,
    hl_group = "awiwiFileTypePrefix",
  })
  vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, prefix_end, {
    end_col = prefix_end + #value,
    hl_group = "awiwiFileType",
  })
end

--- `\s*{"[^}]+}$` port (item 13's `awiwiTaskDate`, `.todo`-filetype-only):
--- bare-conceals the trailing `{"..."}` metadata blob.
local function paint_task_date(bufnr, lnum, line)
  local s, e = line:find('%s*{"[^}]+}$')
  if not s then
    return
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, s - 1, {
    end_col = e,
    conceal = "",
  })
end

--- Line-local marker/redaction/redmine/modeline/bad-spaces pass (items
--- 2-7, 11, 13, 29, 31). Masked against `hi.code_line_mask` (B10 fix: the
--- legacy file highlights all of these inside fenced code blocks today)
--- except items 2 (redacted) and 31 (modeline), which have explicit
--- carve-outs in the brief.
local function paint_markers(bufnr)
  local mask = hi.code_line_mask(bufnr)
  local nlines = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, nlines, false)
  local is_todo_ft = str.endswith(vim.bo[bufnr].filetype, ".todo")
  -- item 15: the link-highlighting master switch also gates
  -- awiwiRedmineIssue (brief: "none of awiwiLink*, awiwiRedmineIssue fire").
  local highlight_links = gbool("awiwi_highlight_links", true)

  local tag_tokens = {}
  for _, g in ipairs(TAG_GROUPS) do
    tag_tokens[g.tag] = g.hl
  end

  for lnum = 0, nlines - 1 do
    local line = lines[lnum + 1]

    paint_redacted(bufnr, lnum, line)
    paint_modeline(bufnr, lnum, line)

    if not mask[lnum] then
      for _, g in ipairs(TAG_GROUPS) do
        for _, span in ipairs(find_tokens(line, { g.tag }, ws_or_edge_ok)) do
          vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, span.s - 1, {
            end_col = span.e,
            hl_group = g.hl,
          })
        end
      end

      for _, g in ipairs(SIMPLE_MARKER_GROUPS) do
        for _, span in ipairs(find_tokens(line, marker_tokens(g.type_), ws_or_edge_ok)) do
          vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, span.s - 1, {
            end_col = span.e,
            hl_group = g.hl,
          })
        end
      end

      for _, span in ipairs(find_tokens(line, marker_tokens("urgent"), word_edge_ok)) do
        vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, span.s - 1, {
          end_col = span.e,
          hl_group = "awiwiUrgent",
        })
      end

      for _, span in ipairs(find_tokens(line, marker_tokens("due"), word_edge_ok)) do
        vim.api.nvim_buf_set_extmark(bufnr, ns_markers, lnum, span.s - 1, {
          end_col = span.e,
          hl_group = "awiwiDue",
        })
      end

      paint_delegate(bufnr, lnum, line)
      paint_bad_spaces(bufnr, lnum, line)
      if highlight_links then
        paint_redmine(bufnr, lnum, line)
      end

      if is_todo_ft then
        paint_task_date(bufnr, lnum, line)
      end
    end
  end
end

-- Public lifecycle ---------------------------------------------------------

--- Full structural + line-local repaint of `bufnr`. Idempotent: clears
--- this module's namespaces first, then repaints.
function M.attach(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  M.setup_highlights()
  M.detach(bufnr)
  paint_structure(bufnr)
  paint_markers(bufnr)
  paint_links(bufnr)
end

return M
