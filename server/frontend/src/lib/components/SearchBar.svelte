<script lang="ts">
  // Header search box. Off the "/search" route: plain navigate-on-submit
  // (Enter). On "/search": also live-updates the URL (debounced) as the user
  // types, so it doubles as the results page's own query input — the
  // mockups never show a second input in the results view, only this one.
  import { router } from "../router.svelte";
  import { parseSearchUrl, searchPath, type SearchUrlState } from "../searchState";

  const DEBOUNCE_MS = 300;

  let value = $state("");
  let debounceTimer: ReturnType<typeof setTimeout> | undefined;

  const onSearchRoute = $derived(router.current.name === "search");
  // Re-derives on every router.current reassignment (incl. query-only
  // navigations — router.navigate() always creates a fresh Route object).
  const urlState = $derived<SearchUrlState>(
    onSearchRoute ? parseSearchUrl(location.search) : { q: "", mode: "fixed", scopes: [] },
  );

  // Keep the box in sync with the URL (arriving via a link, back/forward,
  // or leaving "/search" entirely) without fighting the user's own typing —
  // only resync when the URL's q actually differs from what's shown.
  $effect(() => {
    const q = urlState.q;
    if (q !== value) value = q;
  });

  function navigateWithQuery(q: string, opts: { replace?: boolean } = {}): void {
    const base = onSearchRoute ? urlState : { q: "", mode: "fixed" as const, scopes: [] };
    router.navigate(searchPath({ ...base, q }), opts);
  }

  function onInput(e: Event): void {
    value = (e.target as HTMLInputElement).value;
    if (!onSearchRoute) return; // live-update only while already on /search
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => navigateWithQuery(value, { replace: true }), DEBOUNCE_MS);
  }

  function onSubmit(e: SubmitEvent): void {
    e.preventDefault();
    clearTimeout(debounceTimer);
    const q = value.trim();
    if (q) navigateWithQuery(q, { replace: onSearchRoute });
  }
</script>

<form class="header-search" onsubmit={onSubmit}>
  <input
    class="input"
    type="search"
    placeholder="Search notes… ( / )"
    aria-label="Search all notes"
    {value}
    oninput={onInput}
  />
</form>
