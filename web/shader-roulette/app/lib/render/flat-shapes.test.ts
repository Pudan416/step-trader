import assert from 'node:assert/strict';
import test from 'node:test';
import { generateArtwork } from '../generative/flat-genome.ts';
import { flatDistances } from './flat-sdf.generated.ts';

test('flat recipes have visible interiors and clear margins throughout the seed corpus', () => {
  for (let seed = 0; seed < 256; seed++) {
    const g = generateArtwork(seed, seed % 7);
    const distance = flatDistances[g.flat!.family];
    let inside = 0;
    for (let iy = 0; iy <= 64; iy++) for (let ix = 0; ix <= 64; ix++) {
      const x = ix / 32 - 1, y = iy / 32 - 1;
      const d = distance(x,y,g.params.lobes,g.params.warp,g.params.hollow,g.params.thickness);
      assert.ok(Number.isFinite(d), `${seed}: non-finite distance`);
      if (d < 0) {
        inside++;
        assert.ok(Math.hypot(x,y) < .92, `${seed}: ${g.flat!.family} leaves its safe bounds`);
      }
    }
    assert.ok(inside > 80, `${seed}: invisible or too thin`);
    assert.ok(inside < 2300, `${seed}: overwhelms its frame`);
  }
});
