// Inline-render `.drawio` links found in a rendered doc body (S31.2,
// feedback round 1: "if in a journal there is a link to a drawio diagram,
// show the link as a sub text" — interpreted as: render the diagram inline,
// self-hosted viewer, keeping the original link navigable as a caption
// beneath it).
//
// Mirrors media.ts's relative-href resolution (assets/ is already
// home-relative; anything else resolves against the doc's own directory).
// Reuses the same singleton viewer script as DrawioView.svelte (see
// ../drawioViewer.ts) — `lightbox: false` is the same deliberate
// self-hosting decision (never load app.diagrams.net), preserved here.
//
// Best-effort: any failure (resolve, fetch, or viewer-script load) leaves
// the original `<a>` untouched — no partial DOM mutation on the failure
// path. Idempotent: an anchor is marked via `data-drawio-inline` the moment
// processing starts, and already-inlined figures (and the caption anchor
// inside them) are excluded from future passes over the same container.
import { getDoc } from "../api";
import { loadDrawioViewer } from "../drawioViewer";
import { resolveRelpath } from "./paths";

/** Resolve an `<a href>` to the home-relative relpath `getDoc` expects, or
 * `null` when the href is absolute (or empty) and can't be a local doc. */
export const resolveDrawioPath = resolveRelpath;

async function renderOne(anchor: HTMLAnchorElement, watchPath: string): Promise<void> {
  anchor.dataset.drawioInline = "pending";
  try {
    const href = anchor.getAttribute("href") ?? "";
    const relpath = resolveDrawioPath(href, watchPath);
    if (!relpath) throw new Error("drawio link is not a resolvable local path");

    const doc = await getDoc(relpath);
    const xml = doc.text ?? "";
    await loadDrawioViewer();
    if (!anchor.isConnected) return;

    const caption = anchor.cloneNode(true) as HTMLAnchorElement;
    delete caption.dataset.drawioInline;

    const graph = document.createElement("div");
    graph.className = "mxgraph";
    graph.setAttribute("data-mxgraph", JSON.stringify({ xml, lightbox: false }));

    const figcaption = document.createElement("figcaption");
    figcaption.appendChild(caption);

    const figure = document.createElement("figure");
    figure.className = "drawio-inline";
    figure.appendChild(graph);
    figure.appendChild(figcaption);

    anchor.replaceWith(figure);
    window.GraphViewer?.processElements();
    figure.dataset.drawioInline = "done";
  } catch {
    // Graceful degradation: leave the original link in place, just mark it
    // so this container doesn't keep retrying it on every re-enhance.
    anchor.dataset.drawioInline = "error";
  }
}

/** Find `a[href$=".drawio"]` links in `container` not already processed (or
 * already-inlined) and render each inline as a `<figure class="drawio-inline">`
 * with the original link kept as a `<figcaption>`. Fire-and-forget per link;
 * returns a no-op cleanup (nothing to detach — the pass mutates the DOM once
 * and leaves no listeners of its own). */
export function enhanceDrawio(container: HTMLElement, watchPath: string): () => void {
  const anchors = Array.from(
    container.querySelectorAll<HTMLAnchorElement>('a[href$=".drawio"]'),
  ).filter((a) => a.dataset.drawioInline === undefined && !a.closest(".drawio-inline"));

  for (const anchor of anchors) {
    void renderOne(anchor, watchPath);
  }

  return () => {};
}
