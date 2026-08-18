// Freezes the original stylesheet's clock and screenshots it, so the port's
// motion layer can be compared against the thing it is a port of.
//
//   luajit tools/dump_animated.lua mad > /tmp/motion/index.html
//   node tools/motion_shot.mjs <seconds> <label>
import { chromium } from "playwright";

const T = Number(process.argv[2] || 3.0);
const label = process.argv[3] || "idle";

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 620 }, deviceScaleFactor: 1 });
await page.goto("file:///tmp/motion/index.html");
await page.waitForTimeout(200);

// Every idle loop is an infinite CSS animation, and setting its currentTime is
// the same as asking what the page looked like T seconds after it opened: the
// negative delays the stylesheet uses are already folded into the effect's own
// timing, so this needs no correction for them.
await page.evaluate((t) => {
  for (const a of document.getAnimations()) {
    a.pause();
    a.currentTime = t * 1000;
  }
}, T);
await page.waitForTimeout(120);
await page.screenshot({ path: `/tmp/motion-${label}.png` });
await browser.close();
console.log(`wrote /tmp/motion-${label}.png at t=${T}s`);
