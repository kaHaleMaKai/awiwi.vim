// Attach a table export CopyMenu to every rendered <table>.
//
// The server emits a plain `<table>`; here we insert a small toolbar bar above
// each one (matching the mockup's `.spread` header) and mount a CopyMenu into
// it. Returns a cleanup that unmounts every menu and removes the inserted
// toolbars (the CopyMenu instances are external Svelte components, so they must
// be explicitly unmounted — the container's `{@html}` re-render only clears the
// DOM, not the component instances).
import { mount, unmount } from "svelte";
import CopyMenu from "../components/CopyMenu.svelte";

let styleInjected = false;
function injectCss(): void {
  if (styleInjected || typeof document === "undefined") return;
  styleInjected = true;
  const style = document.createElement("style");
  style.id = "awiwi-table-tools";
  style.textContent = `.table-tools { display: flex; justify-content: flex-end; margin-bottom: var(--space-2); }`;
  document.head.appendChild(style);
}

export function enhanceTables(container: HTMLElement): () => void {
  const tables = Array.from(container.querySelectorAll("table"));
  if (tables.length > 0) injectCss();
  const mounted: Array<{ instance: object; toolbar: HTMLElement }> = [];

  for (const table of tables) {
    const toolbar = document.createElement("div");
    toolbar.className = "table-tools";
    table.parentElement?.insertBefore(toolbar, table);
    const instance = mount(CopyMenu, {
      target: toolbar,
      props: { table: table as HTMLTableElement },
    });
    mounted.push({ instance, toolbar });
  }

  return () => {
    for (const { instance, toolbar } of mounted) {
      void unmount(instance);
      toolbar.remove();
    }
  };
}
