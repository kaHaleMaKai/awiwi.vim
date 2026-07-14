<script lang="ts">
  // "/search" — grouped ripgrep results (mockups/search.html). The query box
  // itself lives in the header (SearchBar); this page only owns the scope
  // chips, regex toggle, and results. All three (q/mode/scope) live in the
  // URL (`lib/searchState.ts`) so the page is shareable/back-button-safe —
  // reloading or pasting the URL reproduces the exact same search.
  import { router } from "../router.svelte";
  import { search, ApiError, type SearchHit, type SearchScope } from "../api";
  import { breadcrumbs } from "../breadcrumbs.svelte";
  import {
    parseSearchUrl,
    searchPath,
    groupSearchHits,
    searchHitHref,
    type SearchUrlState,
  } from "../searchState";
  import { highlightMatch } from "../searchHighlight";

  const SCOPES: SearchScope[] = ["journal", "assets", "recipes"];

  // Re-parsed on every router.current reassignment — router.navigate()
  // always creates a fresh Route object, including for query-only
  // (replaceState) navigations that keep the same "/search" path, so this
  // derived value tracks chip/regex/typing updates too, not just full nav.
  const urlState = $derived<SearchUrlState>(parseSearchUrl(location.search));

  function pushState(next: Partial<SearchUrlState>): void {
    router.navigate(searchPath({ ...urlState, ...next }), { replace: true });
  }

  function toggleScope(scope: SearchScope): void {
    const scopes = urlState.scopes.includes(scope)
      ? urlState.scopes.filter((s) => s !== scope)
      : [...urlState.scopes, scope];
    pushState({ scopes });
  }

  function toggleMode(): void {
    pushState({ mode: urlState.mode === "regex" ? "fixed" : "regex" });
  }

  let hits = $state<SearchHit[]>([]);
  let loading = $state(false);
  let errorMsg = $state<string | null>(null);

  $effect(() => {
    breadcrumbs.set([
      { name: "awiwi", target: "/" },
      { name: "search", target: "/search" },
    ]);
  });

  $effect(() => {
    const q = urlState.q.trim();
    const mode = urlState.mode;
    const scope = urlState.scopes;
    if (!q) {
      hits = [];
      errorMsg = null;
      loading = false;
      return;
    }
    let cancelled = false;
    loading = true;
    errorMsg = null;
    search({ q, mode, scope: scope.length ? scope : undefined })
      .then((result) => {
        if (cancelled) return;
        hits = result;
      })
      .catch((err) => {
        if (cancelled) return;
        hits = [];
        errorMsg =
          err instanceof ApiError && typeof err.detail === "string"
            ? err.detail
            : "Search failed.";
      })
      .finally(() => {
        if (!cancelled) loading = false;
      });
    return () => {
      cancelled = true;
    };
  });

  const groups = $derived(groupSearchHits(hits));
</script>

<section class="stack">
  <div>
    <span class="deco-title">Search</span>
    <h1 class="page-title u-mt-2">
      {urlState.q.trim() ? `Results for “${urlState.q.trim()}”` : "Search"}
    </h1>
  </div>
  <div class="deco-rule"></div>

  <div class="search-toolbar">
    <div class="cluster">
      {#each SCOPES as scope (scope)}
        <button
          class="chip"
          class:is-active={urlState.scopes.includes(scope)}
          type="button"
          aria-pressed={urlState.scopes.includes(scope)}
          onclick={() => toggleScope(scope)}
        >
          {scope}
        </button>
      {/each}
    </div>
    <div class="u-flex-1"></div>
    <label class="regex-toggle">
      <span class="switch">
        <input
          type="checkbox"
          checked={urlState.mode === "regex"}
          onchange={toggleMode}
          aria-label="Use regex mode"
        />
        <span class="track"><span class="thumb"></span></span>
      </span>
      Regex
    </label>
  </div>

  {#if !urlState.q.trim()}
    <p class="u-muted">Type a query above to search every journal, asset, and recipe.</p>
  {:else if loading}
    <p class="u-muted">Searching…</p>
  {:else if errorMsg}
    <p class="u-muted">{errorMsg}</p>
  {:else if groups.length === 0}
    <p class="u-muted">No matches for “{urlState.q.trim()}”.</p>
  {:else}
    <div>
      {#each groups as group (group.relpath)}
        <div class="search-group">
          <div class="search-group-header">
            <span class="search-file"
              >{group.relpath}<span class="search-file-path"
                >{group.crumbs.join(" › ")}</span
              ></span
            >
            <span class="u-flex-1"></span>
            <span>{group.hits.length} match{group.hits.length === 1 ? "" : "es"}</span>
          </div>
          {#each group.hits as hit (`${hit.line}:${hit.col}`)}
            {@const seg = highlightMatch(hit.text, urlState.q, urlState.mode)}
            <a class="search-hit" href={searchHitHref(hit)}>
              <span class="hit-line">{hit.line}</span>
              <span class="hit-text">
                {#if seg}{seg.before}<mark class="hit-match">{seg.match}</mark
                  >{seg.after}{:else}{hit.text}{/if}
              </span>
            </a>
          {/each}
        </div>
      {/each}
    </div>
  {/if}
</section>
