# server-rewrite / T22 — SPA design checkpoint mockups

**Responsibility:** produce static HTML mockups of the new awiwi SPA viewer under
`mockups/`, establishing the "Noir-Deco" visual language and a reusable token file
that seeds the real SPA's `app.css`.
**Boundary:** `mockups/**` only (tokens.css, fonts/, 12 HTML pages, README.md) + this
handover + `.claude/progress/designer-mockups.md`. No `server/`, `lua/`, or `docs/`
were touched — this unit does design/markup only, no application code.

## What downstream (S25.1 SPA-scaffold engineer) needs from me

### tokens.css — structure and naming

File layout mirrors the ui-ux-designer skill's layered CSS architecture, in this
order (kept as literal `/* === SECTION === */` comments — preserve the order when
porting into the real `app.css`):

`FONTS` → `RESET` → `TOKENS` (`:root` + `[data-theme='light']` + reduced-motion) →
`BASE` → `LAYOUT` → `COMPONENTS` → `UTILITIES` → `STATES`.

**Two-tier variable naming** — this is the one design decision to carry over
verbatim, because it's what makes the light theme cost zero extra component CSS:

1. **Raw palette scale** — literal token names from the spec (`--ink-950` … `--ink-500`,
   `--smoke-400`, `--paper-50/100/200`, `--brass-900/700/600/500/400/300`,
   `--neon-cyan/-dim/-magenta/-red/-amber/-emerald`). These are the only variables
   `[data-theme='light']` redefines (exactly the leaves the spec lists as flipping;
   `--ink-950`, `--brass-900/700/600/500`, `--neon-cyan-dim` are constant across themes
   per spec and are NOT redefined in the light block).
2. **Semantic role layer** — `--bg-canvas`, `--bg-surface`, `--bg-surface-raised`,
   `--bg-inset`, `--bg-hover`, `--bg-current`, `--border-subtle/default/strong`,
   `--text-primary/secondary/tertiary/muted/on-accent`, `--accent-brass*`,
   `--accent-cyan*`, `--color-error/warn/success/link`. Every component in
   `COMPONENTS` binds to the semantic layer, never to the raw scale directly.

The flip mechanism: semantic backgrounds are aliased to the **ink** scale, semantic
text to the **paper** scale. In light mode the spec redefines `--ink-900` → a warm
cream (`#faf5e8`) and `--paper-50` → a dark brown (`#241b0f`) — i.e. the *leaves*
re-tone, not the semantic aliases. That's why `[data-theme='light']` in tokens.css
is short (just the raw-scale overrides) and every component automatically re-tones
correctly with zero component-level dark/light branching. **Preserve this** — if a
future component needs a new color, add it as a semantic alias pointing at an
existing (or new) raw leaf, don't hardcode hex or branch on `[data-theme]` in the
component rule.

Other token groups: 8px spacing scale (`--space-1`…`--space-8`, 4/8/12/16/24/32/48/64px),
type scale (`--text-xs`…`--text-2xl`), `--radius-sm:2px` / `--radius-md:4px` (nothing
rounder — enforced by the spec, "2–4px radii only, ever"), `--shadow-noir`,
`--shadow-focus-cyan`, motion (`--dur-fast:100ms`, `--dur-med:180ms`, zeroed under
`prefers-reduced-motion`), and the code/syntax role vars (`--code-bg`, `--code-fg`,
`--tok-comment/keyword/string/function/constant/plain` — see revision item 2 below).

### Component recipes already built (reuse, don't re-invent)

`.deco-rule` (chevron trim band), `.deco-card` (corner-bracket dialog/card frame via
`::before`/`::after`), `.deco-title` / `.page-title`, `.btn` / `.btn-primary` /
`.btn-ghost` / `.btn-icon`, `.input`/`.select`/`.textarea`, `.chip` (filter chips,
`aria-pressed`/`.is-active` for selected state), `.tag` / `.mention` / `.redacted`,
`.row` (list rows incl. `.is-current`), `.breadcrumbs`, `.app-header` (the shared
page chrome), `.theme-toggle`, `.ws-dot` (`.is-live`/`.is-reconnecting`/`.is-down` +
`@keyframes ws-pulse`), `.code-block` + `.copy-btn` + `.tok-*` (hand-authored
syntax-color placeholders — comment/keyword/string/function/constant/plain — mapped
to smoke/brass-400/emerald/cyan-dim/amber/paper per the spec; swap for Shiki's own
class names when wiring real highlighting, keep the color mapping), `.copy-menu` +
`.copy-menu-list` (table export menu), `.data-table`, `.task-item` (custom checkbox),
`.mermaid-box` (placeholder — swap inner content for the real mermaid SVG target),
`.toc`, `.day-nav`, `.lightbox-overlay` (see CSS-only demo pattern below),
`.week-band` (nth-of-type odd/even striping), `.search-group`/`.search-hit`/
`mark.hit-match`, `.download-card`, `.empty-state` (404 uses this), `.skeleton`
(loading placeholder, not yet used on any page — wire it in for real async states).

### Font

**Cinzel** (SIL OFL 1.1, via Google Fonts / fonts.google.com/specimen/Cinzel).
Justification: engraved, letterspaced Roman capitals — the closest OFL match to a
Copperplate/deco-title feel, and it's exactly what "Noir-Deco" asks for (uppercase
letterspaced brass titles). Weights 400/600/700 downloaded as woff2 into
`mockups/fonts/cinzel-{400,600,700}.woff2` (~15–25 KB each, latin subset only — the
`@font-face` blocks in tokens.css are latin-subset; add latin-ext/other subsets if
the real app needs non-Latin note content). `@font-face` includes a `local()`
fallback chain (`Copperplate`, `Copperplate Gothic Std`) for robustness, then the
generic `serif` at the end of `--font-display`. Used only for `.page-title` and
`h1`–`h3` (per the spec: "page titles/headers only"). No network gap — the download
succeeded; nothing to flag here.

Body copy: **Verdana** (user decision, feedback round 1 — "much more legible"):
`--font-body: Verdana, 'DejaVu Sans', Geneva, Tahoma, 'Segoe UI', sans-serif`
(DejaVu Sans is the metric-compatible Linux stand-in). Because Verdana runs wide,
`--text-base` was dropped from 15px to 14px — 14px Verdana reads like 15–16px of
most other faces; keep this pairing if the body font ever changes again. UI chrome
(header, buttons, chips, breadcrumbs): system sans (`--font-ui`). Code: `--font-mono`
(`ui-monospace, 'Cascadia Mono', 'JetBrains Mono', monospace`) exactly per spec.

### Design decisions worth knowing

- **No JS framework; one shared demo script** — these are static mockups, not the
  real Svelte app. All interactive demos live in `mockups/mockup.js`, loaded in
  `<head>` (non-deferred, so the persisted theme applies before first paint) by
  every page: theme toggle + persistence, code-block copy buttons, table copy-menu,
  and redaction reveal. The script is mockup-only and discardable — but the
  *behavior specs* it demonstrates (revision items 2–5 below) are the contract the
  real SPA implements from.
- **Lightbox is CSS-only** (`asset-image.html`): a hidden `<input type="checkbox"
  id="lightbox-toggle">` at the top of `<body>`, opened by a `<label for=…>` wrapping
  the thumbnail, closed by another `<label for=…>` inside the overlay. Pattern:
  `#lightbox-toggle:checked ~ .lightbox-overlay { display: flex; }`. This means the
  checkbox **must be a sibling that precedes** `.lightbox-overlay` in the DOM — keep
  that ordering if this markup shape is reused, or replace wholesale with real
  Svelte show/hide state (recommended for the real app; the checkbox hack is a
  mockup-only convenience, not a pattern to port).
- **Week banding** (`dir-journal-month.html`) is `nth-of-type(odd/even)` on
  `.week-band` groups, not per-row zebra — each week is one visual band (per the
  spec: "alternate-week background stripes"), with an inner `.day-row` for per-day
  hover/current states.
- **WS-dot legend** lives on `journal.html`'s right rail (below the TOC) since it's
  the flagship/most-visited page; all three states are also independently
  demonstrated live in other pages' headers: `is-live` (most pages), `is-reconnecting`
  (`search.html`/`search-light.html`), `is-down` (`404.html`).
- Placeholder art (image/drawio canvases) uses a diagonal-hatch / grid CSS
  background rather than an embedded raster, so mockups stay dependency-free and
  theme-reactive (the hatch uses `--bg-surface-raised`/`--bg-inset`, which re-tone
  correctly in light mode).
- Desktop-first per the brief; `.layout-with-rail` (used by `journal*.html`) collapses
  the TOC rail below the article at `max-width: 900px` — the only explicit
  responsive breakpoint. Not extensively tested below ~800px beyond that breakpoint;
  worth a pass when this becomes real, interactive markup.

### Design revisions — user feedback round 1 (2026-07-14, all applied)

The user reviewed the first mockup set and requested five changes. All are
implemented in the mockups; the S25 frontend engineers implement the real SPA
from these specs:

1. **Body font is Verdana** (see Font section above). Cinzel stays for page
   titles/headers only; mono stack unchanged.

2. **Code blocks are dual-theme via CSS variables.** New semantic role vars in
   tokens.css: `--code-bg`, `--code-fg`, and `--tok-comment/keyword/string/
   function/constant/plain`. The `[data-theme='light']` block re-points
   `--bg-sunken` to `--ink-800` (#f2e8d2 — this also fixes the mermaid/drawio
   placeholder canvases, which share the sunken role) and overrides exactly two
   token roles: `--tok-keyword: var(--brass-300)` (light brass-400 only hits
   3.7:1) and `--tok-function: var(--neon-cyan)` (`--neon-cyan-dim` is
   theme-constant and only 3.2:1 on paper). All six light token colors are
   AA-verified ≥4.5:1 on #f2e8d2 (comment 5.45, keyword 6.60, string 10.13,
   function 4.93, constant 4.86, plain 8.97 — computed, not eyeballed).
   **Real-app note:** use Shiki's css-variables theme so each token role maps to
   one CSS var, exactly mirroring this structure — theme switching then costs
   zero re-highlighting. The flip must live in the theme block in app.css, never
   in per-page/per-component overrides.

3. **Table copy-menu behavior spec:** clicking the trigger opens the format
   menu (Markdown / CSV / HTML); clicking a format (a) serializes the adjacent
   table to that format, (b) writes it to the clipboard, (c) **closes the menu**,
   and (d) flashes "Copied ✓" on the trigger for ~1.4s. Click-outside closes the
   menu without copying. The mockup's serializers in mockup.js (`toMarkdown`/
   `toCsv`/`toHtml`, incl. CSV quote-escaping) are a reasonable reference
   implementation; clipboard write is try/catch'd because `file://` pages may
   lack clipboard permission — the demo still shows the Copied state.

4. **Redaction is click-to-reveal.** Contract: on localhost (the only normal
   deployment, i.e. non-remote mode) the **server embeds the original value in
   the DOM**, obscured by CSS (`.redacted`: ink-600 block, transparent text,
   `user-select: none`); the frontend only toggles visibility. Click or
   Enter/Space toggles `.is-revealed` (text shown on a faint brass tint with a
   dashed brass border, `user-select: text` restored), with `role="button"`,
   `tabindex="0"`, `aria-pressed`, and a title that flips between "Click to
   reveal"/"Click to redact". In a future remote mode the server must *omit*
   the value entirely — never rely on the CSS obscuring for actual secrecy.

5. **Live theme switching with transition.** The header toggle now really flips
   the theme on every page: set `data-theme` on `<html>`, persist as
   localStorage key **`awiwi-theme`**. Around the flip, a `.theme-transition`
   class is stamped on `<html>` for ~350ms; tokens.css defines a 250ms
   cross-fade (background-color/color/border-color/fill/stroke/box-shadow)
   scoped to that class and wrapped in `@media (prefers-reduced-motion:
   no-preference)` — reduced-motion users get an instant switch. The transition
   rule is class-gated on purpose: leaving permanent transitions on `*` would
   fight the per-component `--dur-fast` transitions and animate initial paint.
   The static `*-light.html` snapshot pages carry `data-theme-fixed` on `<html>`,
   which makes the script skip the persisted-theme restore on load (they stay
   light snapshots) while their toggle still works live.

6. **Task checkboxes: strikethrough follows live state** (feedback round 2).
   The mockups render the strikethrough from the *initial* checked state only
   and don't update it on toggle — known mockup artifact, deliberately not
   fixed. In the real SPA (S25.2 checkbox wiring) the done-styling
   (strikethrough/dimming) must be bound to the checkbox's *current* state:
   toggling on applies it, toggling off removes it, and a 409-revert restores
   the correct style with the reverted state.

### Gaps / things NOT done here (explicitly out of scope for T22)

- No build step, no bundler, no Svelte — plain HTML+CSS+trivial JS as specified.
- No accessibility audit tooling was run (no axe/lighthouse in this sandbox); states
  were hand-checked for focus-visible rings and semantic roles but not machine-verified.
- Only Latin-subset Cinzel woff2s were fetched; non-Latin fallback is `local()` →
  generic `serif`, which will look inconsistent for non-Latin note titles. Flag if
  the real app needs to support non-Latin daily-journal filenames/titles.
- Mermaid/drawio placeholders are static boxes with an SVG glyph + caption; no attempt
  to fake real diagram rendering.

## Inputs I consumed

- Task brief (this unit's prompt): full Noir-Deco token spec (dark + light palettes,
  idioms), the required page list, and the ui-ux-designer skill's multi-pass method
  (IA → design system → hierarchy/polish → interaction/UX states).
- `ui-ux-designer` skill instructions (layered CSS architecture, states, a11y).
- No repo docs were read (out of boundary) beyond what was already in this task's
  context (CLAUDE.md project overview, for note-content realism: doc-type hierarchy,
  journal/assets/recipes paths).

## Tests

N/A — static design artifacts, no test suite. Verified manually: every page's
`<div>` open/close tag counts balance (`grep -c` sanity check), all three woff2 font
files downloaded as valid WOFF2 (`file` confirmed), all 12 required pages plus
README present, `mockup.js` passes `node --check`, and the light-mode syntax token
contrast ratios were computed programmatically (WCAG relative-luminance formula).

## Status

status: done (incl. feedback round 1 revisions)
updated: 2026-07-14
commit: see ledger (orchestrator commits)

## File manifest

```
mockups/
  tokens.css
  mockup.js
  README.md
  fonts/
    cinzel-400.woff2
    cinzel-600.woff2
    cinzel-700.woff2
  journal.html
  journal-light.html
  dir-root.html
  dir-journal-month.html
  todo.html
  search.html
  search-light.html
  asset-image.html
  asset-text.html
  asset-drawio.html
  download.html
  404.html
```
