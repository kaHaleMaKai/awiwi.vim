# lua-port / str

**Responsibility:** Leaf string-predicate helpers (`startswith`, `endswith`, `contains`,
`is_empty`) used throughout the plugin for filetype/path/line-prefix checks. No state, no I/O.

**Public surface:**
- `awiwi#str#startswith(str, prefix)` -> `v:true`/`v:false`
- `awiwi#str#endswith(str, suffix)` -> `v:true`/`v:false`
- `awiwi#str#contains(str, part)` -> `v:true`/`v:false`
- `awiwi#str#is_empty(str)` -> `v:true`/`v:false`

**Reads/writes:** none. Pure functions, no globals/files/buffers/registers. Only side effect in
the source is the autoload re-source guard `g:autoloaded_awiwi_str` (a Lua module doesn't need an
equivalent — `require` caching replaces it).

**External:** none. No shelling out, no other awiwi modules called, no VimL plugin deps.

## Behavior contract

1. `startswith(str, prefix)`: returns `true` iff `str` begins with the exact byte sequence
   `prefix`. `startswith("", "")` -> `true`. `startswith("x", "")` -> `true` (every string starts
   with the empty string). `startswith("", "x")` -> `false`. `startswith("ab", "abc")` -> `false`
   (prefix longer than str). Comparison is on the full string, not per-character/rune — a
   multibyte (UTF-8) prefix that is a substring at the byte level compares correctly as long as
   caller passes valid UTF-8 boundaries (this is what the vimscript actually does: byte-length
   compare + byte-range equality, not codepoint-aware).
2. `endswith(str, suffix)`: mirror of (1) for the tail. `endswith("", "")` -> `true`.
   `endswith("x", "")` -> `true`. `endswith("", "x")` -> `false`. `endswith("ab", "abc")` ->
   `false`.
3. `contains(str, part)`: returns `true` iff `part` occurs anywhere in `str` (byte-substring
   search, first-index >= 0). `contains(str, "")` -> `true` for any `str` including `""` (empty
   needle always "found" at index 0). `contains("", "x")` -> `false`.
4. `is_empty(str)`: returns `true` iff `str`, after trimming leading/trailing whitespace, has zero
   length. `is_empty("")` -> `true`. `is_empty("   ")` -> `true` (vimscript `trim()` with no mask
   strips space/tab/newline/CR — the whitespace set `%s` matches in Lua patterns covers this).
   `is_empty("  x  ")` -> `false`. Whitespace-only strings containing only-spaces/tabs are the
   only non-empty-input case that must still return `true`.
5. All four functions are argument-order-sensitive and take exactly two string args; there is no
   variadic/optional-arg behavior and no case-insensitive mode in the *intended* contract (see
   Bstr-2 below for what the vimscript actually ships).

## Call sites

All are boolean predicates gating control flow or `filter()` predicates; none rely on any return
value beyond truthiness.

- `awiwi#str#startswith`:
  - `autoload/awiwi/cmd.vim:220,221,272` — matching `-h`/`-w` journal-window CLI flags
  - `autoload/awiwi/util.vim:39` — command-completion filtering by `ArgLead`
  - `autoload/awiwi/util.vim:156` — checking a completion-opts string starts with `'customlist'`
  - `autoload/awiwi/util.vim:310,318,329` — detecting fenced-code-block lines (`` ``` ``) in a buffer
  - `autoload/awiwi/server.vim:124` — routing on whether current file path starts with `'journal'`
  - `autoload/awiwi/path.vim:14,16,31` — path-join/absolute-path checks (leading `/`)
- `awiwi#str#endswith`:
  - `ftplugin/awiwi.vim:127`, `syntax/awiwi.vim:117` — detecting `&filetype ==# 'awiwi.todo'`-ish
    via `.todo` suffix
  - `autoload/awiwi.vim:676` — checking a line already ends in a trailing space
  - `autoload/awiwi/cmd.vim:191` — `awiwi#str#endswith(awiwi#get_recipe_subpath(), '/')` — **note:**
    result is assigned to a local named `prefix_len` and never used as a length; this is a bug in
    `cmd.vim`, not in `str.vim` — flag for the `cmd` module brief, not fixed here.
  - `autoload/awiwi/cmd.vim:554` — ensuring a recipe filename has a `.md` suffix
  - `autoload/awiwi/hi.vim:138` — `name->awiwi#str#endswith('.md')` (method-call syntax, same fn)
  - `autoload/awiwi/path.vim:8,14,16` — path separator normalization
  - `autoload/awiwi/server.vim:122` — routing on `journal/todos.md` suffix
- `awiwi#str#contains`:
  - `autoload/awiwi/cmd.vim:528` — checking a date-file expression contains `:` (time component)
- `awiwi#str#is_empty`:
  - `autoload/awiwi/cmd.vim:615` — filtering blank args out of a list before further processing

No call site depends on non-string input; all inputs observed are literal strings, `&ft`/`&filetype`,
`getline()` output, or list items already known to be strings.

## Port notes

- Implement as pure Lua string ops — no `vim.fn` needed. This module is a textbook case for
  `.claude/skills/lua-port`'s "prefer native Lua" rule:
  - `startswith(s, prefix)`: `s:sub(1, #prefix) == prefix` (handles all edge cases above natively:
    `("" ):sub(1,0)` == `""`, matches).
  - `endswith(s, suffix)`: `suffix == "" or s:sub(-#suffix) == suffix` (guard `#suffix == 0` before
    negative-index slice, since `s:sub(-0)` behaves like `s:sub(1)` in Lua 5.1/LuaJIT, not empty —
    verify against your target `s:sub` before relying on it, or just early-return `true` when
    `#suffix == 0`).
  - `contains(s, part)`: `part == "" or s:find(part, 1, true) ~= nil` (use `find` with `plain=true`
    to avoid Lua pattern-magic-character surprises — vimscript `stridx` is a literal substring
    search, not a pattern search, so `plain=true` is required for behavior parity, e.g. `part =
    "a.b"` must not match `"axb"`).
  - `is_empty(s)`: `s:match("^%s*$") ~= nil` or `s:gsub("^%s+", ""):gsub("%s+$", "") == ""`.
    Lua's `%s` whitespace class covers space/tab/newline/CR/vtab/formfeed, a superset of what
    vimscript `trim()` strips by default — acceptable, no observed caller passes exotic whitespace.
  - Both vimscript and Lua string operations here are byte-based (not codepoint-based), so no
    UTF-8/multibyte special-casing is needed for parity — this is a "preserve as-is" case, not a
    place to introduce treesitter/codepoint awareness.
  - No `vim.fn.stridx`/`vim.fn.strpart`/`vim.fn.trim` needed at all; keep the Lua module
    dependency-free (no `vim.*` calls) so it's trivially unit-testable outside nvim too.

## Bugs found

- **Bstr-1** (cosmetic, low severity): `startswith`/`endswith` special-case
  `a:str == "" && a:prefix/suffix == ""` before the general branch, but this branch is dead code —
  the general `strpart(...) == ...` branch already returns the same `true` for that input (verified
  by inspection and by testing the fallthrough manually). No observable behavior difference.
  **Recommendation: fix in port** — just omit the special case; the idiomatic Lua one-liners above
  already produce correct results for the empty/empty case without a branch.
- **Bstr-2** (real, latent, medium severity): `startswith`/`endswith` compare with plain `==`,
  which in Vimscript is sensitive to the `'ignorecase'` option (confirmed via
  `nvim --clean --headless -c 'set ignorecase' -c 'echo "HELLO" == "hello"'` -> `1`, vs `0` with
  `noignorecase`). If any user has `ignorecase` set globally, `awiwi#str#startswith`/`endswith`
  silently become case-insensitive everywhere they're used (fenced-code-block detection, `.todo`
  filetype suffix check, path/URL checks, CLI flag matching), which is almost certainly not
  intended. `contains` (via `stridx`) and `is_empty` are unaffected since they don't use `==`.
  **Recommendation: fix in port** — Lua string equality (`==`) is always byte-exact regardless of
  any option, so the Lua port is automatically case-sensitive and closes this bug for free. Call
  out in `docs/decisions.md` that this is an intentional behavior change (case-sensitive by
  default, no `'ignorecase'`-equivalent knob) rather than a silent regression.

## Suggested acceptance tests

```
startswith("", "")                -> true
startswith("hello", "")           -> true
startswith("hello", "he")         -> true
startswith("hello", "lo")         -> false
startswith("he", "hello")         -> false   -- prefix longer than str
startswith("héllo", "h")          -> true    -- byte-safe multibyte prefix
endswith("", "")                  -> true
endswith("hello", "")             -> true
endswith("hello", "lo")           -> true
endswith("hello", "he")           -> false
endswith("lo", "hello")           -> false   -- suffix longer than str
contains("hello", "ell")          -> true
contains("hello", "")             -> true
contains("", "")                  -> true
contains("", "x")                 -> false
contains("a.b", "a.b")            -> true    -- literal match, not Lua pattern magic
contains("axb", "a.b")            -> false   -- must NOT match via pattern "."
is_empty("")                      -> true
is_empty("   ")                   -> true
is_empty("\t\n")                  -> true
is_empty("  x  ")                 -> false
is_empty("x")                     -> false
-- case sensitivity (regression guard for Bstr-2, no ignorecase-equivalent in Lua):
startswith("Hello", "hello")      -> false
endswith("HELLO", "lo")           -> false
```

## Ported

**Lua module:** `lua/awiwi/str.lua` — `local M = {}` shape, zero `vim.*` calls (pure Lua, matches
port note's "no `vim.fn` needed" guidance). Spec: `tests/str_spec.lua` (26 `it` cases across 4
`describe` blocks, one per function).

**Public API:**
- `M.startswith(s, prefix) -> boolean`
- `M.endswith(s, suffix) -> boolean`
- `M.contains(s, part) -> boolean`
- `M.is_empty(s) -> boolean`

Note: Lua has no `v:true`/`v:false` distinction — these return plain Lua `boolean`, which is the
natural idiom for callers (`if awiwi.str.startswith(...) then`) and needs no adapter.

**Deviations from brief/vimscript (both flagged as intentional, not regressions):**
- **Bstr-1** (dead empty/empty branch): omitted per brief's "fix in port" recommendation. The
  one-liner implementations (`s:sub(1,#prefix)==prefix` etc.) already produce `true` for
  empty/empty without a special case, so there is nothing to special-case.
- **Bstr-2** (`==` sensitive to vimscript `'ignorecase'`): the Lua port is unconditionally
  byte-exact/case-sensitive in `startswith`/`endswith` (Lua `==` has no ignorecase-equivalent
  option). This is an intentional behavior change, not a regression — flagging for
  `docs/decisions.md` (ADR) per the brief: previously, any user with global `set ignorecase` got
  silently case-insensitive fenced-code-block detection, `.todo` filetype suffix checks, and CLI
  flag matching; the Lua port always case-matches exactly regardless of any option. No
  ignorecase-equivalent knob is offered.
- `endswith`'s `#suffix == 0` early-return-`true` guard is kept exactly as the brief's port notes
  warned (`s:sub(-0)` behaves like `s:sub(1)` in Lua, not empty-string semantics) — verified this
  guard is load-bearing via the `endswith("hello", "")` test case.
- `contains` uses `s:find(part, 1, true)` (`plain=true`) to keep vimscript `stridx` literal-substring
  semantics; verified via test cases `contains("a.b","a.b") -> true` and
  `contains("axb","a.b") -> false` (the latter would wrongly match if `plain` were omitted, since
  `.` is a Lua pattern magic char).
- `is_empty` uses `s:match("^%s*$")`; Lua's `%s` class is a superset of vimscript default `trim()`
  whitespace (adds vtab/formfeed) — brief noted this is acceptable, no observed caller passes
  exotic whitespace.

**Test count:** 26 (targeted `tests/str_spec.lua`); full suite 28 passed, 0 failed
(`nvim --clean --headless -l tests/run.lua`), 2 files (`smoke_spec.lua` + `str_spec.lua`).

**Gotchas for T2+ (path is next):** module has zero `vim.*` dependency by design — keep that
property for any module the brief marks "leaf/pure"; don't reach for `vim.startswith`/
`vim.endswith`/`vim.trim` here even though they exist, since the brief explicitly asked for a
dependency-free, outside-nvim-testable module. `path.lua` (next module) is expected to
`require("awiwi.str")` for its prefix/suffix checks per the brief's call-site list (path.vim:8,14,16,31).

status: done
