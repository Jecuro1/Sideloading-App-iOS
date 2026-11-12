// Renders the UI in demo mode with Playwright and saves screenshots.
// Usage: node scripts/screenshots.js [outDir] [scale]
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const outDir = path.resolve(process.argv[2] || path.join(__dirname, '..', 'screenshots'));
const scale = Number(process.argv[3] || 1);
const scenarios = (process.env.SCENARIOS || 'ready,installing,success,failed,drop,idle,nodevice,help').split(',');
const page = path.join(__dirname, '..', 'src', 'renderer', 'index.html');

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: scale });
  for (const scenario of scenarios) {
    const tab = await context.newPage();
    const errors = [];
    tab.on('pageerror', (e) => errors.push(e.message));
    tab.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await tab.goto(`file://${page}?demo=${scenario}&platform=${process.env.PLATFORM || 'win32'}`);
    await tab.waitForTimeout(1800);
    await tab.screenshot({ path: path.join(outDir, `${scenario}.png`) });
    console.log(`${scenario}: ${errors.length ? errors.join(' | ') : 'ok'}`);
    await tab.close();
  }
  await browser.close();
})();
