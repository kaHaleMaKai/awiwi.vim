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
    code.textContent = src;
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
  <div bind:this={container}></div>
</div>
