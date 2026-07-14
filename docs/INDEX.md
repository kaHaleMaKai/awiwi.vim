# Knowledge index

The map of every knowledge artifact in this repo, layered from "read always" to "read on
demand". Agents: start here, follow pointers, load only what your task needs. Each layer maps to a
memory horizon (working/episodic/semantic/decision/procedural); see `docs/knowledge-base.md` for
the architecture spec.

## Layers

| layer          | artifact                       | role                                                    | read when                      |
| -------------- | ------------------------------ | ------------------------------------------------------- | ------------------------------ |
| 1 — rules      | `CLAUDE.md`                    | binding rules, entry point, commands                    | always                         |
| 2 — index      | `docs/INDEX.md`                | this map + freshness contract                           | always                         |
| 4 — deep docs  | `docs/architecture.md`         | **authoritative spec**: module map, command surface, data flow, Lua-rewrite target | touching any plugin/server code |
| 4 — deep docs  | `docs/data-model.md`           | SQLite schema (tasks/checklists) + query files          | touching `dao`/`sql`/`resources/db` |
| 4 — deep docs  | `docs/glossary.md`             | domain + architecture vocabulary                        | you hit an unfamiliar term     |
| 4 — deep docs  | `docs/knowledge-base.md`       | memory-architecture spec + self-maintenance contract    | questions about the doc system |
| 4 — deep docs  | `docs/decisions.md`            | ADR log — **high-water mark: D23** (keep this current)   | before deciding anything       |
| 3 — working    | `handovers/STATE.md`           | Lua-rewrite ledger: transactions done/next, resume point | resuming / orchestrating the rewrite |
| 3 — working    | `handovers/lua-port/<mod>.md`  | per-module port brief + "Ported" handover               | porting that module            |
| 5 — pipeline   | `.claude/agents/kb-curator.md` | doc-refresh subagent                                    | orchestrating                  |
| 5 — pipeline   | `.claude/agents/vim-archaeologist.md` | read-only vimscript recon → port brief (sonnet)  | orchestrating the rewrite      |
| 5 — pipeline   | `.claude/agents/lua-port-engineer.md` | TDD Lua implementation of one module (sonnet)    | orchestrating the rewrite      |
| 5 — pipeline   | `.claude/agents/qa-verifier.md` | independent PASS/FAIL gate per ported module (haiku)   | orchestrating the rewrite      |
| 5 — pipeline   | `.claude/skills/lua-port`      | binding port playbook: layout, order, idioms, done-def  | planning / implementing `lua/` |
| 5 — pipeline   | `.claude/skills/sync-docs`     | the freshness checklist                                 | orchestrating / pre-commit     |
| 6 — memory     | user memory dir (outside repo) | orchestrator process learnings, preferences             | session start (auto-loaded)    |

## Freshness contract

Every (sub)task that changes behavior updates, before its commit: ADRs → affected deep docs
(`architecture.md`, `data-model.md`) → glossary if a term changed → this index. Executable
checklist: `.claude/skills/sync-docs`. The pre-commit hook (`scripts/kb-detect.sh`, rules in
`.claude/kb/rules.tsv`) is the backstop; this contract is the norm. Memory (layer 6) gets process
learnings only — never repo-derivable state. Failure to update an invalidated layer is a bug.

## Maintenance of this file

Update the table when docs are added/removed/repurposed and keep the ADR high-water mark current.
One line per artifact; content lives in the artifacts.
