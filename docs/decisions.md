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
