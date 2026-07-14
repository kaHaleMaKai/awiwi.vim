<script lang="ts">
  // Stub: navigates to /search?q=... on submit. The search route view
  // itself (reading the querystring, rendering hits) is S25.3's job.
  import { router } from "../router.svelte";

  let value = $state("");

  function onSubmit(e: SubmitEvent): void {
    e.preventDefault();
    const q = value.trim();
    if (q) router.navigate(`/search?q=${encodeURIComponent(q)}`);
  }
</script>

<form class="header-search" onsubmit={onSubmit}>
  <input
    class="input"
    type="search"
    placeholder="Search notes… ( / )"
    aria-label="Search all notes"
    bind:value
  />
</form>
