# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Overview

awiwi.vim is a **Neovim** plugin (uses `nvim_*` APIs, `jobstart`, `luaeval`, `pyx`/`py3` — not
plain Vim) for managing markdown notes (spiritual predecessor of Obsidian), focused on daily
journaling. A server component (viewer) renders the notes as extended markdown (internal links,
search, mermaid, TOC).

**Direction:** the vimscript plugin (`autoload/`, `ftplugin/`, `ftdetect/`) is being refactored and
rewritten in **Lua**, modularized module-for-module. The server is being rewritten from Flask
(`server.old/`) to **FastAPI + Pydantic** (`server/`). `docs/architecture.md` is the authoritative
spec and doubles as the rewrite target — keep it truthful.

## Doc types

Awiwi supports this hierarchy of document types (files live under `g:awiwi_home`):

- `journal/{year}/{month}/{year}-{month}-{day}.md` → daily journals
- `assets/{year}/{month}/{day}/{name-of-asset}.md` → any kind of file linked inline in any other doc
- `recipes/{arbitrary-nesting}/{name-of-recipe}.md` → small markdown how-tos linkable from other docs

# Architecture

Read `docs/architecture.md` for the module map, command surface, and data flow. Big picture:

- **Plugin core** — `autoload/awiwi.vim` is the public API; `autoload/awiwi/*.vim` are the modules
  (`cmd` command dispatch, `dao`/`sql` SQLite task store, `task`, `view`, `asset`, `date`, `hi`
  syntax/highlight, `path`, `util`, `server`, `bookmarks`, `str`).
- **Entry** — `ftplugin/awiwi.vim` defines the single `:Awiwi` command (dispatches to
  `awiwi#cmd#run`) plus buffer mappings; `ftdetect/awiwi.vim` sets the `awiwi`/`awiwi.todo`
  filetypes for markdown under `g:awiwi_home`.
- **Persistence** — journals/assets/recipes are plain markdown files on disk. The **shipped** task
  tracker is a plain-text time log (`<g:awiwi_home>/data/task.log`). A SQLite DB
  (`<g:awiwi_home>/task.db`, `resources/db/*.sql`) is a **WIP** replacement not yet reachable from
  `:Awiwi`. See `docs/data-model.md` and `docs/architecture.md` → Dead code / WIP.
- **Server** — `server/` (FastAPI + Pydantic, complete T13–T17) is the note viewer, replacing `server.old/` (Flask).

# Commands

**Plugin:** no build step. Load requires `g:awiwi_home` set. External deps: `sqlite3`, `fzf`,
ripgrep (`rg`) — verify before assuming they exist.

**Server** (`cd server`, uv-managed, Python ≥3.13):

```sh
uv sync                    # install deps
uv run pytest              # tests (testpaths=tests)
uv run pytest tests/test_x.py::test_y   # single test
uv run ruff check .        # lint
uv run ruff format .       # format (line-length 90, double quotes)
uv run basedpyright        # type check
```

`pyproject.toml` carries leftover Django/mypy config from a template — the live stack is
FastAPI + Pydantic + pytest + ruff + basedpyright. Ignore the Django/mypy overrides.

**Frontend** (`cd server/frontend`, npm-managed): `server/frontend/dist/` is gitignored, not
committed (ADR D25, supersedes D20). Run `npm run build` after any change under
`server/frontend/` — the server serves whatever is currently in `dist/`.

# Knowledge base — self-maintaining layered memory

Operational knowledge lives in layered, git-tracked files. Start at `docs/INDEX.md` (the map) and
`docs/knowledge-base.md` (the architecture spec). Deep docs: `docs/architecture.md` (spec),
`docs/data-model.md` (SQLite schema), `docs/glossary.md`, `docs/decisions.md` (ADRs, append-only).

**Contract:** every behavior-changing commit leaves every invalidated knowledge layer fresh.
Failure to update an invalidated layer is a bug. The pre-commit hook (`.githooks/pre-commit`) runs
`scripts/kb-detect.sh`, which gates staged code paths against `.claude/kb/rules.tsv` — at least one
mapped knowledge layer must also be staged. Refresh via the `sync-docs` skill or the `kb-curator`
subagent. Escape hatch for genuinely knowledge-neutral commits: `DOCS_OK=1 git commit …`.

# Lua rewrite flow

The active project: port the vimscript plugin to Lua (nvim ≥0.12 idioms, treesitter where
structure is structural), module-for-module, leaf-first, DRY/KISS, strict red/green TDD.
**Playbook (binding): `.claude/skills/lua-port/SKILL.md`** — layout, port order, idiom table,
definition of done. `docs/architecture.md` stays the behavior spec.

Conventions for `/flow:plan` / `/flow:orchestrate` (Phase A: adopt these, scaffold nothing):

- **ledger**: `handovers/STATE.md`; per-module handovers `handovers/lua-port/<module>.md`,
  archived to `handovers/done/` when a module closes
- **progress**: `.claude/progress/<agent>-<scope>.md` (gitignored)
- **agents/tiers**: `vim-archaeologist` (sonnet, read-only recon → port brief) →
  `lua-port-engineer` (sonnet, TDD implementation; bump to opus for `cmd`/façade) →
  `qa-verifier` (haiku, independent PASS/FAIL gate); `kb-curator` (haiku) refreshes docs.
  Archaeologists and verifiers parallelize; engineers serialize through the verify gate.
- **gates**: full suite `nvim --clean --headless -l tests/run.lua` + pre-commit kb-detect
  (a `lua/` change must move `docs/architecture.md` or `docs/INDEX.md` in the same commit)
- **doc sync**: `sync-docs` skill / `kb-curator` agent

**Lua tests** (zero deps, real nvim): `nvim --clean --headless -l tests/run.lua` (full) or with
spec files as args (targeted). Spec globals: `describe/it/eq/ok`.

# Refactoring judgment

Before implementing any new feature or change, ask:

1. **Existing friction** — does nearby code already make this harder than it should be? If yes, refactor first.
2. **Future friction** — will adding this as-is make the next change harder? Estimate likelihood × impact. If the area is touched often and the cost is high, refactor now.
3. **Cost of skipping** — stale abstractions compound. Skipping today means paying interest on every future change in this area.
4. **Cost of refactoring** — scope creep, test churn, merge risk. Only refactor when the friction is real and near-term, not hypothetical.

**Default**: refactor when friction is present or imminent; skip when it's speculative. Never refactor as a detour — if it warrants doing, do it as a named, atomic commit before the feature work.

# TDD

Enforce strict red/green TDD. Prioritise **high-value (acceptance) tests** over typical developer-oriented tests.

## Test intent classification

Classify each test by intent before writing it:

- **High-value tests** verify user/business outcomes — they implement acceptance criteria from user stories and form the contract for what a feature must do. Write these first and always.
- **Typical tests** validate technical internals (utilities, helpers, DB queries). Write these only when they cover logic not exercised by the high-value tests above.

## Process

1. Start from the feature/user-side (top-down): identify the acceptance criteria, then write the test that proves the feature satisfies them.
2. Analyse which tests are required and which existing ones to change or delete.
3. Do not accumulate low-value unit tests for implementation details already covered by higher-level tests.
4. Tests must stay in sync with code — when behaviour changes, update or delete the test; do not leave dead/stale tests.
