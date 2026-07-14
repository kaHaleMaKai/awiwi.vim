# drawio viewer — vendor pin

Self-hosted client-side draw.io/mxGraph viewer bundle, used by `DrawioView.svelte`
to render `.drawio` XML in the browser without sending any diagram data to a
third-party service.

- **Source**: `jgraph/drawio` GitHub repo
- **Pinned tag**: `v30.3.11`
- **File**: `src/main/webapp/js/viewer-static.min.js` at that tag, fetched from
  `https://raw.githubusercontent.com/jgraph/drawio/v30.3.11/src/main/webapp/js/viewer-static.min.js`
  (the `v30.3.11` GitHub *release* only publishes a `draw.war` server-webapp
  bundle as its release asset — `viewer-static.min.js` isn't attached
  separately — so this pulls the identical built file straight out of the
  source tree at the release's tag, rather than unpacking the 52 MB war just
  to extract one file. Same commit, same build, byte-identical either way.)
- **Size**: ~3.97 MB (3,969,199 bytes)
- **SHA-256**: `7f736ca32f5601fa9ae16b09965c1e6e89bff2381b0ba4ea79510ddf9f8d73c8`
- **Fetched**: 2026-07-14

## Usage contract (see `DrawioView.svelte`)

- Lazy-injected as a classic `<script>` tag (not an ES module import) the
  first time a `kind === "drawio"` doc renders, from
  `${import.meta.env.BASE_URL}vendor/drawio/viewer-static.min.js` (resolves to
  `/_app/vendor/drawio/...` in production per `vite.config.ts`'s
  `base: '/_app/'`).
- Renders diagrams via `<div class="mxgraph" data-mxgraph='{"xml":"...",
  "lightbox":false,...}'>` elements + `window.GraphViewer.processElements()`.
  `lightbox: false` is deliberate — the default lightbox config can surface
  an "Edit in draw.io" affordance that would leak the diagram to
  `https://app.diagrams.net`; self-hosting this file is pointless if that
  path stays open.
- On first load, the script's own bottom-of-file IIFE calls
  `GraphViewer.processElements()` once automatically (it checks
  `window.onDrawioViewerLoad` first, which we don't set). Every subsequent
  SPA navigation to a different `.drawio` doc re-injects a new
  `.mxgraph` div into an already-loaded script — that div needs a **manual**
  `GraphViewer.processElements()` call, since the script only auto-runs once
  per page load, not per DOM mutation. `DrawioView.svelte` does this itself.
- **Known residual risk, not fixed by `lightbox:false` alone**: the script
  sets `window.PROXY_URL`/`STYLE_PATH`/`SHAPES_PATH`/`STENCIL_PATH` to
  `https://viewer.diagrams.net/...` defaults (only if not already set) for
  shape-search/math-typesetting features we don't use from a static XML
  render. Not overridden here — flagging for whoever revisits this if a
  diagram ever exercises those code paths (stencil search, LaTeX) and an
  external request is observed; the simple mitigation is setting those
  `window.*` globals to `""` before this script first loads.

## Updating the pin

Re-run the fetch against a newer tag, update the tag/size/sha above, and
smoke-test a real `.drawio` asset renders. This file is `-diff`/
`linguist-generated` in `.gitattributes` (see `server/frontend/public/vendor/**`)
— replace wholesale, don't hand-edit.
