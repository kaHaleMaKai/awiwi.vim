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
