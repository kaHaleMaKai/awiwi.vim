# Glossary

Semantic-memory vocabulary for this project: domain terms and architecture terms that an
agent or new contributor might not know. Keep entries short (1–3 lines), alphabetical, and
truthful — derive each definition from the code/spec, not from guesses. Add a term the
first time it appears in a doc or the codebase and would not be obvious. Link to the deep
doc that owns the concept where useful.

Format: **Term** — definition. (optional: see `docs/<owning-doc>.md`)

---

**asset** — any file linked inline from another doc; stored at `assets/{year}/{month}/{day}/{name}`. Managed by `autoload/awiwi/asset.vim`.

**awiwi_home** (`g:awiwi_home`) — required global; root directory holding `journal/`, `assets/`, `recipes/`, `todos/`, `data/`, `cache/`. Plugin load fails without it.

**:Awiwi** — the single user command; subcommands dispatch through `awiwi#cmd#run` (`autoload/awiwi/cmd.vim`). See `docs/architecture.md` for the subcommand list.

**checklist** — per-file list of checkable items, persisted in the SQLite `checklist` table. See `docs/data-model.md`.

**DAO** — `autoload/awiwi/dao.vim`, the data-access layer over the SQLite task/checklist DB; builds statements via `sql.vim`.

**journal** — a daily markdown note at `journal/{year}/{month}/{year}-{month}-{day}.md`; the primary doc type.

**Knowledge layer** — a git-tracked artifact that holds one horizon of the project's
memory (working / episodic / semantic / decision / procedural). The freshness contract
keeps each layer in sync with the code; see `docs/knowledge-base.md`.

**marker** — a keyword that classifies a journal line (e.g. `TODO`, `FIXME`, `ONHOLD`, `DUE`, `@incident`, `@issue`, `@bug`, `@@`, `QUESTION`); drives highlighting and task extraction. Defined in `autoload/awiwi.vim`.

**recipe** — a small reusable how-to note under `recipes/`, linkable from other docs.

**task** — a tracked unit of work with state (`started`/`paused`/`done`), urgency, project, and an append-only `task_log`. Backed by SQLite; see `docs/data-model.md`.

**urgency** — named priority level mapped to a numeric value (`backlog`=0 … `immediate`=10).

**viewer / server** — the web renderer for awiwi notes; new impl in `server/` (FastAPI), legacy in `server.old/` (Flask).
