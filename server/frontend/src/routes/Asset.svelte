<!-- Stub route view for "/assets/:date/:file". Filled in by S25.3. -->
<script lang="ts">
  interface Props {
    date: string;
    file: string;
  }
  let { date, file }: Props = $props();
</script>

<section class="stack">
  <span class="deco-title">Asset</span>
  <h1 class="page-title u-mt-2">{file}</h1>
  <p>Owning journal day: {date}. Asset rendering lands in S25.2/S25.3.</p>
</section>
