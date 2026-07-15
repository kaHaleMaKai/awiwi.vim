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
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      aria-hidden="true"
      ><path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7" /></svg
    >
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
</figure>

<div class="card u-mt-6">
  <span class="u-muted" style="font-size: var(--text-xs); letter-spacing:.06em; text-transform:uppercase;">
    File info
  </span>
  <div
    class="u-mt-3"
    style="display:grid; grid-template-columns: 140px 1fr; row-gap: var(--space-2); font-size: var(--text-sm);"
  >
    <span class="u-muted">Path</span><span class="u-mono">{doc.watch_path}</span>
    {#if dims}
      <span class="u-muted">Dimensions</span><span>{dims}</span>
    {/if}
  </div>
</div>

<style>
  .image-frame {
    display: block;
    width: 100%;
    /* mockups/asset-image.html's .placeholder-art caps at 640px; matching
       that keeps the frame from stretching to the real image's full
       intrinsic width (which, via the .container-wide grid item's
       fit-content sizing, was pulling the whole page wider than the
       title/rule above it). */
    max-width: 640px;
    padding: 0;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-noir);
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
