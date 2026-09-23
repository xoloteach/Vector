/**
 * Captures the interface screens from the real exported build.
 *
 * The gameplay capture (`capture_web.mjs`) launches straight into a run with the
 * autopilot, which means it never photographs the title screen, the controls panel,
 * the settings panel, the pause menu or the results screen. Those are exactly the
 * screens most likely to be quietly broken — a layout that overflows, a panel that
 * renders behind another, a button that never receives its click — and none of it is
 * visible from code.
 *
 * This drives the menus with real clicks and keys, at desktop and phone sizes.
 *
 * Usage:
 *   node scripts/capture_ui.mjs --url http://localhost:8080 --out captures/ui
 */

import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const URL = arg('url', 'http://localhost:8080');
const OUT = path.resolve(arg('out', 'captures/ui'));
const BOOT_TIMEOUT_MS = parseInt(arg('boot-timeout', '180000'), 10);

const PROFILES = [
  { name: 'desktop', width: 1280, height: 720, touch: false },
  { name: 'phone', width: 844, height: 390, touch: true },
];

const log = (...a) => console.log('[ui]', ...a);

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
    if (variance > 10) return true;
    await page.waitForTimeout(1500);
  }
  return false;
}

/**
 * Clicks a point given as a fraction of the viewport.
 *
 * Fractions rather than pixels because the panels are centred and sized from the
 * viewport, so the same fraction hits the same control at every resolution.
 */
async function clickAt(page, fx, fy, width, height) {
  await page.mouse.click(Math.round(width * fx), Math.round(height * fy));
  await page.waitForTimeout(650);
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
      hasTouch: profile.touch,
      isMobile: profile.touch,
    });
    const page = await context.newPage();
    const errors = [];
    const consoleLines = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (m) => consoleLines.push(`${m.type()}: ${m.text()}`));

    // No `?bot=1`: the point is to reach the menus, which the autopilot skips.
    const target = profile.touch ? URL : `${URL}/?touch=0`;
    await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForSelector('canvas', { timeout: 60000 });

    if (!(await waitForRender(page, BOOT_TIMEOUT_MS))) {
      findings.push(`${profile.name}: FAIL — never rendered`);
      failures++;
      await context.close();
      continue;
    }

    const { width: w, height: h } = profile;
    const shot = async (name) => {
      await page.screenshot({ path: path.join(OUT, `${profile.name}-${name}.png`) });
      log(`captured ${profile.name}-${name}.png`);
    };

    // Focus the canvas first. Godot's web shell only routes input once the canvas has
    // focus, and without this every click and key press is silently discarded — which
    // looks exactly like a dead button.
    await page.locator('canvas').click({ position: { x: w * 0.5, y: h * 0.12 } });
    await page.waitForTimeout(900);
    await shot('01-title');

    // Controls panel is the second button down the column.
    await clickAt(page, 0.5, 0.63, w, h);
    await shot('02-controls');
    // "Back" sits at the bottom of the panel.
    await clickAt(page, 0.5, 0.88, w, h);
    await page.waitForTimeout(400);

    // Settings is the third button.
    await clickAt(page, 0.5, 0.71, w, h);
    await shot('03-settings');
    await clickAt(page, 0.5, 0.86, w, h);
    await page.waitForTimeout(400);
    await shot('04-title-again');

    // Start a run, then pause it.
    await clickAt(page, 0.5, 0.55, w, h);
    await page.waitForTimeout(2200);
    await shot('05-in-game');

    await page.keyboard.press('Escape');
    await page.waitForTimeout(700);
    await shot('06-paused');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    // Stand still until the pursuer catches up, to reach the results screen.
    log('waiting to be caught for the results screen…');
    await page.waitForTimeout(14000);
    await shot('07-results');

    await writeFile(
      path.join(OUT, `${profile.name}-console.txt`),
      consoleLines.join('\n'),
      'utf8',
    );
    const launch = consoleLines.find((l) => l.includes('launch query'));
    if (launch) log(launch);

    if (errors.length > 0) {
      findings.push(`${profile.name}: FAIL — ${errors.length} page error(s): ${errors[0]}`);
      failures++;
    } else {
      findings.push(`${profile.name}: ok — all screens rendered, no page errors`);
    }

    await context.close();
  }

  await browser.close();

  const report = ['# UI capture', '', ...findings].join('\n');
  await writeFile(path.join(OUT, 'ui-report.txt'), report, 'utf8');
  log('\n' + report);

  if (failures > 0) process.exit(1);
  log(`done — screenshots in ${OUT}`);
}

main().catch((err) => {
  console.error('[ui] FAILED:', err.message);
  process.exit(1);
});
