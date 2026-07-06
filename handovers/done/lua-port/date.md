# lua-port / date

**Responsibility:** Parse, normalize, and validate the plugin's canonical `YYYY-MM-DD` date
string; resolve the special tokens `today`/`prev`/`next` (and their aliases) against the current
buffer's own date and the set of journal files that exist on disk; format a date for human display.
No calendar math is actually shipped (dead code below) — "previous"/"next" day is journal-*file*
navigation, not calendar-day arithmetic.

**Public surface** (`autoload/awiwi/date.vim`, 168 lines — matches `docs/architecture.md` row):

- `awiwi#date#get_today() -> string` — today's date, `strftime('%F')` (ISO `YYYY-MM-DD`, local TZ,
  local clock, no args). No errors.
- `awiwi#date#to_tuple(date: string) -> [number, number, number]` — `split(date, '-')` then
  `str2nr()` each part. **No validation**: works on any hyphen-delimited numeric string, not just
  valid dates; wrong number of `-`-separated fields returns a shorter/longer list, not an error.
- `awiwi#date#parse_date(date: string, options?: dict) -> string` — the main entry point every
  caller in the codebase uses to turn a user-supplied date argument into a canonical ISO string.
  `options.create_dirs` (bool, default `false`) is accepted but see Bug B-date-4 — it is never
  actually reachable from any shipped call site.
  - `'today'` -> `get_today()`.
  - `'prev' | 'previous' | 'previous date' | 'previous day'` -> journal-file-based previous date
    relative to the *current buffer's own date* (`get_own_date()`); if the buffer isn't a journal/
    asset page (`get_own_date()` throws), falls back to relative-to-`get_today()` instead. Throws
    `AwiwiDateError` if there is no earlier journal file (see boundary bug B-date-3).
  - `'next' | 'next date' | 'next day'` -> mirror of the above, offset `+1`.
  - anything else -> `to_iso_date(date)`, then re-validated with `is_date()`; throws
    `AwiwiDateError('%s is not a valid date', date)` if the normalized result doesn't match the
    ISO shape.
  - Note: `'yesterday'` / `'tomorrow'` are **not** special-cased here even though
    `awiwi#get_all_journal_files({'include_literals': v:true})` advertises `'previous day'`,
    `'next day'`, `'today'` as completion literals (it does **not** list `'yesterday'`/`'tomorrow'`).
    Typing `yesterday`/`tomorrow` still works, but only because it falls through to
    `to_iso_date`'s third branch (shells to GNU `date`), which is calendar-arithmetic, NOT
    journal-file navigation — i.e. `prev`/`next` and `yesterday`/`tomorrow` are two different,
    inconsistent navigation semantics that happen to overlap in casual usage. Document, don't
    silently unify, unless an ADR says so.
- `awiwi#date#to_iso_date(date: string) -> string` — normalizes free-form input to `YYYY-MM-DD`.
  Three branches, tried in order:
  1. Already `^\d{4}-\d{2}-\d{2}$` -> returned unchanged (no calendar-range check — see B-date-1).
  2. `^\d{2}\.\d{2}\.?$` (`DD.MM` or `DD.MM.`) -> `YYYY-MM-DD` with `YYYY` = **current** year
     (`strftime('%Y')`) — the year is always "now", never the year of the journal you're currently
     viewing. Intentional shorthand, but a real limitation for cross-year linking; see B-date-2.
  3. Anything else -> rewrites the standalone word `in` (followed by a space or digit) to `+`
     (`in 3 days` -> ` + 3 days`), then shells out: `systemlist(['date', '--date', date, '+%F'])[0]`.
     This is GNU `date`'s full natural-language relative-date parser (`next monday`, `3 weeks ago`,
     `yesterday`, `tomorrow`, `2 days`, ISO strings with time, etc.) — **not** reproducible with
     `os.date`/`os.time` alone without writing a bespoke parser. See Port notes.
- `awiwi#date#get_own_date() -> string` — derives the "date this buffer is about" from the current
  buffer: `expand('%:t:r')` (filename stem) if that's already a valid date (journal file
  `YYYY-MM-DD.md`); else the 3 path components 4th-from-last through 2nd-from-last of the full path
  joined with `-` (asset page `assets/YYYY/MM/DD/name.md` -> `YYYY-MM-DD`), via
  `awiwi#path#split(expand('%:p'))[-4:-2]`. Throws `AwiwiDateError('not on journal or asset page')`
  if neither shape matches. **Reads the current buffer's path** — not a pure function of any
  argument; depends on Vim buffer-local state (`%`).
- `awiwi#date#to_nice_date(date: string) -> string` — human-readable form, e.g. `Wed, Mar 05th
  2024`. Splits `date` on `-`, computes an English ordinal suffix for the day, then shells out:
  `systemlist(['date', '--date', a:date, '+%a, %b %d' . ord . ' %Y'])[0]`. Weekday/month names and
  their capitalization/locale come from the system `date` binary's `LC_TIME` at call time — not a
  parameter, not controlled by the plugin. Ordinal logic is buggy for `12th`/`13th` — see B-date-5.
- `awiwi#date#is_date(expr: string) -> boolean (0/1 via match())` — shape-only check:
  `match(expr, '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$') > -1`. **Purely syntactic** — `2024-13-40` returns
  `true`. No calendar-range validation anywhere in this module. See B-date-1.
- **Dead, never called from anywhere** (in this file or elsewhere in the repo — verified via grep):
  `s:is_leap_year(year)`, `s:get_yesterday(date)`, `s:ints_to_date(year, month, day)`. These are the
  *only* calendar-arithmetic code in the module (leap-year rule, month-rollover, year-rollover) and
  they are entirely unreachable. Do not port them as-is; if calendar-day arithmetic is needed for
  the Lua `prev`/`next` behavior, it must be written fresh using `os.time`/`os.date` (see Port
  notes) — don't resurrect this dead vimscript logic verbatim, it was never exercised/tested.
- `s:AwiwiDateError(msg, ...)` (private) — `printf`-style message formatter, returns (does not
  throw) the string `'AwiwiDateError: ' .. msg`; callers `throw` the result. The one external
  catch site (`autoload/awiwi.vim:336`, `catch /AwiwiDateError/`) pattern-matches on this string
  prefix. Any Lua replacement needs an equally greppable/matchable error identity for that one
  call site (and for date.vim's own two internal `catch /AwiwiDateError/` in `parse_date`).
- `s:get_offset_date(date, offset, options)` (private) — the actual "prev"/"next" implementation.
  Does **not** do calendar math. Gets `files = awiwi#get_all_journal_files()` (sorted list of
  `YYYY-MM-DD` stems for every journal `.md` file that exists on disk, from the top-level facade
  `autoload/awiwi.vim`, not from `date.vim` itself), finds `date`'s index, and returns
  `files[idx + offset]`. So "previous day" from `2024-03-05` means "the journal file immediately
  before `2024-03-05` in the sorted list of files that exist" — if `2024-03-04` has no journal
  entry, "previous" jumps straight to `2024-03-03` (or whatever the closest older *existing* file
  is), silently skipping gaps. This is almost certainly surprising to a user expecting calendar-day
  stepping and should be called out explicitly as a behavior contract item, not assumed.

**Reads/writes:**
- Globals: none (`g:autoloaded_awiwi_date` autoload guard only).
- Files: none directly — reads the *list* of existing journal files indirectly via
  `awiwi#get_all_journal_files()` (glob under `g:awiwi_home`, defined in the facade module).
- Buffers/windows: `get_own_date()` reads `expand('%:t:r')` / `expand('%:p')` — current buffer path.
  No writes anywhere in this module.
- Registers: none.
- Clock: `get_today()`/`to_iso_date()` read the system clock (`strftime`) in local time; `to_iso_date`
  branch 3 and `to_nice_date` additionally read the system's `LC_TIME` locale via the `date` binary.

**External:**
- Binary `date` (GNU coreutils `date --date ... +FORMAT`), shelled via `systemlist()`, in
  `to_iso_date` (branch 3, free-form relative dates) and `to_nice_date` (weekday/month formatting).
  This is a **hard runtime dependency on GNU date's extended `--date` parser** — not just a format
  helper, the actual natural-language date arithmetic ("in 3 days", "next monday", "3 weeks ago")
  lives entirely in the external binary. BSD/macOS `date` does not support `--date` the same way.
- `awiwi#path#split()` (from `path.vim`, not yet ported as of this brief — `lua/awiwi/path.lua`
  does not exist yet in this tree) — used once, in `get_own_date()`, to split the buffer's full
  path into components for the asset-page fallback. **This is a real cross-module dependency the
  task's "depends on ported `str.lua`" note does not mention** — flag it to the orchestrator/
  engineer: either wait for `path.lua` to land first, or inline the minimal path-splitting needed
  here (`vim.split(path, '/', {plain = true})` after `vim.fs.normalize`) so `date.lua` stays a leaf
  module and isn't blocked on T2.
- `awiwi#get_all_journal_files()` (from the top-level facade `autoload/awiwi.vim`, ported **last**,
  step 10 in the port order) — used by the private `s:get_offset_date` for `prev`/`next`
  resolution. This is a real circular-ordering problem: `date.lua` (T3) needs a journal-file lister
  that only exists once the facade (`init.lua`) is ported. **Recommendation:** don't have
  `date.lua` call the facade directly. Give the offset-resolution function an explicit dependency
  (e.g. `M.offset_date(date, offset, files, opts)` taking the sorted file list as a plain argument,
  or `M.parse_date(date, opts)` accepting `opts.list_journal_files` as an injected callback with no
  default). Let the facade (`init.lua`, T10) wire the real journal-file lister in. This keeps
  `date.lua` pure/leaf and independently testable without faking global plugin state.
- No other VimL plugin deps (no `fn#`, external `path#`).

## Behavior contract

1. `get_today()` returns the current local date as `YYYY-MM-DD`. No arguments, no errors, changes
   across a real-time midnight rollover (not memoized).
2. `to_tuple("2024-03-05")` -> `{2024, 3, 5}` (numbers, no zero-padding preserved — `05` becomes
   `5`). `to_tuple` performs no validation; it is a dumb split+parse and must stay that way (nothing
   downstream relies on it rejecting malformed input; `is_date` is the actual validator).
3. `is_date(s)` returns `true` iff `s` matches `^\d{4}-\d{2}-\d{2}$` exactly (full-string anchors).
   It does **not** check that month is 1-12 or day is valid for that month/year — `is_date("2024-13-40")`
   -> `true`. Preserve this shallowness unless an ADR explicitly asks for real calendar validation
   (several call sites, e.g. `awiwi.vim:876`, rely only on the shape check to decide "is this a
   single-date filter vs. a range/other expression").
4. `to_iso_date("2024-03-05")` -> `"2024-03-05"` unchanged (already ISO-shaped; no calendar check,
   see (3)).
5. `to_iso_date("05.03")` -> `"<current-year>-03-05"` — day and month come from the input in
   `DD.MM` order, year is always **today's** year at call time, never inferred from context (e.g.
   the journal buffer you're on). `to_iso_date("05.03.")` (trailing dot) behaves identically.
6. `to_iso_date("in 3 days")`, `to_iso_date("next monday")`, `to_iso_date("3 weeks ago")`,
   `to_iso_date("yesterday")`, `to_iso_date("tomorrow")` -> resolved via GNU `date --date <expr>
   +%F`, i.e. whatever GNU date's relative-date grammar returns, converted to ISO. The literal
   substring `in` (as a whole word followed by whitespace or a digit) is rewritten to `+` before
   being handed to `date` (e.g. `"in 3 days"` -> `" + 3 days"` is what's actually shelled out).
7. `parse_date("today")` -> `get_today()`.
8. `parse_date("previous day")` on a buffer whose own date is `D` -> the sorted-journal-files entry
   immediately before `D`'s index; if `D` has no journal file at all but equals today, returns `D`
   unchanged (does not throw); if there is no earlier file, throws `AwiwiDateError`. Same shape for
   `"prev"`/`"previous"`/`"previous date"`.
9. `parse_date("next day")` -> mirror of (8), `+1`; if at/past the last known journal file, throws
   `AwiwiDateError('no date found after %s')` (the `options.create_dirs` escape hatch exists in code
   but is dead in practice — see B-date-4).
10. `parse_date(x)` for any `x` not `today`/`prev*`/`next*` -> `to_iso_date(x)`, validated with
    `is_date`; throws `AwiwiDateError('%s is not a valid date', <normalized>)` if the result isn't
    ISO-shaped (e.g. GNU `date` failed to parse `x` and `systemlist` returned something unexpected,
    or returned empty).
11. `get_own_date()` on a journal buffer `.../journal/2024/03/2024-03-05.md` -> `"2024-03-05"`
    (from the filename stem). On an asset buffer `.../assets/2024/03/05/photo.md` -> `"2024-03-05"`
    (from path components). On any other buffer -> throws `AwiwiDateError('not on journal or asset
    page')`.
12. `to_nice_date("2024-03-05")` -> `"Tue, Mar 05th 2024"`. Ordinal: `1st/2nd/3rd/...th` by
    `day % 10` with a special case only for the literal string `"11"`. **Bug:** `"12"` and `"13"`
    are not special-cased and get `nd`/`rd` respectively instead of `th` — see B-date-5.
13. `is_date` and `to_iso_date`'s first branch are the fast, pure paths; every other path in this
    module either shells out or reads mutable process/buffer state (system clock, current buffer,
    filesystem glob of journal files) — none of `parse_date`/`get_own_date`/`to_iso_date`(branches
    2-3)/`to_nice_date`/`s:get_offset_date` are pure functions of their arguments alone.

## Call sites

- `autoload/awiwi.vim:260` — `awiwi#get_journal_file_by_date`: `parse_date(a:date)` to resolve the
  file path for a given date argument.
- `autoload/awiwi.vim:326` — `awiwi#edit_journal`: `parse_date(a:date)` — **called with a single
  arg**, so `options`/`create_dirs` is never passed here either (confirms B-date-4).
- `autoload/awiwi.vim:327` — `date == awiwi#date#get_today()` to decide whether to force
  `create_dirs` for today's file.
- `autoload/awiwi.vim:331,399,923` — `get_own_date()` to compare "the journal you're on" against
  another date (continuation-note flow, journal linking).
- `autoload/awiwi.vim:340` — `date > awiwi#date#get_today()` — plain ISO string comparison works
  here because ISO-formatted dates sort lexicographically = chronologically.
- `autoload/awiwi.vim:400` — `parse_date('today')`.
- `autoload/awiwi.vim:727` — `awiwi#insert_journal_link`: `parse_date(a:date)`.
- `autoload/awiwi.vim:795,805` — `to_iso_date(val)` / `to_iso_date(d.due)` normalizing task
  due-dates from user/JSON input before storing.
- `autoload/awiwi.vim:876` — `is_date(date)` to branch "single date" vs. other filter expressions.
- `autoload/awiwi.vim:894` — `to_nice_date(date)` for a display title.
- `autoload/awiwi/asset.vim:205` — `parse_date(a:date)`, single arg (same `create_dirs` gap).
- `autoload/awiwi/view.vim:241` — uses date-derived data; `view.vim` is dead/WIP (guard commented
  out, side-effecting sourcing) per `docs/architecture.md` — not excavated further here, drop per
  existing ADR policy.
- `autoload/awiwi/hi.vim:14-15` — `to_tuple(date1)` / `to_tuple(date2)` feeding `s:get_date_diff`.
- `autoload/awiwi/hi.vim:16-18` — **the luaeval hack this brief was asked to flag**:
  ```vim
  return luaeval(
        \ printf('os.time{year=%d,month=%d,day=%d} - os.time{year=%d,month=%d,day=%d}',
        \ year1, month1, day1, year2, month2, day2)) / 86400
  ```
  `s:get_date_diff(date1, date2)` builds a *Lua source string by printf-interpolating integers*
  and evaluates it with `luaeval()` purely to get day-difference arithmetic that vimscript itself
  cannot do — it is already reaching into Lua's `os.time` because there is no other way to diff two
  calendar dates in vimscript without shelling out. This function backs `awiwi#hi#draw_due_dates()`
  (due-date badges: `TODAY` / `[ 2d ago ]` / `[ in 1w, 3d ]`) — a real, user-visible, per-buffer,
  per-redraw feature (`awiwi#hi#redraw_due_dates`, autocmd-driven).
  **Port implication for `hi.lua` (T6a, downstream of this transaction):** once `date.lua` exists
  natively in Lua, `hi.lua` must call a real exported function — e.g. `require('awiwi.date').diff_days(date1,
  date2)` — instead of building a `luaeval()` string. That is the whole point of porting `date`
  before `hi`: this brief's `date.lua` should expose a `diff_days(date1: string, date2: string) ->
  integer` (whole days, `date1 - date2`, matching the sign convention used at `hi.vim:72`:
  `s:get_date_diff(meta.due, today)` where a positive result means "due is in the future") so the
  `luaeval` string-templating hack disappears entirely in T6a, not just gets reimplemented as a
  different string hack.
- `autoload/awiwi/hi.vim:146` — `to_nice_date(get_own_date())` for an "entitlement.nvim" title
  helper.

No test files, ftplugin, or plugin/ files call `awiwi#date#*` directly.

## Port notes

1. **`os.date`/`os.time`, no subprocess**, per the transaction directive — applies cleanly to
   `get_today()` (`os.date('%Y-%m-%d')` or `os.date('!*t')`/`os.date('*t')` + manual formatting),
   `to_tuple()` (trivial), `is_date()` (Lua pattern `^%d%d%d%d%-%d%d%-%d%d$`), and the `DD.MM`
   branch of `to_iso_date()` (`os.date('%Y')` for the current year). These have no ambiguity.
2. **`to_iso_date`'s branch 3 (free-form relative dates) is the hard case.** GNU `date --date`
   accepts a large, genuinely useful natural-language grammar (`next monday`, `3 weeks ago`,
   `yesterday`, `tomorrow`, `in 3 days`, bare weekday names, ISO timestamps, etc.) that real users
   type into `:Awiwi journal <date>`. Pure `os.date`/`os.time` cannot parse arbitrary English —
   this is not a formatting difference, it's a missing parser. Do not silently drop this feature;
   surface the decision explicitly (this is exactly the kind of thing that needs an ADR):
   - **Option A (recommended minimal-scope):** hand-write a small Lua parser covering only the
     vocabulary actually reachable from this plugin's UI/docs: `today`/`yesterday`/`tomorrow`,
     `in N day(s)/week(s)/month(s)`, `N day(s)/week(s)/month(s) ago`, and weekday names
     (`next/last <weekday>`), computed with `os.time{year=,month=,day=}` arithmetic (note: **do not
     set `hour`** in the table — Lua defaults `hour` to `12` (noon) when omitted, which is exactly
     what the existing `luaeval` hack in `hi.vim` relies on to avoid DST-induced off-by-one errors
     at midnight; setting `hour=0` explicitly would reintroduce that class of bug).
   - **Option B:** keep a narrow, explicit exception to the "no subprocess" rule for this one branch
     only (`vim.system({'date', '--date', expr, '+%F'})`), accepting the GNU-`date`-only
     runtime dependency the vimscript already has (already undocumented/unenforced — no check that
     `date` supports `--date` exists today either).
   Either way, document the choice in `docs/decisions.md`; don't let the engineer pick silently.
3. **`to_nice_date`'s locale dependency changes shape in Lua.** The vimscript version's weekday/
   month names come from the system `date` binary's `LC_TIME` at call time (whatever locale the
   user's shell/environment has). Lua's `os.date('%a, %b %d')` uses the C library's *current*
   locale as set via `os.setlocale` — Neovim does not call `setlocale(LC_TIME, "")` by default, so
   an unmodified `os.date` will very likely always produce `"C"`-locale (English) abbreviations
   regardless of the user's system locale. This is a **behavior change** (probably a desirable one
   — deterministic English output — but flag it, don't let it slip in silently). No dependency on
   the `date` binary is needed once this is accepted: `os.date('%a, %b %d', os.time{year=y,
   month=m, day=d})` is otherwise format-compatible with the vimscript's `strftime`-style spec.
4. **`get_own_date()` reads current-buffer state**, making it hard to unit test in isolation.
   Recommend the Lua signature take an explicit path/bufnr, defaulting to the current buffer, e.g.
   `M.get_own_date(bufname)` where `bufname` defaults to `vim.api.nvim_buf_get_name(0)` — this lets
   `tests/date_spec.lua` exercise the journal-filename and asset-path branches with plain strings,
   no scratch buffers required.
5. **Cross-module dependency on `path.split`** (see "External" above) — `path.lua` doesn't exist in
   this tree yet. Don't block T3 on it: inline the 1-line path split needed here, or take it as a
   parameter, and swap to `require('awiwi.path')` later once T2 lands, if/when the orchestrator
   sequences it that way.
6. **`s:get_offset_date`'s journal-file-list dependency on the not-yet-ported facade** (see
   "External" above) — solve via dependency injection (explicit `files` argument or injected
   callback), not a forward `require` on `init.lua`.
7. **Error identity**: replace the `throw 'AwiwiDateError: ...'` / `catch /AwiwiDateError/` string-
   prefix convention with something Lua-idiomatic but still easily distinguishable by callers —
   e.g. `error({code = 'AwiwiDateError', message = ...})` plus a small `M.is_date_error(err)`
   helper, or simplest: keep throwing plain strings prefixed `'AwiwiDateError: '` and have callers
   `pcall` + `err:match('^AwiwiDateError:')`, mirroring today's one external catch site
   (`autoload/awiwi.vim:336`, itself to be ported later) without inventing new machinery this early.
8. `diff_days(date1, date2)` (new, not in the vimscript source) should be added to `date.lua`'s
   public surface specifically to let `hi.lua` (T6a) delete the `luaeval` string-templating hack —
   see Call sites, `hi.vim:16-18`. Implement with `os.time{year=y1,month=m1,day=d1} -
   os.time{year=y2,month=m2,day=d2}) / 86400`, no `hour` field set (see note 2 re: DST).
9. Dead code (`s:is_leap_year`, `s:get_yesterday`, `s:ints_to_date`) — do not port. If leap-year-
   aware calendar arithmetic is needed for option A of note 2, write it fresh against `os.time`
   (which already handles month/year rollover and leap years correctly via the C library) rather
   than resurrecting the hand-rolled vimscript version.

## Bugs found

- **B-date-1** (preserve, unless ADR): `is_date`/`to_iso_date` do shape-only validation — `2024-13-40`
  is accepted as "a valid date" everywhere. No call site currently supplies genuinely
  out-of-range values, but nothing prevents it (e.g. malformed task `due:` JSON). Low risk;
  tightening this changes what currently-accepted-but-nonsensical dates do, which is a behavior
  change several call sites (`awiwi.vim:795,805,876`) would inherit silently. Recommend: **preserve**
  as shape-only for this transaction; note as a candidate for a follow-up ADR if it ever causes a
  real bug report.
- **B-date-2** (preserve, documented limitation): `to_iso_date`'s `DD.MM` shorthand always resolves
  to the *current* year, never the year of the buffer/context you're in. Cross-year linking via the
  short form is impossible (e.g. typing `31.12` while journaling in January always means *this*
  Dec 31, never last year's). Intentional-looking shorthand; **preserve**, just document the
  limitation for users if a Lua-port user guide gets written.
- **B-date-3** (fix in port, off-by-one): in `s:get_offset_date`, the backward-boundary check is
  `a:offset <= 0 && idx + a:offset <= 0` — this should be `< 0`, not `<= 0`. Concretely: if you are
  on the *second-oldest* journal file (`idx == 1`) and go `previous` (`offset == -1`), `idx +
  offset == 0`, which is a perfectly valid index (`files[0]`, the oldest existing journal) — but
  the `<= 0` check throws `AwiwiDateError('no date found before %s')` anyway, making the very
  oldest journal entry unreachable via "previous" navigation from its immediate successor.
  **Recommendation: fix in port** (`idx + offset < 0`).
- **B-date-4** (fix in port or drop, dead option): `parse_date`/`s:get_offset_date`'s
  `options.create_dirs` forward-boundary escape hatch (`return a:date` instead of throwing, when
  going `next` past the last known journal file) is **never reachable** — every call site in the
  repo calls `parse_date(date)` with exactly one argument (verified: `autoload/awiwi.vim:260,326,
  400,727`, `autoload/awiwi/asset.vim:205` — none pass a second arg). "Next" navigation therefore
  always throws once you're on the newest journal file, full stop; there is no live path today. In
  the port, either (a) drop the unused `options`/`create_dirs` parameter from `parse_date`'s
  translated behavior entirely (simplify signature, since nothing wires it), or (b) if the
  orchestrator wants "next from newest journal creates tomorrow" as a real feature, implement it
  properly (return `date + 1 day` via calendar arithmetic, not the vimscript's `return a:date`
  no-op which — even if it were reachable — would return the *same* date, not the next one; that's
  a second, latent bug inside the dead branch). Recommend: **drop the dead option in port**, file a
  feature request if "auto-create tomorrow's journal via `:Awiwi journal next`" is actually wanted.
- **B-date-5** (fix in port): `to_nice_date`'s ordinal-suffix logic special-cases only the literal
  day string `"11"` before falling back to `day % 10` (`1st/2nd/3rd/else-th`). Days `"12"` and
  `"13"` are not special-cased, so they get `day % 10` treatment: `12 % 10 == 2` -> `"12nd"`
  (wrong, should be `"12th"`), `13 % 10 == 3` -> `"13rd"` (wrong, should be `"13th"`). Every other
  day (14-31, including 21/22/23/31 which correctly get `st/nd/rd` via the same mod-10 rule) is
  unaffected. **Recommendation: fix in port** — check `day % 100` in `{11, 12, 13}` for the `th`
  exception, not just the literal string `"11"`.

## Suggested acceptance tests

Deterministic ones (no clock/locale/journal-fixture dependency):

```
to_tuple("2024-03-05")          -> {2024, 3, 5}
is_date("2024-03-05")           -> true
is_date("2024-3-05")            -> false   -- month not zero-padded, shape check fails
is_date("2024-13-40")           -> true    -- B-date-1, shape-only, preserve
is_date("today")                -> false
to_iso_date("2024-03-05")       -> "2024-03-05"
to_iso_date("05.03")            -> "<this-year>-03-05"   -- stub the clock/year in the test
to_nice_date("2024-03-01")      -> "..., Mar 01st 2024"
to_nice_date("2024-03-02")      -> "..., Mar 02nd 2024"
to_nice_date("2024-03-03")      -> "..., Mar 03rd 2024"
to_nice_date("2024-03-11")      -> "..., Mar 11th 2024"
to_nice_date("2024-03-12")      -> "..., Mar 12th 2024"   -- regression test for B-date-5
to_nice_date("2024-03-13")      -> "..., Mar 13th 2024"   -- regression test for B-date-5
to_nice_date("2024-03-21")      -> "..., Mar 21st 2024"
to_nice_date("2024-03-31")      -> "..., Mar 31st 2024"
diff_days("2024-03-10", "2024-03-05") -> 5     -- new fn, backs hi.lua's due-date badges
diff_days("2024-03-01", "2024-03-01") -> 0
diff_days("2024-02-01", "2024-03-01") -> -29   -- crosses a month boundary, 2024 is a leap year
get_own_date("journal/2024/03/2024-03-05.md")   -> "2024-03-05"
get_own_date("assets/2024/03/05/photo.md")      -> "2024-03-05"
get_own_date("recipes/pasta/carbonara.md")      -> throws AwiwiDateError
```

Fixture/injection-dependent (require the "no facade dependency" fix from Port note 6):

```
offset_date("2024-03-05", -1, {"2024-03-01","2024-03-05","2024-03-10"}) -> "2024-03-01"
offset_date("2024-03-01", -1, {"2024-03-01","2024-03-05","2024-03-10"}) -> throws (B-date-3 fixed: idx 0, offset -1, idx+offset=-1 <0)
offset_date("2024-03-05", -1, {"2024-03-01","2024-03-05","2024-03-10"}) with idx=1: -1+1=0 -> "2024-03-01" (B-date-3 regression: must NOT throw)
offset_date("2024-03-10", +1, {"2024-03-01","2024-03-05","2024-03-10"}) -> throws AwiwiDateError('no date found after ...')
```

Clock-dependent (stub `os.date`/`os.time` or inject a clock, per the module's design):

```
get_today() -> matches os.date('%Y-%m-%d') at call time
parse_date("today") -> get_today()
```

## Ported

**Lua module:** `lua/awiwi/date.lua` — `local M = {} … return M` shape, `require("awiwi.path")`
for `get_own_date`'s path-splitting (T2 already landed, no inline shim needed). Zero subprocess
calls anywhere in the module (orchestrator directive: `os.date`/`os.time` only).

**Public surface:**
- `M.get_today() -> string` — `os.date('%Y-%m-%d')`.
- `M.to_tuple(date) -> {year, month, day}` (numbers) — dumb split+`tonumber`, no validation.
- `M.is_date(s) -> boolean` — shape-only `^%d%d%d%d%-%d%d%-%d%d$` (B-date-1 preserved).
- `M.to_iso_date(date) -> string` — three branches: already-ISO passthrough (B-date-1 preserved);
  `DD.MM`/`DD.MM.` with current year (B-date-2 preserved); else the hand-written relative-date
  grammar below. Throws `AwiwiDateError` for anything matching none of these (no subprocess, no
  GNU-`date` natural-language fallback).
- `M.parse_date(date, options?) -> string` — `'today'` -> `get_today()`; `'prev'|'previous'|
  'previous date'|'previous day'` / `'next'|'next date'|'next day'` -> `offset_date` against
  `get_own_date()` (falling back to `get_today()` if the current buffer isn't a journal/asset
  page), `-1`/`+1`; anything else -> `to_iso_date` + `is_date` validation, throws
  `AwiwiDateError('%s is not a valid date', ...)` on failure. `options.files` (array of ascending
  `YYYY-MM-DD` journal-file dates) is the T10-facade dependency injection point for `prev`/`next`
  — defaults to `{}` if omitted, meaning only the "today has no journal file yet" case still
  resolves.
- `M.offset_date(date, offset, files) -> string` — the (now public, was private
  `s:get_offset_date`) journal-file-list navigation primitive; `files` is plain dependency
  injection, no facade `require`. B-date-3 fixed (backward-boundary check is `idx0 + offset < 0`,
  0-based, not `<= 0` — the oldest journal file is now reachable via "previous" from its immediate
  successor). B-date-4's dead `create_dirs` escape hatch is dropped entirely — hitting the forward
  boundary always throws `AwiwiDateError('no date found after %s', date)`.
- `M.get_own_date(bufname?) -> string` — takes an explicit `bufname` (defaults to
  `vim.api.nvim_buf_get_name(0)`) per the brief's testability recommendation, so
  `tests/date_spec.lua` exercises journal-filename and asset-path branches with plain strings, no
  scratch buffers. Filename-stem branch first, then `path.split` + last-4th..2nd-from-last
  components joined with `-` (asset-page fallback); throws `AwiwiDateError('not on journal or
  asset page')` otherwise.
- `M.to_nice_date(date) -> string` — e.g. `"2024-03-05" -> "Tue, Mar 05th 2024"`. B-date-5 fixed:
  ordinal-suffix exception checks `day % 100 in {11, 12, 13}`, not just the literal string `"11"`
  (the vimscript bug made `"12nd"`/`"13rd"` instead of `"12th"`/`"13th"`). Weekday/month names come
  from `os.date`'s C-locale (effectively always English under Neovim, which doesn't call
  `setlocale(LC_TIME, "")`) rather than the vimscript original's shelled-out `$LC_TIME`-honoring
  `date` binary — documented, intentional behavior change (deterministic output), not a
  regression.
- `M.diff_days(date1, date2) -> integer` — new (not in vimscript source), whole-day
  `date1 - date2`, positive when `date1` is later. Built with `os.time{year=,month=,day=,hour=12}`
  on both sides (never `hour=0`) so a DST transition can't shift either side across a day boundary
  — this is exactly the calculation `hi.vim:16-18`'s `luaeval()` string-templating hack was
  reaching into Lua for; T6a (`hi.lua`) should call `require('awiwi.date').diff_days(...)` directly
  and delete that hack.
- `M.is_date_error(err) -> boolean` — `type(err) == 'string' and err:match('^AwiwiDateError:')`.
  Errors are thrown as plain `'AwiwiDateError: <msg>'` strings via `error(msg, 0)` (no
  file:line prefix), mirroring the vimscript `throw`/`catch /AwiwiDateError/` string-prefix
  convention closely enough for `autoload/awiwi.vim`'s eventual (T10) `pcall` + `is_date_error`
  call site.

**Supported relative-date-expression shapes (Option A, per ADR — see `docs/decisions.md`):**
hand-written pure-Lua grammar, deliberately narrower than GNU `date --date`'s full
natural-language parser, covering exactly the vocabulary the brief's call-site inventory showed
reachable from the plugin's UI:
- `today`, `yesterday`, `tomorrow`
- `in N day(s)` / `in N week(s)` / `in N month(s)` (singular or plural unit)
- `N day(s) ago` / `N week(s) ago` / `N month(s) ago`
- `next <weekday>` / `last <weekday>` (full English weekday names, lowercase-normalized before
  matching; "next"/"last" always means strictly future/past, skipping today even if today is that
  weekday — matches GNU `date`'s own "next monday" semantics)

Anything else (bare weekday names with no `next`/`last`, ISO timestamps with a time component,
ordinal-day expressions like "the third tuesday", etc.) throws `AwiwiDateError` — a clear
rejection rather than a silent wrong answer. Month arithmetic uses `os.time`'s `month` field
directly (`month = m + n`), so `os.time`/`os.date` handle year rollover and day-count-per-month
correctly without hand-rolled calendar tables; day/week arithmetic uses fixed 86400s/604800s
steps via `hour = 12` (noon) anchoring to dodge DST off-by-ones, per the brief's Port note 2.

**Deviations from the brief:**
- `to_iso_date` throws `AwiwiDateError` directly for unparseable input (rather than returning some
  non-ISO string for `parse_date` to catch via `is_date`) — `parse_date`'s own `is_date` check
  after `to_iso_date` is kept anyway as a harmless safety net, but in practice `to_iso_date` never
  returns a non-ISO-shaped string.
- `M.offset_date` (was private `s:get_offset_date`) is a public function, not nested inside
  `parse_date`'s options — matches the brief's own suggested acceptance-test call shape
  (`offset_date(date, offset, files)`) directly.
- Dead code (`s:is_leap_year`, `s:get_yesterday`, `s:ints_to_date`) and B-date-4's `create_dirs`
  option are dropped entirely, not ported in any form, per the brief's and orchestrator's explicit
  instruction.

**Test count:** 52 (targeted `tests/date_spec.lua`, including two regression tests manually
verified to fail against the pre-fix logic for B-date-3 and B-date-5); full suite 110 passed, 0
failed (`nvim --clean --headless -l tests/run.lua`), 4 files (`smoke_spec.lua` + `str_spec.lua` +
`path_spec.lua` + `date_spec.lua`).

**Notes for T4 (`util`) / T6a (`hi`):**
- `hi.lua` (T6a): replace the `hi.vim:16-18` `luaeval()` day-diff string-templating hack with
  `require('awiwi.date').diff_days(meta.due, today)` directly — same sign convention (positive =
  due in the future) already matches `hi.vim:72`'s usage. Also replace `hi.vim:146`'s
  `to_nice_date(get_own_date())` call site directly (signature-compatible; `get_own_date()` with
  no arg still defaults to the current buffer).
- Any future façade (`init.lua`, T10) wiring `awiwi#get_all_journal_files()` into `prev`/`next`
  resolution should pass the resolved list as `options.files` to `M.parse_date` — no `require`
  from `date.lua` back into the façade; the dependency direction stays one-way.
- `M.get_own_date`'s `bufname` parameter accepts plain strings (relative or absolute) — no
  scratch-buffer ceremony needed by callers/tests.

status: done
