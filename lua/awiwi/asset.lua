-- Create, name, link, and open "asset" files (images, drawio diagrams,
-- pasted clipboard content, arbitrary downloads) stored under
-- `<g:awiwi_home>/assets/{year}/{month}/{day}/{name}`, and insert markdown
-- links to them into the current buffer at the cursor.
--
-- Cycle break (binding, see handovers/lua-port/asset.md "Port notes"): this
-- module owns the three asset-type string constants (`M.types`). It must
-- never `require('awiwi.cmd')` — T9's `cmd.lua` reads `M.types` from here
-- instead of redefining the strings.
--
-- Ownership boundary: `insert_link_here`, `download_file`, `paste_file`,
-- `open_file`, `get_journal_file_by_date` and `get_asset_subpath` all live in
-- the not-yet-ported `awiwi.vim` façade (T10). Until that lands, this module
-- calls them through `M.deps`, a table of overridable default
-- implementations — tests stub these directly; the façade port can later
-- either leave the defaults in place or overwrite `M.deps.*` with the
-- "real"/shared versions without any call-site changes here.
--
-- Async input: `awiwi.util`'s `input(opts, on_confirm)` is callback-shaped
-- (mirrors `vim.ui.input`, see handovers/lua-port/util.md "## Ported"). Every
-- function in this module that prompts the user (`create_asset_link`, and
-- `create_asset_here_if_not_exists`/the internal `create_asset`'s `url`
-- branch, both of which sit downstream of it) is therefore callback-shaped
-- too (`on_done(...)` last argument), not synchronous-returning like the
-- vimscript original. See handovers/lua-port/asset.md "## Ported" for the
-- full signature-deviation writeup.
--
-- See handovers/lua-port/asset.md for the full behavior contract and the
-- vimscript bugs fixed/dropped in this port (B4, B5, B-new-1, B-new-2).

local pathlib = require("awiwi.path")
local date = require("awiwi.date")
local util = require("awiwi.util")

local M = {}

--- The three asset-type string constants, owned here (cycle break — see
--- module header). Values match `cmd.vim`'s existing `s:empty_asset_cmd` /
--- `s:url_asset_cmd` / `s:paste_asset_cmd` exactly; T9 must reuse this table,
--- not redefine the strings.
M.types = { empty = "empty", url = "url", paste = "paste" }

--- Overridable dependencies owned by the not-yet-ported `awiwi.vim` façade
--- (T10) — see module header. Defaults are minimal, standalone-usable
--- implementations, not full ports of the façade's richer behavior (e.g.
--- `open_file`'s split/tab/anchor options); override in tests or once T10
--- lands.
M.deps = {}

function M.deps.get_asset_subpath()
  return pathlib.join(vim.g.awiwi_home, "assets")
end

function M.deps.get_journal_file_by_date(date_expr)
  local parsed = date.parse_date(date_expr)
  local parts = vim.split(parsed, "-", { plain = true })
  return pathlib.join(vim.g.awiwi_home, "journal", parts[1], parts[2], parsed .. ".md")
end

--- Minimal default `insert_link_here`: inserts `link` at the cursor in the
--- current line (with a leading space if the cursor sits on a non-space
--- character, and a trailing space), byte-faithful port of the vimscript
--- original's `getcurpos`/`getline`/`setline`/`setpos` dance.
function M.deps.insert_link_here(link)
  local win = 0
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, ccol = cursor[1], cursor[2]
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, ccol + 1)
  local ch = line:sub(ccol + 1, ccol + 1)
  local after = line:sub(ccol + 2)
  local sep = (ch ~= "" and not ch:match("%s")) and " " or ""
  vim.api.nvim_set_current_line(before .. sep .. link .. " " .. after)
  vim.api.nvim_win_set_cursor(win, { row, #before + #sep + #link + 1 })
end

--- Minimal default `download_file`: `curl --no-progress-meter <url> -o <path>`
--- via `vim.system` (not `jobstart`/`system()` — per the plan's idiom table).
function M.deps.download_file(path, url)
  local result = vim.system({ "curl", "--no-progress-meter", url, "-o", path }, { text = true }):wait()
  if result.code ~= 0 then
    vim.api.nvim_err_writeln(
      ('[ERROR] could not download "%s" to "%s": %s'):format(url, path, vim.trim(result.stderr or ""))
    )
    return false
  end
  return true
end

local MIME_PROBE_ORDER = { "text/plain", "image/jpg", "image/png", "image/gif", "image/bmp" }

--- Probes the X clipboard's MIME type by piping `xclip -o -t <mime>` into
--- `file --mime-type -`, trying each candidate in order and stopping at the
--- first one that isn't reported "empty". Linux/X11-only (`xclip`), no
--- Wayland/macOS fallback — preserved as-is from the vimscript original per
--- the brief's Port notes (a cross-platform clipboard would be a feature
--- add, not a port).
local function guess_selection_mime_type()
  for _, mime in ipairs(MIME_PROBE_ORDER) do
    local xclip = vim.system({ "xclip", "-selection", "clipboard", "-o", "-t", mime }, { text = true }):wait()
    local sniff =
      vim.system({ "file", "--mime-type", "-" }, { text = true, stdin = xclip.stdout or "" }):wait()
    local mime_type = vim.trim(sniff.stdout or ""):match("(%S+)%s*$")
    if mime_type and not mime_type:find("empty", 1, true) then
      return mime_type
    end
  end
  return ""
end

--- Minimal default `paste_file`: guesses the clipboard MIME type, then pipes
--- `xclip -o` for that type straight into `path` (two `vim.system` calls,
--- not the vimscript original's shell-redirection string join).
function M.deps.paste_file(path)
  local mime = guess_selection_mime_type()
  if mime == "" then
    vim.api.nvim_err_writeln("[ERROR] cannot guess mime-type from selection")
    return false
  end
  local xclip = vim.system({ "xclip", "-selection", "clipboard", "-t", mime, "-o" }, { text = true }):wait()
  if xclip.code ~= 0 then
    vim.api.nvim_err_writeln(('[ERROR] could not paste to "%s"'):format(path))
    return false
  end
  local f = io.open(path, "w")
  if not f then
    vim.api.nvim_err_writeln(('[ERROR] could not paste to "%s"'):format(path))
    return false
  end
  f:write(xclip.stdout or "")
  f:close()
  return true
end

--- Minimal default `open_file`: just `:edit`s `path`. The vimscript
--- original's richer split/tab/anchor/xdg-open option handling belongs to
--- the façade port (T10, `awiwi#open_file`) — see module header.
function M.deps.open_file(path, _opts)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

--- `date` MUST already be in canonical `YYYY-MM-DD` form (no parsing here —
--- see `awiwi.date`). Pure otherwise (except reading `M.deps.get_asset_subpath`,
--- which itself only reads config). Throws `AwiwiAssetError` if `date`
--- doesn't split into exactly 3 `-`-separated parts, mirroring the vimscript
--- original's list-destructure `E687`/`E688` errors.
function M.get_asset_path(date_str, name)
  local parts = vim.split(date_str, "-", { plain = true })
  if #parts ~= 3 then
    error(("AwiwiAssetError: malformed date %q"):format(date_str), 0)
  end
  return pathlib.join(M.deps.get_asset_subpath(), parts[1], parts[2], parts[3], name)
end

--- Derives the default filename slugification: lower-cases runs of uppercase
--- letters, collapses whitespace runs to `-`, then strips runs of characters
--- outside `[-a-z0-9.:+]`. NOT a generic slugify — preserved exactly from the
--- vimscript original's 3-stage `substitute()` chain (does not touch
--- already-lowercase symbols like `_`, does not collapse repeated `-`, does
--- not trim leading/trailing `-`).
local function derive_default_filename(name)
  local lowered = name:gsub("%u+", string.lower)
  local dashed = lowered:gsub("%s+", "-")
  return (dashed:gsub("[^%-a-z0-9.:+]+", ""))
end

--- Backslash-escapes `[` and `]` in `name`, for use in markdown link text
--- only (the returned `name` elsewhere stays unescaped).
local function escape_link_text(name)
  return (name:gsub("([%[%]])", "\\%1"))
end

--- Prompts for (or reads from `opts.name`) an asset name, then (unless the
--- user aborts) a default-filled filename, and builds a relative markdown
--- link for it. `on_done(name, filename, link_text)` — all three `''` if the
--- user aborted either prompt (the "user aborted" sentinel used throughout
--- this module).
---
--- Callback-shaped (see module header) because `util.input` is: this
--- function's two prompts are the one genuinely *sequential* case in the
--- module (prompt #2's default depends on prompt #1's answer), so it nests
--- one `on_confirm` inside the other.
function M.create_asset_link(opts, on_done)
  opts = opts or {}
  on_done = on_done or function() end

  local function aborted()
    vim.api.nvim_echo({ { "[INFO] no asset created" } }, false, {})
    on_done("", "", "")
  end

  local function with_name(name)
    if name == nil or name == "" then
      aborted()
      return
    end

    local default_suffix = opts.suffix or ""
    local default_filename = derive_default_filename(name) .. default_suffix

    util.input({ prompt = "asset file: ", default = default_filename }, function(filename)
      if filename == nil or filename == "" then
        aborted()
        return
      end

      local own_date = date.get_own_date()
      local asset_file = M.get_asset_path(own_date, filename)
      local rel_path = util.relativize(asset_file, vim.api.nvim_buf_get_name(0))
      local link_text = ("[%s](%s)"):format(escape_link_text(name), rel_path)
      on_done(name, filename, link_text)
    end)
  end

  local name = opts.name or ""
  if name == "" then
    util.input({ prompt = "asset name: " }, with_name)
  else
    with_name(name)
  end
end

--- `true` iff `filename` matches `\.(jpe?g|gif|png|bmp)$` — case-sensitive,
--- no `i`/`\c` flag, so e.g. `.JPG` does NOT match. Preserved exactly (this
--- is a "load-bearing edge case", not a bug — see the brief's Bugs section).
local function is_image_filename(filename)
  return filename:match("%.jpe?g$") ~= nil
    or filename:match("%.gif$") ~= nil
    or filename:match("%.png$") ~= nil
    or filename:match("%.bmp$") ~= nil
end

local function ensure_dir(dir)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- `20`-ish-character alphanumeric random string, pure Lua (B4's `pyx`/
--- `pyxeval` round-trip is dropped entirely — see Port notes). No entropy/
--- charset contract is preserved from the vimscript original (it never had a
--- meaningful one — see B4's base64-newline-leakage note); this is a clean
--- `length`-character draw from `[A-Za-z0-9]`, freshly generated on every
--- call (not "once per session" — that laziness was bug B4, not a feature).
local RANDOM_CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
math.randomseed(os.time())

local function get_random_string(length)
  local chars = {}
  for i = 1, length do
    local idx = math.random(1, #RANDOM_CHARSET)
    chars[i] = RANDOM_CHARSET:sub(idx, idx)
  end
  return table.concat(chars)
end

-- Single-page drawio diagram body (deflate+base64-encoded XML, drawio's own
-- storage format) — copied verbatim from the vimscript original; only the
-- `id` attribute is freshly randomized per call now (B4 fix).
local DRAWIO_PAGE_DATA = "ddHNEoIgEADgp+GOUk53s7p08tCZkU2YQddBGqmnTwfIGOvE8u3C8kNY2bmz4YO8ogBNciocYUeS51lRZPOwyNPLYb/z0BolQtEKtXpBQBr0oQSMSaFF1FYNKTbY99DYxLgxOKVld9Rp14G3sIG64XqrNyWsjLegq19AtTJ2zmjIdDwWBxglFzh9EasIKw2i9VHnStDL48V38etOf7Kfgxno7Y8Fc7DuPU+SH2LVGw=="

local function get_file_template(extension)
  if extension == "drawio" then
    return {
      '<mxfile host="Electron" type="device">',
      ('<diagram id="%s" name="Page-1">'):format(get_random_string(20)),
      DRAWIO_PAGE_DATA,
      "</diagram>",
      "</mxfile>",
    }
  end
  return {}
end

local function write_lines(path, lines)
  local f, err = io.open(path, "w")
  if not f then
    error(("AwiwiAssetError: could not write file %q: %s"):format(path, tostring(err)), 0)
  end
  if #lines > 0 then
    f:write(table.concat(lines, "\n"), "\n")
  end
  f:close()
end

--- Ensures `path`'s parent directory exists, then dispatches on `type_`:
--- `empty` writes a template (drawio skeleton, or an empty file for any
--- other extension); `url` prompts for a URL and downloads it; `paste`
--- pastes the X clipboard; anything else is a no-op "success". `on_done(ok)`
--- — callback-shaped because the `url` branch prompts via `util.input`.
local function create_asset(type_, path, on_done)
  ensure_dir(vim.fs.dirname(path))
  if type_ == M.types.empty then
    local extension = path:match("%.([^./]+)$") or ""
    write_lines(path, get_file_template(extension))
    on_done(true)
  elseif type_ == M.types.url then
    util.input({ prompt = "url: " }, function(url)
      if url == nil or url == "" then
        on_done(false)
        return
      end
      on_done(M.deps.download_file(path, url))
    end)
  elseif type_ == M.types.paste then
    on_done(M.deps.paste_file(path))
  else
    on_done(true)
  end
end

--- Creates (if it doesn't already exist) an asset of `type` (one of
--- `M.types.*`) under the current buffer's own date
--- (`awiwi.date.get_own_date()` — throws if the buffer isn't a journal/asset
--- page), inserts a markdown link to it at the cursor, and reports the
--- resulting filename via `on_done(filename)`.
---
--- `on_done(filename)`: `filename` is `''` if the user aborted naming (see
--- `create_asset_link`'s sentinel), `nil` if asset creation itself failed
--- (mirrors the vimscript original's `echoerr` + bare `return`), or the
--- actual filename on success.
---
--- If `filename` matches an image extension (`is_image_filename`), the
--- inserted link is overwritten with an absolute embed
--- (`![name](/assets/{date}/{filename})`, `date` re-evaluated at this point)
--- instead of `create_asset_link`'s relative link.
---
--- Deviation from the vimscript original: when the user aborts naming
--- (`create_asset_link`'s `''` sentinel), this short-circuits immediately
--- after inserting the (empty) link, rather than continuing on to compute
--- `get_asset_path`/`get_own_date`/`create_asset` with an empty filename (an
--- unflagged latent quirk of the original, not covered by any brief bug
--- entry or contract item — see handovers/lua-port/asset.md "## Ported" for
--- the full note). This keeps the "aborted" sentinel meaning the same thing
--- everywhere in the module.
function M.create_asset_here_if_not_exists(type_, opts, on_done)
  opts = opts or {}
  on_done = on_done or function() end

  if type_ == M.types.paste then
    opts.suffix = ".png"
  end

  M.create_asset_link(opts, function(name, filename, link)
    if filename == "" then
      M.deps.insert_link_here(link)
      on_done(filename)
      return
    end

    local own_date = date.get_own_date()
    local path = M.get_asset_path(own_date, filename)

    local function finish()
      if is_image_filename(filename) then
        local embed_date = date.get_own_date()
        link = ("![%s](/assets/%s/%s)"):format(name, embed_date, filename)
      end
      M.deps.insert_link_here(link)
      on_done(filename)
    end

    if vim.fn.filereadable(path) == 1 then
      finish()
      return
    end

    create_asset(type_, path, function(created_ok)
      if not created_ok then
        vim.api.nvim_err_writeln(('[ERROR] could not create asset "%s"'):format(filename))
        on_done(nil)
        return
      end
      vim.api.nvim_echo({ { ("asset %s created"):format(filename) } }, false, {})
      finish()
    end)
  end)
end

--- The path of the journal file directly above the current buffer, assumed
--- to be an asset page (`.../assets/{year}/{month}/{day}/{file}`). No
--- existence check — the returned path may not exist on disk.
function M.get_journal_for_current_asset()
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h")
  local parts = pathlib.split(dir)
  local n = #parts
  local date_str = table.concat({ parts[n - 2], parts[n - 1], parts[n] }, "-")
  return M.deps.get_journal_file_by_date(date_str)
end

--- Inserts a markdown link to asset `name` (dated `date_str`) at the cursor.
--- `opts.anchor`, if non-empty, adds an in-page fragment to both the link
--- text and target.
function M.insert_asset_link(date_str, name, opts)
  opts = opts or {}
  local path = util.relativize(M.get_asset_path(date_str, name))
  local anchor = opts.anchor or ""
  local link
  if anchor == "" then
    link = ("[asset %s, %s](%s)"):format(name, date_str, path)
  else
    link = ("[asset %s: %s, %s](%s#%s)"):format(name, anchor, date_str, path, anchor)
  end
  M.deps.insert_link_here(link)
end

--- Opens asset `name` under the current buffer's own date
--- (`awiwi.date.get_own_date()` — throws if not on a journal/asset page).
function M.open_asset(name, opts)
  local own_date = date.get_own_date()
  M.open_asset_by_name(own_date, name, opts)
end

--- Opens (or creates) asset `name` dated `date_expr` (any form
--- `awiwi.date.parse_date` accepts — `'today'`, `'prev'`, an ISO date, ...).
--- Ensures the parent directory exists, then delegates to `M.deps.open_file`.
---
--- B-new-1 fix (binding): the vimscript original unconditionally ran a bare
--- `write` after opening, on *every* call — silently creating an empty file
--- even for a pure "open existing asset" call, and erroring on a read-only/
--- `nomodifiable` existing asset. Fixed here: `write` only runs when the
--- asset did **not** already exist before this call (i.e. opening an
--- existing asset never rewrites it; creating a new one via `open_asset*` is
--- now an explicit, conditional write, not a silent unconditional one).
--- This is a user-visible behavior change — flagged for
--- `docs/decisions.md` per the brief.
function M.open_asset_by_name(date_expr, name, opts)
  opts = opts or {}
  local date_str = date.parse_date(date_expr)
  local path = M.get_asset_path(date_str, name)
  ensure_dir(vim.fs.dirname(path))
  local existed_before = vim.fn.filereadable(path) == 1
  M.deps.open_file(path, opts)
  if not existed_before then
    vim.cmd("write")
  end
end

--- Resolves an `image`-type link `target` to its on-disk asset path, iff
--- `target` is an absolute filesystem path whose parent directory component
--- is a `YYYY-MM-DD` date (e.g. `/assets/2024-03-05/pic.png` or
--- `/x/2024-03-05/pic.png`) — returns
--- `M.deps.get_asset_subpath()/2024/03/05/pic.png`. Returns `nil` for
--- anything else: relative targets (no leading `/`), `http(s)://` URLs, or
--- absolute targets whose parent directory isn't a `YYYY-MM-DD` date (e.g.
--- `/tmp/pic.png`).
---
--- Pure: no side effects, no filesystem access, no `vim.g` reads — goes
--- through `M.deps.get_asset_subpath()` like every other path builder in
--- this module (mirrors the join pattern at `M.get_asset_path`).
function M.resolve_image_link(target)
  if not pathlib.is_absolute(target) then
    return nil
  end
  local dir = vim.fn.fnamemodify(target, ":h:t")
  local y, m, d = dir:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then
    return nil
  end
  local fname = vim.fn.fnamemodify(target, ":t")
  return pathlib.join(M.deps.get_asset_subpath(), y, m, d, fname)
end

--- fzf/telescope-picker sink shape: `expr` is `"date:name"`. Currently only
--- wired in a commented-out fzf sink (dead in the shipped binary today) —
--- kept live per the brief, it becomes T9's telescope-picker sink callback.
function M.open_asset_sink(expr)
  local parts = vim.split(expr, ":", { plain = true })
  if #parts ~= 2 then
    error(("AwiwiAssetError: malformed asset sink expr %q"):format(expr), 0)
  end
  M.open_asset_by_name(parts[1], parts[2])
end

--- All asset files under `<g:awiwi_home>/assets/2*/**`, sorted ascending by
--- date then name (plain lexicographic string compare — correct for
--- zero-padded `Y-M-D`, not locale-aware).
---
--- B-new-2 fix: uses `M.deps.get_asset_subpath()` (like every other function
--- in this module) instead of hardcoding `g:awiwi_home .. 'assets'` directly
--- in the glob pattern (the two were always value-identical, so this is a
--- non-behavior-changing consistency fix, not an ADR item).
function M.get_all_asset_files()
  local pattern = pathlib.join(M.deps.get_asset_subpath(), "2*", "**")
  local matches = vim.fn.glob(pattern, false, true)
  local files = {}
  for _, m in ipairs(matches) do
    if vim.fn.filereadable(m) == 1 then
      local parts = vim.split(m, "/", { plain = true, trimempty = true })
      local n = #parts
      files[#files + 1] = {
        date = table.concat({ parts[n - 3], parts[n - 2], parts[n - 1] }, "-"),
        name = parts[n],
      }
    end
  end
  table.sort(files, function(a, b)
    if a.date ~= b.date then
      return a.date < b.date
    end
    return a.name < b.name
  end)
  return files
end

return M
