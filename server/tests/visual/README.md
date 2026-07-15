# Visual-parity screenshot harness (T28.2)

Dep-free CDP screenshot tool that shoots every SPA route + T22 mockup page pair listed in
`pairs.json`, then post-processes each pair with ImageMagick (pad to common canvas, RMSE
diff, 1440x760 band slices) so a cheap model or a human can eyeball parity band by band.

No puppeteer/playwright — `shoot.mjs` talks raw Chrome DevTools Protocol over a WebSocket per
page target. The only runtime deps are things already on this machine: node 20, `/usr/bin/chromium`,
ImageMagick (`magick`/`compare`), and `uv` (to boot the FastAPI server).

## Invocation

```sh
cd server/tests/visual
node --experimental-websocket shoot.mjs --out <output-dir>
```

`--experimental-websocket` is required: node 20's global `WebSocket` is still
experimental-flagged (verified on node 20.19.2 — omitting the flag makes `new WebSocket(...)`
throw `ReferenceError: WebSocket is not defined`).

By default the script:

1. Spawns `uv run uvicorn awiwi.app:app --port 5824` with `cwd=server/` and
   `AWIWI_HOME=server/tests/visual/fixture/home`, and polls
   `http://127.0.0.1:5824/api/dir/` until it answers 200 (up to 20s).
2. Launches headless chromium, tries sandboxed first, and falls back to `--no-sandbox` once
   if the sandboxed launch fails or doesn't print a `DevTools listening on ws://...` line
   within ~10s.
3. Shoots every pair in `pairs.json`: the mockup (`file://.../mockups/<file>.html`, if any)
   and the SPA route (`http://127.0.0.1:5824<spaUrl>`).
4. Post-processes every pair with ImageMagick and writes `metrics.json`.
5. Kills chromium and uvicorn (in `finally`, and on `SIGINT`/`SIGTERM`), even on error.

### Flags

| Flag | Required | Meaning |
|---|---|---|
| `--out <dir>` | yes | Output directory for PNGs/bands/diffs/`metrics.json` (created if missing). |
| `--only a,b,c` | no | Only shoot these pair `id`s (comma-separated). Errors out if an id doesn't exist in `pairs.json`. |
| `--no-server` | no | Don't spawn uvicorn — reuse one already listening on `127.0.0.1:5824` (e.g. a manually-started instance, or a previous run's server left up for iteration). Still polls `/api/dir/` first (shorter, 5s timeout), and never kills a server it didn't start. |
| `-h`, `--help` | no | Print usage. |

Example — reshoot just the journal pair against an already-running server:

```sh
AWIWI_HOME=$PWD/fixture/home uv run --project ../.. uvicorn awiwi.app:app --port 5824 &
node --experimental-websocket shoot.mjs --out /tmp/shots --only journal,journal-light --no-server
```

## Output layout

For a pair `id` with a mockup:

```
<out>/<id>-mockup.png        # padded to the pair's common canvas extent
<out>/<id>-spa.png           # padded to the pair's common canvas extent
<out>/<id>-diff.png          # `magick compare -metric RMSE` heatmap
<out>/<id>-mockup-band-00.png, -01.png, ...   # 1440x760 crops, top to bottom
<out>/<id>-spa-band-00.png, -01.png, ...
```

For the one unpaired entry (`recipe-audit`, `mockup: null` in `pairs.json`): only
`<id>-spa.png` and `<id>-spa-band-NN.png` — no diff, no mockup bands (nothing to diff
against; it's an audit-only shot for token consistency, see `handovers/visual-parity/T28.1-fixture.md`).

`metrics.json`:

```json
{
  "<id>": {
    "rmse": "6907.57 (0.105403)",       // raw `compare -metric RMSE` stderr line
    "rmseNormalized": 0.105403,          // parenthesized normalized value, parsed out
    "mockupDims": { "w": 1440, "h": 1777 },  // post-pad, common to both sides
    "spaDims": { "w": 1440, "h": 1777 },
    "bands": { "mockup": 3, "spa": 3 }
  },
  "recipe-audit": {
    "rmse": null, "rmseNormalized": null, "mockupDims": null,
    "spaDims": { "w": 1440, "h": 1000 },
    "bands": { "spa": 2 },
    "note": "unpaired audit shot (no mockup)"
  }
}
```

`compare` exits 1 whenever the two images differ at all (i.e. essentially always) — the
script treats that as expected and only errors out on other exit codes.

Console output (stderr) has one line per page shot:

```
[journal] mockup captured in 862ms (stable after 860ms) height=1759px
[journal] spa captured in 1610ms (stable after 1609ms) height=1777px
```

`stable after Xms` is how long the byte-stability loop (capture every 500ms until two
consecutive PNGs are byte-identical) took before it settled; `CAP(15000ms)` means it never
stabilized and the last capture (at the 15s cap) was used anyway — this is expected for
pages with genuinely never-settling content (e.g. a live ws-dot, though the harness kills
CSS animations/transitions on both sides specifically to avoid that).

If any page fails to load, the script still shoots every other page first, then prints a
summary of failures and exits non-zero:

```
shoot.mjs: 1 page(s) failed to load:
  - [journal] spa (http://127.0.0.1:5824/journal/2026-07-14): mockup ... Page.loadEventFired timed out after 20000ms
```

## How the pages are shot

- **Viewport**: 1440x1000 via both chromium's `--window-size` and
  `Emulation.setDeviceMetricsOverride` (dsf 1).
- **Theme**: mockups are static — the two `*-light.html` files are fixed light snapshots and
  are never touched. For the SPA side, the harness *always* explicitly sets
  `localStorage['awiwi.theme']` via `Page.addScriptToEvaluateOnNewDocument` before navigation
  — to `'light'` for `theme: "light"` pairs, to `'dark'` otherwise. This must be asserted on
  *every* SPA shot, not just the light ones: every SPA target shares one browser profile (one
  origin, one `localStorage`), so once any light-theme shot sets the key, it silently leaks
  into every later "dark" shot unless each navigation re-asserts its own value. (This was
  caught during iter0 verification — see the handover for the before/after screenshots.)
- **Animations**: `*{animation:none!important;transition:none!important}` is injected via
  `Page.addScriptToEvaluateOnNewDocument` on *every* shot, both sides — kills the ws-dot pulse
  and the mockups' theme cross-fade so screenshots aren't flaky.
- **Capture**: after `Page.loadEventFired` and `document.fonts.ready`, the script captures
  `Page.captureScreenshot({format:'png', captureBeyondViewport:true})` every 500ms until two
  consecutive captures are byte-identical (Shiki/mermaid/webfont settle) or 15s elapse.
- **Padding**: within a pair, whichever image is shorter gets padded (top-anchored,
  `-gravity North`) to the taller one's height, using *its own* top-left pixel
  (`p{1,1}`) as the fill color — so the padded margin matches that side's actual page
  background, dark or light.

## Adding a new pair

1. Add a fixture page under `fixture/home/` if the new pair needs new content (see
   `handovers/visual-parity/T28.1-fixture.md` for the render-pipeline gotchas already
   documented there — redaction, `.txt` language sniffing, etc.).
2. Add an entry to `pairs.json`: `{"id": ..., "mockup": "<file>.html" | null, "spaUrl": "/...", "theme": "dark" | "light"}`.
   - `mockup: null` means an unpaired audit shot (spa-only, no diff/mockup bands) — use this
     for pages with no T22 mockup counterpart.
   - `spaUrl` must be the exact path the SPA client router resolves, not just "any path that
     looks right": e.g. `/recipes/<name>` 404s (`DocPage`'s recipe route builds
     `recipes/${rest}` verbatim and hits `/api/doc/recipes/<rest>`, which requires the file
     extension) — the working URL is `/recipes/<name>.md`.
3. Run `node --experimental-websocket shoot.mjs --out <scratch-dir> --only <new-id>` and
   spot-check the resulting `-band-00.png` files before trusting the RMSE number — a wrong
   `spaUrl` or a theme-leak-style bug will still produce a PNG and a plausible-looking (often
   very high) RMSE, not an error.
