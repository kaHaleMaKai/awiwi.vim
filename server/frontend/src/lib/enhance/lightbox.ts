// Lazy singleton wiring for the fullscreen image overlay. One Lightbox
// component is mounted to <body> on first use and reused thereafter, so the
// overlay survives MarkdownView re-renders and there's only ever one.
import { mount } from "svelte";
import Lightbox from "../components/Lightbox.svelte";

interface LightboxApi {
  open(src: string, alt?: string): void;
}

let instance: LightboxApi | null = null;

/** Open the shared lightbox on `src` (mounting it on first call). */
export function openLightbox(src: string, alt = ""): void {
  if (typeof document === "undefined") return;
  if (!instance) {
    instance = mount(Lightbox, { target: document.body }) as unknown as LightboxApi;
  }
  instance.open(src, alt);
}
