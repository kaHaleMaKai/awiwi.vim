<!-- Route view "/journal/:date". -->
<script lang="ts">
  import JournalPage from "../lib/components/JournalPage.svelte";
  interface Props {
    date: string;
  }
  let { date }: Props = $props();
</script>

<JournalPage {date} />
