# Data model

awiwi stores two kinds of state:

- **Documents** (journals, assets, recipes) — plain markdown files on disk under `g:awiwi_home`.
  No database; the filesystem hierarchy *is* the model (see `CLAUDE.md` → Doc types).
- **Active-task timer (shipped)** — a JSON-formatted log at `<g:awiwi_home>/data/task.log`, written by
  `lua/awiwi/init.lua` (Lua port, T10). One JSON object per line; format described below.
  This is the task feature that actually ships. (Vimscript version wrote vimscript `string()` dicts;
  see ADR D8 for the format change.)
- **SQLite DB (WIP, not reachable from `:Awiwi`)** — `<g:awiwi_home>/task.db`, accessed through
  `autoload/awiwi/dao.vim` (ORM) and `autoload/awiwi/sql.vim` (shells out to the `sqlite3` binary).
  An in-progress replacement for the file log; see `docs/architecture.md` → Dead code / WIP.

This doc is the source of truth for the SQLite schema. Schema lives in `resources/db/init.sql`;
each query is a separate file `resources/db/<verb>-<noun>.sql`.

## Shipped task.log format (active-task timer)

**File:** `<g:awiwi_home>/data/task.log` (appended-only, JSON lines format, one record per line).

**Record structure** (JSON object):
```json
{
  "title": "Task title",
  "state": "active",
  "task_duration": 0,
  "created_at": 1234567890,
  "activity": [
    {"action": "activate", "ts": 1234567890},
    {"action": "deactivate", "ts": 1234567905}
  ]
}
```

- `title` (string) — task title extracted from the journal line where the task appears (e.g., `## My Task`).
- `state` (string) — `"active"` or `"inactive"`.
- `task_duration` (number) — cumulative duration in seconds at the time the record was written.
- `created_at` (number) — Unix timestamp when the task was first created/logged.
- `activity` (array of objects) — chronological list of actions (`"activate"` or `"deactivate"`)
  and their timestamps (`ts`, Unix time).

**Migration note:** Vimscript version (prior to T10) wrote vimscript `string()` dict literals;
the Lua port (T10+) writes JSON. Old lines fail gracefully on decode and are skipped; no explicit
migration step is needed. See ADR D8 for the rationale and consequences.

## Schema (`resources/db/init.sql`)

`PRAGMA foreign_keys = 1`. All DDL runs in one transaction.

| table            | purpose                                     | key columns                                                                                                    |
| ---------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `task`           | one row per task                            | `id`, `title`, `task_state_id`, `date`, `start`, `end`, `backlink`, `forwardlink`, `project_id`, `issue_link`, `urgency_id`, `updated` |
| `task_state`     | lookup: task lifecycle state                | `id`, `name` (`started`, `paused`, `done`), `added`                                                            |
| `task_log`       | append-only event log per task              | `id`, `timestamp`, `task_id`→`task`, `state_id`→`task_log_state`                                               |
| `task_log_state` | lookup: log event kinds                     | `name` (`created`, `restarted`, `paused`, `done`, `duration_updated`, `urgency_changed`)                       |
| `urgency`        | lookup: urgency level → numeric value       | `name`/`value` (`backlog`=0, `low`=3, `normal`=5, `high`=7, `immediate`=10)                                    |
| `project`        | project a task belongs to                   | `id`, `name`, `url`, `added`                                                                                    |
| `tag`            | free tags                                   | `id`, `name`, `added`                                                                                           |
| `task_tags`      | M:N join `task` ↔ `tag`                    | `task_id`→`task`, `tag_id`→`tag`                                                                               |
| `project_tags`   | M:N join `project` ↔ `tag`                  | `project_id`→`project`, `tag_id`→`tag`                                                                          |
| `checklist`      | per-file checklist items                    | `id`, `file`, `title`, `created`, `checked`, `updated`                                                         |
| `setting`        | DB metadata                                 | `name`/`value` — seeded with `version=1`, `db_created`                                                          |

Trigger `update_task_timestamp` bumps `task.updated` on change. Seeded lookups: `urgency` (5
levels), `task_state` (3), `task_log_state` (6), `setting` (version + created).

## Queries (`resources/db/*.sql`)

One file per statement, loaded by `dao.vim`:

- `init.sql` — full schema + seed data (run once to create the DB).
- `create-task.sql`, `create-project.sql`, `create-tag.sql`, `create-urgency.sql`, `create-checklist.sql` — inserts.
- `get-active-task.sql`, `get-all-tasks.sql`, `get-tasks-by-title.sql`, `get-most-recent-task-by-title.sql`, `get-task-tags-by-title.sql` — reads.

## Notes for the rewrite

- `task.task_state_id` and `task_log.state_id` are declared `varchar` but reference integer PK
  lookup tables — a schema smell to fix when porting (record an ADR in `docs/decisions.md`).
- **Query/schema drift:** several `get-*.sql` reference columns absent from `init.sql`
  (`task.state`, `task.issue_id`, `task_log.change` vs actual `task_state_id`, `issue_link`,
  `task_log.state_id`). The queries and schema were last edited out of sync — reconcile in the port.
- Markers that classify journal lines (TODO / ONHOLD / FIXME / DUE / @incident / @change / @issue /
  @bug / @@ delegate / QUESTION) are defined in `autoload/awiwi.vim`, not the DB — they drive
  highlighting and task extraction. Any change to marker semantics is a behavior change.
