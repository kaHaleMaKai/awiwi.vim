<script lang="ts">
  // kind === "text": whole-file Shiki highlight (reusing the S25.2 shiki
  // module directly, same as MarkdownView's code blocks) + copy button.
  // Files over 500KB skip highlighting (Key risks: don't hang the tab
  // highlighting a huge file) but still get a plain, escaped <pre> and copy
  // button — addCopyButton works on either.
  import type { DocPayload } from "../api";
  import { highlightBlock } from "../enhance/shiki";
  import { addCopyButton } from "../enhance/copyButtons";
  import { guessLanguage } from "../lang";

  interface Props {
    doc: DocPayload;
    path: string;
  }
  const { doc, path }: Props = $props();

  const MAX_HIGHLIGHT_BYTES = 500 * 1024;

  const text = $derived(doc.text ?? "");
  const lang = $derived(doc.language ?? guessLanguage(path, text) ?? "text");
  const lineCount = $derived(text.length ? text.split("\n").length : 0);
  const tooBig = $derived(new Blob([text]).size > MAX_HIGHLIGHT_BYTES);

  let container: HTMLElement;

  $effect(() => {
    const src = text;
    const codeLang = lang;
    const skip = tooBig;
    if (!container) return;
    container.replaceChildren();
    const pre = document.createElement("pre");
    const code = document.createElement("code");
    code.className = `language-${codeLang}`;
    if (skip) {
      // Too big to Shiki-highlight, but still numbered per line (mockups/
      // asset-text.html) — build the same `.line`-per-row shape Shiki's own
      // output uses, so the CSS-counter gutter below works either way.
      const lines = src.split("\n");
      lines.forEach((line, i) => {
        const span = document.createElement("span");
        span.className = "line";
        span.textContent = line;
        code.appendChild(span);
        if (i < lines.length - 1) code.appendChild(document.createTextNode("\n"));
      });
    } else {
      code.textContent = src;
    }
    pre.appendChild(code);
    container.appendChild(pre);
    const cleanup = addCopyButton(pre);
    if (!skip) void highlightBlock(pre);
    return cleanup;
  });
</script>

<span class="deco-title">Asset &middot; Text file</span>
<h1 class="page-title u-mt-2">{path.split("/").pop()}</h1>
<div class="deco-rule u-mt-4"></div>

<div class="code-block u-mt-6">
  <div class="code-toolbar">
    <span
      >{doc.watch_path} &middot; {lineCount} lines{tooBig
        ? " · too large to highlight"
        : lang !== "text"
          ? ` · ${lang}`
          : ""}</span
    >
  </div>
  <div class="code-block-file" bind:this={container}></div>
</div>

<!-- mockups/asset-text.html's file-info card: no "File info" eyebrow (unlike
     asset-image.html's), just the Path row -- Size/Linked-from stay
     data-gap-excluded (not in DocPayload). -->
<div class="card u-mt-6">
  <div
    class="u-mt-1"
    style="display:grid; grid-template-columns: 140px 1fr; row-gap: var(--space-2); font-size: var(--text-sm);"
  >
    <span class="u-muted">Path</span><span class="u-mono">{doc.watch_path}</span>
  </div>
</div>

<style>
  /* Line-number gutter (mockups/asset-text.html's `.file-pre`/`.file-line`),
     re-keyed off Shiki's own `.line` class so it works for both the
     highlighted and too-big-to-highlight (plain `.line` spans above) paths.
     Scoped to this file view only -- MarkdownView's embedded code fences
     don't get line numbers. */
  .code-block-file :global(pre) {
    counter-reset: line;
  }
  .code-block-file :global(.line) {
    /* NB: no `display: block` here -- Shiki's real output (and our own
       too-big-fallback markup above) already separates `.line` spans with a
       literal newline text node; adding block display would double every
       line break. */
    counter-increment: line;
  }
  .code-block-file :global(.line)::before {
    content: counter(line);
    display: inline-block;
    width: 3em;
    margin-right: var(--space-4);
    text-align: right;
    color: var(--text-muted);
    user-select: none;
  }

  /* This view already sits inside its own `.code-block`/`.code-toolbar` box
     (mockups/asset-text.html); copyButtons.ts's `.awiwi-code-block` wrapper
     would otherwise add a second, redundant border/padding around the
     Shiki output here (see enhance/shiki.ts) -- strip it back out. */
  .code-block-file :global(.shiki) {
    border: none;
    border-radius: 0;
    padding: 0;
  }
</style>
