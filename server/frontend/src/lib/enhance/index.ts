// The enhance pipeline: post-render DOM passes over server-injected markdown
// HTML. `MarkdownView` calls `enhance(container)` after `{@html}` and holds the
// returned handle for its lifetime.
//
// Passes: Shiki highlighting + copy buttons on code blocks, table export
// CopyMenus, checkbox PATCH wiring, lazy theme-aware mermaid, inline image-link
// rendering, media rewrite + lightbox, inline drawio-link rendering, and
// redaction click-to-reveal.
// Everything is best-effort and
// tolerant of missing structure — a doc with no code/tables/checkboxes just
// gets fewer passes run.
import type { Theme } from "../theme.svelte";
import { highlightBlock } from "./shiki";
import { addCopyButton } from "./copyButtons";
import { enhanceTables } from "./tables";
import { wireCheckboxes } from "./checkbox";
import { renderMermaid } from "./mermaid";
import { inlineImageLinks } from "./imageLinks";
import { rewriteMedia } from "./media";
import { enhanceDrawio } from "./drawio";
import { wireRedaction } from "./redaction";

export interface EnhanceOptions {
  /** DocPayload.watch_path — relpath for checkbox PATCH + media resolution. */
  watchPath: string;
  /** Current app theme, used for the initial mermaid render. */
  theme: Theme;
  /** Called on a checkbox 409 (stale) so the page can refetch the doc. */
  onCheckboxStale?: () => void;
  /** Called with the new mtime_ns after a successful checkbox toggle. */
  onCheckboxSuccess?: (mtimeNs: number) => void;
}

export interface EnhanceHandle {
  /** Re-run theme-dependent passes (mermaid). Shiki switches via CSS, so it
   * needs no re-highlight. */
  setTheme(theme: Theme): void;
  /** Detach listeners and unmount injected components. Call before dropping
   * or re-rendering the container. */
  destroy(): void;
}

export function enhance(container: HTMLElement, opts: EnhanceOptions): EnhanceHandle {
  const cleanups: Array<() => void> = [];

  // Code blocks: wrap + copy button first, then highlight in place (async).
  const codeBlocks = Array.from(
    container.querySelectorAll<HTMLElement>("pre"),
  ).filter((pre) => pre.querySelector("code"));
  for (const pre of codeBlocks) {
    cleanups.push(addCopyButton(pre));
    void highlightBlock(pre);
  }

  cleanups.push(enhanceTables(container));
  cleanups.push(
    wireCheckboxes(container, {
      watchPath: opts.watchPath,
      onStale: opts.onCheckboxStale,
      onSuccess: opts.onCheckboxSuccess,
    }),
  );
  // Before rewriteMedia: converts image links to <img>, which rewriteMedia
  // then resolves to /api/raw/... and makes click-to-zoom.
  cleanups.push(inlineImageLinks(container, opts.watchPath));
  cleanups.push(rewriteMedia(container, opts.watchPath));
  cleanups.push(enhanceDrawio(container, opts.watchPath));
  cleanups.push(wireRedaction(container));

  void renderMermaid(container, opts.theme);

  let destroyed = false;
  return {
    setTheme(theme: Theme) {
      if (!destroyed) void renderMermaid(container, theme);
    },
    destroy() {
      if (destroyed) return;
      destroyed = true;
      for (const cleanup of cleanups) cleanup();
    },
  };
}
