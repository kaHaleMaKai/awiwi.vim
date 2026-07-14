<!-- Stub route view for "/journal/:date". Filled in by S25.3
     (MarkdownView + enhance/ pipeline land in S25.2). -->
<script lang="ts">
  interface Props {
    date: string;
  }
  let { date }: Props = $props();
</script>

<section class="stack">
  <span class="deco-title">Daily Journal</span>
  <h1 class="page-title u-mt-2">{date}</h1>
  <p>Journal rendering lands in S25.2/S25.3.</p>
</section>
