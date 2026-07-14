<script lang="ts">
  // kind === "image": inline preview + fullscreen via the shared S25.2
  // Lightbox singleton (openLightbox), not the mockup's CSS-only lightbox
  // pattern — the Svelte one already exists and is reused by MarkdownView's
  // inline images too.
  import { rawUrl, type DocPayload } from "../api";
  import { openLightbox } from "../enhance/lightbox";

  interface Props {
    doc: DocPayload;
    path: string;
  }
  const { doc, path }: Props = $props();

  const filename = $derived(path.split("/").pop() ?? path);
  const src = $derived(rawUrl(doc.watch_path));

  let dims = $state<string | null>(null);
  function onImgLoad(e: Event): void {
    const img = e.currentTarget as HTMLImageElement;
    dims = `${img.naturalWidth} × ${img.naturalHeight}`;
  }
</script>

<div class="spread">
  <div>
    <span class="deco-title">Asset &middot; Image</span>
    <h1 class="page-title u-mt-2">{filename}</h1>
  </div>
  <button class="btn btn-primary" type="button" onclick={() => openLightbox(src, filename)}>
    View fullscreen
  </button>
</div>
<div class="deco-rule u-mt-4"></div>

<figure class="u-mt-6">
  <button
    type="button"
    class="image-frame"
    onclick={() => openLightbox(src, filename)}
    aria-label={`View ${filename} fullscreen`}
  >
    <img {src} alt={filename} onload={onImgLoad} />
  </button>
  {#if dims}
    <figcaption class="u-muted u-mt-3" style="font-size: var(--text-sm);">{dims}</figcaption>
  {/if}
</figure>

<style>
  .image-frame {
    display: block;
    width: 100%;
    padding: 0;
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-md);
    background: var(--bg-sunken);
    cursor: zoom-in;
  }
  .image-frame img {
    display: block;
    max-width: 100%;
    max-height: 70vh;
    margin: 0 auto;
  }
</style>
