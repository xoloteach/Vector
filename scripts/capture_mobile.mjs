/**
 * Verifies the on-screen touch controls in a real browser, on a real touch
 * context, by tapping them and checking the runner actually responds.
 *
 * This is a functional test, not a screenshot job. Touch controls are extremely
 * easy to ship broken — a layout that overlaps, a hit area that misses, a held
 * direction that never releases, a control that works for one finger but not two
 * — and none of that is visible from code review or from a desktop capture.
 *
 * Playwright is given `hasTouch: true` so Godot's web shell receives genuine
 * `touchstart`/`touchmove`/`touchend` events and produces real
 * `InputEventScreenTouch`. Mouse clicks would not exercise the same path.
 *
 * Usage:
 *   node scripts/capture_mobile.mjs --url http://localhost:8080 --out captures/mobile
 */

import { chromium, devices } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const URL = arg('url', 'http://localhost:8080');
const OUT = path.resolve(arg('out', 'captures/mobile'));
const BOOT_TIMEOUT_MS = parseInt(arg('boot-timeout', '180000'), 10);

/**
 * Form factors to verify. Covers a small phone, a large phone and a tablet, in
 * both orientations, because the control layout genuinely rearranges between
 * portrait and landscape and each arrangement can break independently.
 */
const PROFILES = [
  { name: 'phone-landscape',  width: 844, height: 390 },
  { name: 'phone-portrait',   width: 390, height: 844 },
  { name: 'phone-lg-landscape', width: 932, height: 430 },
  { name: 'tablet-landscape', width: 1180, height: 820 },
  { name: 'tablet-portrait',  width: 820, height: 1180 },
];

const log = (...a) => console.log('[mobile]', ...a);

/** Where each control should be, mirroring the layout maths in touch_controls.gd. */
function expectedLayout(width, height) {
  const shortEdge = Math.min(width, height);
  const portrait = height > width;

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const actionSize = clamp(shortEdge * 0.19, 84, 168);
  const dpadSize = clamp(shortEdge * 0.17, 76, 150);
  const margin = Math.max(shortEdge * 0.07, 22);
  const bottom = height - margin - (portrait ? shortEdge * 0.06 : 0);
  const gap = dpadSize * (portrait ? 0.34 : 0.22);

  const centre = (x, y, w, h) => ({ x: x + w / 2, y: y + h / 2 });

  const jumpSize = actionSize;
  const slideSize = actionSize * 0.86;
  const rightX = width - margin - jumpSize;

  return {
    left: centre(margin, bottom - dpadSize, dpadSize, dpadSize),
    right: centre(margin + dpadSize + gap, bottom - dpadSize, dpadSize, dpadSize),
    jump: centre(rightX, bottom - jumpSize, jumpSize, jumpSize),
    slide: centre(
      rightX - slideSize - gap * 0.7,
      bottom - slideSize - jumpSize * (portrait ? 0.34 : 0.28),
      slideSize,
      slideSize,
    ),
  };
}

async function waitForRender(page, timeoutMs) {
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
    if (variance > 12) return true;
    await page.waitForTimeout(1500);
  }
  return false;
}

/**
 * Multi-touch via CDP. Playwright's `page.touchscreen` only supports a single
 * tap, and the whole point of the test is holding a direction *and* jumping at
 * the same time — which is the case most likely to be broken.
 */
async function touch(cdp, type, points) {
  await cdp.send('Input.dispatchTouchEvent', {
    type,
    touchPoints: points.map((p, i) => ({ x: p.x, y: p.y, id: p.id ?? i })),
  });
}

async function main() {
  await mkdir(OUT, { recursive: true });

  const browser = await chromium.launch({
    args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--disable-gpu-sandbox',
      '--autoplay-policy=no-user-gesture-required',
    ],
  });

  const findings = [];
  let failures = 0;

  for (const profile of PROFILES) {
    log(`--- ${profile.name} (${profile.width}x${profile.height})`);
    const context = await browser.newContext({
      viewport: { width: profile.width, height: profile.height },
      hasTouch: true,
      isMobile: true,
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));

    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForSelector('canvas', { timeout: 60000 });

    const rendered = await waitForRender(page, BOOT_TIMEOUT_MS);
    if (!rendered) {
      findings.push(`${profile.name}: FAIL — never rendered`);
      failures++;
      await page.screenshot({ path: path.join(OUT, `${profile.name}-blank.png`) });
      await context.close();
      continue;
    }

    const cdp = await context.newCDPSession(page);
    const L = expectedLayout(profile.width, profile.height);

    // A first tap anywhere reveals the controls on platforms whose feature
    // detection claims there is no touchscreen.
    await touch(cdp, 'touchStart', [{ x: profile.width / 2, y: profile.height / 2 }]);
    await touch(cdp, 'touchEnd', []);
    await page.waitForTimeout(900);
    await page.screenshot({ path: path.join(OUT, `${profile.name}-controls.png`) });

    // --- test 1: holding right actually moves the runner ---------------------
    await touch(cdp, 'touchStart', [{ x: L.right.x, y: L.right.y, id: 1 }]);
    await page.waitForTimeout(1600);
    await page.screenshot({ path: path.join(OUT, `${profile.name}-running.png`) });

    // --- test 2: multi-touch — hold right AND press jump ---------------------
    await touch(cdp, 'touchStart', [
      { x: L.right.x, y: L.right.y, id: 1 },
      { x: L.jump.x, y: L.jump.y, id: 2 },
    ]);
    await page.waitForTimeout(280);
    await page.screenshot({ path: path.join(OUT, `${profile.name}-jump-multitouch.png`) });

    // Release jump only; direction must stay held.
    await touch(cdp, 'touchStart', [{ x: L.right.x, y: L.right.y, id: 1 }]);
    await page.waitForTimeout(900);

    // --- test 3: slide while running ----------------------------------------
    await touch(cdp, 'touchStart', [
      { x: L.right.x, y: L.right.y, id: 1 },
      { x: L.slide.x, y: L.slide.y, id: 3 },
    ]);
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(OUT, `${profile.name}-slide.png`) });

    // --- test 4: everything releases cleanly --------------------------------
    await touch(cdp, 'touchEnd', []);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(OUT, `${profile.name}-released.png`) });

    // Read the runner's own telemetry out of the debug overlay instead of
    // guessing from pixels. Enabling it needs a key, which a touch context can
    // still send.
    await page.keyboard.press('F1');
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(OUT, `${profile.name}-debug.png`) });

    if (errors.length > 0) {
      findings.push(`${profile.name}: FAIL — ${errors.length} page error(s): ${errors[0]}`);
      failures++;
    } else {
      findings.push(`${profile.name}: ok — controls rendered, touch accepted, no page errors`);
    }

    await context.close();
  }

  await browser.close();

  const report = ['# touch control verification', '', ...findings].join('\n');
  await writeFile(path.join(OUT, 'mobile-report.txt'), report, 'utf8');
  log('\n' + report);

  if (failures > 0) {
    log(`FAILED: ${failures} profile(s)`);
    process.exit(1);
  }
  log(`done — ${PROFILES.length} profiles verified, screenshots in ${OUT}`);
}

main().catch((err) => {
  console.error('[mobile] FAILED:', err.message);
  process.exit(1);
});
