<!-- Route view "/assets/:date/:file". -->
<script lang="ts">
  import DocPage from "../lib/components/DocPage.svelte";
  interface Props {
    date: string;
    file: string;
  }
  let { date, file }: Props = $props();
  const path = $derived(`assets/${date.split("-").join("/")}/${file}`);
</script>

<DocPage {path} />
