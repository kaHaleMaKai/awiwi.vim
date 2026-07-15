<script lang="ts">
  // Directory listing: `/` (home root) and `/dir/*` (any nested directory —
  // journal year/month dirs, assets dirs, recipes dirs). Journal-month dirs
  // (all non-dir entries are `YYYY-MM-DD` day files) get the week-banded
  // layout from mockups/dir-journal-month.html; everything else is a plain
  // row list (mockups/dir-root.html), minus the mockup's fabricated
  // "no entry"/future placeholder rows and word-count summaries — the real
  // API only returns entries that exist on disk, with no size/summary
  // metadata, so those can't be reproduced.
  import { getDir, getMeta, rawUrl, ApiError, type DirPayload, type DirEntry } from "../api";
  import { breadcrumbs, fallbackCrumbs } from "../breadcrumbs.svelte";
  import { bandByWeek, isJournalDayName } from "../weekBands";
  import { shortDayDate, monthTitle } from "../format";
  import EmptyState from "./EmptyState.svelte";

  // Root-only row order/icons/descriptions (mockups/dir-root.html) — the
  // fixed home subtrees in their documented display order, not the
  // backend's (alphabetical) entry order. Anything else falls back to its
  // name/no description.
  const ROOT_ORDER = ["journal", "assets", "recipes"];
  const ROOT_ICON: Record<string, string> = {
    journal:
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="4" width="18" height="17" rx="2"/><path d="M3 9h18M8 3v3M16 3v3"/></svg>',
    assets:
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 7a2 2 0 0 1 2-2h3l1.5-2h5L16 5h3a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><circle cx="12" cy="13" r="3.5"/></svg>',
    recipes:
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M4 19.5V6a2 2 0 0 1 2-2h8.5L20 8.5V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2.5Z"/><path d="M14 4v4.5H18.5"/></svg>',
  };
  // Static per-doc-type blurb (mockups/dir-root.html's row-meta text). The
  // mockup's journal row also shows a "· 2019–2026" year range, but that's
  // derived from real journal contents the backend doesn't expose (no
  // earliest/latest-entry field on DirPayload) -- omitted as a data-gap.
  const ROOT_DESC: Record<string, string> = {
    journal: "daily journals",
    assets: "images, text files, drawio diagrams",
    recipes: "nested how-tos, linkable from any note",
  };

  interface Props {
    /** Home-relative directory path; "" for the root. */
    path: string;
  }
  const { path }: Props = $props();

  let dir = $state<DirPayload | null>(null);
  let notFound = $state(false);
  // Server's notion of "today" (date.today() in the app's own tz), used only
  // to highlight the current day's row in a journal-month listing — fetched
  // once, independent of which directory is being viewed.
  let today = $state<string | null>(null);
  getMeta()
    .then((meta) => {
      today = meta.today;
    })
    .catch(() => {});

  $effect(() => {
    const p = path;
    dir = null;
    notFound = false;
    breadcrumbs.reset();
    getDir(p)
      .then((payload) => {
        dir = payload;
        // Root dir has no ancestors (backend returns `[]`) — mockups/dir-root.html
        // shows a single "home" crumb rather than nothing.
        breadcrumbs.set(
          payload.breadcrumbs.length ? payload.breadcrumbs : [{ name: "home", target: "/" }],
        );
      })
      .catch((err) => {
        notFound = true;
        breadcrumbs.set(fallbackCrumbs(p));
        if (!(err instanceof ApiError)) console.error(err);
      });
  });

  // journal/YYYY/MM dirs get their own eyebrow/title (mockups/dir-journal-month.html:
  // "Journal" / "July 2026") instead of the generic "Directory" / "MM/".
  const journalMonthMatch = $derived(/^journal\/(\d{4})\/(\d{2})$/.exec(path));
  const title = $derived(
    journalMonthMatch
      ? monthTitle(journalMonthMatch[1], journalMonthMatch[2])
      : path
        ? (path.split("/").pop() ?? path) + "/"
        : "g:awiwi_home",
  );
  const deco = $derived(journalMonthMatch ? "Journal" : path ? "Directory" : "Awiwi Home");

  const fileEntries = $derived(dir?.entries.filter((e) => !e.is_dir) ?? []);
  const dayEntries = $derived(fileEntries.filter((e) => isJournalDayName(e.name)));
  const isJournalMonth = $derived(dayEntries.length > 0 && dayEntries.length === fileEntries.length);
  const weeks = $derived(isJournalMonth ? bandByWeek(dayEntries) : []);

  const isRoot = $derived(!path);
  // Root listing order/icons follow mockups/dir-root.html (journal, assets,
  // recipes) rather than the backend's alphabetical entry order.
  const rootEntries = $derived(
    isRoot
      ? [...(dir?.entries ?? [])].sort(
          (a, b) => ROOT_ORDER.indexOf(a.name) - ROOT_ORDER.indexOf(b.name),
        )
      : [],
  );

  function entryHref(e: DirEntry): string {
    if (e.is_dir) return `/dir/${e.relpath}`;
    switch (e.doc_type) {
      case "journal":
        return e.relpath === "journal/todos.md" ? "/todo" : `/journal/${e.name}`;
      case "asset": {
        // Fixed hierarchy: assets/{year}/{month}/{day}/{name} — always 4
        // segments deep from home.
        const parts = e.relpath.split("/");
        return `/assets/${parts.slice(1, 4).join("-")}/${parts[4]}`;
      }
      case "recipe":
        return `/recipes/${e.relpath.replace(/^recipes\//, "")}`;
      default:
        return rawUrl(e.relpath);
    }
  }
</script>

{#if notFound}
  <EmptyState
    glyph="404"
    message={`/${path} doesn't exist, or was moved.`}
    actions={[
      { label: "Go to journal home", href: "/", primary: true },
      { label: "Search notes instead", href: "/search" },
    ]}
  />
{:else if dir}
  <span class="deco-title">{deco}</span>
  <h1 class="page-title u-mt-2">{title}</h1>
  <div class="deco-rule u-mt-4"></div>

  {#if isJournalMonth}
    <div class="u-mt-5 stack">
      {#each weeks as week (week.label)}
        <div class="week-band">
          <div class="week-label">{week.label}</div>
          {#each week.days as day (day.relpath)}
            <a class="row" class:is-current={day.name === today} href={entryHref(day)}>
              <span class="row-title">{shortDayDate(day.name)}</span>
            </a>
          {/each}
        </div>
      {/each}
    </div>
  {:else if dir.entries.length}
    <div class="card u-mt-6">
      {#each (isRoot ? rootEntries : dir.entries) as entry (entry.relpath)}
        <a class="row" href={entryHref(entry)}>
          <span class="cluster">
            {#if isRoot && ROOT_ICON[entry.name]}
              <span class="dir-icon" aria-hidden="true">{@html ROOT_ICON[entry.name]}</span>
            {/if}
            <span class="row-title">{entry.name}{entry.is_dir ? "/" : ""}</span>
          </span>
          <span class="row-meta">
            {isRoot ? (ROOT_DESC[entry.name] ?? "") : entry.doc_type !== "other" ? entry.doc_type : ""}
          </span>
        </a>
      {/each}
    </div>
  {:else}
    <p class="u-muted u-mt-6">Empty directory.</p>
  {/if}
{/if}

<style>
  /* Not in app.css: this one small label needs its own home. */
  .week-label {
    padding: var(--space-2) var(--space-2) 0;
    font-size: var(--text-xs);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--text-muted);
  }
  /* Root row icons (mockups/dir-root.html) — mockup-only, not in tokens.css. */
  .dir-icon {
    display: inline-flex;
    color: var(--accent-brass);
    flex: none;
  }
  /* mockups/dir-journal-month.html's .day-row.is-current is plain cyan text
     with no background/border (its .day-row has no border at all). Our
     shared .row always carries border-bottom + .is-current's bg tint
     (app.css), which reads as a "boxed" highlight here — drop the tint in
     this one context to match the mockup's plainer look. */
  .week-band .row.is-current {
    background: none;
  }
</style>
