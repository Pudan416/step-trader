import assert from 'node:assert/strict';
import test from 'node:test';

import { generateGenome, isGenomeValid, normalizeSeed } from './genome.ts';

test('the same seed produces the same genome', () => {
  assert.deepEqual(generateGenome(0x8f31), generateGenome(0x8f31));
});

test('a broad seed corpus stays within structural constraints', () => {
  for (let seed = 0; seed < 2048; seed += 1) {
    assert.equal(isGenomeValid(generateGenome(seed)), true, `seed ${seed}`);
  }
});

test('the seed corpus reaches every family and dimensional mode', () => {
  const genomes = Array.from({ length: 4096 }, (_, seed) =>
    generateGenome(seed),
  );
  assert.deepEqual(
    new Set(genomes.map((value) => value.geometry)),
    new Set(['organism', 'relic', 'ribbon', 'glyph', 'field', 'constellation']),
  );
  assert.deepEqual(
    new Set(genomes.map((value) => value.dimension)),
    new Set(['graphic', 'volumetric', 'hybrid']),
  );
});

test('rare mutations never stack', () => {
  for (let seed = 0; seed < 4096; seed += 1) {
    assert.ok(generateGenome(seed).rareMutation.length <= 1);
  }
});

test('normalizes decimal and unsigned seed values', () => {
  assert.equal(normalizeSeed('36657'), 36657);
  assert.equal(normalizeSeed(0x1_0000_8f31), 0x8f31);
});
