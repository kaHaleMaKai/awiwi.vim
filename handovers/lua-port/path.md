# lua-port / path

**Responsibility:** Pure(-ish) filesystem-path string manipulation (join, split,
absolutize, relativize, canonicalize) used by every other module to build
paths under `g:awiwi_home`. No module-local state.

**Source:** `autoload/awiwi/path.vim` (82 lines). Target: `lua/awiwi/path.lua` +
`tests/path_spec.lua`.

**Depends on (Lua):** `lua/awiwi/str.lua` (T1) is NOT actually needed for a
faithful reimplementation — the vimscript uses `awiwi#str#startswith`/`endswith`
only as trivial string-prefix/suffix checks; Lua's native `string` ops or
`vim.startswith`/`vim.endswith` cover this without depending on T1 at all. Treat
the "dep: T1" edge in STATE.md as soft — path.lua does not need to `require`
str.lua, but keep using the same idiom (`vim.startswith`/`vim.endswith`) for
consistency if str.lua exposes it.

## Public surface (vimscript, `awiwi#path#*`)

1. `awiwi#path#join(path, ...) -> string` — variadic path join.
2. `awiwi#path#absolute(path) -> string` — resolve to absolute path.
3. `awiwi#path#is_absolute(path) -> bool`
4. `awiwi#path#is_relative(path) -> bool`
5. `awiwi#path#split(path) -> list<string>`
6. `awiwi#path#relativize(path, relative_to) -> string`
7. `awiwi#path#canonicalize(path) -> string`

None of these read or write `g:`/`s:`/buffers/windows/registers/files directly.
`absolute()` reads Neovim's current-working-directory and environment (via
`expand()`) and (quirk, see Bugs) stats the filesystem. Everything else is a
pure string function over its arguments.

## Reads/writes

- Globals: none read/written by `path.vim` itself. (Callers pass `g:awiwi_home`
  in as the base path — see Call sites.)
- Files/buffers/windows/registers: none, except the implicit filesystem stat
  inside `absolute()` (see Bug B-PATH-9).

## External

- `awiwi#str#startswith` / `awiwi#str#endswith` (sibling module, T1).
- `fn#apply` / `fn#spread` — **external VimL plugin, not vendored anywhere in
  this repo** (`find / -iname fn.vim` outside `autoload/awiwi/` finds nothing;
  `exists('*fn#apply')` is `0` in a clean nvim). Used only inside
  `awiwi#path#join`'s recursion step. See Bug B-PATH-2 — this makes 3+-arg
  `join()` calls dead/broken today unless the user happens to have some
  `fn.vim` plugin on `runtimepath`. Irrelevant for the Lua port (native
  varargs replace it entirely).
- Vim builtins: `split()`, `strpart()`, `expand()`, `fnamemodify(...,':p')`,
  `funcref()`/`call()`, `remove()`, `map()`.

## Behavior contract

### 1. `join(path, ...)`

1.1 With zero variadic args, `join(p)` returns `p` unchanged, **except** if `p`
    ends with `/` it strips exactly one trailing `/` (`strpart(p,0,len(p)-1)`).
    `join('a')  == 'a'`; `join('a/') == 'a'`; `join('/') == ''` (see Bug
    B-PATH-5 — root collapses to empty string).

1.2 If the first variadic arg is the empty string `""`, behaves exactly as
    1.1 applied to `path`, and **all further variadic args are silently
    discarded** (`join('a', '', 'b') == 'a'`, `'b'` is lost). See Bug B-PATH-3.

1.3 Otherwise, exactly one `/` separator is inserted between `path` and the
    first variadic segment, using this rule to avoid doubling or omitting the
    separator:
    - neither `path` ends with `/` nor the segment starts with `/` → insert `/`
    - both do → drop the segment's leading `/` and concatenate (no extra `/`)
    - exactly one of the two → straight concatenation (a `/` is already present)

1.4 The result of 1.3 is then recursively joined with the *rest* of the
    variadic segments (left fold), i.e. `join(a,b,c,d) == join(join(join(a,b),c),d)`.

1.5 The final result never has a trailing `/` unless the whole thing reduces
    to the literal root case in 1.1 (in current shipped code that case is
    actually `''`, a bug — see B-PATH-5).

1.6 `join` is used both as an N-ary path combinator (`join(g:awiwi_home,
    'journal')`) and, with 0 extra args, as a single-path "strip trailing
    slash" normalizer (`call('awiwi#path#join', parts)` where `parts` is a
    dynamically-sized list, sometimes length 1). Preserve both uses.

### 2. `absolute(path)`

2.1 Expands `~`, `~user`, `$ENV_VARS` and Vim special keywords (`%`, `#`, …) in
    `path` via `expand()`, then resolves the result to an absolute path
    relative to Neovim's current working directory via
    `fnamemodify(..., ':p')`.

2.2 Quirk (non-referentially-transparent): the trailing `/` on the result is
    added **iff the resolved path currently exists as a directory on disk** at
    call time (`fnamemodify(...,':p')`'s own behavior, confirmed empirically:
    `fnamemodify(expand('/tmp'), ':p') == '/tmp/'`, but
    `fnamemodify(expand('nonexistentdir'), ':p') == '<cwd>/nonexistentdir'`, no
    slash). See Bug B-PATH-9 — no live call site depends on this, safe to drop.

2.3 Does not touch buffers/files other than the implicit stat in 2.2.

### 3/4. `is_absolute(path)` / `is_relative(path)`

3.1 `is_absolute(p) == (p starts with "/")`. Anything else (including `~/foo`,
    `""`, Windows-style `C:\...`) is **not** absolute.

4.1 `is_relative(p) == not is_absolute(p)` (strict complement, no independent
    logic).

### 5. `split(path)`

5.1 Splits on `/`, collapsing **leading/trailing** empty components but
    **preserving embedded ones** from doubled slashes: `split('/a/b/c') ==
    {'a','b','c'}`; `split('a//b') == {'a','','b'}` (embedded empty string is
    kept! only `canonicalize`, not `split` itself, filters it out).

5.2 If `is_absolute(path)`, a literal `'/'` element is **prepended** to the
    result: `split('/a/b') == {'/','a','b'}`. This is the sentinel that lets
    `join(unpack(split(p))) == p` round-trip for absolute paths (except the
    root case, B-PATH-5).

5.3 `split('') == {}`; `split('/') == {'/'}` (5.2's sentinel with the "/" body
    stripped away since 5.1's split-with-collapse yields `{}` for a lone `/`).

### 6. `relativize(path, relative_to)`

6.1 If `path` is absolute and `relative_to` is relative, returns `path`
    unchanged (mismatched-kind guard). The symmetric mismatch (`path` relative,
    `relative_to` absolute) is **not** guarded and falls through to 6.2 with
    undefined/meaningless results — no live call site does this.

6.2 Otherwise: split both into component lists `P = split(path)`,
    `R = split(relative_to)`. Find the length of the common prefix between `P`
    and `R` over `range(min(#P,#R))`; the number of `..` segments emitted is
    `len(R) - 1 - common_prefix_length` (i.e. **`relative_to`'s own last
    component is always excluded from the `..` count** — treat `relative_to`
    as a *file path*, not a directory: the returned path navigates from that
    file's containing directory to `path`). The remainder of `P` after the
    common prefix is appended verbatim. Result = `join(('..' * up_count) ..
    P[common_prefix_length:])`.

6.3 Contract for callers: **`relative_to` must be a file path** (its last
    component is discarded as "the current file"), not a bare directory — see
    Bug B-PATH-7 for what happens if you pass a directory whose full component
    list is a prefix of `path`'s.

6.4 All live call sites pass two absolute paths (`awiwi#path#absolute(...)` or
    paths built from `g:awiwi_home`).

### 7. `canonicalize(path)`

7.1 Splits `path` (7.1 uses the same absolute-sentinel convention as `split`),
    then walks components left-to-right building an output list: `.` and
    empty components are dropped; `..` pops the last output component;
    anything else is appended. Result = `join(output_list)`.

7.2 Purely lexical — does **not** touch the filesystem, does not resolve
    symlinks.

7.3 Crashes (`E684: List index out of range`, uncaught) if a `..` is
    encountered with no component left to pop — see Bug B-PATH-6.

## Call sites

Grep of `awiwi#path#` across the repo (module: line):

- `autoload/awiwi.vim:8-14,29-30` — build `s:journal_subpath`, `s:todos_subpath`,
  `s:asset_subpath`, `s:recipe_subpath`, `s:awiwi_data_dir`, `s:cache_dir`,
  `s:log_file`, `s:task_log_file` via `join(g:awiwi_home, '<subdir>')`.
- `autoload/awiwi.vim:262` — journal file path: `join(s:journal_subpath, year, month, date..'.md')`.
- `autoload/awiwi.vim:350` — todo file: `join(s:todos_subpath, filename)`.
- `autoload/awiwi.vim:434` — glob pattern: `glob(call('awiwi#path#join', pattern), ...)`.
- `autoload/awiwi.vim:651` — `canonicalize(join(expand('%:p:h'), link.target))` (resolving a
  markdown-link relative target against the current buffer's directory).
- `autoload/awiwi.vim:659` — `join(g:awiwi_home, 'assets', date, file)`.
- `autoload/awiwi.vim:703` — `join(s:recipe_subpath, a:recipe)`.
- `autoload/awiwi.vim:712` — `call('awiwi#path#join', parts[start:])`.
- `autoload/awiwi.vim:713,728` — `awiwi#util#relativize(recipe_file)` /
  `(awiwi#get_journal_file_by_date(date))` → indirectly calls `path#relativize`.
- `autoload/awiwi.vim:251,253` — `s:add_link()`: `awiwi#util#relativize(a:target, a:1)`.
- `ftplugin/awiwi.vim:347` — `join(current_dir, fnamemodify(a:file, ':p:t'))`.
- `autoload/awiwi/asset.vim:128` — `awiwi#path#split(expand('%:p:h'))[-3:]` (year/month/day
  from directory depth, tail-indexed — unaffected by the leading `/` sentinel).
- `autoload/awiwi/asset.vim:148` — `join(awiwi#get_asset_subpath(), year, month, day, name)`.
- `autoload/awiwi/asset.vim:240` — `glob(join(g:awiwi_home, 'assets', '2*', '**'), ...)`.
- `autoload/awiwi/asset.vim:117,135` — `awiwi#util#relativize(asset_file, expand('%:p'))` /
  `awiwi#util#relativize(get_asset_path(...))`.
- `autoload/awiwi/util.vim:77` — `call(funcref('awiwi#path#join'), paths)`.
- `autoload/awiwi/util.vim:362-368` — `awiwi#util#relativize(path, ...)` wraps
  `path#absolute` + `path#relativize` (this is the sole indirection through which
  almost every other module reaches `relativize`).
- `autoload/awiwi/server.vim:20,89,90` — config/venv/app paths via `join`.
- `autoload/awiwi/cmd.vim:141,196,510,559` — session file, recipe glob, link-target
  canonicalize (same pattern as `awiwi.vim:651`), recipe file join.
- `autoload/awiwi/date.vim:138` — `awiwi#path#split(expand('%:p'))[-4:-2]` (tail-indexed).
- `autoload/awiwi/hi.vim:129-130` — `awiwi#hi#get_recipe_title()`:
  `relativize(expand('%:p'), awiwi#get_recipe_subpath())` **then manually strips
  the first split component of the result** (`->awiwi#path#split()[1:]`) — this
  is a compensating workaround for Bug B-PATH-7 (see below). **Do not port this
  workaround verbatim if B-PATH-7 is fixed in `path.lua`** — read that note again
  when T6a ports `hi.vim`.
- `autoload/awiwi/hi.vim:135` — `expand('%:p')->awiwi#path#split()[-4:]` (tail-indexed).

## Bugs found

- **B-PATH-1 — wrong autoload guard** (`path.vim:4` sets `g:autoloaded_path`
  instead of `g:autoloaded_awiwi_path`, per `docs/architecture.md:157`,
  already tracked repo-wide). *Recommendation: fix-in-port — moot by
  construction, Lua's `require` cache is the guard.*

- **B-PATH-2 — `join()`'s 3+-arg recursion depends on an unvendored external
  plugin** (`fn#apply`/`fn#spread`; confirmed absent from the repo and from a
  clean nvim runtimepath). Multi-segment `join()` calls are effectively dead
  code today unless the user's environment happens to provide `fn.vim`.
  *Recommendation: fix-in-port — trivial, Lua has native varargs, no
  dependency needed.*

- **B-PATH-3 — `join(path, "", rest...)` silently drops `rest`** (the
  `!a:0 || a:1 == ""` guard short-circuits before variadic args beyond `a:1`
  are ever consulted). No known live call site triggers it (nothing passes an
  empty string as a non-final segment), but it's a footgun for future
  callers. *Recommendation: fix-in-port — an empty segment should be a no-op
  in the fold, not a truncation (matches `vim.fs.joinpath` behavior — see
  Port notes).*

- **B-PATH-5 — root path collapses to `""`.** `join('/')` returns `''` because
  the trailing-slash-strip logic doesn't special-case the single-character
  root; this also corrupts `canonicalize('/')` (returns `''` instead of `'/'`)
  since canonicalize's last step is `join(new_parts)`.
  *Recommendation: fix-in-port — `join('/') == '/'`; trivial one-line
  special case (matches `vim.fs.joinpath('/') == '/'`, verified empirically).*

- **B-PATH-6 — `canonicalize()` crashes (`E684: List index out of range`) on
  under-flowing `..`.** Any path with more `..` segments than resolvable
  directory depth (e.g. `canonicalize('../x')`, or `canonicalize('/../../x')`)
  hits `remove(new_parts, -1)` on an empty list and throws, uncaught. Two live
  call sites (`awiwi.vim:651`, `cmd.vim:510`) feed
  `canonicalize(join(expand('%:p:h'), link.target))` where `link.target` comes
  from a markdown link a human typed — a shallow file with an overly-relative
  link (e.g. `../../../../oops.png`) crashes the plugin today.
  *Recommendation: fix-in-port — clamp at the root for absolute paths, and
  preserve leading `..` (don't crash) for relative paths, matching
  `vim.fs.normalize` semantics (verified empirically: `vim.fs.normalize('/../../x')
  == '/x'`, `vim.fs.normalize('../../x') == '../../x'`, no error either way).*

- **B-PATH-7 — `relativize()` off-by-one when `relative_to`'s components are
  a full prefix of `path`'s** (i.e. the common-prefix loop never finds a
  divergence before exhausting `range(min(#P,#R))`, so `start` is left
  pointing at the *last matching index* instead of one past it). Concretely:
  `relativize('/a/b/c', '/a/b')` returns `'b/c'` instead of `'c'`;
  `relativize('/a/b', '/a/b')` returns `'b'` instead of `'.'` (and would
  actually crash — `join()` with zero args — once B-PATH-2/3 style edge cases
  are excluded, since `parts` ends up empty in some variants; verify in
  tests). The one live call site that hits this (`hi.vim:129`, passing a
  *directory* as `relative_to` instead of a file) works around it manually by
  stripping the spurious leading component from the result
  (`rel_path->awiwi#path#split()[1:]`).
  *Recommendation: fix-in-port* — minimal fix: initialize `start = length`
  before the loop and only overwrite it (`start = i; break`) on an actual
  mismatch, so a fully-matching common prefix leaves `start == length`; also
  return `'.'` when the computed parts list is empty (identical paths).
  **Coordination requirement: if this is fixed here, `hi.vim`'s Lua port
  (T6a) must drop the compensating `[1:]` slice at `hi.vim:130`, or the fix
  and the workaround will double-cancel and re-break `get_recipe_title()`.**
  Flag this explicitly in `handovers/STATE.md` / the T6a handover before that
  transaction starts.

- **B-PATH-8 (minor, no live impact) — mismatched-kind guard in `relativize`
  is one-sided.** Only `is_absolute(path) && is_relative(relative_to)` is
  special-cased; the symmetric case falls through to nonsense. No call site
  triggers it (all pass two absolute paths). *Recommendation: preserve
  (defer) — add a defensive error or symmetric guard only if a future caller
  needs it; not worth speculative test coverage now.*

- **B-PATH-9 (minor, no live impact) — `absolute()` is not referentially
  transparent.** `fnamemodify(expand(path), ':p')` appends a trailing `/`
  *iff* the resolved path currently exists as a directory on disk (confirmed
  empirically), independent of whether the input had one. Both live call
  sites (`util.vim:364,366`) immediately feed the result into `relativize`,
  whose `split()` is trailing-slash-agnostic, so this is inert today.
  *Recommendation: fix-in-port — drop the stat dependency, use
  `vim.fs.abspath` (pure, no filesystem access) instead.*

## Port notes (nvim ≥0.12 idioms)

Empirically verified in this repo's nvim (`v0.12.2`) — all of the following
exist and behave as shown:

- **`vim.fs.joinpath(...)`** already implements almost exactly the *intended*
  (bug-fixed) semantics of `join`: dedupes doubled `/` at boundaries
  (`vim.fs.joinpath('/a/', '/b') == '/a/b'`), keeps `join('/') == '/'` (fixes
  B-PATH-5 for free), and does **not** drop trailing args after an empty
  segment (`vim.fs.joinpath('a','','b') == 'a/b'`, fixes B-PATH-3 for free).
  Recommended implementation: `M.join = function(path, ...) local r =
  vim.fs.joinpath(path, ...); if r ~= '/' and r:sub(-1) == '/' then r =
  r:sub(1, -2) end; return r end` — the manual trailing-slash strip
  reproduces contract 1.5 (`vim.fs.joinpath('a','b/') == 'a/b/'`, keeps it,
  unlike the vimscript original which always strips the *final* trailing
  slash via its recursive single-arg base case).
- **`vim.fs.normalize(path)`** is a safe drop-in for `canonicalize`: purely
  lexical, no filesystem access, handles `.`/`..`/doubled-slash collapsing,
  and — critically — never crashes on excess `..` (clamps at root for
  absolute paths, preserves leading `..` for relative paths). Recommended:
  `M.canonicalize = function(path) return vim.fs.normalize(path, {
  expand_env = false }) end` (pass `expand_env=false` to avoid surprising
  `$VAR` expansion that the vimscript version never did).
- **`vim.fs.abspath(path)`** replaces `absolute()`'s `expand()` +
  `fnamemodify(...,':p')` combo without the filesystem stat (no
  trailing-slash quirk — see B-PATH-9). Verified: `vim.fs.abspath('~') ==
  '/home/<user>'`, `vim.fs.abspath('relative/dir')` resolves against cwd.
  Note it does **not** expand `$ENV_VARS` the way `expand()` did — if any
  caller relies on `$VAR` expansion (grep found none), fall back to
  `vim.fn.expand()` first.
- **`vim.fs.relpath(base, target)`** (also present in 0.12) is tempting for
  `relativize` but is the **wrong shape**: it only returns a path when
  `target` is a descendant of `base` and returns `nil` otherwise (verified:
  `vim.fs.relpath('/a/b/c','/a/x/y')` → `nil`). Our `relativize` must support
  sibling/`..`-style relative paths (journal → asset in a different month,
  etc.), so it needs a custom implementation (see fixed algorithm under
  B-PATH-7). Do not swap in `vim.fs.relpath`.
- `is_absolute`/`is_relative`/`split` are trivial string ops — no vim.fs
  helper needed; `vim.split(path, '/', { plain = true, trimempty = true })`
  reproduces `split()`'s embedded-empty-preserving, edge-trimming behavior
  precisely (verify with a test: `vim.split('a//b','/',{plain=true,trimempty=true})`).
- Treesitter is not applicable to this module (no buffer/syntax content).

## Suggested acceptance tests

Behavior to lock in (fixed versions, per the fix-in-port recommendations
above — flip to the "preserve" values in parens if the ADR decides
otherwise):

1. `join('a', 'b') == 'a/b'`
2. `join('a/', 'b') == 'a/b'`
3. `join('a', '/b') == 'a/b'`
4. `join('a/', '/b') == 'a/b'`
5. `join('a') == 'a'`; `join('a/') == 'a'`
6. `join('/') == '/'` (preserve-mode: `''`)
7. `join('a', '', 'b') == 'a/b'` (preserve-mode: `'a'`)
8. `join('a', 'b', 'c') == 'a/b/c'`
9. `absolute('~') == <home dir>`; result has no trailing `/` even though
   `<home dir>` exists as a directory (fix-in-port; preserve-mode: trailing `/`).
10. `is_absolute('/a/b') == true`; `is_absolute('a/b') == false`;
    `is_absolute('~/a') == false` (tilde is NOT treated as absolute).
11. `is_relative(p) == not is_absolute(p)` for a handful of inputs.
12. `split('/a/b/c') == {'/','a','b','c'}`
13. `split('a/b') == {'a','b'}`
14. `split('') == {}`
15. `split('a//b') == {'a','','b'}` (embedded empty preserved — do not
    silently "fix" this without checking `canonicalize` still filters it).
16. `relativize('/a/b/c.md', '/a/x.md') == '../b/c.md'`
    (relative_to's own filename `x.md` is excluded from the `..` count).
17. `relativize('/a/b/c', '/a/b') == 'c'` (fix-in-port; preserve-mode: `'b/c'`).
18. `relativize('/a/b', '/a/b') == '.'` (fix-in-port; preserve-mode: crash/empty-parts).
19. `canonicalize('/a/b/../c') == '/a/c'`
20. `canonicalize('/a/./b') == '/a/b'`
21. `canonicalize('/../../x') == '/x'` (fix-in-port; preserve-mode: `E684` crash).
22. `canonicalize('../../x') == '../../x'` (fix-in-port; preserve-mode: `E684` crash).
23. `canonicalize('/') == '/'` (fix-in-port; preserve-mode: `''`).

## Ported

**Lua module:** `lua/awiwi/path.lua` — `local M = {} … return M` shape, `require("awiwi.str")`
for `is_absolute`'s prefix check (DRY per SKILL.md: dep already ported, don't re-derive). All
fix-in-port recommendations applied. Spec: `tests/path_spec.lua` (30 `it` cases across 6
`describe` blocks, one per public function).

**Public API (all pure over their args except `absolute`):**
- `M.join(path, ...) -> string`
- `M.absolute(path) -> string`
- `M.is_absolute(path) -> boolean`
- `M.is_relative(path) -> boolean`
- `M.split(path) -> string[]`
- `M.relativize(path, relative_to) -> string`
- `M.canonicalize(path) -> string`

**Implementation notes (all per the brief's empirically-verified idiom recommendations):**
- `join`: `vim.fs.joinpath(path, ...)` then strip exactly one trailing `/` unless the result is
  literally `"/"`. This one-liner gets B-PATH-2 (native varargs, no `fn#apply`/`fn#spread`),
  B-PATH-3 (empty segment is a no-op, doesn't truncate) and B-PATH-5 (`join('/') == '/'`) for free,
  as the brief predicted.
- `absolute`: `vim.fs.abspath(vim.fn.expand(path))` — `expand()` first (keeps `~`/`~user`/`$ENV`/
  `%`/`#` expansion), `abspath` second (resolves against cwd, no filesystem stat → B-PATH-9 fixed,
  no spurious trailing slash).
- `is_absolute`/`is_relative`/`split`: exactly as specced; `split` uses
  `vim.split(path, "/", { plain = true, trimempty = true })` + manual `/` sentinel prepend for
  absolute paths.
- `canonicalize`: single-line delegation to `vim.fs.normalize(path, { expand_env = false })` —
  verified empirically this already implements the *fixed* B-PATH-6 semantics (clamps at root for
  absolute paths, preserves leading `..` for relative paths, never crashes) and B-PATH-5 (root
  preserved) with zero custom code needed.
- `relativize`: custom implementation (per brief — `vim.fs.relpath` has the wrong shape, doesn't
  support sibling/`..`-style results). B-PATH-7 fixed by initializing the common-prefix counter to
  the full compared length (not leaving it at the last-matched-index) and only lowering it on an
  actual mismatch; the `..`-count formula (`#relative_to - 1 - common`) is clamped to `math.max(0,
  ...)` so the now-correct full-prefix-match case (which drives `common` up to where the old
  formula would go negative) can't underflow. Empty result list returns `"."` (identical-path case).

**IMPORTANT — coordination requirement for T6a (`hi.vim` port):** `hi.vim:129-130`
(`awiwi#hi#get_recipe_title()`) contains a live compensating workaround for B-PATH-7
(`relativize(...)->awiwi#path#split()[1:]`, manually stripping the spurious leading component the
old buggy vimscript produced). **`M.relativize` in this Lua port is already fixed** — do NOT
port that `[1:]`/first-component-strip workaround into the Lua `hi` module. Doing so would
double-cancel: the fix removes the extra leading component that the workaround was designed to
strip, so re-applying the workaround on top of the fixed function will silently eat one path
component too many and re-break `get_recipe_title()`. Call `path.relativize` directly, unmodified.

**Deviation from brief's suggested test 16:** the brief's acceptance-test example
`relativize('/a/b/c.md', '/a/x.md') == '../b/c.md'` does not match hand-tracing the specified
algorithm (6.2) against that literal input — the correct result for those exact arguments is
`'b/c.md'` (verified by tracing the algorithm and cross-checked against the still-executable
parts of the live vimscript, e.g. `relativize('/a/b','/a/b') == 'b'`, which matches the brief's
own B-PATH-7 preserve-mode note and confirms the trace method). `'../b/c.md'` is only correct if
`relative_to` is a genuine sibling like `/a/d/x.md`, not a prefix like `/a/x.md`. The acceptance
test in `tests/path_spec.lua` locks in the corrected pair instead:
`relativize('/a/b/y/c.md', '/a/b/x/d.md') == '../y/c.md'`. See
`.claude/progress/lua-port-engineer-path.md` for the full derivation. This is a documentation
correction, not a behavior-contract hole — the underlying algorithm (6.1-6.3) is unambiguous.

**Dropped as dead code:** the 3+-arg `join` recursion's original dependency on the unvendored
`fn#apply`/`fn#spread` VimL plugin (B-PATH-2) is fully gone — native Lua varargs replace it, no
compatibility shim needed, per the brief's confirmation that this path was already dead/broken in
the shipped vimscript.

**Test count:** 30 (targeted `tests/path_spec.lua`); full suite 58 passed, 0 failed
(`nvim --clean --headless -l tests/run.lua`), 3 files (`smoke_spec.lua` + `str_spec.lua` +
`path_spec.lua`).

**Gotchas for T3+ (date is next):** `path.lua` has zero filesystem/global-state side effects
except `absolute()`'s `vim.fn.expand`/`vim.fs.abspath` calls (no stat, no read/write of `g:`).
`relativize`'s fixed behavior is the one deviation from "just port the vimscript" worth
re-reading before any caller assumes the old (buggy) shape — re-check any hand-derived expected
values against `M.relativize` directly rather than against the vimscript source once other
modules' specs reference it.

status: done
