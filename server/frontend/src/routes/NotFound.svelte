<!-- Catch-all 404 route view — no route in the client's matcher table
  matched the URL at all (unmatched client-side path, not a failed fetch;
  see DirPage/DocPage/JournalPage for server-404 handling of matched
  routes whose payload doesn't exist). -->
<script lang="ts">
  import { onMount } from "svelte";
  import { breadcrumbs, fallbackCrumbs } from "../lib/breadcrumbs.svelte";
  import EmptyState from "../lib/components/EmptyState.svelte";

  onMount(() => {
    breadcrumbs.set(fallbackCrumbs(location.pathname.replace(/^\//, "")));
  });
</script>

<EmptyState
  glyph="404"
  message="This page doesn't exist, or was moved."
  actions={[
    { label: "Go to journal home", href: "/", primary: true },
    { label: "Search notes instead", href: "/search" },
  ]}
/>
