<script lang="ts">
  // Directory listing: `/` (home root) and `/dir/*` (any nested directory —
  // journal year/month dirs, assets dirs, recipes dirs). Journal-month dirs
  // (all non-dir entries are `YYYY-MM-DD` day files) get the week-banded
  // layout from mockups/dir-journal-month.html; everything else is a plain
  // row list (mockups/dir-root.html), minus the mockup's fabricated
  // "no entry"/future placeholder rows and word-count summaries — the real
  // API only returns entries that exist on disk, with no size/summary
  // metadata, so those can't be reproduced.
  import { getDir, rawUrl, ApiError, type DirPayload, type DirEntry } from "../api";
  import { breadcrumbs, fallbackCrumbs } from "../breadcrumbs.svelte";
  import { bandByWeek, isJournalDayName } from "../weekBands";
  import { beautifyDate } from "../format";
  import EmptyState from "./EmptyState.svelte";

  interface Props {
    /** Home-relative directory path; "" for the root. */
    path: string;
  }
  const { path }: Props = $props();

  let dir = $state<DirPayload | null>(null);
  let notFound = $state(false);

  $effect(() => {
    const p = path;
    dir = null;
    notFound = false;
    breadcrumbs.reset();
    getDir(p)
      .then((payload) => {
        dir = payload;
        breadcrumbs.set(payload.breadcrumbs);
      })
      .catch((err) => {
        notFound = true;
        breadcrumbs.set(fallbackCrumbs(p));
        if (!(err instanceof ApiError)) console.error(err);
      });
  });

  const title = $derived(path ? (path.split("/").pop() ?? path) + "/" : "g:awiwi_home");
  const deco = $derived(path ? "Directory" : "Awiwi Home");

  const fileEntries = $derived(dir?.entries.filter((e) => !e.is_dir) ?? []);
  const dayEntries = $derived(fileEntries.filter((e) => isJournalDayName(e.name)));
  const isJournalMonth = $derived(dayEntries.length > 0 && dayEntries.length === fileEntries.length);
  const weeks = $derived(isJournalMonth ? bandByWeek(dayEntries) : []);

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
            <a class="row" href={entryHref(day)}>
              <span class="row-title">{@html beautifyDate(day.name)}</span>
            </a>
          {/each}
        </div>
      {/each}
    </div>
  {:else if dir.entries.length}
    <div class="card u-mt-6">
      {#each dir.entries as entry (entry.relpath)}
        <a class="row" href={entryHref(entry)}>
          <span class="row-title">{entry.name}{entry.is_dir ? "/" : ""}</span>
          <span class="row-meta">{entry.doc_type !== "other" ? entry.doc_type : ""}</span>
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
</style>
