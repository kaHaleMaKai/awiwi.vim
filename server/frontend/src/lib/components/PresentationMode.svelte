<script lang="ts">
  // Fullscreen slide-deck overlay ("presentation mode", S2.1). Modeled on
  // Lightbox.svelte: bind:this + exported open()/close(), $effect listeners
  // attached only while visible and cleaned up on teardown.
  //
  // open() reads the live enhanced .markdown-body via the getRoot prop,
  // splits it into per-h1 slide HTML strings (see ../presentation/slides,
  // S1.1), and renders each slide read-only via {@html} in a `.pm-slide`
  // clone — the original DOM is never touched.
  import { fly } from "svelte/transition";
  import { splitSlides, step, arrowOpacity } from "../presentation/slides";

  interface Props {
    /** Returns the live `.markdown-body` root to split into slides, or null
     * if there is nothing to present (e.g. no doc loaded). */
    getRoot: () => Element | null;
  }
  const { getRoot }: Props = $props();

  let visible = $state(false);
  let slides = $state<string[]>([]);
  let index = $state(0);
  // Direction of the last step, drives the fly transition's in/out sign.
  let dir = $state<1 | -1>(1);
  // Bottom-fifth mousemove reveal — deliberately not CSS-only :hover, which
  // would swallow the click-to-advance gesture in that same region.
  let controlsVisible = $state(true);

  let overlayEl: HTMLElement | undefined = $state();

  const count = $derived(slides.length);

  export function open() {
    const root = getRoot();
    if (!root) return;
    slides = splitSlides(root);
    index = 0;
    dir = 1;
    controlsVisible = true;
    visible = true;
    // overlayEl isn't bound yet here — the {#if visible} block hasn't
    // mounted. The fullscreen request happens in the $effect below, which
    // runs after the DOM update, once overlayEl is available.
  }

  export function close() {
    visible = false;
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    }
  }

  function next() {
    dir = 1;
    index = step(index, count, 1);
  }

  function prev() {
    dir = -1;
    index = step(index, count, -1);
  }

  // Clicking the overlay advances, unless the click landed on an in-slide
  // interactive element (links, buttons, form controls inside the slide
  // HTML) — those should behave normally, not eat the click as "next".
  function onOverlayClick(e: MouseEvent) {
    const target = e.target as Element | null;
    if (target?.closest("a, button, input, summary, textarea, select")) return;
    next();
  }

  // Separate from the listener effect below so a plain overlayEl rebind
  // (mount) doesn't churn the keydown/mousemove/fullscreenchange listeners.
  $effect(() => {
    if (visible) overlayEl?.requestFullscreen().catch(() => {});
  });

  $effect(() => {
    if (!visible) return;

    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        // Native Esc already exits fullscreen and fires fullscreenchange
        // (which calls close()); this is the fallback for when fullscreen
        // was rejected/unavailable and no fullscreenchange event fires.
        close();
      } else if (e.key === "ArrowLeft") {
        prev();
      } else if (e.key === "ArrowRight") {
        next();
      } else if (e.key === " ") {
        e.preventDefault();
        next();
      }
    };
    const onMouseMove = (e: MouseEvent) => {
      controlsVisible = e.clientY >= window.innerHeight * 0.8;
    };
    const onFullscreenChange = () => {
      if (!document.fullscreenElement) close();
    };

    document.addEventListener("keydown", onKey);
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("fullscreenchange", onFullscreenChange);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("fullscreenchange", onFullscreenChange);
    };
  });

  // JS-computed duration: the app.css --dur-* custom properties are zeroed
  // under prefers-reduced-motion, but Svelte transition durations are JS
  // values and don't see that CSS — so it's checked directly here.
  function flyDuration(): number {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 220;
  }
</script>

{#if visible}
  <div
    class="pm-overlay"
    bind:this={overlayEl}
    role="button"
    tabindex="0"
    aria-label="Presentation slide, click to advance"
    onclick={onOverlayClick}
    onkeydown={(e) => {
      if (e.key === "Enter") next();
    }}
  >
    <div class="pm-stage">
      {#key index}
        <div
          class="markdown-body pm-slide"
          in:fly={{ x: 80 * dir, duration: flyDuration() }}
          out:fly={{ x: -80 * dir, duration: flyDuration() }}
        >
          {@html slides[index] ?? ""}
        </div>
      {/key}
    </div>

    <!-- Stop propagation so control clicks don't also trigger click-to-advance. -->
    <div class="pm-controls" role="presentation" onclick={(e) => e.stopPropagation()}>
      {#if controlsVisible}
        <div class="pm-arrows">
          <button
            class="btn btn-icon"
            type="button"
            aria-label="Previous slide"
            style:opacity={arrowOpacity(index, count, -1)}
            disabled={index <= 0}
            onclick={prev}
          >‹</button>
          <button
            class="btn btn-icon"
            type="button"
            aria-label="Next slide"
            style:opacity={arrowOpacity(index, count, 1)}
            disabled={index >= count - 1}
            onclick={next}
          >›</button>
        </div>
        <button class="btn btn-ghost pm-exit" type="button" onclick={close}>
           Normal mode
        </button>
      {/if}
    </div>
  </div>
{/if}
