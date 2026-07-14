<script lang="ts">
  // Table export menu (Markdown / CSV / HTML), mounted per-table by the
  // enhance pipeline. Behaviour per T22 feedback round 1 item 3: picking a
  // format serializes the adjacent table, writes it to the clipboard, closes
  // the menu, and flashes "Copied ✓". Click-outside closes without copying.
  import { serializeTable, type TableFormat } from "../enhance/tableExport";
  import { writeClipboard } from "../enhance/clipboard";

  interface Props {
    table: HTMLTableElement;
  }
  const { table }: Props = $props();

  let open = $state(false);
  let label = $state("Copy ▾");
  let root: HTMLDivElement;
  let flashTimer: ReturnType<typeof setTimeout> | undefined;

  const FORMATS: { key: TableFormat; text: string }[] = [
    { key: "markdown", text: "as Markdown" },
    { key: "csv", text: "as CSV" },
    { key: "html", text: "as HTML" },
  ];

  function pick(format: TableFormat) {
    void writeClipboard(serializeTable(table, format));
    open = false;
    label = "Copied ✓";
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => {
      label = "Copy ▾";
    }, 1400);
  }

  // Close on outside click only while open (listener is torn down on unmount).
  $effect(() => {
    if (!open) return;
    const onDocClick = (e: MouseEvent) => {
      if (!root.contains(e.target as Node)) open = false;
    };
    document.addEventListener("click", onDocClick);
    return () => document.removeEventListener("click", onDocClick);
  });

  $effect(() => () => clearTimeout(flashTimer));
</script>

<div class="copy-menu" bind:this={root}>
  <button
    class="copy-btn"
    class:is-copied={label === "Copied ✓"}
    type="button"
    aria-haspopup="true"
    aria-expanded={open}
    onclick={() => (open = !open)}
  >
    {label}
  </button>
  {#if open}
    <div class="copy-menu-list" role="menu">
      {#each FORMATS as fmt (fmt.key)}
        <button type="button" role="menuitem" onclick={() => pick(fmt.key)}>
          {fmt.text}
        </button>
      {/each}
    </div>
  {/if}
</div>
