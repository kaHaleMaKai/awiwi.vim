#!/usr/bin/env bash
# Knowledge-base freshness gate — deterministic, offline, no LLM.
#
# Reads the machine-readable freshness contract (.claude/kb/rules.tsv) and checks
# that every code change in the staged set (or a given git ref/range) is paired
# with an update to at least one of the knowledge layers it provably invalidates.
#
# Usage:
#   scripts/kb-detect.sh             # check the staged set (pre-commit use)
#   scripts/kb-detect.sh REF..REF    # check an arbitrary diff (validation/history)
#   scripts/kb-detect.sh REF         # check a single ref against its parent-style diff
#
# Exit: 0 = layers fresh (or fail-open) · 1 = at least one violation.
# Escape hatch: DOCS_OK=1 forces exit 0 (genuinely knowledge-neutral change).
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "kb-detect: not in a git repo — skipping (fail-open)"
  exit 0
}
rules_file="$repo_root/.claude/kb/rules.tsv"

# ── escape hatch ────────────────────────────────────────────────
if [ "${DOCS_OK:-0}" = "1" ]; then
  echo "kb-detect: DOCS_OK=1 — skipping freshness check"
  exit 0
fi

# ── rules manifest must exist (fail-open if absent) ─────────────
if [ ! -f "$rules_file" ]; then
  echo "kb-detect: rules manifest missing ($rules_file) — skipping (fail-open)"
  exit 0
fi

# ── compute the changed file set ────────────────────────────────
# With an argument we diff that ref/range (testing against history); otherwise
# we use the staged set, which is what the pre-commit hook cares about.
if [ -n "${1:-}" ]; then
  changed="$(git diff --name-only "$1")"
else
  changed="$(git diff --cached --name-only)"
fi

if [ -z "$changed" ]; then
  echo "kb-detect: no changed files — nothing to check"
  exit 0
fi

# Non-shipping paths carry no knowledge surface — a test double or fixture is not
# a real "shared lib"/"domain" change, so it must not trip a rule on its own.
# Filtering these here (rather than encoding negative lookahead into every ERE in
# rules.tsv) keeps the contract patterns simple and honest.
#
# EXTEND THIS for your framework's GENERATED / non-authored paths — they have no authored
# knowledge surface either and should never trip a rule on their own. Common additions
# (add the alternatives you need to the regex below):
#   (^|/)migrations/        # Django / Rails / etc. auto-generated migrations
#   \.(po|mo)$              # compiled / source i18n catalogs
#   (^|/)(package-lock\.json|yarn\.lock|uv\.lock|Cargo\.lock|poetry\.lock)$  # lockfiles
changed="$(printf '%s\n' "$changed" | grep -Ev '(^|/)(__mocks__|__fixtures__)/|(\.|/)(test|spec|fixtures?|mock|mocks)\.[^/]+$|\.test\.|\.spec\.' || true)"

if [ -z "$changed" ]; then
  echo "kb-detect: only non-shipping (test/mock/fixture) paths changed — nothing to check"
  exit 0
fi

# ── evaluate every rule ─────────────────────────────────────────
violations=0
# Dedup key = the REQUIRED_ANY set; avoids printing the same missing layer set
# many times when several code paths trip rules with identical requirements.
seen_required=""

while IFS=$'\t' read -r pattern required rationale; do
  # skip comments and blanks
  case "$pattern" in
    '' | \#*) continue ;;
  esac
  [ -n "$required" ] || continue

  # which staged paths match this rule's PATTERN?
  matched="$(printf '%s\n' "$changed" | grep -E "$pattern" || true)"
  [ -n "$matched" ] || continue

  # is at least one REQUIRED_ANY file in the changed set?
  satisfied=0
  IFS=',' read -ra req_arr <<<"$required"
  for req in "${req_arr[@]}"; do
    req="${req#"${req%%[![:space:]]*}"}" # ltrim
    req="${req%"${req##*[![:space:]]}"}" # rtrim
    [ -n "$req" ] || continue
    if printf '%s\n' "$changed" | grep -Fxq "$req"; then
      satisfied=1
      break
    fi
  done
  [ "$satisfied" -eq 1 ] && continue

  # dedup on the required-set string
  case "$seen_required" in
    *"|$required|"*) continue ;;
  esac
  seen_required="$seen_required|$required|"

  if [ "$violations" -eq 0 ]; then
    echo "kb-detect: knowledge layers are STALE — code changed without its docs:"
    echo ""
  fi
  violations=$((violations + 1))
  echo "  ✗ ${rationale}"
  echo "    matched code path(s):"
  printf '%s\n' "$matched" | sed 's/^/      - /'
  echo "    expected one of: ${required}"
  echo ""
done <"$rules_file"

if [ "$violations" -ne 0 ]; then
  echo "kb-detect: $violations violation(s) — stage the listed layer(s) or DOCS_OK=1 for a knowledge-neutral change"
  exit 1
fi

echo "kb-detect: knowledge layers fresh"
exit 0
