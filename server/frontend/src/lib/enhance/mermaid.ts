// Lazy, theme-aware mermaid rendering.
//
// The server emits `<div class="mermaid">SOURCE</div>` (mdrender.py). We stash
// the original source in `data-mermaid-src` before the first render so a theme
// flip can re-run mermaid from the pristine source (mermaid replaces the div's
// content with an <svg>, which can't be re-parsed). Mermaid itself is
// dynamically imported on the first block only.
import type { Theme } from "../theme.svelte";

type MermaidModule = typeof import("mermaid").default;

let mermaidPromise: Promise<MermaidModule> | null = null;

async function getMermaid(): Promise<MermaidModule> {
  if (!mermaidPromise) {
    mermaidPromise = import("mermaid").then((m) => m.default);
  }
  return mermaidPromise;
}

function themeName(theme: Theme): "dark" | "default" {
  return theme === "dark" ? "dark" : "default";
}

/** Render (or re-render) every `.mermaid` block in `container` for `theme`.
 * Safe to call repeatedly: each call resets blocks to their stashed source and
 * re-runs with the requested theme. No-op (and no mermaid import) if there are
 * no mermaid blocks. */
export async function renderMermaid(
  container: HTMLElement,
  theme: Theme,
): Promise<void> {
  const blocks = Array.from(
    container.querySelectorAll<HTMLElement>("div.mermaid"),
  );
  if (blocks.length === 0) return;

  for (const el of blocks) {
    // Stash the pristine source once; restore it on every (re-)render.
    if (el.dataset.mermaidSrc === undefined) {
      el.dataset.mermaidSrc = el.textContent ?? "";
    }
    el.textContent = el.dataset.mermaidSrc;
    el.removeAttribute("data-processed");
  }

  const mermaid = await getMermaid();
  if (!container.isConnected) return;
  mermaid.initialize({ startOnLoad: false, theme: themeName(theme) });
  await mermaid.run({ nodes: blocks });
}
