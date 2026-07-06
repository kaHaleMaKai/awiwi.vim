# lua-port / syn

**Responsibility:** Buffer-local structural + line-local decoration for awiwi markdown
buffers — headings/list/task/link/code-fence painting normally done by `:syntax`
(`syntax/awiwi.vim`), reimplemented as a single treesitter-driven extmark repaint pass, plus
a small set of "marker keyword" / modeline / redaction highlights that are inherently
line-local text patterns, not markdown structure.

**Source of the contract:** `syntax/awiwi.vim` (214 lines) — a legacy `:syntax` file loaded
once per buffer by nvim's `synload.vim` when `'filetype'` is set to `awiwi`/`awiwi.todo`
(see ftdetect notes below). It is *not* an `autoload/awiwi/*.vim` module — it has **no**
`awiwi#syn#*` functions today; there is nothing to "port 1:1" call-signature-wise. This brief
therefore both specs the legacy visual contract *and* proposes the new Lua module surface
(see Port notes).

**IMPORTANT — a much-earlier read of this file (via a caching/compression proxy in this
environment) produced corrupted output that showed several active lines as vimscript
comments and vice versa.** All facts below were re-verified line-by-line against the raw
file with `awk 'NR==N'` after that corruption was caught. Do not trust any transcript of
`syntax/awiwi.vim` that shows the `contains=`/`containedin=` clauses on the `awiwiRedacted`
region (lines 83-84) as quoted-out comments — they are **live** in the shipped file.

## Why the runtime doesn't need `runtime! syntax/markdown.vim` (line 6, commented out)

Not a bug. `ftdetect/awiwi.vim` never sets a dotted filetype (`markdown.awiwi`); it sets
plain `awiwi`/`awiwi.todo`/`awiwi.asset`/`awiwi.recipe` — but only *after* the buffer briefly
had `'filetype'` = `markdown` (from the file's `.md` extension and stock/plugin markdown
ftdetect), which already triggered `syntax/markdown.vim` and left `markdownH1..H6`,
`markdownCode`, `markdownCodeBlock`, `markdownCodeDelimiter`, `markdownList`,
`markdownListMarker`, `markdownStrike`, `markdownStrikeDelimiter`, `htmlStrike` defined
before `awiwi.vim`'s ftdetect autocmd flips `'filetype'` to `awiwi`. `syntax/awiwi.vim`'s
`containedin=markdown*`/`contains=markdown*`/`hi link ... htmlStrike` clauses lean on those
groups already existing from that transient moment. **The Lua/treesitter port has no
equivalent** — there is no `:syntax` file to piggy-back on, and treesitter's own markdown
highlighting uses `@markup.*` captures, not `markdownH1`-style group names. This is why the
binding architecture below derives heading/list/code-fence regions structurally from
`vim.treesitter` queries instead of relying on borrowed group names.

## Public surface (proposed — no 1:1 vimscript source)

`syntax/awiwi.vim` is fire-and-forget: nvim's `:syntax`/`synload.vim` machinery sources it
once per buffer, no callable API exists. The Lua module needs an attach/detach lifecycle
instead (nothing currently drives repaints on edits — the legacy file paints once at load
and never repaints, which is itself only "correct" because Vim's regex syntax engine
re-evaluates matches live on every screen redraw; extmarks do not, so the Lua port must
explicitly repaint on buffer change):

- `M.attach(bufnr) -> nil` — full structural + line-local repaint of `bufnr`. Idempotent:
  clears this module's namespaces first, then repaints. Called from `ftplugin/awiwi.*`
  (`FileType awiwi,awiwi.todo` autocmd) and from a debounced `TextChanged`/`TextChangedI`
  autocmd (mirror `hi.lua`'s `redraw_due_dates` debounce pattern — reuse the same
  `w:last_redraw`-style guard rather than inventing a second one).
- `M.detach(bufnr) -> nil` — clears every namespace this module owns for `bufnr` (used on
  `BufDelete`/filetype-change-away, and by tests to reset state between cases).
- `M.setup_highlights() -> nil` — one-time (module-load-time is fine) `nvim_set_hl(0, name,
  attrs)` calls for every static color in the contract below (idempotent, safe to call more
  than once — do not gate behind a guard that a test-suite re-`require` would trip).

No `g:`/`s:` state is read by `syntax/awiwi.vim` itself except the `g:awiwi_*` config
globals enumerated in the contract (all read once at attach-time is fine; they are not
expected to change mid-session, matching legacy behavior where they're read once at
`:syntax` load time).

**Reads:** `vim.g.awiwi_highlight_links`, `vim.g.awiwi_conceal_links`,
`vim.g.awiwi_conceal_link_start_char`, `vim.g.awiwi_conceal_link_end_char` (legacy code
never actually reads this one — see B1), `vim.g.awiwi_conceal_link_target_char`,
`vim.g.awiwi_conceal_link_internal_target_char`, `vim.g.awiwi_domain_color`,
`vim.g.awiwi_link_color`, `vim.g.awiwi_link_style`, buffer `filetype`/`'ft'` (to gate the
`.todo`-only task-date group definitions and, in the port, to decide whether the
`task_list_marker_checked`/`unchecked` queries are needed at all — they're markdown-grammar
universal, `.todo` gating in the legacy file is about which *highlight groups get defined*,
not which nodes exist).

**Writes:** extmarks only (buffer text and `b:current_syntax` are never touched by the port
— that variable is a `:syntax`-engine artifact with no Lua-port equivalent and should not be
set).

**External:** `require('awiwi.mdstruct')` (new shared module specified in `handovers/lua-port/hi.md`
Port notes — see below), `require('awiwi.markers')` (this transaction's sibling brief).
`vim.treesitter.get_parser`/`vim.treesitter.query.parse` for `markdown` and
`markdown_inline` languages (bundled with nvim ≥0.11; verify present via
`vim.treesitter.language.add('markdown')` at module load, error clearly if absent — the
legacy file has no equivalent failure mode since regex syntax always "works").

## Behavior contract

Numbered by syntax concern, in file order. Each item states: pattern/node, highlight
group(s), conceal behavior, containment, and target bucket (**TS** = treesitter-structural,
**LUA** = line-local Lua pattern outside the code mask, **STATIC** = unconditional color
definition with no pattern of its own).

1. **STATIC palette** (`syntax/awiwi.vim:10-24`, always defined regardless of any `g:`
   flag): `awiwiUrgent` `guifg=#d7ff00 guibg=#807000 gui=bold`; `awiwiDelegate`
   `guifg=#20e020 gui=italic`; `awiwiDue` `guifg=#d7ff00 gui=bold`; `awiwiList1`
   `guifg=#808000 gui=bold`; `awiwiList2` `guifg=#0087af gui=bold`; `awiwiListBadSpaces`
   `guibg=#626262 gui=bold`; `awiwiListBadSpacesAfterCheckbox` `guibg=#626262 gui=bold`;
   `awiwiTaskListOpen1` `guifg=#808000 gui=bold` (**same values as `awiwiList1` today** —
   distinct group, currently visually identical, keep separate per "preserve group names");
   `awiwiTaskListOpen2` `guifg=#0087af gui=bold` (ditto vs. `awiwiList2`); `awiwiFileTypePrefix`
   `guifg=#9e9e9e`; `awiwiFileType` `guifg=#808000 gui=bold`; `awiwiLinkPath`
   `guifg=#9e9e9e`; `awiwiRedminePath` `guifg=#9e9e9e` (**dead** — no match/region anywhere
   references this group, see Bugs); `awiwiRedactedCause` `guifg=#8a8a8a gui=bold`;
   `awiwiRedactedTag` linked to `awiwiUrgent`. Bucket: STATIC.

2. **Redacted block** (`:79-87`) — region `awiwiRedacted` starts at literal `!!redacted`
   (case-sensitive) to end of line, `keepend`, contains `awiwiRedactedTag` (re-matches the
   literal `!!redacted` token itself, styled as `awiwiUrgent`) and `awiwiRedactedCause`
   (`[[:space:]]\+.*` — everything after the first run of whitespace following the tag,
   styled `awiwiRedactedCause` gray+bold). `containedin=markdownH1..H6,markdownCode` on the
   outer region is a no-op today (see "why runtime doesn't need markdown.vim" — those groups
   exist transiently, so it *does* work in practice) but functionally the region is
   *unrestricted* (not itself `contained`), so `!!redacted…` is recognized on **any** line,
   heading or body, code-fenced or not. Bucket: LUA (a line starting-with/containing
   `!!redacted` → highlight from that point to EOL as `awiwiRedacted`, then re-highlight the
   literal tag substring as `awiwiRedactedTag`/`awiwiUrgent` and the remainder as
   `awiwiRedactedCause`). No code-mask exclusion in the legacy file (fires inside fences
   too) — preserve or fix is an ADR call; recommend **preserve** (redaction is a
   deliberate, user-typed directive; suppressing it inside a fenced code block someone
   redacted on purpose would be surprising).

3. **`@change`/`@incident`/`@issue`/`@bug` → `awiwiUrgent`** (`:89-92`, via
   `s:tagInHeader`). Pattern: token preceded by whitespace-or-line-start, followed
   (lookahead, not consumed) by whitespace-or-line-end, case-sensitive. **Despite the
   function name (`tagInHeader`) and the `containedin=markdownH1..H6` clause, these matches
   are never declared `contained`, so they are top-level and fire on any line, not just
   headings** — `containedin=` only forces recognition inside those groups *if* the header
   group's own `contains=` would otherwise exclude non-contained items; it does not restrict
   the match elsewhere. Treat as plain "marker anywhere" highlights. hi: `hi link
   awiwiChange/awiwiIncident/awiwiIssue/awiwiBug awiwiUrgent`. Bucket: LUA, masked by
   fenced-code lines (see Bugs B10 — legacy doesn't mask, port should).

4. **`todo`/`question`/`onhold` marker groups** (`:93-95`, via
   `s:inHeaderWithSimpleMarkers` → `awiwi#get_markers(type, {'escape_mode':'vim'})`, joined
   `\|`). Same "anywhere, not header-restricted" caveat as #3. Groups today: `awiwiTodo`,
   `awiwiQuestionn` (typo, see B3), `awiwiOnHole` (typo, see B3). Style for all three: `gui=bold
   guifg=#808000` (identical to `awiwiList1`/`awiwiTodo`'s own color — a shared "action
   marker" yellow). Marker word lists come from `markers.lua` (sibling brief) — `todo_markers`
   = `TODO`, `@todo`; `question_markers` = `QUESTION`, `q?`, `Q?`; `onhold_markers` =
   `ONHOLD`, `HOLD`, `@onhole`, `@onhold`. Bucket: LUA, masked (same B10 caveat).

5. **`awiwiUrgent` full marker set** (`:100`) — `exe printf('syn match awiwiUrgent
   /\C\<%s\>/ contains=markdownCode,markdownCodeBlock,markdownCodeDelimiter',
   awiwi#get_markers('urgent', {'escape_mode':'vim'}))`. Word-bounded (`\<...\>`),
   case-sensitive. Marker list (`markers.lua` `urgent`): `FIXME`, `CRITICAL`, `URGENT`,
   `IMPORTANT`, `@fixme`, `@critical`, `@urgent`, `@important`. The `contains=markdownCode,…`
   clause is a **no-op for a `match`** (a `match` has no interior to recurse `contains=`
   into beyond a possible embedded end-of-match token) and — combined with the item not
   being `contained` — does **not** stop this marker from also matching inside fenced code
   (see B10). Bucket: LUA, masked in the port.

6. **`@@delegate`** (`:102`) — hardcoded regex `\C@@[-a-zA-Z.,+_0-9@]\+[a-zA-Z0-9]`
   (**not** driven by `markers.lua`'s `delegate_markers=['@@']` list — that list exists in
   `awiwi.vim` but this pattern is independently hand-written here and must match a
   trailing identifier-ish token, e.g. `@@jdoe`, `@@first.last-2@x`, ending in an
   alphanumeric). Group `awiwiDelegate`. Bucket: LUA, masked in the port.

7. **`awiwiDue` full marker set** (`:104`) — same shape as #5, marker list (`markers.lua`
   `due`): `DUE`, `DUE TO`, `UNTIL`, `@until`, `@due`. Same no-op `contains=` /
   fires-inside-fences caveat as #5 (B10). Bucket: LUA, masked in the port.

8. **`syn clear markdownListMarker`** (`:106`) — legacy-only cleanup, un-defines the borrowed
   markdown plugin's own bullet-marker highlighting so awiwi's own List1/List2 groups are
   visible instead. **No-op in the port** — treesitter highlighting doesn't use
   `markdownListMarker`, nothing to clear.

9. **List bullets, level 1 / level 2** (`:107-108`) — `awiwiList1` = `^[-*] ` (bullet + one
   space at column 0); `awiwiList2` = 2-space-indented bullet + one space
   (`^[[:space:]]\{2}\)\zs[-*] `, only the bullet+space is matched, indent itself
   discarded). Only two indent buckets exist today (0 and exactly-2-space); anything deeper
   falls through unstyled by either. On a task-list line (`- [ ] foo`), this ALSO matches
   (task lines start with the same `- `), but is subsequently shadowed for that column
   range by `awiwiTaskListOpen1/2` (item #11) because that group is *defined later* in the
   file (Vim breaks same-start-position ties by definition order, later wins) — net visible
   effect today is zero difference since both groups render identically (see #1). Bucket:
   **TS** — derive bullet position and *nesting depth* from the `list_item` node (treesitter
   gives true depth, not just "0 or 2 spaces" — a real improvement opportunity, see Port
   notes) rather than counting leading spaces with a Lua pattern.

10. **Canceled (struck-through) list item** (`:109`) — `awiwiCanceledList` =
    `\(^[[:space:]]\{0,2}\)\zs[-*] \~\~.*` (0-or-2-space indent, bullet+space, then literal
    `~~` through EOL — i.e. `- ~~done thing~~`), `contains=markdownStrike,
    markdownStrikeDelimiter` (again a no-op for a `match`). Highlight: `hi link
    awiwiCanceledList htmlStrike` (`:124`, defined unconditionally, order-independent of the
    match definition). Bucket: LUA line-pattern for the `~~…~~` detection refining a **TS**
    `list_item` hit; masked in the port (no legacy masking).

11. **List "bad spaces"** (`:111-112`) — `awiwiListBadSpaces` = one-or-more extra spaces
    immediately after a bullet (optionally after a `[ ]`/`[x]` checkbox token) at any indent;
    `awiwiListBadSpacesAfterCheckbox` = one-or-more extra spaces specifically after
    `[-*][[:space:]]\+\[[ x]\] ` (bullet + checkbox already-consumed). Both styled with gray
    background (`guibg=#626262 gui=bold`) — a "you typed too many spaces" nag highlight.
    Bucket: LUA (fine-grained whitespace check on lines already identified as `list_item`
    by TS), masked in the port.

12. **Open task checkboxes, level 1 / level 2** (`:114-115`) — `awiwiTaskListOpen1` =
    `^[-*] \[ \]` (column 0); `awiwiTaskListOpen2` = 2-space-indented equivalent. Only
    matches the **unchecked** `[ ]` form (this is what treesitter markdown's
    `task_list_marker_unchecked` node captures directly — no need for the two-indent-bucket
    hack in the port, see #9). Bucket: **TS** (`task_list_marker_unchecked` node position);
    styling still needs the "level 1 vs level 2" (top-level vs nested) split from the
    `list_item` ancestor's depth.

13. **`.todo`-filetype-only task metadata** (`:117-122`, gated on `awiwi#str#endswith(&ft,
    '.todo')`): `awiwiTaskDate` matches `\s*{"[^}]\+}$` (trailing `{…}` JSON blob) with bare
    `conceal` (hides it entirely — subject to `'conceallevel'`>0, see Port notes); three
    highlight groups defined **only when `&ft` ends in `.todo`**: `awiwiCreatedDate`
    (`guifg=#585858 gui=italic`), `awiwiFutureDueDate` (`guifg=#5fd700 gui=bold`),
    `awiwiNearDueDate` (`guifg=#d7ff00 gui=bold guibg=#5f0000`). These three groups are
    *consumed*, not defined, by `hi.vim`/`hi.lua`'s due-date virtual-text badges
    (`awiwi-todo-dates` namespace) — confirmed consistent scoping: that namespace/feature is
    itself todo-buffer-only (see `handovers/lua-port/hi.md`). Bucket: STATIC color defs
    (gated by filetype) + LUA pattern/conceal for `awiwiTaskDate`. **Must still define these
    3 groups even though this brief's own painting logic never uses them** — `hi.lua`
    depends on the names existing with these exact colors.

14. **Completed task checkbox line** (`:123,125`) — `hi link awiwiTaskListDone htmlStrike`
    (unconditional, any filetype); match `\C\(^[[:space:]]*\)\zs[-*] \[x\].\{-} \?\ze\s*
    \({\|$\)` — from the bullet through the checked `[x]` through the task text
    (non-greedy) up to (not including) an optional trailing space, before either the
    trailing `{…}` metadata blob or EOL. In effect: strike-through the whole `- [x] task
    text` span but stop before any trailing `{meta}` JSON. Bucket: **TS**
    (`task_list_marker_checked` node) + LUA extension to find where the trailing `{…}`
    metadata (if any) begins, so the strike-through extmark's end column stops there.

15. **Link highlighting master switch** (`:127`, `g:awiwi_highlight_links` default `true`)
    — items 16-27 below only apply when this is truthy. When falsy: none of `awiwiLink*`,
    `awiwiRedmineIssue` fire; `link_color`/`domain_color`/`link_style` groups never get set
    (relevant to B12).

16. **`awiwiLink` region** (`:128-134`) — start `\C\[\([ x]*\]\)\@!` (an opening `[` **not**
    immediately followed by zero-or-more of `{space,x}` then `]` — i.e. explicitly excludes
    checkbox-shaped `[ ]`/`[x]`/`[]`/`[ x]` so task checkboxes are never mistaken for link
    starts); end `\C[^)]\zs)` (first `)` whose preceding character is not itself `)`,
    discarding that preceding char from the match); `keepend`, `oneline` (single physical
    line only — links never span lines). Contains `awiwiLinkNameBlock`.
    `containedin=markdownH1..H6,awiwiList1,awiwiList2,awiwiTaskListOpen1,awiwiTaskListOpen2,
    markdownList,markdownListMarker` — again a top-level (non-`contained`) region, so it
    matches everywhere the start/end patterns line up regardless of `containedin`; the
    clause only matters for forcing recognition where a container's `contains=` would
    otherwise exclude non-contained items. Bucket: **TS** — this whole region is exactly
    `markdown_inline`'s `inline_link` node; use the node's link-text/link-destination child
    ranges directly instead of re-deriving them with the bracket/paren regex gymnastics
    below (items 17-26 map onto `inline_link`'s `link_text` and `link_destination`
    children).

17. **`awiwiLinkNameBlock` region** (`:136-143`) — `\C\[` to `\C\](\@=` (the `]` immediately
    followed, lookahead, by `(` — i.e. only treats `[...]` as a link name if immediately
    followed by `(`, distinguishing it from a bare `[reference]`-style or checkbox
    bracket), `keepend`, `contained`, `oneline`, contains `awiwiLinkNameStart`, `nextgroup
    awiwiLinkUrlBlock`. Maps to `inline_link.link_text` in TS.

18. **`awiwiLinkUrlBlock` region** (`:145-151`) — `\C(` to `\C)`, `keepend`, `contained`,
    `oneline`, contains `awiwiLinkUrlStart`. Maps to `inline_link.link_destination` in TS.

19. **Conceal helper** (`:153-169`) — `g:awiwi_conceal_links` (default `true`) gates all
    conceal application in items 20-26; when `false`, the four conceal-char globals below
    are irrelevant (no `conceal`/`conceal cchar=` clause is ever emitted). When `true`, an
    empty configured char → bare `conceal` (fully hides text, e.g. the default target/path
    char); a non-empty char → `conceal cchar=<char>` (replaces the concealed span with that
    single display character). Bucket: applies as an extmark `conceal` opt (string char, or
    `""`/absent-string to fully hide) — see Port notes for the exact extmark field mapping.

20. **`awiwiLinkNameStart`** (`:171-172,180`) — matches literal `[`, `contained` in
    `awiwiLinkNameBlock`, `nextgroup=awiwiLinkName`. Conceal char =
    `g:awiwi_conceal_link_start_char` default `▶`.

21. **`awiwiLinkName`** (`:181`) — `\C[^[\]]\+` (the visible link title, everything between
    the brackets), `contained`, `nextgroup=awiwiLinkNameEnd`. **Never concealed** — always
    the visible part of a link. Styled `gui=<link_style> guifg=<link_color>` (defaults
    `underline`, `#afaf00`) via the `for group in ['Name','Start','End']` loop at `:201-203`
    — **only the `Name` iteration actually lands on a real group** (see B11).

22. **`awiwiLinkNameEnd`** (`:172,182`) — matches literal `]`, `contained`, `nextgroup=
    awiwiLinkUrlBlock`. Conceal char = `get(g:, 'awiwi_conceal_link_start_char', ' ')` —
    **this is B1**: reads the *start*-char global (not `awiwi_conceal_link_end_char`, which
    is never read anywhere in the file) but only when the user hasn't customized it does the
    literal default of a single space (` `) apply; if the user *has* set
    `g:awiwi_conceal_link_start_char`, both `[` and `]` conceal to the **same** custom
    character.

23. **`awiwiLinkUrlStart`** (`:184`) — matches literal `(`, `contained` in
    `awiwiLinkUrlBlock`, `nextgroup=awiwiLinkInternalTarget,awiwiLinkProtocol` (first
    matching one wins). Never concealed. Styled gray (`domain_color`) via the second loop
    (`:205-207`, this one *does* land correctly, see item 26).

24. **`awiwiLinkProtocol`** (`:186-191`) — `_\Chttps\?://\(www\.\)\?_` (matches `http://`,
    `https://`, `http://www.`, `https://www.`), `contained`, `nextgroup=awiwiLinkDomain`.
    When `conceal` is on: `conceal` (bare — hides the whole protocol/www prefix). When
    conceal is off: **no color is ever applied** — the `exe printd(...)` call at `:190` is a
    typo for `printf` (**B2**), so the intended `hi awiwiLinkProtocol guifg=<domain_color>`
    never runs; a plain `E117: Unknown function: printd` error is thrown every time a buffer
    with `g:awiwi_conceal_links = 0` sources this file (this is a **hard error at syntax
    load time**, not silently swallowed — confirm behavior before deciding preserve vs fix;
    recommend fix in port regardless of ADR, an error on every non-concealed buffer load is
    not shippable).

25. **`awiwiLinkDomain`** (`:192`) — `_[^/)]\+_` (domain: everything up to the next `/` or
    `)`), `contained`, `nextgroup=awiwiLinkUrlEnd,awiwiLinkPath`. Never concealed. Styled
    gray via second loop (correct).

26. **`awiwiLinkPath`** (`:193`) — `_/[^)]*_` (the `/rest/of/path` portion, if any),
    `contained` in `awiwiLinkUrlBlock`, `nextgroup=awiwiLinkUrlEnd`. Conceal char =
    `g:awiwi_conceal_link_target_char` default `''` (empty → bare `conceal`, i.e. hides the
    path portion of **external** URLs entirely when concealed).

27. **`awiwiLinkInternalTarget`** (`:194`) — `_[./][^)]\+_` (a destination starting with `.`
    or `/` — i.e. relative/internal awiwi links, as opposed to `awiwiLinkProtocol`'s
    `http(s)://` external links), `contained`, reached via `awiwiLinkUrlStart`'s
    `nextgroup` (the `containedin=awiwiLink` clause on this item is defensive/redundant —
    `nextgroup` chains don't need permission from the outer region's own `contains=` list).
    Conceal char = `g:awiwi_conceal_link_internal_target_char` default `…`. This is the
    classification point for **internal vs external link** — same distinction the binding
    architecture's `markdown_inline`/`inline_link` query needs to reproduce by inspecting
    the `link_destination` text (starts with `http://`/`https://` → external/`awiwiLinkProtocol`+`awiwiLinkDomain`+`awiwiLinkPath` path; starts with `.`/`/` → internal/`awiwiLinkInternalTarget`).

28. **`awiwiLinkUrlEnd`** (`:196`) — matches literal `)`, `contained` in
    `awiwiLinkUrlBlock`. Never concealed. Styled gray via second loop (`:205-207`, matches).

29. **Redmine issue reference** (`:198-199`) — `\(^\|\s\)\zs#[0-9]\{5,}` (a `#` followed by 5
    or more digits, preceded by line-start or whitespace, discarded via `\zs`), `oneline`,
    `containedin=markdownH1..H6,awiwiList1,awiwiList2,awiwiTaskListOpen1,
    awiwiTaskListOpen2,markdownList,markdownListMarker` (again top-level/unrestricted in
    practice). Group `awiwiRedmineIssue`, `gui=bold guifg=<link_color>`. **Not** driven by
    `markers.lua` — hardcoded here, independent pattern (matches the description in
    `docs/architecture.md` calling out `#NNNNN` Redmine refs). Bucket: LUA, masked in the
    port (no legacy masking, but this is prose text, should not fire inside fenced code —
    apply the same B10 fix).

30. **Link/domain color loops** (`:201-207`) — loop 1 `for group in ['Name','Start','End']`
    → `hi awiwiLink{Name,Start,End} gui=<link_style> guifg=<link_color>`: only
    `awiwiLinkName` is a real syntax group; `awiwiLinkStart`/`awiwiLinkEnd` don't exist
    anywhere else in the file (**B11** — the real un-styled delimiter groups are
    `awiwiLinkNameStart`/`awiwiLinkNameEnd`, and arguably `awiwiLinkUrlStart` too, though
    that one gets a *different* (gray) style from loop 2). Loop 2 `for group in
    ['Domain','UrlStart','UrlEnd']` → `hi awiwiLink{Domain,UrlStart,UrlEnd}
    guifg=<domain_color>`: all three are real, correctly wired.

31. **Filetype modeline block** (`:210-212`) — `awiwiFileTypeBlock` = `\C^[^a-zA-Z0-9_]*vim:
    ft=[a-z].*$` (a `vim: ft=xxx` modeline-shaped comment anywhere on the line, prefixed only
    by non-identifier chars, e.g. a markdown/HTML comment opener), `contains=
    awiwiFileTypePrefix,awiwiFileType` (this one's a `match`, so `contains=` is again
    inert); `awiwiFileTypePrefix` = the `vim: ft` prefix text, `contained`; `awiwiFileType` =
    the filetype value after `vim: ft=`, `contained`. Bucket: LUA (single-line regex on
    prose text, not markdown structure), masked in the port — but note: modelines
    legitimately *can* appear inside a fenced code block (e.g. someone pasting a vimrc
    snippet with a trailing modeline comment) — recommend **preserve unmasked** for this one
    specific concern as an explicit carve-out from the general B10 fix, flag in ADR.

32. **`awiwiDateOverlay`** (`:214`) — `exe printf('hi awiwiDateOverlay guifg=%s',
    link_color)`, unconditional, **outside** the `if get(g:, 'awiwi_highlight_links',
    v:true)` block (closes at `:208`) that defines `link_color`. Two independent problems:
    (a) if `g:awiwi_highlight_links` is falsy, `link_color` is undefined at this point →
    `E121: Undefined variable: link_color`, a hard error on every buffer load; (b) even when
    it doesn't error, `awiwiDateOverlay` is never referenced by any `syn match`/`region` in
    this file nor by any extmark call in `hi.vim` — it is dead/orphaned regardless (**B12**).

## Bugs found

- **B1** (`syntax/awiwi.vim:172`, existing STATE.md item) — `conceal_end_char` reads
  `g:awiwi_conceal_link_start_char` (copy-paste of the line above) instead of
  `g:awiwi_conceal_link_end_char`; the latter global has **zero effect** today. **Recommend
  fix in port**: read the correct global; keep the same literal default (`' '`, a single
  space) for parity.
- **B2** (`:190`) — `exe printd(...)` typo for `printf`; throws `E117` on every buffer with
  `g:awiwi_conceal_links = 0` (link protocol color never gets set as a side effect).
  **Recommend fix in port** — not a "preserve the bug" candidate, it's a crash, not a
  cosmetic quirk.
- **B3** (`:93-95` + `autoload/awiwi.vim:47`) — highlight group names `awiwiQuestionn`
  (double-n) and `awiwiOnHole` (should be `awiwiOnHold`); separately, the onhold marker word
  list itself contains the literal string `@onhole` (typo for `@onhold`) alongside the
  correctly-spelled `@onhold`. **Recommend fix in port**: rename the two highlight groups to
  `awiwiQuestion`/`awiwiOnHold`. For the `@onhole` marker string (owned by `markers.lua`,
  see that brief) recommend **keep as a backward-compat alias** in the `onhold` list (zero
  cost, protects any notes a user already wrote with the typo) — flag both renames for an
  ADR since `awiwiOnHole`/`awiwiQuestionn` are public highlight-group names an external
  colorscheme could reference (unlikely but the binding architecture explicitly calls this
  out as an ADR-worthy naming change).
- **B10** (new, this transaction — matches the binding architecture's explicit call-out)
  — every line-local marker/list/checkbox/redmine `syn match` in this file is emitted
  without `contained`, and several (`awiwiUrgent`, `awiwiDue`) use `contains=` where
  `containedin=` was clearly intended; neither restricts them from firing inside fenced code
  blocks under Vim's default syntax semantics. Net effect: `TODO`, `FIXME`, `@urgent`, list
  bullets, bad-space nags, task checkboxes, and Redmine refs **all highlight inside code
  fences today**. **Recommend fix in port**: mask every LUA-bucket pattern in this brief
  against `mdstruct.code_line_mask(bufnr)` before applying (except item 31, the modeline
  block — see its carve-out above).
- **B11** (new) — the `for group in ['Name', 'Start', 'End']` styling loop (`:201-203`) only
  hits a real group for `'Name'`; `awiwiLinkStart`/`awiwiLinkEnd` don't exist, so the actual
  un-styled delimiter groups (`awiwiLinkNameStart`, `awiwiLinkNameEnd`) never get the
  `link_style`/`link_color` treatment — visible only when `g:awiwi_conceal_links = 0` (since
  otherwise these chars are hidden). **Recommend fix in port**: style
  `awiwiLinkNameStart`/`awiwiLinkNameEnd` with `link_style`/`link_color` directly instead of
  looping over mismatched suffixes.
- **B12** (new) — `hi awiwiDateOverlay guifg=%s` (`:214`) sits after the `endif` that scopes
  `link_color`'s definition, causing `E121: Undefined variable: link_color` whenever
  `g:awiwi_highlight_links` is falsy; the group is additionally dead code (zero consumers
  anywhere in the codebase) independent of the crash. **Recommend fix in port**: drop
  `awiwiDateOverlay` entirely — no evidence of intended use, and reintroducing it "fixed"
  would just be defining an unused group.
- **Cross-reference (not this module's bug, FYI only)** — `awiwi#get_markers('todo',
  {escape_mode='rg'})` (default options, used by `cmd.vim` `Awiwi tags`/`todo`/`all` and by
  `awiwi#server#`'s `config.json` writer) appends a Vim-regex-flavored fragment
  (`\(`,`\)`,`\zs`) to an otherwise rg/PCRE-flavored joined pattern. Irrelevant to
  `syntax/awiwi.vim` itself (the only two call sites in this file use `escape_mode='vim'`,
  which does not trigger that branch) but is a live correctness risk in `markers.lua` —
  fully specified in `handovers/lua-port/markers.md`.

## Port notes

**Architecture (binding, per the T6b plan):**

- One structural repaint pass per buffer via two runtime-parsed treesitter queries:
  - `markdown` query: `atx_heading`, `fenced_code_block` (+ `indented_code_block` — the
    legacy file has no indented-code concept at all, so there's nothing to regress, but
    `mdstruct.code_line_mask` already covers it per `hi.md`), `list_item`,
    `task_list_marker_checked`, `task_list_marker_unchecked`.
  - `markdown_inline` query: `inline_link` → `link_text` (name) and `link_destination`
    (target) children, for conceal + internal/external classification (items 16-28 above).
- **Reuse, do not re-derive, `hi.md`'s planned shared module.** `handovers/lua-port/hi.md`
  (T6a, this module's own dependency) specifies a new `lua/awiwi/mdstruct.lua` with
  `M.headings(bufnr)` and `M.code_line_mask(bufnr)` built from exactly the `markdown` query
  fragments this brief needs for headings/code. **Extend `mdstruct.lua`** with
  `M.list_items(bufnr)` (or equivalent) and `M.task_markers(bufnr)` rather than running a
  second independent `markdown`-language query pass — one parser, one tree walk, shared by
  `hi.lua` and `syn.lua`, per DRY. Verify `mdstruct.lua`'s *actual shipped* interface when
  T6a lands (this brief describes the interface as drafted in `hi.md`, written before T6a
  is implemented — STATE.md shows T6a unchecked, so treat this as a dependency risk, not a
  guarantee).
- `inline_link` handling (items 16-28) has no existing home in `mdstruct.lua` (nothing else
  needs it yet) — fine to keep local to `syn.lua`'s own `markdown_inline` query unless a
  future consumer appears.
- Line-local concerns (items 2-7, 10-14 fine-grained parts, 29, 31) run as plain Lua string
  patterns (`string.find`/`string.match`, not full regex — note several legacy vim-regexes
  use lookaround (`\zs`, `\@=`, `\@!`) that Lua patterns can't express directly; use anchored
  captures instead, e.g. `line:match("^()%[%-%*%] ")` style position-capture idioms, or
  simple substring search + manual boundary checks) over buffer lines **outside**
  `mdstruct.code_line_mask(bufnr)` (this is the B10 fix). Exception: item 31 (modeline)
  should NOT be masked (see its carve-out).
- **Namespaces**: one per concern, matching `hi.lua`'s existing convention
  (`awiwi-todo-dates`, `awiwi-horizontal-lines`). Suggest: `awiwi-syn-structure` (headings/
  list/task painting derived from TS), `awiwi-syn-links` (link region + conceal + link
  colors), `awiwi-syn-markers` (marker keywords/redaction/redmine/modeline, all LUA-bucket).
  Splitting lets `M.detach` or future selective-disable toggles clear one concern without
  nuking the others.
- **Conceal via extmarks**: `nvim_buf_set_extmark(bufnr, ns, row, col, {end_col=…, conceal
  = char or ""})`. Concealing requires the buffer's window(s) to have `'conceallevel' >= 1`
  — the legacy plugin sets `concealcursor=nciv` (`ftplugin/awiwi.vim:14`) but **never sets
  `'conceallevel'` itself**; it has always relied on the user's own config setting it
  globally. This is a pre-existing, out-of-scope-for-this-module precondition, not a
  regression to fix — note it so tests explicitly `vim.wo.conceallevel = 2` rather than
  assuming conceal "just works" in a clean `nvim --clean` test buffer.
- **Highlight group names**: preserve every name in the contract above **exactly**, except
  the three explicit renames in B3 (`awiwiQuestionn`→`awiwiQuestion`,
  `awiwiOnHole`→`awiwiOnHold` — flag for ADR) and the drop of `awiwiDateOverlay` (B12,
  clearly dead). Define via `vim.api.nvim_set_hl(0, name, {...})`, converting `guifg=#RRGGBB
  gui=bold` → `{fg='#RRGGBB', bold=true}` etc. `hi link X Y` → `nvim_set_hl(0, X, {link=Y})`.
- **List nesting depth** (items 9, 12): the legacy 2-bucket (`List1`/`List2`) hack based on
  counting exactly 0 or 2 leading spaces is a crude regex approximation of "top-level vs.
  nested" that breaks past one nesting level (3+ levels all fall through unstyled). TS
  `list_item` gives real ancestor depth — this is a genuine improvement opportunity, but the
  contract above only requires reproducing the *current two-color* behavior; going further
  (e.g. a third color for depth ≥2) is a scope decision for an ADR, not a silent addition.
- **Priority/ordering**: Vim's syntax engine breaks same-start-position ties by
  definition-order (later wins); extmarks have no such implicit rule — the port must apply
  its own explicit ordering (e.g. paint `list_item` bullet color first, then overlay
  `task_list_marker_*` color on top for the same span) to reproduce items 9 vs. 12's
  "checkbox wins over generic bullet" behavior.

## Suggested acceptance tests

1. Line `- foo` at column 0 → `awiwiList1` extmark on `- ` (cols 0-2).
2. Line `  - foo` (2-space indent) → `awiwiList2` extmark on `- ` at cols 2-4.
3. Line `- [ ] foo` → `awiwiTaskListOpen1` extmark on `- [ ]`, and **no** separate
   `awiwiList1` extmark overlapping the same span (or if both extmarks exist, the
   task-list one must be the one actually rendered — test via `nvim_buf_get_extmarks`
   `hl_group`/priority, not just "an extmark exists").
4. Line `- ~~cancelled item~~` → `awiwiCanceledList` extmark linked to `htmlStrike`,
   spanning from the bullet through end of line.
5. Line `TODO buy milk` → `awiwiTodo` extmark on `TODO` only (word-bounded); line
   `TODOING` → no `awiwiTodo` match (boundary check).
6. Line `` `TODO in code` `` inside a fenced ` ```lua ... ``` ` block → **no** `awiwiTodo`/
   `awiwiUrgent`/list-marker extmarks anywhere inside the fence (B10 fix verification).
7. Line `!!redacted this is secret` → `awiwiRedacted` region from `!!redacted` to EOL,
   `awiwiRedactedTag` on `!!redacted`, `awiwiRedactedCause` on ` this is secret`.
8. Line `[my link](./other.md)` with `g:awiwi_conceal_links=true` (default): `[` concealed
   to `▶`, `]` concealed to `▶` too (**B1 preserved-then-fixed** — write the test against
   the *fixed* behavior: `]` should conceal to the default space `' '`, not `▶`, once B1 is
   fixed; if fix-in-port is deferred, adjust expected value and note it), `.` /`other.md`
   destination concealed to `…` (internal target char), `awiwiLinkName` text `my link`
   styled `underline`/`#afaf00`.
9. Line `[ext](https://www.example.com/path)`: protocol `https://www.` concealed (bare,
   hidden); domain `example.com` gray (`#808080`); path `/path` concealed to empty (bare
   hidden, default target char).
10. With `g:awiwi_highlight_links=false`: no `awiwiLink*` or `awiwiRedmineIssue` extmarks
    anywhere in the buffer, and — this is the crash regression test for B12 — attaching
    must **not** error (`M.attach` must not reference an undefined `link_color`).
11. `#12345` preceded by whitespace on any line → `awiwiRedmineIssue` extmark, bold +
    `link_color`; `#1234` (4 digits) → no match (5-digit minimum).
12. `vim: ft=markdown` inside a fenced code block → still highlighted (item 31's B10
    carve-out) as `awiwiFileTypePrefix`/`awiwiFileType`.
13. Buffer with `&ft` = `awiwi.todo`: `awiwiCreatedDate`/`awiwiFutureDueDate`/
    `awiwiNearDueDate` highlight groups exist (`nvim_get_hl(0, {name=...})` returns
    non-empty) after `M.setup_highlights()`; for `&ft` = `awiwi` (plain journal), the brief's
    own painting never uses them but `hi.lua`'s consumer contract (see `hi.md`) should still
    be checked in that module's own test suite, not duplicated here.
14. `awiwiQuestionn`/`awiwiOnHole` do not exist as highlight group names after the port;
    `awiwiQuestion`/`awiwiOnHold` do (B3 fix verification). `@onhole` in a note still
    triggers the onhold marker highlight (backward-compat alias verification).

## Ported

**Lua module:** `lua/awiwi/syn.lua` (`local M = {} … return M`). Deps: `require("awiwi.hi")`
(consumes `M.headings`/`M.code_line_mask` — the shared treesitter structural pass, per this
brief's own dependency note, NOT re-derived), `require("awiwi.markers")` (consumes `M.lists`
raw table directly, plus the same `g:awiwi_custom_<type>_markers` merge logic
`get_markers` uses — see "Consumes" below), `require("awiwi.str")` (`endswith`, for the
`.todo`-filetype gate). No `:syntax`/`b:current_syntax` side effects anywhere — extmarks
only, three namespaces. Spec: `tests/syn_spec.lua` (31 `it` cases across 10 `describe`
blocks).

**Public API:**

- `M.ns_structure`, `M.ns_links`, `M.ns_markers` — the three namespace ids
  (`"awiwi-syn-structure"`, `"awiwi-syn-links"`, `"awiwi-syn-markers"`), exposed so
  tests/T10 can assert/clear per-concern without needing to re-derive the namespace name.
- `M.setup_highlights()` — idempotent `nvim_set_hl` calls for every static + `g:`-derived
  color in the contract; safe to call more than once (re-reads `g:awiwi_link_color`/
  `g:awiwi_domain_color`/`g:awiwi_link_style` each time).
- `M.attach(bufnr)` — `setup_highlights()` → `detach(bufnr)` → structural pass → line-local
  marker pass → link pass. Idempotent (repaint clears its own extmarks first, no
  accumulation across repeated calls on the same buffer).
- `M.detach(bufnr)` — clears all three namespaces for `bufnr` (`bufnr == 0` resolves to the
  current buffer).

**Consumes from `markers.lua` (DRY, not reimplemented):** line-local marker painting reads
`markers.lists[type_]` (the raw builtin vocab) directly and merges
`vim.g.awiwi_custom_<type>_markers` the same way `markers.get_markers` does, rather than
round-tripping through `get_markers`'s rg/vim escape+join machinery (which is the wrong
shape for a plain substring search with a treesitter-code-mask gate — no regex engine is
involved on this side at all; boundary checks are hand-rolled Lua helpers, see below).

**Queries (runtime-parsed, once at module load):**
- `markdown`: `(list_item) @list_item` — walked recursively via `iter_children` to get
  real per-node nesting depth (mapped onto the existing two-color `List1`/`List2` contract);
  each item's own bullet/checkbox marker is found via a *direct-children-only* scan so a
  nested item's marker is never mistaken for its parent's.
- `markdown_inline`: `(inline_link (link_text) @text (link_destination) @dest)` — accessed
  via `parser:children()["markdown_inline"]` (the injected-language subtree), one match per
  link, iterated with `iter_matches(..., {all=true})` (`match[1][1]`/`match[2][1]` are the
  `link_text`/`link_destination` nodes).

**Boundary-check helpers (not `vim.regex`):** word-edge (`\<`/`\>`-equivalent, for
`urgent`/`due` markers) and whitespace-edge (`\zs`/lookahead-equivalent, for
`todo`/`question`/`onhold`/`@tag` markers) checks are hand-rolled Lua predicates
(`word_edge_ok`, `ws_or_edge_ok`) rather than compiled Vim-regex alternations. This
deliberately sidesteps a real (undocumented, not one of B1-B12) latent bug class in the
legacy file: unguarded `\<A\|B\|C\>` alternation only anchors the first/last branch in Vim
regex (`\|` has the lowest precedence), so a middle marker in a `\|`-joined list would
silently lose its word-boundary anchoring. Not reproduced — each marker gets its own
independent boundary check regardless of position in its vocabulary list.

**Bugs fixed in port (see brief's "Bugs found" for full descriptions):**
- **B1** — `]`'s conceal char now reads `g:awiwi_conceal_link_end_char` (was copy-pasted
  from the start-char global).
- **B2** — `printd`→`printf` typo dropped entirely; `awiwiLinkProtocol` always gets
  `domain_color` set, no crash path exists when `g:awiwi_conceal_links` is falsy.
- **B3** — `awiwiQuestionn`→`awiwiQuestion`, `awiwiOnHole`→`awiwiOnHold`. The `@onhole`
  *marker word* (as opposed to the highlight-group-name typo) is kept as a permanent
  backward-compat alias in `markers.lua`'s `onhold` list — separate concern, not a bug fix,
  ADR-worthy (a real note might have been typed with the typo already).
- **B11** — `awiwiLinkNameStart`/`awiwiLinkNameEnd` get `link_style`/`link_color` directly
  (the legacy 3-group loop only ever landed on `awiwiLinkName` since `awiwiLinkStart`/
  `awiwiLinkEnd` don't exist as groups anywhere else).
- **B12** — `awiwiDateOverlay` dropped entirely (dead code; the `E121` crash path it was
  reachable from doesn't exist in the port either since `link_color` is always computed
  before it would be needed).
- **B-syn-new-1** (found this transaction, not in the brief's original B1-B12 list) — the
  legacy `awiwiFileTypePrefix` sub-pattern required a literal `?` (`vim: ft?`) that never
  occurs in real `vim: ft=xxx` text (typo for `=`), so that sub-highlight was permanently
  dead in the shipped file. Fixed in port to the evidently-intended `vim: ft=` literal
  match. Flagging for `docs/decisions.md`/STATE.md ADR entry — not yet added there, this
  transaction's boundary is `syn`/`markers` files only.
- Item 15's master switch (`g:awiwi_highlight_links`) also gates `awiwiRedmineIssue`, per
  the brief's explicit wording — not just the `awiwiLink*` groups; the port's
  `paint_markers` orchestration checks the flag before calling `paint_redmine`.

**Deviations / preserved quirks:**
- `!!redacted` (item 2) and the `vim: ft=` modeline (item 31) are deliberately **not**
  masked by `hi.code_line_mask` — both can legitimately appear inside a fenced code block
  (a redacted paste, a pasted vimrc snippet) and the brief calls out an explicit carve-out
  for the modeline case; extended the same carve-out to redaction since the brief's item 2
  text doesn't mention masking either.
- The modeline split mirrors the legacy `\zs` semantics exactly: leading junk
  (`^[^a-zA-Z0-9_]*`, e.g. an HTML comment's `<!-- `) is consumed but never itself
  highlighted; `awiwiFileTypePrefix` covers only the literal `vim: ft=` text, and
  `awiwiFileType` covers everything from the value through EOL (not just the filetype word —
  matches `[a-z].*$`, i.e. legacy intentionally highlights any trailing comment-closer like
  ` -->` too).
- `awiwiTaskListDone`'s strike-through trims trailing whitespace immediately before a
  trailing `{meta}` JSON blob, not just the blob itself (`- [x] done thing {"due":...}` →
  strikes through `- [x] done thing`, stopping before the space).
- Exactly one structural extmark per list item (bullet vs. open-checkbox vs. done-checkbox
  vs. canceled-strike are mutually exclusive) — matches the legacy "most specific wins"
  visible net effect without needing extmark-priority games.

**Gotchas for T10 / future spec authors:**
- Lua patterns do **not** support an optional *group* the way regex does — `(pattern)?`
  actually requires a literal `?` character in the text (quantifiers only apply to a single
  preceding character class). `paint_bad_spaces` originally used
  `(%[[ x]%] ?)?` for an optional checkbox and silently never matched non-checkbox bullets;
  fixed by trying the checkbox-inclusive shape first and falling back to the bare-bullet
  shape. Grepped the rest of the module for the same anti-pattern (`)?`) — no other
  instances.
- **Do not** set a scratch buffer's `filetype` to the real `"awiwi"` or `"awiwi.todo"` in
  headless specs. Neovim's own filetype-triggered `:runtime! syntax/<component>.vim`
  autocommand splits compound filetypes on `.` and will load the *legacy*
  `syntax/awiwi.vim` as a side effect (independent of `ftplugin/awiwi.vim`'s own
  `g:awiwi_home`-guard erroring out), polluting the global highlight namespace with the very
  B3-typo'd group names this module fixes, and corrupting later assertions in the same test
  run. `tests/syn_spec.lua`'s `.todo`-gated test uses a non-colliding stand-in
  (`"journal.todo"`) instead — `str.endswith` only cares about the `.todo` suffix.
- A `with_g`-style test helper that does `saved[k] = vim.g[k]` to snapshot-and-restore
  globals must **not** restore via `for k, v in pairs(saved) do ... end` — assigning `nil`
  to a Lua table key never creates an entry, so any override of a previously-unset global
  silently fails to restore, leaking state (e.g. `g:awiwi_highlight_links = false`) into
  every subsequent test in the file. Track the override key list separately from the saved
  values.

**What T10 needs to do to activate this module:** call `require("awiwi.syn").attach(bufnr)`
from an `autocmd FileType awiwi,awiwi.todo` (or wherever `ftplugin/awiwi.vim` currently does
`:syntax` setup) instead of sourcing `syntax/awiwi.vim`; call `M.detach(bufnr)` on
`BufUnload`/filetype-change if the buffer's filetype stops matching. `M.setup_highlights()`
can be called once at that point too (it's idempotent, but `M.attach` already calls it, so a
separate call is only needed if highlight groups must exist before the first buffer
attaches, e.g. for a colorscheme-change autocommand to call `M.setup_highlights()` again).
No `b:current_syntax` needs to be set or checked — nothing in this module reads it.

**Test count:** 31 (targeted `tests/syn_spec.lua`, across 10 `describe` blocks); full suite
266 passed, 3 failed (`nvim --clean --headless -l tests/run.lua`, 9 files) — the 3 failures
are pre-existing, unrelated `date_spec.lua` flakiness (system-clock date rollover
mid-session), not touched by this transaction.

status: done
