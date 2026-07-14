<script lang="ts">
  import type { BreadcrumbPayload } from "../api";

  interface Props {
    crumbs: BreadcrumbPayload[];
  }
  let { crumbs }: Props = $props();
</script>

<nav class="breadcrumbs" aria-label="Breadcrumb">
  {#each crumbs as crumb, i (crumb.target)}
    {#if i < crumbs.length - 1}
      <a href={crumb.target}>{crumb.name}</a>
      <span class="sep">&rsaquo;</span>
    {:else}
      <span class="current">{crumb.name}</span>
    {/if}
  {/each}
</nav>
