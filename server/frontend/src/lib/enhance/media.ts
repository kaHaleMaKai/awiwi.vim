// Rewrite relative image sources to `/api/raw/...` and open images in the
// lightbox on click.
//
// The server renders markdown `![alt](path)` to `<img src="path">` with the
// raw, unresolved path (mdrender doesn't rewrite links). This mirrors the old
// server's `resolve_image_link`: a `assets/…` path is already home-relative; any
// other relative path is resolved against the document's own directory. Absolute
// URLs (scheme, protocol-relative, or root-absolute like `/api/raw/…`) are left
// untouched.
import { rawUrl } from "../api";
import { openLightbox } from "./lightbox";

function isAbsolute(src: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith("//") || src.startsWith("/");
}

/** Collapse `.`/`..` segments in a POSIX-style relative path. */
function normalizePosix(path: string): string {
  const out: string[] = [];
  for (const seg of path.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") out.pop();
    else out.push(seg);
  }
  return out.join("/");
}

/** Resolve an `<img src>` to its `/api/raw/...` URL, or `null` when the src is
 * absolute and needs no rewrite. `watchPath` is the doc's home-relative path. */
export function resolveMediaSrc(src: string, watchPath: string): string | null {
  if (!src || isAbsolute(src)) return null;
  let relpath: string;
  if (src.startsWith("assets/")) {
    relpath = src;
  } else {
    const dir = watchPath.includes("/")
      ? watchPath.slice(0, watchPath.lastIndexOf("/"))
      : "";
    relpath = normalizePosix(dir ? `${dir}/${src}` : src);
  }
  return rawUrl(relpath);
}

/** Rewrite relative image srcs under `container` and wire click-to-lightbox.
 * Returns a cleanup that detaches the click listeners. */
export function rewriteMedia(container: HTMLElement, watchPath: string): () => void {
  const imgs = Array.from(container.querySelectorAll<HTMLImageElement>("img"));
  const removers: Array<() => void> = [];

  for (const img of imgs) {
    const original = img.getAttribute("src") ?? "";
    const resolved = resolveMediaSrc(original, watchPath);
    if (resolved) img.setAttribute("src", resolved);
    img.style.cursor = "zoom-in";

    const onClick = () => openLightbox(img.getAttribute("src") ?? "", img.alt);
    img.addEventListener("click", onClick);
    removers.push(() => img.removeEventListener("click", onClick));
  }

  return () => {
    for (const remove of removers) remove();
  };
}
