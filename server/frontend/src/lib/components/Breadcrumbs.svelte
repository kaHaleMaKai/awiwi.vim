<script lang="ts">
  import type { BreadcrumbPayload } from "../api";

  interface Props {
    crumbs: BreadcrumbPayload[];
  }
  let { crumbs }: Props = $props();

  // Root/index page only: DirPage.svelte appends a "today" quick link after
  // the lone "home" crumb (S31.1) instead of an ancestor trail — render that
  // exact `[home, today]` pair with a "|" separator and both ends as real
  // links, rather than the usual "›"-separated trail whose last crumb is
  // plain (non-link) "current page" text.
  const isHomeQuickLink = $derived(
    crumbs.length === 2 && crumbs[0].name === "home" && crumbs[0].target === "/",
  );
</script>

<nav class="breadcrumbs" aria-label="Breadcrumb">
  {#if isHomeQuickLink}
    <a href={crumbs[0].target}>{crumbs[0].name}</a>
    <span class="sep">|</span>
    <a href={crumbs[1].target}>{crumbs[1].name}</a>
  {:else}
    {#each crumbs as crumb, i (crumb.target)}
      {#if i < crumbs.length - 1}
        <a href={crumb.target}>{crumb.name}</a>
        <span class="sep">&rsaquo;</span>
      {:else}
        <span class="current">{crumb.name}</span>
      {/if}
    {/each}
  {/if}
</nav>
