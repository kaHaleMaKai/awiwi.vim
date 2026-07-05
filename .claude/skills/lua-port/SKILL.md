---
name: lua-port
description: >
  Binding playbook for the vimscript→Lua rewrite of awiwi.vim: target layout,
  leaf-first port order, vimscript→nvim-Lua idiom table, treesitter guidance,
  KISS/DRY rules, test-runner usage, and the per-module definition of done.
  Read before planning (/flow:plan) or implementing any lua/ change; the
  lua-port-engineer and qa-verifier agents treat it as their contract.
---

# Lua port playbook

`docs/architecture.md` is the behavior spec; this file is *how* the port is
built. One vimscript module → one work unit → one Lua module, spec'd by a port
brief (`handovers/lua-port/<module>.md`), implemented red/green, verified
independently.

## Target layout

```
lua/awiwi/init.lua        -- façade (ports autoload/awiwi.vim) — LAST
lua/awiwi/<module>.lua    -- one per autoload/awiwi/<module>.vim
tests/run.lua             -- dependency-free runner (nvim -l)
tests/<module>_spec.lua   -- acceptance specs from the port brief
```

Modules are `local M = {} … return M`. No `_G` writes ever. Config stays on the
existing `g:awiwi_*` globals (read via `vim.g`) so vimscript and Lua coexist
during the port — no new config system.

## Port order (leaf-first; deps of a unit are already ported)

1. `str` → 2. `path` → 3. `date` → 4. `util` → 5. `asset` → 6. `hi`
→ 7. `server` → 8. `sql` → 9. `cmd` → 10. façade `init.lua` + `ftplugin`/`ftdetect` switchover.

**Dropped, not ported** (dead/unloadable per architecture.md — record the drop
as an ADR when the decision is confirmed): `task.vim`, `view.vim`,
`bookmarks.vim`, `ask.vim` (stub). `dao.vim` (WIP SQLite store) is deferred —
port only after an explicit ADR picks it over the file-based task log.

## Idiom table (vimscript → nvim ≥0.12 Lua)

| vimscript                         | Lua port                                             |
| --------------------------------- | ---------------------------------------------------- |
| `system('date …')` / shelling out | `os.date`/`os.time`; keep subprocesses only for `sqlite3`, `rg`, `fzf`, `xclip`, `drawio` |
| `jobstart` / `system()`           | `vim.system(cmd, opts, on_exit)`                     |
| manual path joins, `fnamemodify`  | `vim.fs.joinpath/dirname/basename/normalize/find`    |
| `readfile`/`writefile`            | `io` / `vim.uv.fs_*` (async only where it matters)   |
| `json_encode/decode`              | `vim.json.encode/decode`                             |
| `matchadd`, `:syntax`, virtualtext dicts | `nvim_buf_set_extmark` in one namespace per concern |
| regex over markdown structure     | `vim.treesitter` (see below)                         |
| `pyx`/`py3` (random id, todo cleanup) | pure Lua (`vim.uv.random`/`os.time`-seeded), no Python |
| `fn#apply`/`fn#spread`, ext `path#` | drop — plain Lua calls; deps on external VimL plugins end here |
| `input()`/`inputlist()`           | `vim.ui.input` / `vim.ui.select`                     |
| `s:` script-locals                | `local` in module scope                              |
| autoload guards `g:autoloaded_*`  | drop — `require` caches                              |

## Treesitter (replaces regex where structure is structural)

Markdown structure — headings (TOC, `entries`, link `#anchor` completion), list
items/checkboxes (`o`/`O`/`<C-y>` logic, todo meta), fenced code blocks
(`aP`/`iP` text objects) — is read via `vim.treesitter.get_parser(buf,
'markdown')` + queries on `markdown`/`markdown_inline` (`atx_heading`,
`list_item`, `task_list_marker_(un)checked`, `fenced_code_block`,
`inline_link`). Awiwi-specific *line* syntax (markers like `TODO:`/`DUE`, `{…}`
JSON meta, `!!redacted`) is not in the grammar — plain Lua patterns are correct
there. Don't force treesitter where a `:match` on one line is honest.

## KISS / DRY rules (enforced by qa-verifier)

- Port the brief's behavior contract, nothing more. No speculative options,
  no compat layers for the dropped modules.
- A dep already ported? `require('awiwi.<dep>')` — never re-derive its logic.
- `str.vim`-style helpers that nvim now provides (`vim.startswith`,
  `vim.endswith`, `vim.trim`, `string.find(..., 1, true)`) become thin aliases
  or disappear at call sites — prefer disappearing.
- Bugs listed in the brief: `fix in port` → fix silently correct; `preserve` →
  keep with a one-line comment naming the quirk.

## Tests

Runner: `tests/run.lua`, zero deps, runs inside real nvim.

```sh
nvim --clean --headless -l tests/run.lua                          # full suite
nvim --clean --headless -l tests/run.lua tests/date_spec.lua      # targeted
```

Specs use the runner's globals: `describe(name, fn)`, `it(name, fn)`,
`eq(expected, actual)`, `ok(cond, msg)`. Real nvim API is available (`--clean`
= no user config; runner prepends the repo to `runtimepath`). Buffer-behavior
specs create scratch buffers (`nvim_create_buf`) — never touch real files
outside a `vim.fn.tempname()` dir. Red first, always.

## Definition of done (per module = one flow transaction)

1. Every numbered behavior-contract item in the brief has a spec; suite green.
2. Full suite green (`nvim --clean --headless -l tests/run.lua`).
3. Handover `handovers/lua-port/<module>.md` gains `## Ported` (Lua surface,
   deviations, gotchas) + `status: done` + commit hash.
4. Committed through the repo gates — `.githooks/pre-commit` requires a
   knowledge layer (`docs/architecture.md` module-map row flips to "ported") to
   move with `lua/` changes; that edit is kb-curator/sync-docs work, in the
   same commit.
5. qa-verifier PASS.
