<script lang="ts">
  // Renders server-produced markdown HTML and runs the enhance pipeline over
  // it. The HTML is injected verbatim via {@html} with NO sanitization — this
  // viewer is localhost-only and shows the user's own notes, a deliberate
  // decision recorded in the plan (ADR D18+). enhance() runs after the DOM
  // update and is re-run whenever `html` (or `watchPath`) changes.
  import { untrack } from "svelte";
  import { theme } from "../theme.svelte";
  import { enhance, type EnhanceHandle } from "../enhance";

  interface Props {
    /** DocPayload.html — the rendered markdown. */
    html: string;
    /** DocPayload.watch_path — relpath for checkbox PATCH + media resolution. */
    watchPath: string;
    /** Called on a checkbox 409 so the page can refetch the doc. */
    onCheckboxStale?: () => void;
    /** Called with the new mtime_ns after a successful checkbox toggle. */
    onCheckboxSuccess?: (mtimeNs: number) => void;
  }
  const { html, watchPath, onCheckboxStale, onCheckboxSuccess }: Props = $props();

  let container: HTMLElement;
  let handle: EnhanceHandle | undefined;

  // Re-enhance on content change. Only `html`/`watchPath` are tracked deps;
  // the enhance() call is untracked so theme/callback changes don't force a
  // full re-enhance (theme is handled by the separate effect below).
  $effect(() => {
    void html;
    const wp = watchPath;
    if (!container) return;
    const active = untrack(() =>
      enhance(container, {
        watchPath: wp,
        theme: theme.current,
        onCheckboxStale,
        onCheckboxSuccess,
      }),
    );
    handle = active;
    return () => {
      active.destroy();
      if (handle === active) handle = undefined;
    };
  });

  // Follow the app theme for theme-dependent passes (mermaid). Shiki's
  // dual-theme output switches purely via CSS — no re-highlight here.
  $effect(() => {
    const current = theme.current;
    handle?.setTheme(current);
  });
</script>

<div class="markdown-body" bind:this={container}>{@html html}</div>
