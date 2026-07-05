local date = require("awiwi.date")

describe("date.get_today", function()
  it("matches os.date('%Y-%m-%d') at call time", function()
    eq(os.date("%Y-%m-%d"), date.get_today())
  end)
end)

describe("date.to_tuple", function()
  it("splits and parses numeric parts, no zero-padding preserved", function()
    eq({ 2024, 3, 5 }, date.to_tuple("2024-03-05"))
  end)

  it("performs no validation (dumb split+parse)", function()
    eq({ 1, 2 }, date.to_tuple("1-2"))
  end)
end)

describe("date.is_date", function()
  it("accepts a well-formed ISO date", function()
    eq(true, date.is_date("2024-03-05"))
  end)

  it("rejects a non-zero-padded month (shape check fails)", function()
    eq(false, date.is_date("2024-3-05"))
  end)

  it("accepts an out-of-range date, shape-only (B-date-1, preserved)", function()
    eq(true, date.is_date("2024-13-40"))
  end)

  it("rejects a non-date token", function()
    eq(false, date.is_date("today"))
  end)
end)

describe("date.to_iso_date", function()
  it("passes through an already-ISO date unchanged", function()
    eq("2024-03-05", date.to_iso_date("2024-03-05"))
  end)

  it("does not calendar-range-check an already-ISO date (B-date-1, preserved)", function()
    eq("2024-13-40", date.to_iso_date("2024-13-40"))
  end)

  it("parses DD.MM using the current year (B-date-2, preserved)", function()
    local this_year = os.date("%Y")
    eq(this_year .. "-03-05", date.to_iso_date("05.03"))
  end)

  it("parses DD.MM. (trailing dot) identically", function()
    local this_year = os.date("%Y")
    eq(this_year .. "-03-05", date.to_iso_date("05.03."))
  end)

  it("parses 'today'", function()
    eq(date.get_today(), date.to_iso_date("today"))
  end)

  it("parses 'yesterday'", function()
    eq(os.date("%Y-%m-%d", os.time() - 86400), date.to_iso_date("yesterday"))
  end)

  it("parses 'tomorrow'", function()
    eq(os.date("%Y-%m-%d", os.time() + 86400), date.to_iso_date("tomorrow"))
  end)

  it("parses 'in N days'", function()
    local expected = os.date("%Y-%m-%d", os.time() + 3 * 86400)
    eq(expected, date.to_iso_date("in 3 days"))
  end)

  it("parses 'in N day' (singular)", function()
    local expected = os.date("%Y-%m-%d", os.time() + 1 * 86400)
    eq(expected, date.to_iso_date("in 1 day"))
  end)

  it("parses 'N weeks ago'", function()
    local expected = os.date("%Y-%m-%d", os.time() - 3 * 7 * 86400)
    eq(expected, date.to_iso_date("3 weeks ago"))
  end)

  it("parses 'in N months' (month-field arithmetic, not fixed-day-count)", function()
    local now = os.date("*t")
    local expected_time = os.time({ year = now.year, month = now.month + 2, day = now.day, hour = 12 })
    eq(os.date("%Y-%m-%d", expected_time), date.to_iso_date("in 2 months"))
  end)

  it("parses 'next <weekday>' as strictly-future occurrence", function()
    local now = os.date("*t")
    local target = 2 -- monday
    local delta = (target - now.wday) % 7
    if delta == 0 then delta = 7 end
    local expected = os.date("%Y-%m-%d", os.time() + delta * 86400)
    eq(expected, date.to_iso_date("next monday"))
  end)

  it("parses 'last <weekday>' as strictly-past occurrence", function()
    local now = os.date("*t")
    local target = 6 -- friday
    local delta = (now.wday - target) % 7
    if delta == 0 then delta = 7 end
    local expected = os.date("%Y-%m-%d", os.time() - delta * 86400)
    eq(expected, date.to_iso_date("last friday"))
  end)

  it("throws AwiwiDateError for an unrecognized expression (no subprocess grammar)", function()
    local success, err = pcall(date.to_iso_date, "the third tuesday of never")
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError, got: " .. tostring(err))
  end)
end)

describe("date.parse_date", function()
  it("'today' resolves to get_today()", function()
    eq(date.get_today(), date.parse_date("today"))
  end)

  it("passes through an already-valid ISO date", function()
    eq("2024-03-05", date.parse_date("2024-03-05"))
  end)

  it("normalizes DD.MM shorthand", function()
    local this_year = os.date("%Y")
    eq(this_year .. "-03-05", date.parse_date("05.03"))
  end)

  it("throws AwiwiDateError for an unparseable date", function()
    local success, err = pcall(date.parse_date, "not a date at all")
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError, got: " .. tostring(err))
  end)

  it("resolves 'previous day' against an injected journal-file list, on a non-journal buffer, falling back to today", function()
    -- current test-runner buffer isn't a journal/asset page, so get_own_date()
    -- throws internally and parse_date falls back to get_today().
    local today = date.get_today()
    local files = { "2024-01-01", today }
    local success, result = pcall(date.parse_date, "previous day", { files = files })
    eq(true, success)
    eq("2024-01-01", result)
  end)

  it("aliases 'prev'/'previous'/'previous date'/'previous day' identically", function()
    local today = date.get_today()
    local files = { "2024-01-01", today }
    for _, alias in ipairs({ "prev", "previous", "previous date", "previous day" }) do
      eq("2024-01-01", date.parse_date(alias, { files = files }))
    end
  end)

  it("aliases 'next'/'next date'/'next day' identically", function()
    local today = date.get_today()
    local files = { today, "2099-01-01" }
    for _, alias in ipairs({ "next", "next date", "next day" }) do
      eq("2099-01-01", date.parse_date(alias, { files = files }))
    end
  end)
end)

describe("date.offset_date", function()
  local files = { "2024-03-01", "2024-03-05", "2024-03-10" }

  it("steps back one entry", function()
    eq("2024-03-01", date.offset_date("2024-03-05", -1, files))
  end)

  it("throws stepping before the oldest entry", function()
    local success, err = pcall(date.offset_date, "2024-03-01", -1, files)
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError")
  end)

  it("does NOT throw reaching the oldest entry from its immediate successor (B-date-3 fix)", function()
    local success, result = pcall(date.offset_date, "2024-03-05", -1, files)
    eq(true, success)
    eq("2024-03-01", result)
  end)

  it("throws stepping past the newest entry (no create_dirs escape hatch, B-date-4 dropped)", function()
    local success, err = pcall(date.offset_date, "2024-03-10", 1, files)
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError")
  end)

  it("returns the date unchanged when it's today but has no journal file yet", function()
    local today = date.get_today()
    eq(today, date.offset_date(today, -1, { "2024-01-01" }))
  end)

  it("throws 'date not found' for an unknown, non-today date", function()
    local success, err = pcall(date.offset_date, "1999-01-01", -1, files)
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError")
  end)
end)

describe("date.get_own_date", function()
  it("derives the date from a journal filename stem", function()
    eq("2024-03-05", date.get_own_date("journal/2024/03/2024-03-05.md"))
  end)

  it("derives the date from an asset page's path components", function()
    eq("2024-03-05", date.get_own_date("assets/2024/03/05/photo.md"))
  end)

  it("throws on any other buffer", function()
    local success, err = pcall(date.get_own_date, "recipes/pasta/carbonara.md")
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError")
  end)

  it("throws on an empty bufname", function()
    local success, err = pcall(date.get_own_date, "")
    eq(false, success)
    ok(date.is_date_error(err), "expected AwiwiDateError")
  end)
end)

describe("date.to_nice_date", function()
  it("formats with 'st' ordinal", function()
    eq("Fri, Mar 01st 2024", date.to_nice_date("2024-03-01"))
  end)

  it("formats with 'nd' ordinal", function()
    eq("Sat, Mar 02nd 2024", date.to_nice_date("2024-03-02"))
  end)

  it("formats with 'rd' ordinal", function()
    eq("Sun, Mar 03rd 2024", date.to_nice_date("2024-03-03"))
  end)

  it("formats 11th with 'th' ordinal", function()
    eq("Mon, Mar 11th 2024", date.to_nice_date("2024-03-11"))
  end)

  it("formats 12th with 'th' ordinal (B-date-5 fix, was '12nd')", function()
    eq("Tue, Mar 12th 2024", date.to_nice_date("2024-03-12"))
  end)

  it("formats 13th with 'th' ordinal (B-date-5 fix, was '13rd')", function()
    eq("Wed, Mar 13th 2024", date.to_nice_date("2024-03-13"))
  end)

  it("formats 21st with 'st' ordinal (mod-10 rule unaffected by the fix)", function()
    eq("Thu, Mar 21st 2024", date.to_nice_date("2024-03-21"))
  end)

  it("formats 31st with 'st' ordinal", function()
    eq("Sun, Mar 31st 2024", date.to_nice_date("2024-03-31"))
  end)
end)

describe("date.diff_days", function()
  it("positive when date1 is later than date2", function()
    eq(5, date.diff_days("2024-03-10", "2024-03-05"))
  end)

  it("zero for identical dates", function()
    eq(0, date.diff_days("2024-03-01", "2024-03-01"))
  end)

  it("negative and month-boundary-correct (2024 is a leap year, Feb has 29 days)", function()
    eq(-29, date.diff_days("2024-02-01", "2024-03-01"))
  end)
end)

describe("date.is_date_error", function()
  it("recognizes an AwiwiDateError string", function()
    eq(true, date.is_date_error("AwiwiDateError: something went wrong"))
  end)

  it("rejects an unrelated error string", function()
    eq(false, date.is_date_error("some other error"))
  end)

  it("rejects a non-string error value", function()
    eq(false, date.is_date_error({ foo = "bar" }))
  end)
end)
