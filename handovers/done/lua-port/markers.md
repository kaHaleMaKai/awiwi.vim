# lua-port / markers

**Responsibility:** Single source of truth for the fixed "marker keyword" vocabularies
(`TODO`, `FIXME`, `@urgent`, `DUE`, …) that classify journal/todo lines, plus the
escaping/joining logic that turns those vocabularies into either a Vim-regex alternation
(for `syntax/awiwi.vim`/`syn.lua`) or an rg/PCRE-flavored alternation (for `cmd.vim`'s
`rg`-based `Awiwi tags`/`search` shell-outs and `server.vim`'s `config.json`). Pure data +
string transforms — no buffers, no files, no shelling out.

**Source:** `autoload/awiwi.vim:43-66` (the marker word lists, `s:*_markers`) and
`autoload/awiwi.vim:179-204` (`awiwi#get_markers`, the one public function), plus
`autoload/awiwi.vim:266-268` (`s:escape_rg_pattern`, private helper this function depends
on) and `autoload/awiwi/util.vim:13-15` (`awiwi#util#escape_pattern`, the sibling escaper
for vim-regex mode — **already ported** per `handovers/lua-port/str.md`/`util` port order;
`markers.lua` should `require('awiwi.util')` for this rather than reimplementing it, unless
`util.lua`'s actual shipped surface doesn't expose it — check `handovers/lua-port/*.md` for
`util` before writing this).

## Public surface

Only one function exists in vimscript; the port should mirror it 1:1 (this is a small, purely
functional module — no reason to redesign it):

- `awiwi#get_markers(type: string, opts?: {join: bool = true, escape_mode: 'rg'|'vim' =
  'rg'}) -> string | string[]`
  (`autoload/awiwi.vim:179-204`)
  - `type` must be one of the ten marker-list names (see below); anything else **throws**
    `AwiwiError: type <type> does not exist` (checked via `exists('s:<type>_markers')` in
    vimscript — the Lua port should use an explicit lookup table, not a dynamic-existence
    check, since `s:`-scope introspection has no Lua equivalent and a table lookup is
    strictly better here).
  - Looks up the built-in list for `type`, appends `g:awiwi_custom_<type>_markers` (default
    `[]`) if the user has set it, escapes every entry (mode-dependent, see below),
    `uniq()`s the result (**vimscript `uniq()` only dedupes *adjacent* duplicates in a
    list — it is not a full-list dedupe**; since escaping happens immediately before
    `uniq()`, adjacent duplicates would only occur today if `type`'s own list already has
    the same literal string twice in a row *before* escaping — it doesn't, for any of the
    ten built-in lists — but a user's `g:awiwi_custom_<type>_markers` list appended at the
    tail could reintroduce an existing marker as a true duplicate and it would **not** be
    deduped unless adjacent to another copy of itself; port faithfully as adjacent-only
    dedupe, do not silently upgrade to full-list dedupe, that would be a behavior change
    beyond this brief's scope — flag as **preserve**, not a bug worth fixing without ADR
    sign-off).
  - `type == 'todo' && escape_mode == 'rg'` (i.e. **only** in the default-options case for
    `todo`): appends one more literal pattern string, unescaped, to the end of the list
    before joining — see **Bug found #1** below, this is broken.
  - If `opts.join` (default `true`): returns a single string, entries joined by `|`
    (`rg`/PCRE mode) or `\|` (`vim` mode). If `false`: returns the list of escaped strings,
    unjoined.
  - Throws are vimscript `throw` (`AwiwiError: ...` string) — Lua port should `error(...)`
    with the same message text (callers today don't catch/pattern-match on the message
    content anywhere in the codebase, confirmed by grep, so exact string preservation is
    nice-to-have, not load-bearing).

## Marker vocabularies (exact strings — copy verbatim, case matters)

All ten lists, from `autoload/awiwi.vim:43-66`:

| `type` | built-in list (`markers.lua` internal name suggestion) |
| --- | --- |
| `todo` | `{'TODO', '@todo'}` |
| `onhold` | `{'ONHOLD', 'HOLD', '@onhole', '@onhold'}` (**`@onhole` is a typo for `@onhold`, see B3 cross-ref**) |
| `urgent` | `{'FIXME', 'CRITICAL', 'URGENT', 'IMPORTANT', '@fixme', '@critical', '@urgent', '@important'}` |
| `delegate` | `{'@@'}` |
| `question` | `{'QUESTION', 'q?', 'Q?'}` |
| `due` | `{'DUE', 'DUE TO', 'UNTIL', '@until', '@due'}` |
| `incident` | `{'@incident'}` |
| `change` | `{'@change'}` |
| `issue` | `{'@issue'}` |
| `bug` | `{'@bug'}` |

**Custom extension**: `g:awiwi_custom_<type>_markers` (list of strings, default `[]`) is
read fresh on every `get_markers` call (not cached) — appended **after** the built-in list,
before escaping. `vim.g.awiwi_custom_<type>_markers` in the port, same per-call re-read
(these are meant to be user-editable at runtime, e.g. from an `.nvimrc`, without restarting).

## Escaping rules (mode-dependent — this is the part most worth getting exactly right)

- `escape_mode = 'vim'` → `awiwi#util#escape_pattern(marker)` =
  `escape(marker, " \t.*\\[]")` (escapes space, tab, `.`, `*`, backslash, `[`, `]` — i.e.
  Vim magic-mode metacharacters, plus whitespace so multi-word markers like `'DUE TO'`
  become a literal `DUE\ TO` safe to embed in a `\|`-joined alternation without the space
  being reinterpreted). **This function already exists in ported `util.lua`** (per the port
  order, `util` is ported before this module ever needs to run standalone) — `require` it,
  do not reimplement.
- `escape_mode = 'rg'` (**default**) → `s:escape_rg_pattern(marker)` =
  `escape(marker, ".*?\\[]")` (escapes `.`, `*`, `?`, backslash, `[`, `]` — **notably does
  NOT escape whitespace**, unlike the vim-mode escaper; a marker containing a literal space,
  e.g. `'DUE TO'`, is passed through with the space untouched, which is fine for
  rg/PCRE-flavored alternation since a literal space needs no escaping there). This helper
  is private (`s:escape_rg_pattern`, `autoload/awiwi.vim:266-268`) — not exposed as
  `awiwi#util#...`, so it belongs **inside `markers.lua`** as a local function, not
  `util.lua`.
- Both escapers run through `uniq()` after mapping (adjacent-dedupe only, see above).
- Join character: `'\|'` for `vim` mode, `'|'` for `rg` mode (only when `opts.join` is
  truthy).

## Consumers (who calls this, and how — cite file:line)

1. `syntax/awiwi.vim:100,104` — `awiwi#get_markers('urgent'|'due', {'escape_mode':
   'vim'})` (no `join` override, so joined), embedded into
   `\C\<%s\>/` word-bounded `syn match` patterns. See `handovers/lua-port/syn.md` items 5, 7.
2. `syntax/awiwi.vim:64,69,73,76` (helper chain `s:inHeaderWithMarkers` →
   `s:inHeaderWithSimpleMarkers`) — same `escape_mode: 'vim'`, called for `type='todo'`,
   `'question'`, `'onhold'` (`syntax/awiwi.vim:93-95`). See `syn.md` item 4.
3. `ftplugin/awiwi.vim:202` — `awiwi#get_markers('due', {'join': v:false, 'escape_mode':
   'vim'})`, unjoined list re-joined locally with `\|` (`let ms = join(markers, '\|')`) to
   build a due-date-toggle pattern (`~~due-marker~~` strike-through detection when marking a
   task list item done/undone). This is a `cmd`-adjacent consumer (task-toggle keymap
   defined in `ftplugin/awiwi.vim`, not yet a brief in this transaction — note for whichever
   transaction ports `ftplugin`/`cmd`'s toggle logic).
4. `autoload/awiwi/cmd.vim:656,662,665,670,673,676,679,682,685` (`awiwi#cmd#show_tasks`,
   backing `:Awiwi tags [urgent|todo|due|onhold|question|incident|change|issue|bug|all]`)
   — **default options** (no override → `escape_mode='rg'`, joined), for **all ten** types
   except `delegate` (delegate is never included in the tags/tasks rg search — confirmed,
   `cmd.vim:646-692` has no `awiwi#get_markers('delegate')` call anywhere). Results are
   `|`-joined again across types (`cmd.vim:694: let pattern = join(markers, '|')`) and
   shelled to `rg` (`cmd.vim:695-698`). The `due`-type result is additionally wrapped:
   `printf('\(?(%s):?( \S+)*\)?', due)` (`cmd.vim:666`) — **note this wrapper itself mixes
   syntaxes**: `\(...\)`/`?` used as if literal-paren-then-optional in some hybrid style;
   this wrapper is a `cmd.vim`-owned pattern, not `markers.lua`'s concern, but flag for
   whoever ports `cmd.vim`'s `show_tasks` that it should be sanity-checked against a real
   `rg` invocation (same class of risk as Bug #1 below).
5. `autoload/awiwi/server.vim:27-30` (`s:write_json_config`, called when the server starts)
   — loops `for marker in ['todo', 'onhold', 'urgent', 'delegate', 'question', 'due']`
   (**six** of the ten types — `incident`/`change`/`issue`/`bug` are **not** exported to
   `config.json`, confirmed, not a bug, just documenting scope), calling
   `awiwi#get_markers(marker, {'join': v:false})` (default `escape_mode='rg'`, unjoined list)
   and writing each as `<type>_markers` key in the JSON config the FastAPI/Flask viewer
   reads. **This is the only consumer that hits the `todo`+`rg` buggy branch (#1 below) via
   an unjoined list** — i.e. the server's `todo_markers` array in `config.json` will contain
   the literal broken Vim-flavored string as one of its array entries, not merged into a
   joined pattern; whatever the server does with that array (presumably its own
   join/compile) inherits the bug.
6. `cmd.vim:662` (inside `show_tasks`, already covered by #4) is the **other** consumer of
   the buggy `todo`+`rg` branch, via the joined/`|`-merged path.

## Bugs found

- **Bug #1 (new, this transaction)** — `autoload/awiwi.vim:194-197`:
  ```vim
  if a:type == 'todo' && options.escape_mode == 'rg'
    let task_list = '\(^[[:space:]]*\)\zs[-*][[:space:]]+\[[[:space:]]+\]'
    call add(result, task_list)
  endif
  ```
  This extra alternative is meant to detect an open task-list bullet (`- [ ]`) as an
  additional "todo" signal for `rg`-based search, but it's written in **Vim-regex syntax**
  (`\(`, `\)`, `\zs`) while every other entry in the same joined pattern is rg/PCRE-flavored.
  In rg's default regex engine: `\(` and `\)` are literal parentheses (not grouping — rg
  needs bare `(`/`)` for groups), and `\z` is `\z`+literal-`s`, not a Vim-style
  zero-width "start match here" marker. Two possible outcomes depending on whether the
  installed rg's regex crate accepts `\z` as a valid escape at all:
  (a) it compiles but the `\z...s` sub-expression can never match (a "start of haystack
  or end of haystack" assertion immediately followed by a required literal `s` is
  self-contradictory) → this alternative is silent dead weight, matches nothing, ever;
  (b) `\z` is rejected outright by the regex engine → the **entire** compiled pattern
  (all markers joined by `|`) fails, and the whole `rg` invocation errors out, breaking
  `:Awiwi tags todo`/`:Awiwi tags all` (`cmd.vim`) and the `todo_markers` value written to
  `config.json` (`server.vim`) entirely — not just this one alternative.
  **Recommend: verify empirically against the actual `rg` binary in the target environment
  (`rg --pcre2` off/on matters too — check which mode `cmd.vim`'s invocation uses), then fix
  in port** — replace with a correct rg-flavored equivalent, e.g. (untested sketch, verify
  before shipping) `(?m)^\s*[-*]\s+\[\s+\]` or drop the multi-line anchor requirement
  entirely if `cmd.vim`'s `rg` invocation processes one line at a time. This is not a
  "preserve for compatibility" case — an always-dead-or-fatal branch has no compatibility
  value to preserve.
- **Cross-reference (documented in full in `handovers/lua-port/syn.md`, B3)** — the
  `onhold` list's `@onhole` entry is a typo for `@onhold`. `markers.lua`'s job is only to
  decide: keep `@onhole` as a permanent backward-compat alias (recommended — zero cost,
  documented in `syn.md`), or drop it (ADR call, would silently stop matching any existing
  note text that uses the typo). Do not silently drop it without the ADR.
- **`uniq()` adjacent-only dedupe** (documented above, not filed as a numbered bug — it's
  existing, intentional-enough vimscript behavior) — flagging here so the Lua port doesn't
  "improve" it into a full-list dedupe without being asked; a user's custom marker list
  colliding with a built-in one, non-adjacently, will produce a duplicate alternative in the
  final pattern today, and should continue to after the port, unless an ADR says otherwise.

## Port notes

- Straightforward pure-function port: a Lua table `M.lists = {todo = {...}, onhold =
  {...}, ...}` (ten entries, exact strings above) + `M.get_markers(type, opts)`.
- `opts.escape_mode` default `'rg'`, `opts.join` default `true` — preserve vimscript
  defaults exactly (multiple call sites rely on the defaults implicitly, see Consumers #1
  server.vim, #4 cmd.vim — none of them pass `escape_mode` explicitly except the two
  `'vim'`-mode call sites in `syntax/awiwi.vim`/`ftplugin/awiwi.vim`).
- `s:escape_rg_pattern` (`escape(s, ".*?\\[]")`) has no nvim builtin equivalent — implement
  as a small local Lua function using `string.gsub` with a character class matching
  `[%.%*%?\\%[%]]`, prefixing each with `\`. Double-check Lua string escaping of the
  gsub pattern itself (the backslash needs care both as the *replacement prefix* and inside
  the *pattern* matching a literal backslash).
- `awiwi#util#escape_pattern` for `'vim'` mode: confirm exact shipped signature/name in
  `util.lua`'s port brief/implementation (`handovers/lua-port/util.md` if it exists yet, or
  the module itself once ported) before assuming a 1:1 name — `require('awiwi.util')` and
  call whatever it actually exports; do not duplicate the escaping logic here.
- `uniq()`: Lua has no builtin adjacent-list-dedupe; implement a 3-line loop (`if result[i]
  ~= result[i-1] then table.insert(...) end`), matching vimscript `uniq()`'s exact semantics
  (adjacent-only, first occurrence kept, list must already be in the order dedup should
  apply — no sorting happens before or after, preserve insertion order).
- No treesitter/nvim-API opportunity here — this module is pure string/table manipulation,
  zero UI or buffer surface. The only "port idiom" of note is `vim.g.awiwi_custom_<type>_markers`
  replacing `get(g:, ...)`, per the standard idiom table.
- Type-validation: vimscript throws `AwiwiError: type <type> does not exist` via a dynamic
  `exists()` check against `s:<type>_markers`; Lua port should validate against the `M.lists`
  table's keys (`if not M.lists[type] then error(...) end`) — equivalent behavior, cleaner
  implementation, no dynamic-scope introspection needed.

## Suggested acceptance tests

1. `get_markers('todo')` (defaults: `join=true`, `escape_mode='rg'`) → a `|`-joined string
   containing escaped `TODO` and `@todo`, **plus** whatever the fixed (or, if deferred,
   the original-but-verified-dead) task-list alternative resolves to per Bug #1's
   resolution — write this test only after Bug #1's fix-in-port lands; do not assert on the
   broken string.
2. `get_markers('due', {escape_mode='vim'})` → `\|`-joined, `'DUE TO'` becomes literal
   `DUE\ TO` (space escaped) somewhere in the result.
3. `get_markers('due', {escape_mode='rg'})` → `'DUE TO'` appears with an **unescaped**
   literal space (rg mode doesn't escape whitespace).
4. `get_markers('onhold', {join=false})` → Lua table containing (escaped) `'ONHOLD'`,
   `'HOLD'`, `'@onhole'`, `'@onhold'`, in that order, four entries, no dedupe collapse
   (none are adjacent duplicates).
5. `vim.g.awiwi_custom_urgent_markers = {'@blocker'}`; `get_markers('urgent', {join=false})`
   → built-in eight entries followed by escaped `'@blocker'` as the ninth, order preserved.
6. `get_markers('urgent')` twice in a row with different `g:awiwi_custom_urgent_markers`
   values between calls → second call reflects the new custom list (no caching across
   calls).
7. `get_markers('bogus_type')` → errors (message should mention `bogus_type`); does not
   silently return `nil`/empty string.
8. Adjacent-duplicate preservation: built-in list with two identical *adjacent* custom
   entries `{'@x', '@x'}` appended → `uniq()`-style collapse to one `'@x'` at the tail; a
   *non-adjacent* duplicate (custom `{'@urgent'}` appended to the `urgent` list, which
   already contains `'@urgent'` earlier, non-adjacently) → **both** copies survive
   (documents the "preserve, don't silently improve" bug-adjacent behavior above).
9. `get_markers('delegate')` → single-entry result `'@@'` (escaped trivially, no special
   chars to escape).

## Ported

**Lua module:** `lua/awiwi/markers.lua` (`local M = {} … return M`), `require("awiwi.util")`
for the vim-mode escaper (`M.escape_pattern`) — no new deps introduced. Pure data + string
transforms, no buffers/files/shell-outs, as scoped. Spec: `tests/markers_spec.lua` (11 `it`
cases, 1 `describe` block).

**Public API:**

- `M.lists` — the raw table of ten marker vocabularies (`todo`, `onhold`, `urgent`,
  `delegate`, `question`, `due`, `incident`, `change`, `issue`, `bug`), exact strings
  preserved verbatim including the `@onhole` typo alias. Exposed (not just a private local)
  because `syn.lua` reads it directly for its line-local marker painting instead of
  round-tripping through `get_markers`'s escape/join machinery (DRY — see syn.md's own
  `## Ported` "Consumes" note).
- `M.get_markers(type_, opts)` → `string` (joined, default) or `string[]` (`opts.join =
  false`). `opts.escape_mode` is `'rg'` (default) or `'vim'`. Errors
  (`"AwiwiError: type %s does not exist"`) for an unknown `type_`. Reads
  `vim.g.awiwi_custom_<type_>_markers` fresh on every call (no caching).

**Bug #1 verdict (empirical, against the real `rg` binary):** the legacy fragment
(`\(^[[:space:]]*\)\zs[-*][[:space:]]+\[[[:space:]]+\]`) compiles under rg's regex crate
without erroring — `\(`/`\)` are literal parens there (not grouping), and `\z` is a
recognized "end of haystack" zero-width anchor — but it is permanent dead weight: `\zs` (its
leading `\z` component) asserts absolute end-of-haystack immediately followed by a required
literal `s`, which can never both hold. Outcome matches the brief's predicted case (a):
"compiles but never matches". **Fixed in port**, not preserved: replaced with a real,
self-contained rg pattern for an open task-list bullet, `^\s*[-*]\s+\[\s+\]` (`local
OPEN_TASK_BULLET_RG` in the module) — verified via a live `vim.system({"rg", "-e", ...})`
integration test in the spec (not just a static "no more dead syntax" check). No `(?m)`
multiline flag needed since `rg`'s default mode is already line-by-line.

**Deviations from brief:** none of substance — `s:escape_rg_pattern`'s exact escape set
(`.`, `*`, `?`, `\`, `[`, `]`) and `uniq()`'s adjacent-only dedupe semantics are preserved
exactly as specified (see spec's "adjacent-vs-non-adjacent dedupe" test, which pins the
"preserve, don't silently improve" behavior called out in the brief's Bugs section).

**Test count:** 11 (targeted `tests/markers_spec.lua`); full suite 266 passed, 3 failed
(`nvim --clean --headless -l tests/run.lua`, 9 files) — the 3 failures are pre-existing,
unrelated `date_spec.lua` flakiness (system-clock date rollover mid-session), not touched by
this transaction.

**What T10 needs:** nothing beyond `require("awiwi.markers")` — this module has no
activation/attach lifecycle of its own; it's pure data consumed by `syn.lua` (line-local
marker vocab) and, per the brief, eventually by `cmd.lua`'s `rg`-based search/tags commands
and `server.lua`'s `config.json` (both still pending their own port transactions).

status: done
