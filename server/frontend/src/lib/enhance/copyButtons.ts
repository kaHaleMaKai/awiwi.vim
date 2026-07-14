// Copy-to-clipboard buttons on `<pre>` code blocks.
//
// Wraps each code block in a `.awiwi-code-block` positioning context and adds a
// floating `.copy-btn` (reusing app.css's button styling). The button reads the
// block's current `textContent` at click time, so it works whether or not Shiki
// has already replaced the inner `<pre>`.

import { writeClipboard, flashCopied } from "./clipboard";

let styleInjected = false;
function injectCss(): void {
  if (styleInjected || typeof document === "undefined") return;
  styleInjected = true;
  const style = document.createElement("style");
  style.id = "awiwi-code-block";
  style.textContent = `
.awiwi-code-block { position: relative; }
.awiwi-code-block > pre, .awiwi-code-block > .shiki { margin: 0; }
.awiwi-code-block > .copy-btn-float { position: absolute; top: var(--space-2); right: var(--space-2); z-index: 2; }
`;
  document.head.appendChild(style);
}

/** Wrap `pre` in a `.awiwi-code-block` and add a floating copy button.
 * Returns a cleanup that removes the button's listener. The wrapper/button DOM
 * itself is discarded automatically when the container's HTML is re-rendered. */
export function addCopyButton(pre: HTMLElement): () => void {
  const parent = pre.parentElement;
  if (!parent) return () => {};
  injectCss();

  const wrapper = document.createElement("div");
  wrapper.className = "awiwi-code-block";
  parent.insertBefore(wrapper, pre);
  wrapper.appendChild(pre);

  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "copy-btn copy-btn-float";
  btn.textContent = "Copy";
  btn.setAttribute("aria-label", "Copy code");
  wrapper.appendChild(btn);

  const onClick = () => {
    const block = wrapper.querySelector("pre");
    const text = block?.textContent ?? "";
    void writeClipboard(text).then(() => flashCopied(btn));
  };
  btn.addEventListener("click", onClick);

  return () => btn.removeEventListener("click", onClick);
}
