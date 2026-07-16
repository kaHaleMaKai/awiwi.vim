// Turn a plain markdown link whose target is an image (`[caption](x.png)`,
// rendered by the server as `<a href="x.png">caption</a>`) into an inline
// `<img>`. Runs BEFORE `rewriteMedia`, which then rewrites the src to
// `/api/raw/...` and wires click-to-lightbox — so URL resolution and zoom are
// reused rather than reimplemented here.
import { resolveRelpath } from "./paths";

const IMAGE_EXT = /\.(png|jpe?g|gif|svg|webp|avif|bmp|ico)$/i;

/** Replace every `<a>` pointing at a local image with an `<img>` (src = the
 * home-relative relpath, alt = the link text). Skips absolute hrefs, non-image
 * targets, and anchors that already wrap an `<img>` (thumbnail links — left to
 * `rewriteMedia`). Returns a no-op cleanup (one-shot DOM mutation, no listeners). */
export function inlineImageLinks(container: HTMLElement, watchPath: string): () => void {
  for (const anchor of container.querySelectorAll("a[href]")) {
    if (anchor.querySelector("img")) continue;
    const relpath = resolveRelpath(anchor.getAttribute("href") ?? "", watchPath);
    // ponytail: naive ?/# strip before the ext check; upgrade to URL parsing
    // only if a real path legitimately contains one.
    if (relpath === null || !IMAGE_EXT.test(relpath.replace(/[?#].*$/, ""))) continue;

    const img = document.createElement("img");
    img.setAttribute("src", relpath);
    img.setAttribute("alt", anchor.textContent ?? "");
    anchor.replaceWith(img);
  }
  return () => {};
}
