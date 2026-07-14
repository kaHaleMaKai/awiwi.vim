<script lang="ts">
  // Fullscreen image overlay, per the T22 asset-image mockup. A single
  // instance is mounted lazily on the first image click (see enhance/lightbox);
  // `open(src, alt)` is exposed via bind:this. Closes on overlay click, the
  // close button, or Escape.
  let visible = $state(false);
  let src = $state("");
  let alt = $state("");

  export function open(nextSrc: string, nextAlt = "") {
    src = nextSrc;
    alt = nextAlt;
    visible = true;
  }

  function close() {
    visible = false;
  }

  $effect(() => {
    if (!visible) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  });
</script>

{#if visible}
  <div
    class="lightbox-overlay"
    role="button"
    tabindex="0"
    aria-label="Close image"
    onclick={close}
    onkeydown={(e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        close();
      }
    }}
  >
    <!-- Stop propagation so clicks on the image/frame don't close. -->
    <div
      class="lightbox-frame"
      role="presentation"
      onclick={(e) => e.stopPropagation()}
    >
      <img {src} {alt} />
      {#if alt}<div class="lightbox-caption">{alt}</div>{/if}
      <button class="lightbox-close" type="button" aria-label="Close" onclick={close}>
        &times;
      </button>
    </div>
  </div>
{/if}
