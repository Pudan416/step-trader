import assert from 'node:assert/strict';
import test from 'node:test';
import { generateSculpture } from '../generative/sculpture.ts';
import { rasterizeSculpture } from './sculpture-canvas.ts';
import { membraneDistances } from './membranes.generated.ts';

test('fallback keeps complex figures visible and leaves a clear border', () => {
  for (const seed of [0, 2, 7, 9, 14, 33]) {
    const pixels = rasterizeSculpture(generateSculpture(seed), 64);
    let occupied = 0;
    for (let y = 0; y < 64; y++)
      for (let x = 0; x < 64; x++) {
        const offset = (y * 64 + x) * 4,
          delta =
            Math.abs(pixels[offset]! - 9) +
            Math.abs(pixels[offset + 1]! - 10) +
            Math.abs(pixels[offset + 2]! - 12);
        assert.equal(pixels[offset + 3], 255);
        if (x === 0 || y === 0 || x === 63 || y === 63)
          assert.ok(delta < 4, `${seed}: touches frame`);
        if (delta > 20) occupied++;
      }
    assert.ok(occupied > 200, `${seed}: disappears in fallback`);
    assert.ok(occupied < 2800, `${seed}: fills the whole field`);
  }
});

test('membrane surfaces are finite and bounded throughout the corpus', () => {
  for (let seed = 0; seed < 128; seed++) {
    const g = generateSculpture(seed),
      model = g.sculpture!.model;
    if (model < 8) continue;
    const sdf = Object.values(membraneDistances)[model - 8]!;
    let filled = 0;
    for (let y = -1; y <= 1; y += 0.04)
      for (let x = -1; x <= 1; x += 0.04) {
        const d = sdf(x, y, g.params.lobes, g.params.warp, g.params.hollow);
        assert.ok(Number.isFinite(d));
        if (d < 0) {
          filled++;
          assert.ok(Math.hypot(x, y) < 0.86, `${seed}: unbounded surface`);
        }
      }
    assert.ok(filled > 100, `${seed}: empty surface`);
  }
});
