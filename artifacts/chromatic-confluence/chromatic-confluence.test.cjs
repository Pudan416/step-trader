const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

const artifactPath = path.join(__dirname, 'chromatic-confluence.html');

async function openArtwork(t) {
  assert.ok(fs.existsSync(artifactPath), 'the artwork HTML must exist');

  const browser = await chromium.launch({ headless: true });
  t.after(() => browser.close());
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.goto(pathToFileURL(artifactPath).href, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.chromaticConfluence?.ready === true);
  assert.deepEqual(pageErrors, [], `runtime errors: ${pageErrors.join('; ')}`);
  return page;
}

test('renders exactly ten bodies on a portrait 9:16 canvas', async t => {
  const page = await openArtwork(t);
  const scene = await page.evaluate(() => window.chromaticConfluence.snapshot());

  assert.equal(scene.canvas.width, 1080);
  assert.equal(scene.canvas.height, 1920);
  assert.equal(scene.objectCount, 10);
});

test('the choreography moves and produces proximity interactions', async t => {
  const page = await openArtwork(t);
  const result = await page.evaluate(() => {
    const api = window.chromaticConfluence;
    api.pause();
    api.setTime(0);
    const start = api.snapshot();
    api.setTime(8.75);
    const later = api.snapshot();

    let maxInteractions = 0;
    for (let time = 0; time <= 80; time += 0.25) {
      maxInteractions = Math.max(maxInteractions, api.probe(time).interactionCount);
    }

    return { start, later, maxInteractions };
  });

  assert.notDeepEqual(result.start.positions, result.later.positions);
  assert.ok(result.maxInteractions > 0, 'at least one choreographed intersection should occur');
});

test('trail memory control changes how much gesture history is rendered', async t => {
  const page = await openArtwork(t);
  const trailControl = page.locator('#trailLength');
  assert.equal(await trailControl.count(), 1, 'the artwork must expose a trail memory control');

  await page.evaluate(() => {
    window.chromaticConfluence.pause();
    window.chromaticConfluence.setTime(12);
  });

  await trailControl.fill('24');
  await trailControl.dispatchEvent('input');
  const shortTrail = await page.evaluate(() => window.chromaticConfluence.snapshot().trailPointCount);

  await trailControl.fill('96');
  await trailControl.dispatchEvent('input');
  const longTrail = await page.evaluate(() => window.chromaticConfluence.snapshot().trailPointCount);

  assert.ok(longTrail > shortTrail * 3, 'long memory should render substantially more gesture history');
});

test('pause and PNG download controls work', async t => {
  const page = await openArtwork(t);

  await page.click('#pause-button');
  const label = await page.textContent('#pause-button');
  assert.match(label, /Resume/);

  const download = page.waitForEvent('download');
  await page.click('#download-button');
  const downloaded = await download;
  assert.match(downloaded.suggestedFilename(), /^gesture-field-seed-\d+\.png$/);
});
