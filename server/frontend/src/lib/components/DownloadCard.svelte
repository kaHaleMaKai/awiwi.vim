<script lang="ts">
  // kind === "binary": file types that can't be previewed inline
  // (mockups/download.html). No size/MIME from DocPayload — just a path
  // label and a direct download link.
  import { rawUrl, type DocPayload } from "../api";

  interface Props {
    doc: DocPayload;
    path: string;
  }
  const { doc, path }: Props = $props();
  const filename = $derived(path.split("/").pop() ?? path);
</script>

<div class="deco-card download-card" style="max-width: 480px; margin-inline: auto;">
  <div class="download-icon">
    <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4">
      <path d="M4 4h9l5 5v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z" />
      <path d="M13 4v5h5" />
      <path d="M12 12v6M9 15l3 3 3-3" />
    </svg>
  </div>
  <span class="deco-title">Binary file</span>
  <h1 class="page-title u-mt-2" style="font-size: var(--text-xl);">{filename}</h1>
  <p class="u-muted u-mt-2" style="font-size: var(--text-sm); max-width: none;">
    This file type can't be previewed inline. Download it to view locally.
  </p>
  <div class="u-mt-5">
    <a
      class="btn btn-primary"
      style="justify-content:center; width:100%;"
      href={rawUrl(doc.watch_path, { download: true })}
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
        <path d="M12 3v12m0 0l-4-4m4 4l4-4" />
        <path d="M4 19h16" />
      </svg>
      Download
    </a>
  </div>
  <div class="u-mt-4 u-mono" style="font-size: var(--text-xs); color: var(--text-muted);">
    {doc.watch_path}
  </div>
</div>
