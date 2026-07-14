// Small clipboard helpers shared by the code-block copy button and the table
// copy menu. Ported from the T22 mockup behavior: the write is best-effort
// (some contexts deny clipboard access) and the "Copied ✓" flash still fires.

const FLASH_MS = 1400;

/** Best-effort clipboard write; never rejects. */
export function writeClipboard(text: string): Promise<void> {
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    return navigator.clipboard.writeText(text).catch(() => {});
  }
  return Promise.resolve();
}

/** Flash a transient "Copied ✓" label on `btn`, then restore its text.
 * The original label is stashed so repeated clicks don't compound. */
export function flashCopied(btn: HTMLElement, label = "Copied ✓"): void {
  const original = btn.dataset.originalLabel ?? btn.textContent ?? "";
  btn.dataset.originalLabel = original;
  btn.textContent = label;
  btn.classList.add("is-copied");
  window.setTimeout(() => {
    btn.textContent = btn.dataset.originalLabel ?? original;
    btn.classList.remove("is-copied");
  }, FLASH_MS);
}
