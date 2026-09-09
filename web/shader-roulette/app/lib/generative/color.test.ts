import assert from 'node:assert/strict';
import test from 'node:test';

import { makePalette, relativeLuminance } from './color.ts';
import { mulberry32 } from './random.ts';

test('generated palettes use parseable opaque hex roles', () => {
  const palette = makePalette(mulberry32(42), 'film');
  for (const color of Object.values(palette))
    assert.match(color, /^#[0-9a-f]{6}$/i);
});

test('background and light retain readable luminance separation', () => {
  for (let seed = 0; seed < 512; seed += 1) {
    const palette = makePalette(mulberry32(seed), 'matte');
    assert.ok(
      Math.abs(
        relativeLuminance(palette.light) -
          relativeLuminance(palette.background),
      ) >= 0.36,
      `seed ${seed}`,
    );
  }
});
