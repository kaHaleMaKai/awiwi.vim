<script lang="ts">
  // Single-file document view: dispatches on DocPayload.kind. Used for any
  // path that isn't a dedicated journal/todo route — recipe files, non-day
  // assets, arbitrary markdown under `/dir/...`-browsable directories.
  import { getDoc, ApiError, type DocPayload } from "../api";
  import { breadcrumbs, fallbackCrumbs, withCurrent } from "../breadcrumbs.svelte";
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
  const backHref = $derived(doc?.journal_date ? `/journal/${doc.journal_date}` : null);
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
  {#if backHref}
    <a
      class="link"
      href={backHref}
      style="font-size: var(--text-sm); display: block; margin-bottom: var(--space-3);"
    >
      &larr; Back to journal/{doc.journal_date}
    </a>
  {/if}

  {#if doc.kind === "text"}
    <TextFileView {doc} {path} />
  {:else if doc.kind === "image"}
    <ImageView {doc} {path} />
  {:else if doc.kind === "drawio"}
    <DrawioView {doc} {path} />
  {:else if doc.kind === "binary"}
    <DownloadCard {doc} {path} />
  {:else}
    <span class="deco-title">{doc.doc_type === "recipe" ? "Recipe" : "Document"}</span>
    <h1 class="page-title u-mt-2">{filename}</h1>
    <div class="deco-rule u-mt-4"></div>
    <div class="u-mt-6">
      <MarkdownView
        html={doc.html ?? ""}
        watchPath={doc.watch_path}
        onCheckboxStale={() => load(path)}
        onCheckboxSuccess={(mtimeNs) => {
          if (doc) doc.mtime_ns = mtimeNs;
        }}
      />
    </div>
  {/if}
{/if}
