import assert from 'node:assert/strict';
import test from 'node:test';

import { generateGenome } from './generative/genome.ts';
import { titleForGenome } from './title.ts';

test('titles are deterministic and include a compact seed suffix', () => {
  const genome = generateGenome(0x8f31);
  assert.equal(titleForGenome(genome), titleForGenome(genome));
  assert.match(titleForGenome(genome), / #[0-9A-F]{4}$/);
});

test('different visual families do not all use the same noun', () => {
  const titles = Array.from({ length: 128 }, (_, seed) =>
    titleForGenome(generateGenome(seed)),
  );
  assert.ok(new Set(titles.map((value) => value.split(' ')[1])).size >= 12);
});
