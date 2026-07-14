<script lang="ts">
  // Stub: static "down" state. T24's DocWatcher/WS wiring (live/reconnecting
  // transitions) lands in S25.4 — this component just owns the markup +
  // the status->label mapping so that subtask only has to feed a prop in.
  type Status = "live" | "reconnecting" | "down";

  interface Props {
    status?: Status;
  }
  let { status = "down" }: Props = $props();

  const labels: Record<Status, string> = {
    live: "Live",
    reconnecting: "Reconnecting",
    down: "Down",
  };
  const titles: Record<Status, string> = {
    live: "Live sync connected",
    reconnecting: "Reconnecting…",
    down: "No connection — viewing cached copy",
  };
</script>

<div class="ws-indicator" title={titles[status]}>
  <span class="ws-dot is-{status}" aria-hidden="true"></span>
  {labels[status]}
</div>
