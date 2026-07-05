---
name: sync-docs
description: >
  The doc-freshness contract as an executable checklist. Use before every commit
  that changes behavior, and whenever the docs / plan / state files drift from
  reality. Every implementing (sub)agent runs this before committing.
---

# Sync the knowledge layers

This project keeps its knowledge in layered, indexed files (map: `docs/INDEX.md`) that
form a memory system with explicit horizons — working / episodic / semantic / decision
/ procedural (model: `docs/knowledge-base.md`). Run this checklist top to bottom before
committing; skip a step only when it is genuinely untouched by your change. The
deterministic gate `scripts/kb-detect.sh` (path→layer rules in `.claude/kb/rules.tsv`)
backstops this checklist at pre-commit — if it flags a layer, that layer is provably
stale; fix it (or invoke the `kb-curator` subagent to do it from the diff).

Adapt the file names below to this project's real artifacts (the parentheticals are
placeholders).

1. **Task / work-item file** — tick completed acceptance boxes; each tick gets a short
   parenthetical note saying HOW it is verified (test suite, manual, deferred, …).
2. **ADRs** (`docs/decisions.md`) — every decision you made that the spec/docs did not
   already dictate gets the next D-number: decision + rationale, 3–8 lines. Reference
   the ADR number from any doc text that depends on it.
3. **Deep docs** (`docs/*.md`, e.g. architecture / data-model / API / rules) — update
   whatever your change made stale: module lists, API tables, data shapes, rule tables.
4. **Spec** (your authoritative spec doc, if any) — only when observable behavior
   diverges from it; the spec must never contradict the implementation.
5. **Plan / changelog** (e.g. `plan.md`) — extend the status line when a unit of work
   completes (commit, test counts, ADR range, deferred items — match existing entries).
6. **Index** (`docs/INDEX.md`) — update the row of every doc you touched if its
   one-liner changed; add rows for new docs; keep the ADR high-water mark current.
7. **Handover / state ledger** (your live state doc) — append the API handoff facts the
   next unit of work needs and move the "where we are" marker forward. This file is the
   resume point — write it for an agent with zero context.
8. **Memory** (orchestrator only, outside the repo) — store process learnings and
   environment surprises; never repo-derivable state.

The git pre-commit hook runs `scripts/kb-detect.sh`: for each code path it changed it
checks that the knowledge layer the change provably invalidates (per
`.claude/kb/rules.tsv`) is also staged, and blocks the commit otherwise — failure to
update an invalidated layer is a bug. This checklist is the norm; the gate is the
backstop. Escape hatch for genuinely knowledge-neutral commits: `DOCS_OK=1 git commit`.
