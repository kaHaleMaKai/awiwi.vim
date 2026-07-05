#!/usr/bin/env bash
# Knowledge-base self-updating fallback — opt-in, never blocks a commit.
#
# When kb-detect found a stale layer, this drives a headless Haiku Claude run to
# WRITE the missing knowledge-layer updates from the staged diff. It is designed
# to fail safe in every way: disabled by default, recursion-guarded, hard-timed.
#
# Always exits with kb-detect's verdict (0 fresh / 1 still stale) so the caller
# can re-gate. It NEVER itself blocks: if it cannot run (disabled / no CLI /
# timeout) it simply leaves the tree untouched and re-runs the detector.
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
detect="$repo_root/scripts/kb-detect.sh"

# ── recursion guard ─────────────────────────────────────────────
# The headless run itself stages files and may trip hooks/this script again.
if [ -n "${KB_RUNNING:-}" ]; then
  exit 0
fi

# ── opt-in ──────────────────────────────────────────────────────
if [ "${KB_AUTOUPDATE:-0}" != "1" ]; then
  echo "kb-update: auto-update disabled; set KB_AUTOUPDATE=1 to enable"
  exit 0
fi

# ── require the CLI ─────────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  echo "kb-update: 'claude' not on PATH — skipping auto-update"
  exit 0
fi

echo "── kb-update: attempting headless knowledge-layer refresh (Haiku) ──"

read -r -d '' prompt <<'PROMPT' || true
You are updating this project's knowledge layers to match a code change that is
about to be committed. The pre-commit gate (scripts/kb-detect.sh) flagged that code
changed without its documentation layer.

Do this:
1. Read .claude/kb/rules.tsv — the machine-readable freshness contract (its header
   documents the format). If docs/knowledge-base.md exists, read it too for context.
2. Run `scripts/kb-detect.sh` to get the exact worklist: each violation lists the
   matched code path(s), the rationale, and the knowledge layer(s) expected to move.
3. Inspect the staged diff (`git diff --cached`) to understand what actually changed.
4. Update ONLY knowledge layers to reflect the change accurately and concisely:
   docs/*.md, docs/INDEX.md, and any plan / changelog / state / task files your
   rules.tsv points at. For each violation, update at least one of the expected
   layer files with real, correct content derived from the diff — do not fabricate.
5. `git add` every layer file you edit.
6. Re-run `scripts/kb-detect.sh` and stop once it exits clean.

Hard rules — NEVER violate:
- NEVER edit source code, tests, scripts/**, or .githooks/**.
- NEVER run `git commit`, `git push`, or any history-rewriting command.
- Only `git add` knowledge-layer files (docs/, your plan/state/task files).
- Keep edits minimal and truthful; mirror the existing doc style.
PROMPT

# Build the invocation. We prefer the rich flag set this CLI (v2.1.x) supports and
# degrade to the simplest working form if any flag is rejected. We deliberately do
# NOT pass any --dangerously / --allow-dangerously flag. acceptEdits lets the
# headless run apply edits to the allowed doc files without interactive prompts.
run_claude() {
  KB_RUNNING=1 timeout 300 "$@"
}

rc=0
if ! run_claude claude -p \
  --model claude-haiku-4-5 \
  --permission-mode acceptEdits \
  --allowedTools "Read,Edit,Write,Bash,Grep,Glob" \
  "$prompt"; then
  rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "kb-update: headless run timed out (300s) — leaving tree as-is"
  else
    # A non-timeout failure may be an unsupported flag on this CLI build; retry
    # with the simplest portable invocation before giving up.
    echo "kb-update: rich invocation failed (rc=$rc) — retrying minimal 'claude -p'"
    KB_RUNNING=1 timeout 300 claude -p "$prompt" || \
      echo "kb-update: minimal invocation also failed — leaving tree as-is"
  fi
fi

# ── re-gate and propagate the detector's verdict ────────────────
echo "── kb-update: re-checking freshness ──"
"$detect"
