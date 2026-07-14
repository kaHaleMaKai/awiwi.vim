// Best-effort client-side re-match of a search hit's line text against the
// query, so the results view can wrap the match in <mark> the way
// mockups/search.html's `<mark class="hit-match">` does. `SearchHit` (T23.2)
// only carries a `col` (match start column, 1-based per ripgrep --column),
// not a match length, so exact byte-for-byte reproduction of ripgrep's match
// span isn't attempted — this is a display nicety, not a correctness-critical
// path. `rg` always runs case-insensitively (`-i`, search.py's _RG_BASE_ARGS),
// so both modes below match case-insensitively too.
import type { SearchMode } from "./api";

export interface HighlightSegment {
  before: string;
  match: string;
  after: string;
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Returns the first case-insensitive match of `query` in `text` split into
 * before/match/after, or `null` if there's no match (or `query` is empty, or
 * — `mode: "regex"` — `query` isn't a valid RegExp source). Never throws. */
export function highlightMatch(
  text: string,
  query: string,
  mode: SearchMode,
): HighlightSegment | null {
  if (!query) return null;
  let re: RegExp;
  try {
    re = new RegExp(mode === "regex" ? query : escapeRegExp(query), "i");
  } catch {
    return null;
  }
  const m = re.exec(text);
  if (!m) return null;
  return {
    before: text.slice(0, m.index),
    match: m[0],
    after: text.slice(m.index + m[0].length),
  };
}
