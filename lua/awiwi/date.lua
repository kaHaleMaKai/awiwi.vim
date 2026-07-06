-- Parse, normalize, validate the plugin's canonical `YYYY-MM-DD` date
-- string; resolve the special tokens `today`/`prev`/`next` (and aliases)
-- against a caller-supplied list of journal-file dates; format a date for
-- human display; diff two calendar dates.
--
-- No subprocess (`os.date`/`os.time` only, per ADR — see
-- handovers/lua-port/date.md "Port notes" and docs/decisions.md). The
-- vimscript original shelled out to GNU `date --date <expr>` for free-form
-- relative-date parsing; this port hand-writes a small parser instead (see
-- `to_iso_date` below for the exact supported grammar).
--
-- See handovers/lua-port/date.md for the full behavior contract and the
-- vimscript bugs fixed/preserved in this port (B-date-1..5).

local path = require("awiwi.path")

local M = {}

--- Injection seam for the ascending journal-file-date list `prev`/`next`
--- resolution needs (see `offset_date`). The façade wires this to
--- `awiwi.get_all_journal_files` at bootstrap; the default keeps this
--- module filesystem-free (only "today has no journal file yet" resolves).
--- T10.1 dogfood fix: without this seam every `parse_date` caller had to
--- pass `options.files`, and none did — `:Awiwi journal previous` threw.
M.deps = {
  journal_dates = function()
    return {}
  end,
}

local WEEKDAYS = {
  sunday = 1,
  monday = 2,
  tuesday = 3,
  wednesday = 4,
  thursday = 5,
  friday = 6,
  saturday = 7,
}

--- Build (does not throw) the `'AwiwiDateError: ...'`-prefixed message and
--- immediately `error()`s it at level 0 (no "file:line:" prefix), mirroring
--- the vimscript `throw s:AwiwiDateError(...)` convention closely enough
--- that `pcall` + `err:match('^AwiwiDateError:')` still works for the one
--- external catch site (`autoload/awiwi.vim`, to be ported later).
local function date_error(msg, ...)
  if select("#", ...) > 0 then
    msg = msg:format(...)
  end
  error("AwiwiDateError: " .. msg, 0)
end

--- True iff `err` (as caught by `pcall`) is one of this module's errors.
function M.is_date_error(err)
  return type(err) == "string" and err:match("^AwiwiDateError:") ~= nil
end

--- Today's date, ISO `YYYY-MM-DD`, local TZ/clock. No arguments, no errors.
function M.get_today()
  return os.date("%Y-%m-%d")
end

--- Dumb `split('-') + tonumber()` — no validation, works on any hyphen-
--- delimited numeric string, not just dates. `is_date` is the real
--- validator; keep this shallow (nothing downstream relies on it rejecting
--- malformed input).
function M.to_tuple(date)
  local parts = vim.split(date, "-", { plain = true })
  local result = {}
  for i, v in ipairs(parts) do
    result[i] = tonumber(v)
  end
  return result
end

--- Shape-only check: `^\d{4}-\d{2}-\d{2}$`, full-string anchored. Does not
--- validate month 1-12 or day-of-month range — `is_date("2024-13-40")` is
--- `true`. Preserved as-is (B-date-1): call sites rely only on the shape
--- check to distinguish "single date" from other filter expressions.
function M.is_date(s)
  return s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

--- Add `n` days to a Y/M/D triple via `os.time`/`os.date` (handles month and
--- year rollover, leap years, correctly — no hand-rolled calendar table).
--- `hour = 12` (noon) is set deliberately, never `0`: `os.time` defaults the
--- hour to 12 when omitted too, but pinning it explicitly documents *why* —
--- using midnight would risk an off-by-one day around DST transitions.
local function shift_days(y, m, d, n)
  local t = os.time({ year = y, month = m, day = d, hour = 12 }) + n * 86400
  local dt = os.date("*t", t)
  return dt.year, dt.month, dt.day
end

--- Add `n` months (or `n` weeks, as `7*n` days) to a Y/M/D triple.
--- `unit` is already singularized ("day"/"week"/"month").
local function shift_unit(y, m, d, n, unit)
  if unit == "day" then
    return shift_days(y, m, d, n)
  elseif unit == "week" then
    return shift_days(y, m, d, n * 7)
  elseif unit == "month" then
    local t = os.time({ year = y, month = m + n, day = d, hour = 12 })
    local dt = os.date("*t", t)
    return dt.year, dt.month, dt.day
  end
  return nil
end

--- Nearest `weekday` strictly in the `dir` ("next"/"last") direction from
--- Y/M/D — never today itself, matching GNU `date`'s "next monday" grammar.
local function shift_weekday(y, m, d, weekday, dir)
  local target = WEEKDAYS[weekday]
  local cur_wday = os.date("*t", os.time({ year = y, month = m, day = d, hour = 12 })).wday
  if dir == "next" then
    local delta = (target - cur_wday) % 7
    if delta == 0 then
      delta = 7
    end
    return shift_days(y, m, d, delta)
  else
    local delta = (cur_wday - target) % 7
    if delta == 0 then
      delta = 7
    end
    return shift_days(y, m, d, -delta)
  end
end

--- Hand-written relative-date grammar (Option A from the port brief):
--- `today`/`yesterday`/`tomorrow`, `in N day(s)/week(s)/month(s)`,
--- `N day(s)/week(s)/month(s) ago`, and `next|last <weekday>`. This is
--- deliberately the small subset of GNU `date --date`'s natural-language
--- grammar that the plugin's call sites actually exercise (see the brief's
--- Call sites section) — not a general-purpose parser. Returns `y, m, d`
--- numbers, or `nil` if `expr` matches none of the above.
local function parse_relative(expr, today)
  local low = expr:lower()
  local y, m, d = today.year, today.month, today.day

  if low == "today" then
    return y, m, d
  elseif low == "yesterday" then
    return shift_days(y, m, d, -1)
  elseif low == "tomorrow" then
    return shift_days(y, m, d, 1)
  end

  local n, unit = low:match("^in%s+(%d+)%s+(%a+)$")
  if n then
    return shift_unit(y, m, d, tonumber(n), (unit:gsub("s$", "")))
  end

  n, unit = low:match("^(%d+)%s+(%a+)%s+ago$")
  if n then
    return shift_unit(y, m, d, -tonumber(n), (unit:gsub("s$", "")))
  end

  local dir, weekday = low:match("^(next)%s+(%a+)$")
  if not dir then
    dir, weekday = low:match("^(last)%s+(%a+)$")
  end
  if dir and WEEKDAYS[weekday] then
    return shift_weekday(y, m, d, weekday, dir)
  end

  return nil
end

--- Normalize free-form input to `YYYY-MM-DD`. Three branches, tried in
--- order:
--- 1. Already ISO-shaped (`is_date`) -> returned unchanged, no calendar-range
---    check (B-date-1, preserved).
--- 2. `DD.MM` or `DD.MM.` -> `<current-year>-MM-DD`; the year is always
---    *today's* year at call time, never inferred from context such as the
---    journal buffer being viewed (B-date-2, preserved intentional
---    shorthand/limitation).
--- 3. Otherwise, the hand-written relative-date grammar in `parse_relative`
---    (`today`/`yesterday`/`tomorrow`/`in N <unit>`/`N <unit> ago`/
---    `next|last <weekday>`). Anything that matches none of these throws
---    `AwiwiDateError` (no subprocess, no GNU `date` natural-language
---    grammar — see module header).
function M.to_iso_date(date)
  if M.is_date(date) then
    return date
  end

  local day, month = date:match("^(%d%d)%.(%d%d)%.?$")
  if day then
    local year = os.date("%Y")
    return string.format("%s-%s-%s", year, month, day)
  end

  local y, m, d = parse_relative(date, os.date("*t"))
  if y then
    return string.format("%04d-%02d-%02d", y, m, d)
  end

  date_error("%s is not a valid date", date)
end

--- "prev"/"next" journal-file-list navigation (NOT calendar arithmetic —
--- see module header). `files` is a caller-supplied, ascending-sorted list
--- of `YYYY-MM-DD` journal-file dates (dependency-injected: this module has
--- no knowledge of the filesystem or the facade's `get_all_journal_files`).
---
--- B-date-3 fix: the backward-boundary check is `idx + offset < 0` (0-based),
--- not `<= 0` — the old `<=` made the *oldest* journal file unreachable via
--- "previous" from its immediate successor.
--- B-date-4 fix: the dead `create_dirs` forward-boundary escape hatch is
--- dropped; hitting the forward boundary always throws.
function M.offset_date(date, offset, files)
  files = files or {}
  local idx0 -- 0-based index of `date` in `files`, matching the vimscript's own indexing
  for i, f in ipairs(files) do
    if f == date then
      idx0 = i - 1
      break
    end
  end

  if not idx0 then
    if M.get_today() == date then
      return date
    end
    date_error("date %s not found", date)
  elseif offset <= 0 and idx0 + offset < 0 then
    date_error("no date found before %s", date)
  elseif offset >= 0 and idx0 + offset >= #files then
    date_error("no date found after %s", date)
  end

  return files[idx0 + offset + 1]
end

--- Entry point turning any user-supplied date expression into a canonical
--- ISO string. `options.files`, if given, is the ascending journal-file-date
--- list needed to resolve `prev`/`next` (dependency injection — see
--- `offset_date`; defaults to `{}`, meaning only "today has no journal file
--- yet" is resolvable and any other prev/next throws).
---
--- `'today'` -> `get_today()`.
--- `'prev'|'previous'|'previous date'|'previous day'` -> the journal file
--- immediately before the current buffer's own date (`get_own_date()`); if
--- the buffer isn't a journal/asset page, falls back to relative-to-
--- `get_today()` instead.
--- `'next'|'next date'|'next day'` -> mirror, `+1`.
--- Anything else -> `to_iso_date(x)`, validated with `is_date`; throws if
--- the result isn't ISO-shaped.
function M.parse_date(date, options)
  options = options or {}
  local files = options.files or M.deps.journal_dates()

  if date == "today" then
    return M.get_today()
  elseif date == "prev" or date == "previous" or date == "previous date" or date == "previous day" then
    local ok, own_date = pcall(M.get_own_date)
    return M.offset_date(ok and own_date or M.get_today(), -1, files)
  elseif date == "next" or date == "next date" or date == "next day" then
    local ok, own_date = pcall(M.get_own_date)
    return M.offset_date(ok and own_date or M.get_today(), 1, files)
  end

  local normalized = M.to_iso_date(date)
  if not M.is_date(normalized) then
    date_error("%s is not a valid date", normalized)
  end
  return normalized
end

--- The date the current buffer (or `bufname`, if given — defaults to
--- `vim.api.nvim_buf_get_name(0)`) is "about": the filename stem if it's
--- already a valid date (journal file `YYYY-MM-DD.md`), else the 4th-from-
--- last through 2nd-from-last path components joined with `-` (asset page
--- `assets/YYYY/MM/DD/name.md`). Throws `AwiwiDateError` on any other
--- buffer.
function M.get_own_date(bufname)
  bufname = bufname or vim.api.nvim_buf_get_name(0)

  local stem = vim.fn.fnamemodify(bufname, ":t:r")
  if M.is_date(stem) then
    return stem
  end

  local parts = path.split(bufname)
  local n = #parts
  if n >= 4 then
    local candidate = table.concat({ parts[n - 3], parts[n - 2], parts[n - 1] }, "-")
    if M.is_date(candidate) then
      return candidate
    end
  end

  date_error("not on journal or asset page")
end

--- Ordinal suffix for a day-of-month number. B-date-5 fix: checks
--- `day % 100` against `{11, 12, 13}` for the `th` exception (the vimscript
--- original only special-cased the literal string `"11"`, so `"12"`/`"13"`
--- wrongly fell through to the `day % 10` rule and got `nd`/`rd`).
local function ordinal_suffix(day)
  local mod100 = day % 100
  if mod100 == 11 or mod100 == 12 or mod100 == 13 then
    return "th"
  end
  local mod10 = day % 10
  if mod10 == 1 then
    return "st"
  elseif mod10 == 2 then
    return "nd"
  elseif mod10 == 3 then
    return "rd"
  end
  return "th"
end

--- Human-display formatting, e.g. `"2024-03-05"` -> `"Tue, Mar 05th 2024"`.
--- Weekday/month names come from `os.date`'s current C-locale (effectively
--- always `"C"`/English under Neovim, which does not call
--- `setlocale(LC_TIME, "")`) rather than the vimscript original's shelled-
--- out `date` binary honoring the user's `$LC_TIME` — an intentional,
--- deterministic behavior change (see handovers/lua-port/date.md Port
--- notes); no subprocess needed.
function M.to_nice_date(date)
  local t = M.to_tuple(date)
  local y, m, d = t[1], t[2], t[3]
  local ord = ordinal_suffix(d)
  local when = os.time({ year = y, month = m, day = d, hour = 12 })
  return os.date("%a, %b %d", when) .. ord .. os.date(" %Y", when)
end

--- Whole-day difference `date1 - date2` (new: not in the vimscript source).
--- Positive means `date1` is later than `date2`. DST-safe: both timestamps
--- are built with `hour = 12` (noon), never midnight, so a DST transition
--- can't shift either side across a day boundary. Added specifically so
--- `hi.lua` (T6a) can call this instead of building a `luaeval()` Lua-
--- source string to reach `os.time` from vimscript.
function M.diff_days(date1, date2)
  local t1 = M.to_tuple(date1)
  local t2 = M.to_tuple(date2)
  local a = os.time({ year = t1[1], month = t1[2], day = t1[3], hour = 12 })
  local b = os.time({ year = t2[1], month = t2[2], day = t2[3], hour = 12 })
  return math.floor((a - b) / 86400 + 0.5)
end

return M
