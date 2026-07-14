<!-- Route view "/dir/*". -->
<script lang="ts">
  import DirPage from "../lib/components/DirPage.svelte";
  interface Props {
    rest: string;
  }
  let { rest }: Props = $props();
</script>

<DirPage path={rest} />
