# T13 S13.1 — pyproject cleanup + package skeleton + Settings/PluginConfig

## Responsibility

Stand up the buildable `awiwi` package skeleton for the FastAPI server rewrite
(`server/src/awiwi/`) and implement its two configuration primitives:
`Settings` (process env, `AWIWI_*`) and `PluginConfig` (`<home>/config.json`
written by the Neovim plugin). Strict red/green TDD.

## Boundary

Touched only:

- `server/pyproject.toml`
- `server/src/awiwi/__init__.py`
- `server/src/awiwi/config.py`
- `server/tests/conftest.py`
- `server/tests/test_config.py`
- `server/uv.lock` (regenerated via `uv sync`, never edited by hand)

Nothing outside `server/` touched. No `lua/`, no `docs/`, no `server.old/`.

## Deviation from the brief (flag for reviewer)

`pyproject.toml` originally declared `readme = "README.md"`, but no
`README.md` exists anywhere in the repo and creating one was outside this
subtask's file boundary. `uv_build` refuses to build the package without the
declared readme file present on disk. **Fix applied: removed the `readme =
"README.md"` line from `[project]`** rather than add an out-of-boundary file.
If a README is later added, that key can be restored in the same commit.

No other deviations. All requested runtime deps (jinja2, markdown, pygments,
uvicorn, python-multipart) and dev dep (httpx) were added; the dead
`[tool.mypy]` + `[[tool.mypy.overrides]]` blocks were deleted; ruff config,
`pytest` `pythonpath=["src","."]`/`testpaths=["tests"]`, and the `uv_build`
backend block were left untouched.

## What downstream needs from me

Import path: `awiwi.config` (package root `server/src/awiwi/`).

```python
from awiwi.config import Settings, PluginConfig
```

### `Settings` (pydantic-settings `BaseSettings`, `env_prefix="AWIWI_"`)

- Field: `home: Path` — **required**, sourced from `AWIWI_HOME`. No default.
  Instantiating `Settings()` with `AWIWI_HOME` unset raises
  `pydantic.ValidationError` immediately (fail-fast, per brief).
- No `host`/`port` fields — brief says those are the launcher's/uvicorn's
  concern (`lua/awiwi/server.lua`'s `default_cmd_builder`), not `Settings`'.
- Note for callers: because `home` is required with no default, static
  type checkers (basedpyright) flag `Settings()` call sites as missing an
  argument even though pydantic-settings fills it from the environment at
  runtime. Test call sites carry `# pyright: ignore[reportCallIssue]`;
  downstream production code calling `Settings()` will need the same
  comment (or construct via `Settings.model_construct` — not recommended,
  since that skips validation).

### `PluginConfig` (pydantic `BaseModel`, `extra="ignore"`)

Mirrors exactly what `lua/awiwi/server.lua`'s `M._write_json_config` writes
(verified by reading that function directly — read-only reference, not
edited):

| field | type | default |
|---|---|---|
| `search_engine` | `str` | `"rg"` |
| `home` | `str` | `""` |
| `screensaver` | `bool` | `False` |
| `link_color` | `str` | `""` |
| `todo_markers` | `list[str]` | `[]` |
| `onhold_markers` | `list[str]` | `[]` |
| `urgent_markers` | `list[str]` | `[]` |
| `delegate_markers` | `list[str]` | `[]` |
| `question_markers` | `list[str]` | `[]` |
| `due_markers` | `list[str]` | `[]` |

- `PluginConfig.load(home: Path) -> PluginConfig` — classmethod. Reads
  `<home>/config.json`; if the file doesn't exist, returns `PluginConfig()`
  (all defaults, no error). If present, parses via
  `model_validate_json` — unknown/extra keys are silently ignored
  (`extra="ignore"`); missing keys fall back to field defaults.
- `home` here is deliberately a plain default-free-`str` field matching the
  JSON, distinct from `Settings.home` (a `Path`, env-sourced, required) —
  don't conflate the two; `PluginConfig.home` is just whatever string the
  plugin happened to write into `config.json`, unvalidated.

### `notes_home` fixture (`server/tests/conftest.py`)

Plain function-scoped pytest fixture (no cleverness, per instructions),
builds this tree under `tmp_path` and returns the tmp_path root itself:

```
journal/2026/06/2026-06-29.md
journal/2026/06/2026-06-30.md
journal/2026/07/2026-07-01.md
journal/2026/07/2026-07-02.md      # spans the June/July month boundary
journal/todos.md
assets/2026/07/01/x.txt
recipes/cooking/pasta.md
config.json                        # search_engine=rg, home=<tmp_path>,
                                    # screensaver=false, link_color=#0000ff,
                                    # each *_markers = single-item list
                                    # matching its own marker name, e.g.
                                    # todo_markers=["TODO"]
```

Every markdown/text file has minimal but non-empty content (a heading + one
line of body text) so downstream content/render tests (T14) have something
to parse. Available to any test module in `server/tests/` automatically
(standard conftest fixture, no import needed).

## Inputs I consumed

- Design brief: `~/.claude/plans/we-want-to-replace-jaunty-engelbart.md`
  (§Context, §User decisions, §Proposed structure, T13 entry) — authoritative.
- `lua/awiwi/server.lua` (read-only) — confirmed exact `config.json` key
  names/shape via `M._write_json_config` and the `MARKER_TYPES` list
  (`{"todo","onhold","urgent","delegate","question","due"}`).
- Existing `server/pyproject.toml` (pre-cleanup) for what to keep/delete.

## Tests

Targeted:

```sh
cd server && uv run pytest tests/test_config.py -q
```
→ 7 passed (confirmed RED first: `ModuleNotFoundError: No module named
'awiwi.config'` before `config.py` existed, then implemented to GREEN).

Full gate (all three, as required):

```sh
cd server && uv run pytest && uv run ruff check . && uv run basedpyright
```

Results:
- `uv run pytest` → **7 passed**
- `uv run ruff check .` → **All checks passed!**
- `uv run basedpyright` → **0 errors, 0 warnings, 0 notes** (exit 0)

Note: basedpyright's default mode is stricter than pyright's — it treats
warnings as gate-failing (nonzero exit on any warning, not just errors).
Getting to a clean 0/0/0 required: `ClassVar[...]` annotations on both
classes' `model_config` (otherwise `reportUnannotatedClassAttribute` /
`reportIncompatibleVariableOverride`), `model_validate_json` instead of
`json.loads` + `model_validate` (avoids `reportAny` on an untyped `json.loads`
result), and `_ = ...`-prefixing fixture/test `write_text`/`mkdir` calls
whose return values are unused (`reportUnusedCallResult`). No project-level
basedpyright config was added — all fixes are local annotations/idioms.

Test breakdown (`test_config.py`, 7 total):
- `TestSettings`: reads `home` from `AWIWI_HOME`; missing `AWIWI_HOME` raises
  `ValidationError`; unrelated env vars ignored.
- `TestPluginConfig`: parses a real fixture `config.json` (all 10 fields
  checked); missing file → `PluginConfig()` defaults; unknown extra key
  ignored; empty `{}` file → same as in-memory defaults.

`uv sync` was run once (after adding deps + fixing the readme issue) to
refresh `server/uv.lock` and `.venv`; installed 33 packages including the 5
new runtime deps + httpx.

## Status

status: done, updated 2026-07-07T15:12:49Z
