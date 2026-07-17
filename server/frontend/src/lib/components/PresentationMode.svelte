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
  import { splitSlides, step } from "../presentation/slides";
  import { parseSettings, fragmentSteps, type Settings } from "../presentation/fragments";

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

  // Fragmenting: per-doc settings + per-slide count of revealed fragments.
  // `revealed` is persistent for the session, so navigating away and back keeps
  // each slide's reveal state; a never-visited slide starts at 0.
  let settings = $state<Settings>({ fragmentAll: false, debug: false });
  let revealed = $state<number[]>([]);
  // Fragment-step count of the current slide, for arrow enablement.
  let stepCount = $state(0);

  // Console tracing, toggled by `"debug": true` in the #awiwi-settings blob.
  // Logs raw input events too, so a single physical click/press showing up
  // twice (e.g. a presenter remote firing click+key) is visible in the console.
  function dbg(...msg: unknown[]) {
    if (settings.debug) console.log("[awiwi:presentation]", ...msg);
  }

  const count = $derived(slides.length);
  const hasPrev = $derived(index > 0 || (revealed[index] ?? 0) > 0);
  const hasNext = $derived(index < count - 1 || (revealed[index] ?? 0) < stepCount);

  export function open() {
    const root = getRoot();
    if (!root) return;
    slides = splitSlides(root);
    settings = parseSettings(root);
    revealed = new Array(slides.length).fill(0);
    index = 0;
    dir = 1;
    controlsVisible = true;
    visible = true;
    dbg(`open deck — ${slides.length} slides, fragmentAll=${settings.fragmentAll}`);
    // overlayEl isn't bound yet here — the {#if visible} block hasn't
    // mounted. The fullscreen request happens in the $effect below, which
    // runs after the DOM update, once overlayEl is available.
  }

  export function close() {
    dbg("close deck");
    visible = false;
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    }
  }

  // One physical input sometimes arrives as two events microseconds apart — a
  // presenter remote firing click+key, or a control button's native activation
  // plus a bubbled handler. Without collapsing them, the click that reveals a
  // slide's last fragment also advances/clears the slide. Human input is >100ms
  // apart, so a real second press is never eaten.
  // ponytail: 50ms window; widen if a specific remote double-fires slower.
  let lastNavAt = -Infinity;
  function coalesced(): boolean {
    const now = performance.now();
    if (now - lastNavAt < 50) {
      dbg("input coalesced — ignored duplicate within 50ms");
      return true;
    }
    lastNavAt = now;
    return false;
  }

  // Fragments-first navigation: reveal/hide the current slide's fragments one
  // at a time before crossing a slide boundary.
  function next() {
    if (coalesced()) return;
    if ((revealed[index] ?? 0) < stepCount) {
      revealed[index] = (revealed[index] ?? 0) + 1;
      dbg(`next: reveal fragment ${revealed[index]}/${stepCount} on slide ${index + 1}`);
      return;
    }
    dir = 1;
    const to = step(index, count, 1);
    dbg(`next: advance slide ${index + 1} → ${to + 1}/${count}`);
    index = to;
  }

  function prev() {
    if (coalesced()) return;
    if ((revealed[index] ?? 0) > 0) {
      revealed[index] = (revealed[index] ?? 0) - 1;
      dbg(`prev: hide fragment (now ${revealed[index]}/${stepCount}) on slide ${index + 1}`);
      return;
    }
    dir = -1;
    const to = step(index, count, -1);
    dbg(`prev: retreat slide ${index + 1} → ${to + 1}/${count}`);
    index = to;
  }

  // The on-screen ‹ / › buttons skip fragment stepping: reveal all of the
  // current slide, then cross a whole slide in one click. (Arrow keys / overlay
  // click keep the fragments-first behaviour above.)
  function nextSlide() {
    if (coalesced()) return;
    revealed[index] = stepCount;
    dir = 1;
    const to = step(index, count, 1);
    dbg(`next slide: ${index + 1} → ${to + 1}/${count}`);
    index = to;
  }

  function prevSlide() {
    if (coalesced()) return;
    revealed[index] = stepCount;
    dir = -1;
    const to = step(index, count, -1);
    dbg(`prev slide: ${index + 1} → ${to + 1}/${count}`);
    index = to;
  }

  // Per-slide action: compute the slide's fragment steps once on mount, hide the
  // ones past `shown`, and re-apply whenever `shown` changes. Scoped to each
  // slide element so keyed transitions can't clobber a shared ref.
  function fragmentize(
    node: HTMLElement,
    args: { shown: number; settings: Settings; index: number },
  ) {
    const steps = fragmentSteps(node, args.settings);
    stepCount = steps.length;
    const slideNo = args.index + 1;
    dbg(`open slide ${slideNo}/${slides.length} — ${steps.length} fragment(s)`);
    if (settings.debug) {
      dbg(
        `fragments on slide ${slideNo}:`,
        steps.map((el, i) => {
          const text = (el.textContent ?? "").replace(/\s+/g, " ").trim();
          return `${i + 1}. <${el.tagName.toLowerCase()}> ${text.slice(0, 40)}`;
        }),
      );
    }
    let prevShown = 0;
    // animate=false on the initial mount so a fresh slide's fragments hide
    // instantly (no 1→0 fade flashing during the incoming fly); true on user
    // reveal/hide so those still transition.
    const apply = (shown: number, animate: boolean) => {
      steps.forEach((frag, i) => {
        frag.classList.add("pm-frag");
        if (animate) frag.classList.add("pm-animate");
        frag.classList.toggle("pm-frag-hidden", i >= shown);
      });
      for (let i = prevShown; i < shown; i++) {
        const el = steps[i];
        const text = (el.textContent ?? "").replace(/\s+/g, " ").trim();
        dbg(
          `show element ${i + 1}/${steps.length} on slide ${slideNo}: <${el.tagName.toLowerCase()}> ${text.slice(0, 40)}`,
        );
      }
      prevShown = shown;
    };
    apply(args.shown, false);
    return {
      update(arg: { shown: number }) {
        apply(arg.shown, true);
      },
      destroy() {
        dbg(`clear slide ${slideNo}`);
      },
    };
  }

  // Clicking the overlay advances, unless the click landed on an in-slide
  // interactive element (links, buttons, form controls inside the slide
  // HTML) — those should behave normally, not eat the click as "next".
  function onOverlayClick(e: MouseEvent) {
    const target = e.target as Element | null;
    dbg(`input: overlay click on <${target?.tagName.toLowerCase() ?? "?"}>`);
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
      const onCtrl = !!(e.target as Element | null)?.closest?.(".pm-controls");
      dbg(`input: key "${e.key}"${onCtrl ? " (on controls)" : ""}`);
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
        // A focused control button (Prev/Next/Exit) activates itself on Space;
        // let it, or Space fires next() twice (native activation + here) and
        // the slide skips a fragment / jumps early.
        if (onCtrl) return;
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
      // Only when the overlay itself is focused. A control button (Prev/Next/
      // Exit) already advances via its own native Enter activation; without
      // this guard the bubbled keydown also lands here → next() twice → slide
      // jumps as soon as the last fragment is revealed.
      if (e.key === "Enter" && e.target === e.currentTarget) next();
    }}
  >
    <div class="pm-stage">
      {#key index}
        <div
          class="markdown-body pm-slide"
          use:fragmentize={{ shown: revealed[index] ?? 0, settings, index }}
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
            style:opacity={hasPrev ? 0.5 : 0.1}
            disabled={!hasPrev}
            onclick={() => {
              dbg("input: Prev button");
              prevSlide();
            }}
          >‹</button>
          <button
            class="btn btn-icon"
            type="button"
            aria-label="Next slide"
            style:opacity={hasNext ? 0.5 : 0.1}
            disabled={!hasNext}
            onclick={() => {
              dbg("input: Next button");
              nextSlide();
            }}
          >›</button>
        </div>
        <button class="btn btn-ghost pm-exit" type="button" onclick={close}>
           Normal mode
        </button>
      {/if}
    </div>
  </div>
{/if}
