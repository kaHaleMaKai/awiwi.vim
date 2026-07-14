<script lang="ts">
  // "/journal/:date" — day entry: TOC sticky rail (T22 item 7: zero-drift
  // `.layout-with-rail`/`.rail`, already in app.css), prev/next day-nav from
  // the payload's `nav`, MarkdownView + enhance for the body.
  import { getJournal, ApiError, type DocPayload } from "../api";
  import { breadcrumbs, fallbackCrumbs, withCurrent } from "../breadcrumbs.svelte";
  import { beautifyDate } from "../format";
  import { useLiveDoc } from "../ws.svelte";
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
        breadcrumbs.set(withCurrent(payload.breadcrumbs, d, `/journal/${d}`));
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
  <div class="layout-with-rail">
    <article class="stack">
      <div>
        <span class="deco-title">Daily Journal</span>
        <h1 class="page-title u-mt-2">{@html beautifyDate(date, "%B %Y")}</h1>
      </div>
      <div class="deco-rule"></div>

      {#if doc.nav && (doc.nav.prev || doc.nav.next)}
        <nav class="day-nav" aria-label="Adjacent days">
          {#if doc.nav.prev}
            <a href={`/journal/${doc.nav.prev}`}>
              <span class="day-nav-label">&larr; Prev</span>
              <span class="day-nav-date">{@html beautifyDate(doc.nav.prev)}</span>
            </a>
          {:else}
            <span></span>
          {/if}
          {#if doc.nav.next}
            <a class="day-nav-next" href={`/journal/${doc.nav.next}`}>
              <span class="day-nav-label">Next &rarr;</span>
              <span class="day-nav-date">{@html beautifyDate(doc.nav.next)}</span>
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
      <aside class="rail">
        <div class="rail-section">
          <div class="deco-title">On this page</div>
          <nav class="toc u-mt-2">{@html doc.toc}</nav>
        </div>
      </aside>
    {/if}
  </div>
{/if}
