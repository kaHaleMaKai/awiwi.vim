<script module lang="ts">
  // Lazy, singleton classic-script injection for the self-hosted drawio
  // viewer bundle (see public/vendor/drawio/README.md for the pinned
  // release + rationale). One <script> tag for the whole app lifetime,
  // regardless of how many DrawioView instances mount.
  let scriptPromise: Promise<void> | null = null;

  function loadDrawioScript(): Promise<void> {
    if (!scriptPromise) {
      scriptPromise = new Promise((resolve, reject) => {
        const el = document.createElement("script");
        el.src = `${import.meta.env.BASE_URL}vendor/drawio/viewer-static.min.js`;
        el.onload = () => resolve();
        el.onerror = () => reject(new Error("failed to load drawio viewer script"));
        document.head.appendChild(el);
      });
    }
    return scriptPromise;
  }

  declare global {
    interface Window {
      GraphViewer?: { processElements: () => void };
    }
  }
</script>

<script lang="ts">
  // kind === "drawio": render .drawio XML client-side via the self-hosted
  // mxgraph viewer. `lightbox: false` is deliberate (see vendor README) — the
  // default lightbox config surfaces an "Edit in draw.io" affordance that
  // leaks the diagram to https://app.diagrams.net; self-hosting is pointless
  // if that path stays open, so we drop it (and the "Open in draw.io" button
  // the mockup shows) rather than ship the leak.
  import { rawUrl, type DocPayload } from "../api";

  interface Props {
    doc: DocPayload;
    path: string;
  }
  const { doc, path }: Props = $props();

  const filename = $derived(path.split("/").pop() ?? path);

  let container: HTMLDivElement;
  let status = $state<"loading" | "ready" | "error">("loading");

  // The script only auto-processes `.mxgraph` elements present at its own
  // load time, once, per page load — every subsequent SPA navigation to a
  // (possibly different) .drawio doc needs its own manual
  // processElements() call, which is what this effect does on every `doc`
  // change (a fresh DocPayload object each load, so it re-fires per file).
  $effect(() => {
    const xml = doc.text ?? "";
    if (!container) return;
    status = "loading";
    let cancelled = false;
    loadDrawioScript()
      .then(() => {
        if (cancelled) return;
        container.innerHTML = "";
        const div = document.createElement("div");
        div.className = "mxgraph";
        div.setAttribute("data-mxgraph", JSON.stringify({ xml, lightbox: false }));
        container.appendChild(div);
        window.GraphViewer?.processElements();
        status = "ready";
      })
      .catch(() => {
        if (!cancelled) status = "error";
      });
    return () => {
      cancelled = true;
    };
  });
</script>

<div class="spread">
  <div>
    <span class="deco-title">Asset &middot; Diagram</span>
    <h1 class="page-title u-mt-2">{filename}</h1>
  </div>
  <a class="btn btn-primary" href={rawUrl(doc.watch_path, { download: true })}>Download .drawio</a>
</div>
<div class="deco-rule u-mt-4"></div>

{#if status === "loading"}
  <div class="mermaid-box u-mt-6"><span>Loading diagram&hellip;</span></div>
{:else if status === "error"}
  <div class="mermaid-box u-mt-6"><span>Couldn't load the diagram viewer.</span></div>
{/if}
<div class="u-mt-6" class:u-hidden={status !== "ready"} bind:this={container}></div>
