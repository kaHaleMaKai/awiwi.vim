<!-- Route view "/recipes/*". Per the backend's breadcrumb contract
  (make_breadcrumbs always targets `/dir/...` for directories — see
  server.old's own `/recipes/<path>` route, which only ever rendered a
  content *file*), a recipe directory is browsed via `/dir/recipes/...`;
  `/recipes/*` itself is always a single recipe file, except the bare
  "/recipes" root (empty `rest`), which has no file to show and falls back
  to a directory listing. -->
<script lang="ts">
  import DirPage from "../lib/components/DirPage.svelte";
  import DocPage from "../lib/components/DocPage.svelte";
  interface Props {
    rest: string;
  }
  let { rest }: Props = $props();
</script>

{#if rest}
  <DocPage path={`recipes/${rest}`} />
{:else}
  <DirPage path="recipes" />
{/if}
