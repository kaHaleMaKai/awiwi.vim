# awiwi SPA mockups — Noir-Deco

Static HTML mockups for the new awiwi viewer SPA (server rewrite, T22). Dark-first
art-deco noir visual language ("Noir-Deco"), with a light "daylight-noir" variant.

## How to view

Open any `.html` file directly in a browser (`file://` works — no server needed):

```sh
xdg-open mockups/journal.html
```

All pages share `tokens.css` via a relative link, plus the display webfont in `fonts/`.

## Pages

| File | What it shows |
|---|---|
| `journal.html` | Daily journal: TOC rail, prev/next day nav, checklist, `#tag`/`@@mention`, redacted span, python code block with copy button, table with copy-menu (Markdown/CSV/HTML), mermaid placeholder, WS-dot legend |
| `journal-light.html` | Same page, `data-theme="light"` (daylight-noir) |
| `dir-root.html` | Root index: `journal/`, `assets/`, `recipes/` + recent files |
| `dir-journal-month.html` | Month listing with alternate-week background banding |
| `todo.html` | Task log grouped by Overdue / Today / Upcoming |
| `search.html` | Search input, scope chips, regex toggle, results grouped by file with line numbers + match highlight |
| `search-light.html` | Same, `data-theme="light"` |
| `asset-image.html` | Image asset page + working CSS-only lightbox (click the image or "View fullscreen"), "Back to journal" link |
| `asset-text.html` | Full-file syntax-highlight look, line numbers, copy-file button |
| `asset-drawio.html` | drawio diagram placeholder canvas + open/download actions |
| `download.html` | Binary file download card |
| `404.html` | SPA 404 (also shows the "down" WS-dot state) |

Every page shares a common header: brand mark, breadcrumbs, search input, WS
connection-status dot, and a theme toggle. The three WS-dot states (live/cyan,
reconnecting/amber, down/red) are each demonstrated on at least one page, with a
legend on `journal.html`.

## Design system

`tokens.css` is the seed of the real SPA's `app.css`:

- `:root` — dark palette (default) + spacing/type/radius/shadow/motion tokens
- `[data-theme='light']` — daylight-noir re-tone (see handover for the flip mechanism)
- Component recipes: buttons, inputs, chips, cards with deco corner brackets, the
  chevron `.deco-rule` divider, rows/lists, code blocks, copy menus, tables, task
  checkboxes, day-nav, lightbox, week banding, search hits, skeletons

Full rationale, naming scheme, and carry-over notes for the SPA-scaffold engineer:
`handovers/server-rewrite/T22-mockups.md`.
