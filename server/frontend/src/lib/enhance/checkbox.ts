// Wire the checkboxes the server renders into `PATCH /api/checkbox` calls.
//
// The server emits (mdrender.py):
//   <input type="checkbox" [checked] data-line-nr="N" class="awiwi-checkbox"
//          data-hash="MD5"> <label for="checkbox-line-N"><span>TEXT</span></label>
//
// On toggle we PATCH the new state using the frozen relpath protocol
// (T23.2-api-routes.md). The done-styling (strikethrough) follows the
// checkbox's *current* state (T22 feedback item 6). On 409 (stale hash / the
// file changed underneath us) we revert the checkbox and ask the page to
// refetch via `onStale`.
import { patchCheckbox, ApiError } from "../api";

export interface CheckboxOptions {
  /** DocPayload.watch_path — the home-relative relpath the PATCH addresses. */
  watchPath: string;
  /** Called when a 409 means the client is stale and should refetch the doc. */
  onStale?: () => void;
  /** Called with the new mtime_ns after a successful toggle (WS dedupe). */
  onSuccess?: (mtimeNs: number) => void;
}

let styleInjected = false;
function injectDoneStyleCss(): void {
  if (styleInjected || typeof document === "undefined") return;
  styleInjected = true;
  const style = document.createElement("style");
  style.id = "awiwi-checkbox-done";
  style.textContent = `.awiwi-checkbox-done { text-decoration: line-through; color: var(--text-muted); }`;
  document.head.appendChild(style);
}

function labelFor(input: HTMLInputElement): HTMLElement | null {
  if (input.id) {
    const byFor = document.querySelector<HTMLElement>(`label[for="${input.id}"]`);
    if (byFor) return byFor;
  }
  const next = input.nextElementSibling;
  return next instanceof HTMLElement && next.tagName === "LABEL" ? next : null;
}

function setDone(input: HTMLInputElement, done: boolean): void {
  labelFor(input)?.classList.toggle("awiwi-checkbox-done", done);
}

export function wireCheckboxes(
  container: HTMLElement,
  opts: CheckboxOptions,
): () => void {
  injectDoneStyleCss();
  const inputs = Array.from(
    container.querySelectorAll<HTMLInputElement>("input.awiwi-checkbox"),
  );
  const removers: Array<() => void> = [];

  for (const input of inputs) {
    setDone(input, input.checked);

    const onChange = async () => {
      const checked = input.checked;
      const lineNo = Number(input.dataset.lineNr);
      const lineHash = input.dataset.hash ?? "";
      input.disabled = true;
      setDone(input, checked);
      try {
        const res = await patchCheckbox({
          path: opts.watchPath,
          line_no: lineNo,
          line_hash: lineHash,
          checked,
        });
        opts.onSuccess?.(res.mtime_ns);
      } catch (err) {
        // Revert to the pre-toggle state on any failure; a 409 additionally
        // signals the doc is stale, so trigger a refetch.
        input.checked = !checked;
        setDone(input, !checked);
        if (err instanceof ApiError && err.status === 409) {
          opts.onStale?.();
        }
      } finally {
        input.disabled = false;
      }
    };

    input.addEventListener("change", onChange);
    removers.push(() => input.removeEventListener("change", onChange));
  }

  return () => {
    for (const remove of removers) remove();
  };
}
