// Lazy, singleton classic-script injection for the self-hosted drawio
// viewer bundle (see public/vendor/drawio/README.md for the pinned release +
// rationale). One <script> tag for the app's whole lifetime, regardless of
// how many call sites (DrawioView, the body drawio-link enhance pass) need
// it — every caller awaits the same promise.
let scriptPromise: Promise<void> | null = null;

declare global {
  interface Window {
    GraphViewer?: { processElements: () => void };
  }
}

/** Inject (once) and await the self-hosted mxgraph viewer script. Safe to
 * call from multiple sites concurrently — only the first call creates the
 * <script> tag. */
export function loadDrawioViewer(): Promise<void> {
  if (!scriptPromise) {
    scriptPromise = new Promise((resolve, reject) => {
      const el = document.createElement("script");
      el.src = `${import.meta.env.BASE_URL}vendor/drawio/viewer-static.min.js`;
      el.onload = () => resolve();
      el.onerror = () => reject(new Error("failed to load drawio viewer script"));
      document.head.appendChild(el);
    });
  }
  return scriptPromise;
}
