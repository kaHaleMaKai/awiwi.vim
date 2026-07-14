<script lang="ts">
  // Generic empty/error state (404s, dir/doc fetch failures). Matches
  // mockups/404.html's `.empty-state` markup (existing app.css classes).
  interface Action {
    label: string;
    href: string;
    primary?: boolean;
  }
  interface Props {
    glyph: string;
    message: string;
    actions?: Action[];
  }
  const { glyph, message, actions = [] }: Props = $props();
</script>

<div class="empty-state">
  <div class="empty-glyph">{glyph}</div>
  <p class="u-mt-4" style="max-width: 46ch; margin-inline: auto;">{message}</p>
  {#if actions.length}
    <div class="cluster u-mt-6" style="justify-content:center;">
      {#each actions as action (action.href)}
        <a class={action.primary ? "btn btn-primary" : "btn"} href={action.href}>{action.label}</a>
      {/each}
    </div>
  {/if}
</div>
