const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1200, height: 2200 }, deviceScaleFactor: 1 });
  const artifact = path.join(__dirname, 'chromatic-confluence.html');
  await page.goto(pathToFileURL(artifact).href, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.chromaticConfluence?.ready === true);
  await page.evaluate(() => window.chromaticConfluence.pause());

  for (const time of [0, 3.5, 7, 10.5, 14, 17.5]) {
    await page.evaluate(value => window.chromaticConfluence.setTime(value), time);
    await page.locator('#canvas-container canvas').screenshot({
      path: path.join(__dirname, `preview-${String(time).replace('.', '-')}.png`)
    });
  }

  await page.evaluate(() => window.chromaticConfluence.setTime(14));
  const downloadEvent = page.waitForEvent('download');
  await page.click('#download-button');
  const download = await downloadEvent;
  await download.saveAs(path.join(__dirname, 'gesture-field-wallpaper.png'));

  await browser.close();
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
