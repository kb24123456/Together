const path = require('path');
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require('playwright-core'));
}

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  });
  const page = await browser.newPage({ viewport: { width: 851, height: 1848 } });
  const failures = [];

  page.on('pageerror', error => failures.push(`pageerror: ${error.message}`));
  page.on('console', message => {
    if (message.type() === 'error') failures.push(`console: ${message.text()}`);
  });

  const htmlPath = path.resolve(__dirname, 'index.html');
  await page.addInitScript(() => {
    window.__seekRender = true;
  });
  await page.goto(`file://${htmlPath}`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__ready === true);
  await page.addStyleTag({ content: '.no-record { display: none !important; }' });

  const frames = [
    ['01-enter', 0.20],
    ['02-enabled', 0.84],
    ['03-pressed', 1.55],
    ['04-condense', 1.88],
    ['05-ink-transfer', 2.02],
    ['06-check-draw', 2.14],
    ['07-success-settled', 2.40],
    ['08-end', 3.69],
  ];

  for (const [name, time] of frames) {
    await page.evaluate(value => window.__seek(value), time);
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.screenshot({ path: path.resolve(__dirname, `${name}.png`) });
  }

  const state = await page.evaluate(() => ({
    ready: window.__ready,
    seek: typeof window.__seek,
    imageComplete: document.querySelector('.screen')?.complete,
    actionGroupBox: document.querySelector('.action-group')?.getBoundingClientRect().toJSON(),
  }));

  await browser.close();
  console.log(JSON.stringify({ failures, state }, null, 2));
  if (failures.length > 0) process.exitCode = 1;
})();
