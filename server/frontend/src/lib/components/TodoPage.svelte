<script lang="ts">
  // "/todo" — journal/todos.md rendered as plain markdown (the real API has
  // no structured overdue/today/upcoming grouping or due-date metadata the
  // mockup's todo.html shows; that's a `journal/todos.md` markdown-authoring
  // convention, not something the server computes). `toc` IS populated here
  // (same build_doc_payload as any doc) whenever the file has headings, so
  // this gets the same sticky TOC rail as JournalPage.
  import { getTodo, ApiError, type DocPayload } from "../api";
  import { breadcrumbs, fallbackCrumbs, withCurrent } from "../breadcrumbs.svelte";
  import MarkdownView from "./MarkdownView.svelte";
  import EmptyState from "./EmptyState.svelte";

  let doc = $state<DocPayload | null>(null);
  let notFound = $state(false);

  function load(): void {
    doc = null;
    notFound = false;
    breadcrumbs.reset();
    getTodo()
      .then((payload) => {
        doc = payload;
        breadcrumbs.set(withCurrent(payload.breadcrumbs, "todo", "/todo"));
      })
      .catch((err) => {
        notFound = true;
        breadcrumbs.set(fallbackCrumbs("journal/todos.md"));
        if (!(err instanceof ApiError)) console.error(err);
      });
  }

  $effect(() => {
    load();
  });
</script>

{#if notFound}
  <EmptyState glyph="404" message="No todo file found yet." />
{:else if doc}
  <div class="layout-with-rail">
    <article class="stack">
      <div>
        <span class="deco-title">Journal</span>
        <h1 class="page-title u-mt-2">Todos</h1>
      </div>
      <div class="deco-rule"></div>
      <MarkdownView
        html={doc.html ?? ""}
        watchPath={doc.watch_path}
        onCheckboxStale={load}
        onCheckboxSuccess={(mtimeNs) => {
          if (doc) doc.mtime_ns = mtimeNs;
        }}
      />
    </article>

    {#if doc.toc}
      <aside class="rail">
        <div class="rail-section">
          <div class="deco-title">On this page</div>
          <nav class="toc u-mt-2">{@html doc.toc}</nav>
        </div>
      </aside>
    {/if}
  </div>
{/if}
