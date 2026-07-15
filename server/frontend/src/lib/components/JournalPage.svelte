<script lang="ts">
  // "/journal/:date" — day entry: TOC sticky rail (T22 item 7: zero-drift
  // `.layout-with-rail`/`.rail`, already in app.css), prev/next day-nav from
  // the payload's `nav`, MarkdownView + enhance for the body.
  import { getJournal, ApiError, type DocPayload } from "../api";
  import { breadcrumbs, fallbackCrumbs, withCurrent } from "../breadcrumbs.svelte";
  import { journalTitle, shortDayDate, dayOfMonth } from "../format";
  import { useLiveDoc } from "../ws.svelte";
  import { watchToc } from "../enhance/tocSpy";
  import MarkdownView from "./MarkdownView.svelte";
  import EmptyState from "./EmptyState.svelte";

  interface Props {
    date: string;
  }
  const { date }: Props = $props();

  let doc = $state<DocPayload | null>(null);
  let notFound = $state(false);

  function load(d: string): void {
    doc = null;
    notFound = false;
    breadcrumbs.reset();
    getJournal(d)
      .then((payload) => {
        doc = payload;
        // mockups/journal.html's last crumb is the day number only ("14"),
        // not the full ISO date ("2026-07-14") -- the year/month are already
        // covered by the preceding crumbs from the payload itself.
        breadcrumbs.set(withCurrent(payload.breadcrumbs, dayOfMonth(d), `/journal/${d}`));
      })
      .catch((err) => {
        notFound = true;
        breadcrumbs.set(fallbackCrumbs(`journal/${d}`));
        if (!(err instanceof ApiError)) console.error(err);
      });
  }

  $effect(() => {
    load(date);
  });

  // Live sync: re-subscribes whenever the watch_path changes (route nav),
  // unsubscribes on teardown. `watchPath` is `$derived` so this doesn't
  // resubscribe on every WS-pushed content update, only on a real nav.
  const watchPath = $derived(doc?.watch_path);
  const live = useLiveDoc(
    () => watchPath,
    {
      onDoc: (payload) => {
        doc = payload;
      },
      onDeleted: () => {
        doc = null;
        notFound = true;
      },
      refetch: () => load(date),
    },
  );

  let articleEl: HTMLElement | undefined = $state();
  let tocEl: HTMLElement | undefined = $state();
  $effect(() => {
    void doc?.toc;
    void doc?.html;
    if (!articleEl || !tocEl) return;
    return watchToc(articleEl, tocEl);
  });

  // Collapsible TOC rail (S30.1): below 700px it starts collapsed (seeded
  // once from matchMedia, not re-evaluated on resize -- session-only default,
  // no persistence). The toggle then always wins over that default. The
  // `.rail`/`.toc` DOM stays mounted either way (only hidden via CSS) so
  // `tocEl` and watchToc's scrollspy above are unaffected by collapsing.
  let railCollapsed = $state(
    typeof window !== "undefined" && window.matchMedia("(max-width: 700px)").matches,
  );
  function toggleRail(): void {
    railCollapsed = !railCollapsed;
  }
</script>

{#if notFound}
  <EmptyState
    glyph="404"
    message={`journal/${date} doesn't exist. This day hasn't been written yet, or the note was moved.`}
    actions={[
      { label: "Go to journal home", href: "/", primary: true },
      { label: "Search notes instead", href: "/search" },
    ]}
  />
{:else if doc}
  <div class="layout-with-rail" class:rail-collapsed={railCollapsed}>
    <article class="stack" bind:this={articleEl}>
      <div>
        <span class="deco-title">Daily Journal</span>
        <h1 class="page-title u-mt-2">{journalTitle(date)}</h1>
      </div>
      <div class="deco-rule"></div>

      {#if doc.nav && (doc.nav.prev || doc.nav.next)}
        <nav class="day-nav" aria-label="Adjacent days">
          {#if doc.nav.prev}
            <a href={`/journal/${doc.nav.prev}`}>
              <span class="day-nav-label">&larr; Prev</span>
              <span class="day-nav-date">{shortDayDate(doc.nav.prev)}</span>
            </a>
          {:else}
            <span></span>
          {/if}
          {#if doc.nav.next}
            <a class="day-nav-next" href={`/journal/${doc.nav.next}`}>
              <span class="day-nav-label">Next &rarr;</span>
              <span class="day-nav-date">{shortDayDate(doc.nav.next)}</span>
            </a>
          {/if}
        </nav>
      {/if}

      <MarkdownView
        html={doc.html ?? ""}
        watchPath={doc.watch_path}
        onCheckboxStale={() => load(date)}
        onCheckboxSuccess={(mtimeNs) => {
          if (doc) doc.mtime_ns = mtimeNs;
          live.ackMtime(mtimeNs);
        }}
      />
    </article>

    {#if doc.toc}
      <aside class="rail" class:is-collapsed={railCollapsed}>
        <div class="rail-section">
          <div class="rail-header">
            <div class="deco-title">On this page</div>
            <button
              type="button"
              class="rail-toggle"
              aria-expanded={!railCollapsed}
              aria-label={railCollapsed ? "Expand table of contents" : "Collapse table of contents"}
              onclick={toggleRail}
            >
              {railCollapsed ? "«" : "»"}
            </button>
          </div>
          <nav class="toc u-mt-2" bind:this={tocEl}>{@html doc.toc}</nav>
        </div>
      </aside>
    {/if}
  </div>
{/if}
