<script lang="ts">
  // Single-file document view: dispatches on DocPayload.kind. Used for any
  // path that isn't a dedicated journal/todo route — recipe files, non-day
  // assets, arbitrary markdown under `/dir/...`-browsable directories.
  import { getDoc, ApiError, type DocPayload } from "../api";
  import { breadcrumbs, fallbackCrumbs, withCurrent } from "../breadcrumbs.svelte";
  import { useLiveDoc } from "../ws.svelte";
  import { watchToc } from "../enhance/tocSpy";
  import MarkdownView from "./MarkdownView.svelte";
  import TextFileView from "./TextFileView.svelte";
  import ImageView from "./ImageView.svelte";
  import DrawioView from "./DrawioView.svelte";
  import DownloadCard from "./DownloadCard.svelte";
  import EmptyState from "./EmptyState.svelte";

  interface Props {
    /** Home-relative file path, e.g. "recipes/bread/sourdough.md". */
    path: string;
  }
  const { path }: Props = $props();

  let doc = $state<DocPayload | null>(null);
  let notFound = $state(false);

  function load(p: string): void {
    doc = null;
    notFound = false;
    breadcrumbs.reset();
    getDoc(p)
      .then((payload) => {
        doc = payload;
        breadcrumbs.set(withCurrent(payload.breadcrumbs, p.split("/").pop() ?? p, `/${p}`));
      })
      .catch((err) => {
        notFound = true;
        breadcrumbs.set(fallbackCrumbs(p));
        if (!(err instanceof ApiError)) console.error(err);
      });
  }

  $effect(() => {
    load(path);
  });

  const filename = $derived(path.split("/").pop() ?? path);

  const watchPath = $derived(doc?.watch_path);
  const live = useLiveDoc(
    () => watchPath,
    {
      onDoc: (payload) => {
        doc = payload;
      },
      onDeleted: () => {
        doc = null;
        notFound = true;
      },
      refetch: () => load(path),
    },
  );

  let articleEl: HTMLElement | undefined = $state();
  let tocEl: HTMLElement | undefined = $state();
  $effect(() => {
    void doc?.toc;
    void doc?.html;
    if (!articleEl || !tocEl) return;
    return watchToc(articleEl, tocEl);
  });
</script>

{#if notFound}
  <EmptyState
    glyph="404"
    message={`${path} doesn't exist, or was moved.`}
    actions={[
      { label: "Go to journal home", href: "/", primary: true },
      { label: "Search notes instead", href: "/search" },
    ]}
  />
{:else if doc}
  {#if doc.kind === "text"}
    <TextFileView {doc} {path} />
  {:else if doc.kind === "image"}
    <ImageView {doc} {path} />
  {:else if doc.kind === "drawio"}
    <DrawioView {doc} {path} />
  {:else if doc.kind === "binary"}
    <DownloadCard {doc} {path} />
  {:else}
    <div class="layout-with-rail">
      <article class="stack" bind:this={articleEl}>
        <div>
          <span class="deco-title">{doc.doc_type === "recipe" ? "Recipe" : "Document"}</span>
          <h1 class="page-title u-mt-2">{filename}</h1>
        </div>
        <div class="deco-rule"></div>
        <MarkdownView
          html={doc.html ?? ""}
          watchPath={doc.watch_path}
          onCheckboxStale={() => load(path)}
          onCheckboxSuccess={(mtimeNs) => {
            if (doc) doc.mtime_ns = mtimeNs;
            live.ackMtime(mtimeNs);
          }}
        />
      </article>

      {#if doc.toc}
        <aside class="rail">
          <div class="rail-section">
            <div class="deco-title">On this page</div>
            <nav class="toc u-mt-2" bind:this={tocEl}>{@html doc.toc}</nav>
          </div>
        </aside>
      {/if}
    </div>
  {/if}
{/if}
