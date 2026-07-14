// Pure URL <-> search-state mapping for the "/search" route. Kept state-free
// and DOM-free (only takes/returns strings and plain objects) so it's usable
// from both `SearchBar.svelte` (header, drives typing) and `SearchPage.svelte`
// (results view) without either owning a canonical copy of "what does the URL
// mean" — see handovers/server-rewrite/T25.4-search-ws.md.
//
// URL shape: `/search?q=<pattern>&mode=regex&scope=journal,recipes`.
// - `q` omitted -> "" (empty query -> caller must not fetch, per S25.4 brief).
// - `mode` omitted -> "fixed" (matches the backend's own default, T23.2).
// - `scope` omitted -> [] (meaning "search all three" to the backend, i.e.
//   omit the query param entirely rather than send `scope=journal,assets,recipes`).

import type { SearchHit, SearchMode, SearchScope } from "./api";

export interface SearchUrlState {
  q: string;
  mode: SearchMode;
  scopes: SearchScope[];
}

const VALID_SCOPES: readonly SearchScope[] = ["journal", "assets", "recipes"];

function isSearchScope(value: string): value is SearchScope {
  return (VALID_SCOPES as readonly string[]).includes(value);
}

/** Parse a `location.search`-style string (with or without the leading `?`)
 * into a `SearchUrlState`. Never throws — unknown/malformed `mode`/`scope`
 * tokens are dropped rather than propagated. */
export function parseSearchUrl(search: string): SearchUrlState {
  const params = new URLSearchParams(search);
  const q = params.get("q") ?? "";
  const mode: SearchMode = params.get("mode") === "regex" ? "regex" : "fixed";
  const scopeParam = params.get("scope");
  const scopes = scopeParam
    ? scopeParam.split(",").filter((s) => s.length > 0 && isSearchScope(s))
    : [];
  return { q, mode, scopes: scopes as SearchScope[] };
}

/** Serialize a `SearchUrlState` back to a querystring (no leading `?`, no
 * leading `/search`) — the canonical form parseSearchUrl round-trips
 * losslessly. Empty state serializes to `""` (bare `/search`). */
export function serializeSearchUrl(state: SearchUrlState): string {
  const params = new URLSearchParams();
  if (state.q) params.set("q", state.q);
  if (state.mode === "regex") params.set("mode", "regex");
  if (state.scopes.length) params.set("scope", state.scopes.join(","));
  return params.toString();
}

/** Builds the `/search?...` path for a given state, or bare `/search` when
 * the querystring would be empty. Convenience wrapper around
 * `serializeSearchUrl` for the two callers that both need this exact rule. */
export function searchPath(state: SearchUrlState): string {
  const qs = serializeSearchUrl(state);
  return qs ? `/search?${qs}` : "/search";
}

// --- Hit -> SPA route mapping + grouping (mockups/search.html) ---
//
// SearchHit.target (T23.2) is a faithful copy of the legacy dataclass, not a
// redesign for the SPA: todo/journal/asset targets already happen to match
// this SPA's own route shapes exactly (`/todo`, `/journal/2026-07-01`,
// `/assets/2026-07-01/name.ext`), but the recipe target is the bare
// home-relative relpath with NO leading slash (`recipes/ops/x.md`) — the one
// case that needs adjusting before it's a usable `<a href>`.

/** The home-relative relpath a hit's file actually lives at — used for both
 * the group heading (`mockups/search.html`'s bold `.search-file` text) and
 * for grouping hits from the same file together. */
export function hitRelpath(hit: SearchHit): string {
  switch (hit.type) {
    case "todo":
      return "journal/todos.md";
    case "journal": {
      const [y, m] = hit.name.split("-");
      return `journal/${y}/${m}/${hit.name}.md`;
    }
    case "asset": {
      // hit.name is "YYYY-MM-DD/filename" (search.py's _map_hit).
      const slash = hit.name.indexOf("/");
      const date = slash === -1 ? hit.name : hit.name.slice(0, slash);
      const filename = slash === -1 ? "" : hit.name.slice(slash + 1);
      return `assets/${date.split("-").join("/")}/${filename}`;
    }
    case "recipe":
      return hit.target; // already the bare relpath, per search.py's _map_hit.
    default:
      return hit.name;
  }
}

/** Breadcrumb-style path segments for a hit's group header
 * (`mockups/search.html`: "assets › 2026 › 07 › 14"). Journal hits show the
 * full y/m/d split (the file itself has no per-day directory) rather than
 * just its two real directory components — cosmetic text only, not a link. */
export function hitCrumbSegments(hit: SearchHit): string[] {
  if (hit.type === "todo") return ["journal"];
  if (hit.type === "journal") {
    const [y, m, d] = hit.name.split("-");
    return ["journal", y, m, d];
  }
  return hitRelpath(hit).split("/").slice(0, -1);
}

/** `SearchHit.target` -> an `<a href>` this SPA's router can navigate.
 * todo/journal/asset targets are already shaped like SPA routes; only the
 * recipe target (a bare relpath) needs a leading slash. */
export function searchHitHref(hit: SearchHit): string {
  return hit.type === "recipe" ? `/${hit.target}` : hit.target;
}

export interface SearchGroup {
  relpath: string;
  crumbs: string[];
  hits: SearchHit[];
}

/** Groups consecutive hits that share the same source file. Safe to assume
 * "consecutive" because the backend (`search.sort_hits`) already orders hits
 * by type then lexically by name within a type, so a file's hits are always
 * contiguous in the input array. */
export function groupSearchHits(hits: SearchHit[]): SearchGroup[] {
  const groups: SearchGroup[] = [];
  for (const hit of hits) {
    const relpath = hitRelpath(hit);
    const last = groups[groups.length - 1];
    if (last && last.relpath === relpath) {
      last.hits.push(hit);
    } else {
      groups.push({ relpath, crumbs: hitCrumbSegments(hit), hits: [hit] });
    }
  }
  return groups;
}
