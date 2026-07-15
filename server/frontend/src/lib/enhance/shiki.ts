// Lazy, client-side syntax highlighting via Shiki.
//
// Design points (from the plan / T22 mockups):
// - Lazy singleton highlighter: Shiki is dynamically imported on the first
//   code block only, so it stays out of the main bundle.
// - Dual-theme via CSS variables: every token carries both a light and a dark
//   colour, switched by a `[data-theme]` CSS rule injected once. Flipping the
//   app theme therefore needs NO re-highlight.
// - Reads `textContent` (never `innerText`, which is layout-dependent and
//   would collapse/normalize whitespace).
// - Unknown languages fall back to plain text rather than throwing.

import type { Highlighter } from "shiki";

const LIGHT_THEME = "github-light";
const DARK_THEME = "github-dark";

let highlighterPromise: Promise<Highlighter> | null = null;
const loadedLangs = new Set<string>();
let styleInjected = false;

/** Inject the one-time CSS that makes Shiki's dual-theme output follow the
 * app's `[data-theme]` (light is the default; dark overrides). Kept here so
 * the enhance pipeline is self-contained and doesn't depend on app.css. */
function injectThemeSwitchCss(): void {
  if (styleInjected || typeof document === "undefined") return;
  styleInjected = true;
  const style = document.createElement("style");
  style.id = "awiwi-shiki-theme";
  // Token colors come from Shiki's own dual-theme CSS variables, but the
  // background follows the app's own `--code-bg` token rather than the
  // github-light/dark themes' baked-in background — otherwise light mode
  // renders a plain white box instead of the Noir-Deco tan/beige card.
  // Border/padding/radius (the rest of mockups/tokens.css's `.code-block`
  // look) only apply inside `.awiwi-code-block` (copyButtons.ts's wrapper,
  // used by MarkdownView's bare fenced code) — TextFileView already sits
  // inside its own `.code-block`/`.code-toolbar` box and strips this back
  // out (see its own <style>) so the two boxes don't nest.
  style.textContent = `
.shiki, .shiki span { color: var(--shiki-light); }
:root[data-theme='dark'] .shiki,
:root[data-theme='dark'] .shiki span { color: var(--shiki-dark); }
.shiki { background: var(--code-bg); }
.awiwi-code-block .shiki {
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-md);
  padding: var(--space-4);
  overflow-x: auto;
  font-size: var(--text-sm);
  line-height: var(--leading-normal);
}
`;
  document.head.appendChild(style);
}

async function getHighlighter(): Promise<Highlighter> {
  if (!highlighterPromise) {
    highlighterPromise = import("shiki").then((shiki) =>
      shiki.createHighlighter({ themes: [LIGHT_THEME, DARK_THEME], langs: [] }),
    );
  }
  return highlighterPromise;
}

/** Ensure `lang` is loaded; return the usable language id (`"text"` if `lang`
 * is unknown to Shiki, so highlighting degrades to a plain, escaped block). */
async function ensureLanguage(hl: Highlighter, lang: string | null): Promise<string> {
  if (!lang || lang === "text" || lang === "plaintext") return "text";
  if (loadedLangs.has(lang)) return lang;
  try {
    await hl.loadLanguage(lang as never);
    loadedLangs.add(lang);
    return lang;
  } catch {
    return "text";
  }
}

/** Read the wanted language off a `<pre><code class="language-x">` block, as
 * emitted by the server's mdrender. `null` (bare `<code>`) -> plain text. */
function langFromCode(code: Element | null): string | null {
  if (!code) return null;
  for (const cls of code.classList) {
    if (cls.startsWith("language-")) return cls.slice("language-".length);
  }
  return null;
}

/** Highlight one `<pre>` code block in place, replacing it with Shiki's
 * dual-theme output. No-op if the element has no `<code>` child. Resolves once
 * the (async) replacement is done. */
export async function highlightBlock(pre: HTMLElement): Promise<void> {
  const code = pre.querySelector("code");
  if (!code) return;
  const lang = langFromCode(code);
  const source = code.textContent ?? "";

  const hl = await getHighlighter();
  // The block may have been torn out (re-render) while we awaited — bail.
  if (!pre.isConnected) return;
  const usableLang = await ensureLanguage(hl, lang);
  if (!pre.isConnected) return;

  injectThemeSwitchCss();
  const html = hl.codeToHtml(source, {
    lang: usableLang,
    themes: { light: LIGHT_THEME, dark: DARK_THEME },
    defaultColor: false,
  });
  const tpl = document.createElement("template");
  tpl.innerHTML = html.trim();
  const rendered = tpl.content.firstElementChild;
  if (rendered) pre.replaceWith(rendered);
}
