// Pure helpers for presentation mode: splitting a rendered `.markdown-body`
// element into per-h1 slides, and stepping/dimming the prev/next arrows.

/** Render a single top-level child node to HTML: `outerHTML` for elements,
 * raw text content for text/comment nodes. */
function nodeHtml(node: ChildNode): string {
  if (node.nodeType === Node.ELEMENT_NODE) {
    return (node as Element).outerHTML;
  }
  return node.textContent ?? "";
}

function isTopLevelH1(node: ChildNode): boolean {
  return node.nodeType === Node.ELEMENT_NODE && (node as Element).tagName === "H1";
}

/**
 * Split the top-level children of `root` into slides, starting a new slide
 * at each direct-child `<h1>`. An `<h1>` nested inside another top-level
 * element (blockquote, details, ...) is not a boundary — only direct
 * children of `root` are ever inspected.
 *
 * Content before the first h1 becomes slide 0 iff it is non-empty
 * (whitespace-only preamble produces no slide). Zero h1s means the whole
 * content is returned as a single slide.
 */
export function splitSlides(root: Element): string[] {
  const slides: string[] = [];
  let current: ChildNode[] = [];

  const flush = () => {
    if (current.length === 0) return;
    const html = current.map(nodeHtml).join("");
    const startsWithH1 = isTopLevelH1(current[0]);
    if (startsWithH1 || html.trim().length > 0) {
      slides.push(html);
    }
    current = [];
  };

  for (const node of Array.from(root.childNodes)) {
    if (isTopLevelH1(node)) {
      flush();
    }
    current.push(node);
  }
  flush();

  return slides;
}

/** New slide index after stepping in `dir`, clamped to [0, count-1] (no wrap). */
export function step(index: number, count: number, dir: 1 | -1): number {
  const next = index + dir;
  if (next < 0) return 0;
  if (next > count - 1) return count - 1;
  return next;
}

/** Opacity for the prev/next arrow: 0.5 if a slide exists in that direction,
 * 0.1 otherwise (at an edge, or when there is only one slide). */
export function arrowOpacity(index: number, count: number, dir: 1 | -1): number {
  const target = index + dir;
  return target >= 0 && target <= count - 1 ? 0.5 : 0.1;
}
