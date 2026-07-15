#!/usr/bin/env node
// server/tests/visual/shoot.mjs
//
// Dep-free CDP screenshot harness for the SPA <-> mockup visual-parity loop
// (T28.2). Boots a scratch uvicorn instance serving the built SPA dist
// against the committed fixture tree, drives headless chromium over the
// Chrome DevTools Protocol (raw WebSocket, no puppeteer/playwright), shoots
// every pair in pairs.json (mockup file:// page + SPA route), and
// post-processes the pair with ImageMagick (pad to common extent, RMSE
// diff, 1440x760 band slices) so a cheap model can eyeball parity band by
// band.
//
// Requires: node >=20 run with --experimental-websocket (global WebSocket
// is still experimental in node 20), /usr/bin/chromium, ImageMagick
// (`magick`/`compare` on PATH), `uv` on PATH (unless --no-server).
//
// See README.md in this directory for full usage.

import { spawn, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const VISUAL_DIR = __dirname; // server/tests/visual
const SERVER_DIR = path.resolve(VISUAL_DIR, "..", ".."); // server/
const REPO_ROOT = path.resolve(SERVER_DIR, ".."); // repo root
const FIXTURE_HOME = path.join(VISUAL_DIR, "fixture", "home");
const MOCKUPS_DIR = path.join(REPO_ROOT, "mockups");
const PAIRS_PATH = path.join(VISUAL_DIR, "pairs.json");

const PORT = 5824;
const CHROMIUM_BIN = "/usr/bin/chromium";
const VIEWPORT = { width: 1440, height: 1000, deviceScaleFactor: 1 };
const BAND_SIZE = { width: 1440, height: 760 };
const STABILITY_INTERVAL_MS = 500;
const STABILITY_CAP_MS = 15000;
const NAV_TIMEOUT_MS = 20000;
const FONTS_TIMEOUT_MS = 10000;
const CHROMIUM_LAUNCH_TIMEOUT_MS = 10000;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------

function printHelp() {
  console.log(`usage: node --experimental-websocket shoot.mjs --out <dir> [options]

Required:
  --out <dir>          Output directory for PNGs/bands/diffs/metrics.json.

Options:
  --only a,b,c          Only shoot these pair ids (comma-separated).
  --no-server           Don't spawn uvicorn; reuse one already listening on
                         127.0.0.1:${PORT}.
  -h, --help             Show this help.
`);
}

function parseArgs(argv) {
  const args = { out: null, only: null, noServer: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--out") {
      args.out = argv[++i];
    } else if (a.startsWith("--out=")) {
      args.out = a.slice("--out=".length);
    } else if (a === "--only") {
      args.only = argv[++i]
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    } else if (a.startsWith("--only=")) {
      args.only = a
        .slice("--only=".length)
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    } else if (a === "--no-server") {
      args.noServer = true;
    } else if (a === "-h" || a === "--help") {
      printHelp();
      process.exit(0);
    } else {
      console.error(`shoot.mjs: unknown argument: ${a}`);
      printHelp();
      process.exit(1);
    }
  }
  if (!args.out) {
    console.error("shoot.mjs: --out <dir> is required");
    printHelp();
    process.exit(1);
  }
  return args;
}

// ---------------------------------------------------------------------
// Process management (uvicorn + chromium, both spawned as their own
// process group so we can kill the whole tree on exit).
// ---------------------------------------------------------------------

async function waitForHttp(url, timeoutMs) {
  const start = Date.now();
  let lastErr = null;
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return true;
      lastErr = new Error(`HTTP ${res.status}`);
    } catch (e) {
      lastErr = e;
    }
    await sleep(300);
  }
  throw new Error(
    `timed out after ${timeoutMs}ms waiting for ${url}: ${lastErr?.message ?? "unknown error"}`,
  );
}

function spawnUvicorn() {
  const env = { ...process.env, AWIWI_HOME: FIXTURE_HOME };
  const proc = spawn(
    "uv",
    ["run", "uvicorn", "awiwi.app:app", "--port", String(PORT)],
    { cwd: SERVER_DIR, env, detached: true, stdio: ["ignore", "pipe", "pipe"] },
  );
  proc.stdout.on("data", () => {});
  proc.stderr.on("data", () => {});
  return proc;
}

async function killProcessTree(proc, label) {
  if (!proc || proc.exitCode !== null || proc.signalCode !== null) return;
  try {
    process.kill(-proc.pid, "SIGTERM");
  } catch {
    try {
      proc.kill("SIGTERM");
    } catch {
      /* already dead */
    }
  }
  const start = Date.now();
  while (proc.exitCode === null && proc.signalCode === null && Date.now() - start < 3000) {
    await sleep(100);
  }
  if (proc.exitCode === null && proc.signalCode === null) {
    console.error(`shoot.mjs: ${label} did not exit after SIGTERM, sending SIGKILL`);
    try {
      process.kill(-proc.pid, "SIGKILL");
    } catch {
      try {
        proc.kill("SIGKILL");
      } catch {
        /* nothing more we can do */
      }
    }
  }
}

function spawnChromiumAttempt(useNoSandbox) {
  const userDataDir = mkdtempSync(path.join(tmpdir(), "awiwi-shoot-chromium-"));
  const args = [
    "--headless",
    "--remote-debugging-port=0",
    `--user-data-dir=${userDataDir}`,
    "--hide-scrollbars",
    "--force-device-scale-factor=1",
    "--force-prefers-reduced-motion",
    "--disable-gpu",
    "--no-first-run",
    "--window-size=1440,1000",
  ];
  if (useNoSandbox) args.push("--no-sandbox");
  const proc = spawn(CHROMIUM_BIN, args, {
    detached: true,
    stdio: ["ignore", "ignore", "pipe"],
  });
  return { proc, userDataDir };
}

function waitForDevtoolsPort(proc, timeoutMs) {
  return new Promise((resolve, reject) => {
    let buf = "";
    let done = false;
    const timer = setTimeout(() => {
      if (!done) {
        done = true;
        reject(new Error(`no "DevTools listening" line within ${timeoutMs}ms`));
      }
    }, timeoutMs);
    proc.stderr.on("data", (chunk) => {
      buf += chunk.toString();
      const m = buf.match(/DevTools listening on ws:\/\/127\.0\.0\.1:(\d+)\//);
      if (m && !done) {
        done = true;
        clearTimeout(timer);
        resolve(Number(m[1]));
      }
    });
    proc.on("exit", (code, signal) => {
      if (!done) {
        done = true;
        clearTimeout(timer);
        reject(new Error(`chromium exited early (code=${code}, signal=${signal})`));
      }
    });
  });
}

// Try launching sandboxed first (plan's "test first" instruction); fall
// back to --no-sandbox once if that fails or times out. Returns which mode
// worked so the handover can record the finding.
async function launchChromium() {
  const attempts = [false, true]; // false = sandboxed, true = --no-sandbox
  let lastErr = null;
  for (const useNoSandbox of attempts) {
    const { proc, userDataDir } = spawnChromiumAttempt(useNoSandbox);
    try {
      const port = await waitForDevtoolsPort(proc, CHROMIUM_LAUNCH_TIMEOUT_MS);
      return { proc, userDataDir, port, usedNoSandbox: useNoSandbox };
    } catch (e) {
      lastErr = e;
      console.error(
        `shoot.mjs: chromium launch ${useNoSandbox ? "with --no-sandbox" : "sandboxed"} failed: ${e.message}`,
      );
      await killProcessTree(proc, "chromium (failed attempt)");
      rmSync(userDataDir, { recursive: true, force: true });
    }
  }
  throw new Error(`chromium failed to start in any mode: ${lastErr?.message}`);
}

// ---------------------------------------------------------------------
// Minimal CDP client: one WebSocket per target, JSON-RPC-ish dispatch.
// ---------------------------------------------------------------------

function connectCDP(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let nextId = 1;
    const pending = new Map();
    const eventListeners = new Map();
    let settled = false;

    ws.addEventListener("open", () => {
      if (settled) return;
      settled = true;
      resolve(client);
    });
    ws.addEventListener("error", (e) => {
      if (settled) return;
      settled = true;
      reject(new Error(`CDP websocket error: ${e?.message ?? e}`));
    });
    ws.addEventListener("message", (ev) => {
      let msg;
      try {
        msg = JSON.parse(ev.data);
      } catch {
        return;
      }
      if (msg.id !== undefined) {
        const p = pending.get(msg.id);
        if (p) {
          pending.delete(msg.id);
          if (msg.error) p.reject(new Error(msg.error.message || JSON.stringify(msg.error)));
          else p.resolve(msg.result);
        }
      } else if (msg.method) {
        const cbs = eventListeners.get(msg.method);
        if (cbs) for (const cb of cbs.slice()) cb(msg.params);
      }
    });

    const client = {
      send(method, params = {}) {
        return new Promise((resolve, reject) => {
          const id = nextId++;
          pending.set(id, { resolve, reject });
          try {
            ws.send(JSON.stringify({ id, method, params }));
          } catch (e) {
            pending.delete(id);
            reject(e);
          }
        });
      },
      on(method, cb) {
        if (!eventListeners.has(method)) eventListeners.set(method, []);
        eventListeners.get(method).push(cb);
        return () => {
          const arr = eventListeners.get(method);
          const i = arr.indexOf(cb);
          if (i >= 0) arr.splice(i, 1);
        };
      },
      once(method) {
        return new Promise((resolve) => {
          const off = client.on(method, (params) => {
            off();
            resolve(params);
          });
        });
      },
      close() {
        try {
          ws.close();
        } catch {
          /* ignore */
        }
      },
    };
  });
}

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function newTarget(port) {
  const res = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" });
  if (!res.ok) throw new Error(`PUT /json/new failed: HTTP ${res.status}`);
  return res.json();
}

async function closeTarget(port, targetId) {
  try {
    await fetch(`http://127.0.0.1:${port}/json/close/${targetId}`);
  } catch {
    /* best-effort */
  }
}

const ANIMATION_KILL_SOURCE = `(() => {
  function inject() {
    if (!document.head) return;
    var s = document.createElement('style');
    s.textContent = '*{animation:none!important;transition:none!important}';
    document.head.appendChild(s);
  }
  if (document.head) inject();
  document.addEventListener('DOMContentLoaded', inject);
})();`;

// All SPA targets share one browser profile (same origin -> same
// localStorage), so a light-theme shot's `awiwi.theme=light` would leak
// into every *later* "dark" shot unless every SPA navigation explicitly
// (re-)asserts its own theme value -- not just the light ones.
function themeScriptSource(theme) {
  const value = theme === "light" ? "light" : "dark";
  return `try { localStorage.setItem('awiwi.theme', '${value}'); } catch (e) {}`;
}

// ---------------------------------------------------------------------
// Per-page shoot
// ---------------------------------------------------------------------

async function shootPage(port, { url, outfile, theme, side }) {
  const target = await newTarget(port);
  const cdp = await connectCDP(target.webSocketDebuggerUrl);
  try {
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");

    if (side === "spa") {
      await cdp.send("Page.addScriptToEvaluateOnNewDocument", {
        source: themeScriptSource(theme),
      });
    }
    await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: ANIMATION_KILL_SOURCE });

    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: VIEWPORT.width,
      height: VIEWPORT.height,
      deviceScaleFactor: VIEWPORT.deviceScaleFactor,
      mobile: false,
    });

    const loadPromise = cdp.once("Page.loadEventFired");
    await cdp.send("Page.navigate", { url });
    await withTimeout(loadPromise, NAV_TIMEOUT_MS, `${side} ${url} Page.loadEventFired`);

    try {
      await withTimeout(
        cdp.send("Runtime.evaluate", {
          expression: "document.fonts.ready.then(() => true)",
          awaitPromise: true,
        }),
        FONTS_TIMEOUT_MS,
        `${side} ${url} document.fonts.ready`,
      );
    } catch (e) {
      console.error(`shoot.mjs: [${path.basename(outfile, ".png")}] fonts.ready: ${e.message} (continuing)`);
    }

    // Byte-stability loop: capture repeatedly until two consecutive
    // captures are identical, or the cap elapses.
    const start = Date.now();
    let prev = null;
    let data = null;
    let stableAfterMs = null;
    for (;;) {
      const shot = await cdp.send("Page.captureScreenshot", {
        format: "png",
        captureBeyondViewport: true,
      });
      data = shot.data;
      if (prev !== null && prev === data) {
        stableAfterMs = Date.now() - start;
        break;
      }
      prev = data;
      if (Date.now() - start >= STABILITY_CAP_MS) {
        stableAfterMs = null; // hit the cap; last capture used anyway
        break;
      }
      await sleep(STABILITY_INTERVAL_MS);
    }
    const buf = Buffer.from(data, "base64");
    writeFileSync(outfile, buf);

    // Peek the PNG height straight out of the IHDR chunk (bytes 20-23,
    // big-endian) so the per-page log line doesn't need a second process.
    const height = buf.readUInt32BE(20);
    const captureMs = Date.now() - start;
    return { ok: true, stableAfterMs, captureMs, height };
  } finally {
    cdp.close();
    await closeTarget(port, target.id);
  }
}

// ---------------------------------------------------------------------
// ImageMagick post-processing
// ---------------------------------------------------------------------

function runMagick(args, label) {
  const res = spawnSync("magick", args, { encoding: "utf8" });
  if (res.error) throw new Error(`${label}: ${res.error.message}`);
  return res;
}

function identify(file) {
  const res = runMagick(["identify", "-format", "%wx%h", file], "identify");
  if (res.status !== 0) throw new Error(`identify ${file} failed: ${res.stderr}`);
  const [w, h] = res.stdout.trim().split("x").map(Number);
  return { w, h };
}

function sampleBgColor(file) {
  const res = runMagick([file, "-format", "%[pixel:p{1,1}]", "info:"], "sample bg color");
  if (res.status !== 0) throw new Error(`sample bg color ${file} failed: ${res.stderr}`);
  return res.stdout.trim();
}

function padInPlace(file, w, h) {
  const bg = sampleBgColor(file);
  const tmp = `${file}.pad.png`;
  const res = runMagick(
    [file, "-background", bg, "-gravity", "North", "-extent", `${w}x${h}`, tmp],
    "pad",
  );
  if (res.status !== 0) throw new Error(`pad ${file} failed: ${res.stderr}`);
  renameSync(tmp, file);
}

function compareRMSE(a, b, diffOut) {
  const res = runMagick(["compare", "-metric", "RMSE", a, b, diffOut], "compare");
  // `compare` exits 1 whenever the images differ at all -- that is the
  // expected case, not a failure. Only treat other exit codes as errors.
  if (res.status !== 0 && res.status !== 1) {
    throw new Error(`compare ${a} vs ${b} failed: ${res.stderr}`);
  }
  const raw = (res.stderr || res.stdout || "").trim();
  const m = raw.match(/\(([\d.eE+-]+)\)/);
  return { rmseRaw: raw, rmseNormalized: m ? Number(m[1]) : null };
}

function sliceBands(file, prefixPath) {
  const dir = path.dirname(prefixPath);
  const base = path.basename(prefixPath);
  for (const f of readdirSync(dir)) {
    if (f.startsWith(`${base}-`) && f.endsWith(".png")) rmSync(path.join(dir, f));
  }
  const pattern = `${prefixPath}-%02d.png`;
  const res = runMagick([file, "-crop", `${BAND_SIZE.width}x${BAND_SIZE.height}`, "+repage", pattern], "crop");
  if (res.status !== 0) throw new Error(`crop ${file} failed: ${res.stderr}`);
  return readdirSync(dir).filter((f) => f.startsWith(`${base}-`) && f.endsWith(".png")).length;
}

function postProcessPair(outDir, id, hasMockup) {
  const spaPath = path.join(outDir, `${id}-spa.png`);
  if (!existsSync(spaPath)) {
    console.error(`shoot.mjs: [${id}] no spa capture, skipping post-process`);
    return null;
  }

  if (!hasMockup) {
    const spaDims = identify(spaPath);
    const spaBands = sliceBands(spaPath, path.join(outDir, `${id}-spa-band`));
    return {
      rmse: null,
      rmseNormalized: null,
      mockupDims: null,
      spaDims,
      bands: { spa: spaBands },
      note: "unpaired audit shot (no mockup)",
    };
  }

  const mockupPath = path.join(outDir, `${id}-mockup.png`);
  if (!existsSync(mockupPath)) {
    console.error(`shoot.mjs: [${id}] no mockup capture, skipping post-process`);
    return null;
  }

  let dimsMockup = identify(mockupPath);
  let dimsSpa = identify(spaPath);
  const targetW = Math.max(dimsMockup.w, dimsSpa.w);
  const targetH = Math.max(dimsMockup.h, dimsSpa.h);

  if (dimsMockup.w !== targetW || dimsMockup.h !== targetH) {
    padInPlace(mockupPath, targetW, targetH);
    dimsMockup = { w: targetW, h: targetH };
  }
  if (dimsSpa.w !== targetW || dimsSpa.h !== targetH) {
    padInPlace(spaPath, targetW, targetH);
    dimsSpa = { w: targetW, h: targetH };
  }

  const diffPath = path.join(outDir, `${id}-diff.png`);
  const { rmseRaw, rmseNormalized } = compareRMSE(mockupPath, spaPath, diffPath);

  const mockupBands = sliceBands(mockupPath, path.join(outDir, `${id}-mockup-band`));
  const spaBands = sliceBands(spaPath, path.join(outDir, `${id}-spa-band`));

  return {
    rmse: rmseRaw,
    rmseNormalized,
    mockupDims: dimsMockup,
    spaDims: dimsSpa,
    bands: { mockup: mockupBands, spa: spaBands },
  };
}

// ---------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  mkdirSync(args.out, { recursive: true });

  const manifest = JSON.parse(readFileSync(PAIRS_PATH, "utf8"));
  let pairs = manifest.pairs;
  if (args.only) {
    const wanted = new Set(args.only);
    pairs = pairs.filter((p) => wanted.has(p.id));
    const missing = args.only.filter((id) => !pairs.some((p) => p.id === id));
    if (missing.length > 0) {
      console.error(`shoot.mjs: --only referenced unknown pair id(s): ${missing.join(", ")}`);
      process.exit(1);
    }
  }
  if (pairs.length === 0) {
    console.error("shoot.mjs: no pairs to shoot");
    process.exit(1);
  }

  let uvicornProc = null;
  let chromium = null;
  const errors = [];
  const timings = [];
  let sandboxFinding = null;

  const cleanup = async () => {
    if (chromium) await killProcessTree(chromium.proc, "chromium");
    if (chromium?.userDataDir) rmSync(chromium.userDataDir, { recursive: true, force: true });
    if (uvicornProc) await killProcessTree(uvicornProc, "uvicorn");
  };

  let signalled = false;
  const onSignal = (sig) => {
    if (signalled) return;
    signalled = true;
    console.error(`shoot.mjs: received ${sig}, cleaning up`);
    cleanup().finally(() => process.exit(130));
  };
  process.on("SIGINT", () => onSignal("SIGINT"));
  process.on("SIGTERM", () => onSignal("SIGTERM"));

  try {
    if (!args.noServer) {
      console.error(`shoot.mjs: spawning uvicorn (AWIWI_HOME=${FIXTURE_HOME}, port ${PORT})`);
      uvicornProc = spawnUvicorn();
      await waitForHttp(`http://127.0.0.1:${PORT}/api/dir/`, 20000);
      console.error("shoot.mjs: uvicorn is up");
    } else {
      console.error(`shoot.mjs: --no-server, reusing existing instance on port ${PORT}`);
      await waitForHttp(`http://127.0.0.1:${PORT}/api/dir/`, 5000);
    }

    chromium = await launchChromium();
    sandboxFinding = chromium.usedNoSandbox
      ? "required --no-sandbox (sandboxed launch failed/timed out)"
      : "sandboxed launch worked, --no-sandbox not needed";
    console.error(
      `shoot.mjs: chromium up on devtools port ${chromium.port} (${sandboxFinding})`,
    );

    // Build the flat job list: mockup shot (if any) + spa shot per pair.
    const jobs = [];
    for (const pair of pairs) {
      if (pair.mockup) {
        jobs.push({
          id: pair.id,
          side: "mockup",
          theme: pair.theme,
          url: `file://${path.join(MOCKUPS_DIR, pair.mockup)}`,
          outfile: path.join(args.out, `${pair.id}-mockup.png`),
        });
      }
      jobs.push({
        id: pair.id,
        side: "spa",
        theme: pair.theme,
        url: `${manifest.spaBase}${pair.spaUrl}`,
        outfile: path.join(args.out, `${pair.id}-spa.png`),
      });
    }

    for (const job of jobs) {
      try {
        const result = await shootPage(chromium.port, job);
        const stableLabel = result.stableAfterMs === null ? `CAP(${STABILITY_CAP_MS}ms)` : `${result.stableAfterMs}ms`;
        console.error(
          `[${job.id}] ${job.side} captured in ${result.captureMs}ms (stable after ${stableLabel}) height=${result.height}px`,
        );
        timings.push({ id: job.id, side: job.side, ...result });
      } catch (e) {
        console.error(`[${job.id}] ${job.side} FAILED: ${e.message}`);
        errors.push({ id: job.id, side: job.side, url: job.url, error: e.message });
      }
    }

    // Post-process every pair we have captures for.
    const metrics = {};
    for (const pair of pairs) {
      const entry = postProcessPair(args.out, pair.id, Boolean(pair.mockup));
      if (entry) metrics[pair.id] = entry;
    }
    writeFileSync(path.join(args.out, "metrics.json"), `${JSON.stringify(metrics, null, 2)}\n`);
    console.error(`shoot.mjs: wrote ${path.join(args.out, "metrics.json")}`);
  } finally {
    await cleanup();
  }

  if (errors.length > 0) {
    console.error(`\nshoot.mjs: ${errors.length} page(s) failed to load:`);
    for (const e of errors) {
      console.error(`  - [${e.id}] ${e.side} (${e.url}): ${e.error}`);
    }
    process.exitCode = 1;
  } else {
    console.error(`\nshoot.mjs: all ${timings.length} captures OK.`);
  }
}

main().catch((e) => {
  console.error(`shoot.mjs: fatal: ${e.stack || e.message}`);
  process.exitCode = 1;
});
