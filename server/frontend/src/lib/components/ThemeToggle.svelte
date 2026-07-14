<script lang="ts">
  import { theme } from "../theme.svelte";
</script>

<div class="theme-toggle" role="group" aria-label="Theme">
  <button
    type="button"
    class:is-active={theme.current === "dark"}
    onclick={() => theme.set("dark")}
  >
    Dark
  </button>
  <button
    type="button"
    class:is-active={theme.current === "light"}
    onclick={() => theme.set("light")}
  >
    Light
  </button>
</div>
