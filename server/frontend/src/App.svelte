<script lang="ts">
  import { onMount } from "svelte";
  import { router } from "./lib/router.svelte";
  import type { BreadcrumbPayload } from "./lib/api";
  import Breadcrumbs from "./lib/components/Breadcrumbs.svelte";
  import SearchBar from "./lib/components/SearchBar.svelte";
  import ThemeToggle from "./lib/components/ThemeToggle.svelte";
  import ConnectionDot from "./lib/components/ConnectionDot.svelte";
  import Home from "./routes/Home.svelte";
  import Dir from "./routes/Dir.svelte";
  import Todo from "./routes/Todo.svelte";
  import Journal from "./routes/Journal.svelte";
  import Asset from "./routes/Asset.svelte";
  import Recipes from "./routes/Recipes.svelte";
  import Search from "./routes/Search.svelte";
  import NotFound from "./routes/NotFound.svelte";

  onMount(() => router.start());

  // Placeholder trail until S25.3 wires real DocPayload.breadcrumbs per
  // route view (each fetched doc carries its own `breadcrumbs` field).
  let crumbs = $derived<BreadcrumbPayload[]>([{ name: "awiwi", target: "/" }]);
</script>

<div class="app-shell">
  <header class="app-header">
    <a href="/" class="brand">AWIWI</a>
    <Breadcrumbs {crumbs} />
    <div class="spacer"></div>
    <SearchBar />
    <ConnectionDot />
    <ThemeToggle />
  </header>

  <main class="container-wide u-mt-6">
    {#if router.current.name === "home"}
      <Home />
    {:else if router.current.name === "dir"}
      <Dir rest={router.current.params.rest} />
    {:else if router.current.name === "todo"}
      <Todo />
    {:else if router.current.name === "journal"}
      <Journal date={router.current.params.date} />
    {:else if router.current.name === "asset"}
      <Asset date={router.current.params.date} file={router.current.params.file} />
    {:else if router.current.name === "recipes"}
      <Recipes rest={router.current.params.rest} />
    {:else if router.current.name === "search"}
      <Search />
    {:else}
      <NotFound />
    {/if}
  </main>
</div>
