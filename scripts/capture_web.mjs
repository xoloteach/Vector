/**
 * Drives the exported browser build in real Chromium, plays it with synthetic
 * keyboard input, and writes screenshots plus a console/error report.
 *
 * Why this exists: the headless autopilot proves the *simulation* works, but it
 * runs in Godot's headless server which has no renderer at all. Everything that
 * can only break once pixels are involved — shaders that fail on WebGL2, missing
 * assets, wrong canvas scaling, UI overlapping the action, a black screen from a
 * boot failure — is invisible to it. This script produces the artefacts that the
 * vision critics actually review.
 *
 * Usage:
 *   node scripts/capture_web.mjs --url http://localhost:8080 --out captures/run1
 *
 * Exit code is non-zero if the game fails to boot or logs a page error, so it
 * doubles as a browser smoke test.
 */

import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

// ---------------------------------------------------------------- arguments

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const URL = arg('url', 'http://localhost:8080');
const OUT = path.resolve(arg('out', 'captures/latest'));
const WIDTH = parseInt(arg('width', '1280'), 10);
const HEIGHT = parseInt(arg('height', '720'), 10);
// Software WebGL2 (SwiftShader) is slow to reach a first frame, so boot gets a
// long allowance. Real hardware needs a fraction of this.
const BOOT_TIMEOUT_MS = parseInt(arg('boot-timeout', '180000'), 10);

/**
 * Number of frames to capture, and the gap between them.
 *
 * The build plays itself: the page is opened with `?bot=1`, which hands control
 * to the in-game autopilot. Screenshots are then just samples of a competent
 * run.
 *
 * The first version of this script drove blind timed key presses instead. It
 * could not play a parkour level — it died at the third gap, and eight of the
 * thirteen "gameplay" frames were of a corpse lying in the void. Two of the five
 * critics could not assess their brief at all as a result. Letting the tested
 * bot drive means every frame is real gameplay, and the sampling covers the
 * whole course instead of the first 70 metres.
 */
const FRAME_COUNT = parseInt(arg('frames', '16'), 10);
const FRAME_INTERVAL_MS = parseInt(arg('interval', '1100'), 10);

// ------------------------------------------------------------------- helpers

const log = (...a) => console.log('[capture]', ...a);

async function main() {
  await mkdir(OUT, { recursive: true });

  const browser = await chromium.launch({
    args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      // Force a working WebGL2 implementation. Without ANGLE+SwiftShader,
      // headless Chromium has no GL and Godot's canvas stays blank — which would
      // look exactly like a game bug.
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--disable-gpu-sandbox',
      '--autoplay-policy=no-user-gesture-required',
    ],
  });

  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } });

  const consoleLines = [];
  const pageErrors = [];
  const failedRequests = [];

  page.on('console', (msg) => {
    const line = `${msg.type()}: ${msg.text()}`;
    consoleLines.push(line);
    if (msg.type() === 'error') log('console error:', msg.text());
  });
  page.on('pageerror', (err) => {
    pageErrors.push(String(err));
    log('page error:', String(err));
  });
  page.on('requestfailed', (req) => {
    failedRequests.push(`${req.method()} ${req.url()} — ${req.failure()?.errorText}`);
  });

  // `?bot=1` makes the build play itself. See FRAME_COUNT above for why.
  const target = URL.includes('?') ? `${URL}&bot=1&touch=0` : `${URL}/?bot=1&touch=0`;
  log(`opening ${target}`);
  await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 60000 });

  // --- wait for the engine to actually render -------------------------------
  // Godot's web shell creates the canvas immediately, long before the first
  // frame. Waiting on the canvas element alone would screenshot a blank page, so
  // wait until the canvas has real pixels drawn into it.
  await page.waitForSelector('canvas', { timeout: 60000 });
  log('canvas present, waiting for first rendered frame…');

  const booted = await page
    .waitForFunction(
      () => {
        const c = document.querySelector('canvas');
        if (!c || c.width < 32 || c.height < 32) return false;
        // Godot exposes its engine object on the window once started.
        return true;
      },
      { timeout: 30000 },
    )
    .then(() => true)
    .catch(() => false);

  if (!booted) {
    await page.screenshot({ path: path.join(OUT, '00-boot-failure.png') });
    throw new Error('canvas never reached a usable size — the build did not boot');
  }

  // Poll a downscaled readback of the canvas until it stops being uniformly
  // black. That is the only reliable "the game is on screen" signal available
  // from outside the engine.
  const rendered = await waitForNonBlankCanvas(page, BOOT_TIMEOUT_MS);
  if (!rendered) {
    await page.screenshot({ path: path.join(OUT, '00-black-screen.png') });
    await writeReport(OUT, { consoleLines, pageErrors, failedRequests, booted: false });
    throw new Error(
      'canvas stayed blank — the game booted but rendered nothing (check WebGL2 / shader errors)',
    );
  }
  log('first frame rendered');

  // Click the canvas so keyboard input is routed to the game. The bot drives
  // itself, but the debug-overlay toggle below still needs a focused canvas.
  await page.locator('canvas').click({ position: { x: WIDTH / 2, y: HEIGHT / 2 } });
  await page.waitForTimeout(900);

  // Confirm the bot actually took over rather than silently leaving an idle
  // runner standing on the start deck — that would produce sixteen identical
  // screenshots and look like a rendering problem.
  const engaged = consoleLines.some((l) => l.includes('autopilot engaged'));
  if (!engaged) {
    log('WARNING: no "autopilot engaged" message — frames may show an idle runner');
  }

  // --- sample the run -------------------------------------------------------
  for (let i = 0; i < FRAME_COUNT; i++) {
    await page.waitForTimeout(FRAME_INTERVAL_MS);
    const name = `${String(i + 1).padStart(2, '0')}-run`;
    await page.screenshot({ path: path.join(OUT, `${name}.png`) });
    log(`captured ${name}.png`);
  }

  // One frame with the debug overlay up, for the technical critic.
  await page.keyboard.press('F1');
  await page.waitForTimeout(700);
  await page.screenshot({ path: path.join(OUT, '99-debug-overlay.png') });
  log('captured 99-debug-overlay.png');

  await writeReport(OUT, { consoleLines, pageErrors, failedRequests, booted: true });
  await browser.close();

  // Godot's own shell logs a few benign notices; only real errors should fail
  // the smoke test.
  const realErrors = pageErrors.filter((e) => !/ResizeObserver|AudioContext/i.test(e));
  if (realErrors.length > 0) {
    log(`FAILED: ${realErrors.length} page error(s)`);
    process.exit(1);
  }
  log(`done — ${FRAME_COUNT + 1} screenshots in ${OUT}`);
}

/**
 * Reads the canvas back at low resolution and returns true once the frame is not
 * uniformly dark. Uses `preserveDrawingBuffer`-independent readback via
 * drawImage onto a 2D context, which works regardless of how the WebGL context
 * was created.
 */
async function waitForNonBlankCanvas(page, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const variance = await page.evaluate(() => {
      const src = document.querySelector('canvas');
      if (!src) return -1;
      const s = document.createElement('canvas');
      s.width = 48;
      s.height = 27;
      const ctx = s.getContext('2d');
      try {
        ctx.drawImage(src, 0, 0, s.width, s.height);
      } catch {
        return -1;
      }
      const { data } = ctx.getImageData(0, 0, s.width, s.height);
      let min = 255;
      let max = 0;
      for (let i = 0; i < data.length; i += 4) {
        const v = (data[i] + data[i + 1] + data[i + 2]) / 3;
        if (v < min) min = v;
        if (v > max) max = v;
      }
      return max - min;
    });
    // A rendered 3D scene has a wide value range; a blank or solid-colour canvas
    // has almost none.
    if (variance > 12) return true;
    await page.waitForTimeout(1500);
  }
  return false;
}

async function writeReport(out, { consoleLines, pageErrors, failedRequests, booted }) {
  const report = [
    `booted: ${booted}`,
    '',
    `# page errors (${pageErrors.length})`,
    ...pageErrors,
    '',
    `# failed requests (${failedRequests.length})`,
    ...failedRequests,
    '',
    `# console (${consoleLines.length})`,
    ...consoleLines,
  ].join('\n');
  await writeFile(path.join(out, 'browser-report.txt'), report, 'utf8');
}

main().catch(async (err) => {
  console.error('[capture] FAILED:', err.message);
  process.exit(1);
});
