const fs = require('fs');
const path = require('path');
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require('playwright-core'));
}

const FPS = 60;
const DURATION = 3.7;
const FRAME_COUNT = Math.ceil(FPS * DURATION);
const FRAME_DIR = path.resolve(__dirname, 'frames');

(async () => {
  fs.mkdirSync(FRAME_DIR, { recursive: true });

  const browser = await chromium.launch({
    headless: true,
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  });
  const page = await browser.newPage({ viewport: { width: 851, height: 1848 } });

  await page.addInitScript(() => {
    window.__seekRender = true;
    window.__recording = true;
  });
  await page.goto(`file://${path.resolve(__dirname, 'index.html')}`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__ready === true);
  await page.addStyleTag({ content: '.no-record { display: none !important; }' });

  for (let index = 0; index < FRAME_COUNT; index += 1) {
    const time = Math.min(index / FPS, DURATION - 0.001);
    await page.evaluate(value => window.__seek(value), time);
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.screenshot({
      path: path.join(FRAME_DIR, `frame-${String(index).padStart(4, '0')}.png`),
    });
  }

  await browser.close();
  console.log(`Rendered ${FRAME_COUNT} frames at ${FPS}fps.`);
})();
