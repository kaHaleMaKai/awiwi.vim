# Decisions (ADR log)

Append-only, immutable. One entry per architectural decision, newest at the bottom. Reference the
D-number from any doc whose content depends on it. **High-water mark: D0.**

Record a NEW ADR only when a decision is actually made (by a human or the orchestrator) — the
kb-curator does not invent decisions. Format: number, date, status, context, decision, consequences.

---

## D0 — Adopt layered knowledge-base pipeline

- **Date:** 2026-07-05
- **Status:** accepted
- **Context:** the plugin is being refactored and rewritten from vimscript to Lua, and the server
  from Flask to FastAPI. Both need a durable spec so behavior survives the rewrite.
- **Decision:** install the claude-kb layered-memory pipeline (`docs/INDEX.md`, `knowledge-base.md`,
  `architecture.md`, `data-model.md`, glossary, ADRs) with a deterministic pre-commit gate
  (`scripts/kb-detect.sh` + `.claude/kb/rules.tsv`). `docs/architecture.md` is the authoritative
  spec and the rewrite target.
- **Consequences:** every behavior-changing commit must keep the mapped knowledge layer fresh or be
  marked `DOCS_OK=1`. Future ADRs record rewrite decisions (module boundaries, schema fixes, etc.).

---

## D1 — Drop WIP/dead task-management modules in Lua rewrite

- **Date:** 2026-07-05
- **Status:** accepted
- **Context:** the Lua rewrite (per `docs/architecture.md` Dead code / WIP section) encounters six
  modules that are either unreachable (`dao`, `sql`), syntactically broken (`task`), wired but
  inoperable (`view`, `bookmarks`), or unimplemented (`ask`). These modules target a SQLite
  task-tracking layer (`task.db`, OOP ORM, queries) that is WIP and not reachable from the shipped
  `:Awiwi` command surface. The shipped file-based active-task timer (`data/task.log`, driven by
  `awiwi#activate_current_task` / `#deactivate_active_task`) is separate and complete.
- **Decision:** the Lua rewrite does NOT port `task.vim`, `view.vim`, `bookmarks.vim`, `ask.vim`,
  `sql.vim`, or `dao.vim`. The shipped plain-text task.log behavior (current `awiwi.vim` +
  `cmd.vim` + `hi.vim` only) is ported and remains the only task-tracking surface. If SQLite
  task tracking is revived in the future, it is a separate feature branch, not part of the core
  Lua rewrite.
- **Consequences:** the Lua port is simpler and narrower in scope (no ORM, no test.db plumbing, no
  unfinished UI). The vimscript versions are not deleted from the repo but remain as reference.
  Users never exercised these features so there is no behavior regression. Any future task-db work
  requires separate architectural decisions.

---

## D2 — str functions are case-sensitive in Lua (intentional behavior change)

- **Date:** 2026-07-05
- **Status:** accepted
- **Context:** the vimscript `awiwi#str#startswith` / `endswith` functions use direct byte
  comparison (`strpart(...) == ...`) which, when the vimscript `'ignorecase'` option is set,
  silently honor it (Vim's `==` operator obeys the option). The Lua port (`lua/awiwi/str.lua`)
  uses Lua's `==` operator, which is always case-sensitive and has no 'ignorecase'-equivalent
  option. This is documented as bug Bstr-2 in the port brief. Call sites use these functions
  only for predicates (filetype checks like `.todo`, CLI flag matching, code-block fence detection)
  where case-sensitivity is the correct and intended behavior.
- **Decision:** the Lua port intentionally changes `startswith` / `endswith` / `contains` to always
  be byte-exact and case-sensitive. No `'ignorecase'` knob or case-insensitive variant is offered.
  This closes the Bstr-2 bug (silent ignorecase leakage) and aligns behavior with user intent.
- **Consequences:** users with `set ignorecase` global will see no change in practice (all call
  sites benefit from case-sensitive checks). The change is invisible and correct. The commit
  records this as an intentional simplification, not a regression.

## D3 — Narrowed relative-date grammar in Lua date module (2026-07-05)

**Context.** `date.vim` shelled out to GNU `date --date`, inheriting its full
natural-language parser. The Lua rewrite mandates pure `os.date`/`os.time`
(no subprocess), which cannot replicate that grammar wholesale.

**Decision.** `lua/awiwi/date.lua` implements a hand-written grammar covering
exactly the vocabulary reachable from the plugin's UI (per the T3 port brief's
call-site inventory): `today`/`yesterday`/`tomorrow`; `in N day(s)/week(s)/
month(s)`; `N day(s)/week(s)/month(s) ago`; `next <weekday>`/`last <weekday>`
(strictly future/past, skipping today — GNU semantics). Anything else throws
`AwiwiDateError` — clear rejection over silent wrong answers.

**Consequences.** Exotic GNU expressions ("the third tuesday", timestamps with
a time component) that technically worked before now error. Extending the
grammar is a local change in `date.lua` with spec coverage. Also fixed in the
same port: journal "previous" off-by-one (B-date-3), ordinal suffixes
11th/12th/13th (B-date-5); preserved quirks: shape-only `is_date` (B-date-1),
`DD.MM` assumes current year (B-date-2).

## D4 — Opening an asset no longer silently creates/rewrites files (2026-07-05)

**Context.** `asset.vim`'s `open_asset_by_name` unconditionally `:write`d the
buffer, so merely *opening* a named asset created an empty file on disk (or
rewrote an existing one) as a side effect (bug B-new-1, found during T5 recon).

**Decision.** In `lua/awiwi/asset.lua`, opening an existing asset is
side-effect-free; file creation happens only on the explicit create paths
(`create_asset_link`, `create_asset_here_if_not_exists`). Regression-tested
both ways.

**Consequences.** Workflows that (likely unknowingly) relied on open-to-create
must use the create commands. Empty stray asset files stop appearing.

## D5 — Lua server module launches the FastAPI viewer, not Flask (2026-07-05)

**Context.** `server.vim` launched `server/.venv/bin/flask` + `server/app.py` —
paths that no longer exist since the Flask app moved to `server.old/`; the
shipped `:Awiwi serve` has been broken (T7 recon, bug #5). The live stack is
FastAPI + Pydantic under `server/` (uv-managed).

**Decision.** `lua/awiwi/server.lua` builds `uv run uvicorn app:app --host
<host> --port <port>` with cwd=`server/`, overridable via `M.config.cmd_builder`.
`app:app` is a documented placeholder — `server/` has no app module yet; pin the
real import path when it lands. Spawn via `vim.system` (env scoped per-job);
readiness via bounded non-blocking `wait_ready` (no more editor-blocking sleep).

**Consequences.** `:Awiwi serve` works again once the FastAPI app exists;
anyone still needing the old Flask viewer must run it manually from
`server.old/`.

## D6 — Treesitter syntax layer; highlight-group typo renames (2026-07-06)

**Context.** `syntax/awiwi.vim` (214 lines of regex `:syntax`) is replaced by
`lua/awiwi/syn.lua`: one structural repaint via `markdown`/`markdown_inline`
treesitter queries plus plain-Lua line patterns applied outside the code-block
mask (shared from `hi.lua`). Extmark painting in three namespaces
(structure/links/markers). Built and headless-tested in T6b; **wiring happens
at T10** — activating alongside the live vimscript syntax file would double-
paint running sessions. `lua/awiwi/markers.lua` owns the marker vocabulary
(with `g:awiwi_custom_*_markers` overrides) for both syn and rg-based search.

**Decision.** The legacy typo groups are renamed in the port:
`awiwiQuestionn` → `awiwiQuestion`, `awiwiOnHole` → `awiwiOnHold`. The
`@onhole` marker keyword is kept as a backward-compat alias for `@onhold`.
Dead `awiwiDateOverlay` (crashed when link highlighting was off, referenced
nowhere) is dropped. Also fixed in port: `g:awiwi_conceal_link_end_char` now
takes effect (B1), the `printd` crash branch (B2), unstyled
`awiwiLinkNameStart/End` (B11-syn), markers highlighting inside fences (B10),
and the dead vim-regex fragment in the rg todo pattern (verified against the
real `rg`).

**Consequences.** Configs referencing the misspelled groups must switch to the
corrected names; all other group names are preserved exactly.

## D7 — Picker seam: vim.ui.select default, telescope auto-upgrade (2026-07-06)

**Context.** Legacy pickers ran on fzf (`fzf#run`); the rewrite plan chose
telescope.nvim. At T9 the probe found neither telescope/plenary nor even the
fzf binary on the target machine, so a hard telescope dependency would leave
the plugin without any working picker. User decision (T9 checkpoint).

**Decision.** All picker UI flows through `lua/awiwi/picker.lua` (`select`,
`files`, `grep`). Default backend is built-in `vim.ui.select` — zero deps,
headless-testable. When `require('telescope.*')` succeeds (loaded through the
injectable `picker.deps.require`), the seam auto-upgrades to a telescope list
picker; all three picker types funnel through `select`, so telescope is
implemented once. Live-grep flows materialize rg results via `vim.system`
first, then pick.

**Consequences.** Works on bare nvim; telescope users get telescope for free;
fzf is gone from the Lua plugin. The telescope path is smoke-tested via an
injected fake — machines with real telescope should sanity-check it at T10
dogfooding.

---

## D8 — task.log format change: JSON in Lua port (2026-07-06)

**Context.** `task.log` (the shipped file-based active-task timer) was written by vimscript as
one task record per line in `vim.string()` dict-literal format (vimscript serialization). The Lua
port needs to write the same logical data to the same file, but reading/writing vimscript string
literals in pure Lua is not practical.

**Decision.** `lua/awiwi/init.lua` writes task records to `task.log` as one JSON object per line
(via `vim.json.encode`). Old lines in an existing `task.log` fail gracefully on decode and are
skipped (migration is transparent; no user action needed). The new format is internal and
documented only in this ADR — `task.log` is not a public interchange format.

**Consequences.** Existing task logs are readable but not writable from the Lua port. The first
time the Lua port activates a task after the vimscript port, a new JSON line is appended. No
state is lost; existing records are simply not amended. The file can grow indefinitely
(unbounded, per ADR D10 — `g:awiwi_history_length` remains a no-op).

---

## D9 — Search command routes through picker.grep (2026-07-06)

**Context.** `:Awiwi search <pattern>` in vimscript used `fzf#vim#grep` directly. The Lua port
unifies all picker UI through `lua/awiwi/picker.lua` (ADR D7), which wraps `vim.ui.select`
(default) or telescope (if available). All pickers — `journal` (file), `asset`, `tags`, `entries`,
and now `search` — use the same backend, making the picker choice consistent and upgradeable.

**Decision.** `:Awiwi search` now routes through `picker.lua:grep()` (live-rg → select/telescope
picker), replacing the legacy `fzf#vim#grep` call. The picker backend is chosen once at load time;
no per-command override.

**Consequences.** Users without telescope get the simple `vim.ui.select` default for search (still
functional, just simpler UI). Telescope users get the same multi-selection, live-filter UI as all
other pickers. The `--color=never` rg option is hardcoded (not user-configurable, matching the
pattern from ADR D7).

---

## D10 — g:awiwi_history_length remains a no-op (2026-07-06)

**Context.** The vimscript `awiwi.vim` declared `let s:log_file_size = get(g:, 'awiwi_history_length', 10000)`
and `let s:history = []`, but neither variable is used anywhere in the codebase. The config key
is documented in `docs/architecture.md` as "log size, 10000" but silently ignored — `data/awiwi.log`
grows unbounded forever. The intended behavior (log rotation after N entries) was never implemented.

**Decision.** The Lua port **does not** implement log rotation. The config key `g:awiwi_history_length`
is preserved (no error if set) but produces no effect. If log rotation is desired in the future,
it is a separate feature decision, not a port task.

**Consequences.** `data/awiwi.log` continues to grow unbounded, as it did under vimscript. No user
action is required. If log bloat becomes an issue, either delete `data/awiwi.log` manually or
implement a new rotation feature (which would require an ADR at decision time, not port time).

---

## D11 — split_screen guard pending human ADR (2026-07-06)

**Context.** The vimscript `ftplugin/awiwi.vim` defines `<C-x>` and `<C-v>` command-line-mode mappings
that inject split flags (`+hnew` / `+vnew`) into a command line. The guard logic is: only activate
if `getcmdtype() == ':'` AND the first word of the command is NOT one of the abbreviations
`Aw`, `Awi`, `Awiw`, `Awiwi` (i.e., not an `:Awiwi` command). But the guard uses `match(...)==1`,
which should be `==0` to detect `Awiwi` — as written, it never fires, so the split flag is
**always** injected, even on `:Awiwi ...` commands (where it has no effect, but technically it
violates the stated intent). This is **not** documented as a bug; it has been in the shipped code
and may be relied upon by users.

**Decision.** The Lua port **preserves the guard logic exactly as written** (the `match(...)` return
value check inverted from the intended sense), pending a human decision. If the current behavior is
in fact intentional or has become a convention, the guard can stay. If it is genuinely a bug, a
separate human-initiated ADR should record the intent and authorize a fix.

**Consequences.** The Lua port faithfully reproduces the vimscript behavior. The dogfood checklist
should confirm the `<C-x>` / `<C-v>` mappings work as users expect. Future fixes to the guard logic
are a separate decision.

---

## D12 — split_screen guard corrected: suppress on `:Awiwi` commands (2026-07-07)

**Context.** D11 preserved the vimscript's inverted `<C-x>`/`<C-v>` cmdline guard
(`match(...) == 1`, which never fires) verbatim in `lua/awiwi/init.lua`, pending a human decision.

**Decision.** The user directed: correct the inverted mapping. The guard now checks
`match(...) == 0`, so the split flag (`+hnew`/`+vnew`) is **not** injected when the command line
starts with an `:Awiwi` abbreviation (`Aw`, `Awi`, `Awiw`, `Awiwi`) — the originally stated intent.

**Consequences.** `<C-x>`/`<C-v>` on `:Awiwi …` command lines now submit the command unchanged;
all other ex commands still get the split flag. Supersedes the preservation clause of D11.

---

## D13 — Keep python-markdown with trimmed extensions + local mermaid/strikethrough (2026-07-07)

**Context.** Server rewrite (T13–T17) replaces Flask `server.old/app.py` with FastAPI. Existing app
renders notes with python-markdown library + legacy third-party extensions (`md_mermaid`,
`markdown_strikethrough`, dead `nomnoml` Python extension). Extensions list also includes dead
`meta` (never read) and legacy `markdown-strikethrough` package is unmaintained.

**Decision.** Rewrite keeps python-markdown engine (trimmed extension set: fenced_code, codehilite,
def_list, footnotes, nl2br, sane_lists, toc, tables, attr_list) to preserve corpus semantics —
notes authored against nl2br line-break behavior; switching to CommonMark would visibly change
years of notes. Dropped: `meta`, unmaintained third-party `md_mermaid`/`markdown_strikethrough`.
Replacement: two tiny local preprocessor extensions (`_MermaidExtension`, `_StrikethroughExtension`)
with identical visible output (mermaid divs, `<del>` tags), implemented more idiomatically than legacy.
Also deleted: legacy `;match(N);` non-ASCII escaping hack (proven unnecessary by round-trip unit tests
with umlauts/emoji).

**Consequences.** Server app renders markdown identically to legacy; mermaid/strikethrough behavior
exact; no corpus-wide re-render needed. Dead metadata never used; no loss of feature. Code simpler
(local processors, no third-party extension deps). `server/src/awiwi/mdrender.py` implements;
`server/tests/test_mdrender.py` proves output fidelity.

---

## D14 — Drop auth/login + checkclock; localhost-only access with AWIWI_ALLOW_REMOTE escape hatch (2026-07-07)

**Context.** Legacy Flask app included auth login machinery (`auth` file, `passlib`, session handling)
that never worked (empty `auth` file, random secret regenerated at start, no functional logic). Also
had `checkclock` feature (qtile schedule integration) and "localhost bypass" — a feature that tried
to skip auth for localhost connections. User assessed as: feature set out of scope for viewer, code
fragile/broken, simplify.

**Decision.** Server rewrite drops auth entirely (no login, /logout, sessions, passlib). Instead:
**localhost-only access by default** — HTTP middleware returns 403 for non-localhost requests
(checks `Host` header loopback name OR loopback client peer). Explicit env var override
`AWIWI_ALLOW_REMOTE=1` enables remote access if operator needs it. Checkclock feature dropped
entirely (no work-schedule coupling in viewer). Satisfies user decision (2026-07-07) for a personal,
single-user tool.

**Consequences.** No login UI, no session management, no auth bugs. Remote access possible but
requires explicit opt-in. Notes accessible only over localhost by default, closing the (broken) auth
gap. Config key `AWIWI_ALLOW_REMOTE` goes in `Settings` (env `AWIWI_ALLOW_REMOTE`); middleware
reads it once at lifespan and applies 403 guard to every request (with override check). Simpler than
legacy auth, more secure default (deny remote, require explicit allow).

---

## D15 — AWIWI_HOME env-var home discovery + entrypoint awiwi.app:app pinned (2026-07-07)

**Context.** Config bootstrap problem: `config.json` (plugin output) lives *inside* home directory,
so the server can't bootstrap home discovery from `config.json` (chicken-and-egg). Legacy Flask used
env vars `FLASK_ROOT`, `FLASK_HOST`, `FLASK_PORT`. Lua plugin `:Awiwi serve` already uses
`default_cmd_builder` to construct the launch command (`lua/awiwi/server.lua`, T7, ADR D5); that
function returned a `{cmd, cwd, env}` table structure with env field unpopulated. Server.lua also
needed real `awiwi.app:app` entrypoint (T16 assembled it; T17 must pin it).

**Decision.** Plugin launcher threads `AWIWI_HOME` env var into the spawned uvicorn process:
`lua/awiwi/server.lua`'s `default_cmd_builder(host, port)` now returns env = `{AWIWI_HOME = vim.g.awiwi_home}`;
`vim.system` at `start_server` call site threads that env into the child process (pre-existing plumbing,
just needs populating). Server-side `config.py:Settings` (pydantic-settings) makes `home: Path` field
**required**, sourced from env var `AWIWI_HOME` — fail-fast validation (missing env → `ValidationError`).
Entrypoint: `lua/awiwi/server.lua` `default_cmd_builder` pinned to real `awiwi.app:app` (module-level
ASGI app in `server/src/awiwi/app.py`, landed T16). Doc comment updated to note this supersedes ADR
D5's placeholder clause.

**Consequences.** Home discovery purely env-driven (no config.json bootstrap needed). Launcher control
is clean (pass env vars, avoid process-wide `vim.env` mutations). Server dies fast if `AWIWI_HOME`
unset, not on first config read — clear failure mode. Entrypoint no longer a placeholder; real app
ready. `start_server` call site needs no changes (env plumbing already threaded).

---

**High-water mark: D15**
